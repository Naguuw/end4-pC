pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions


Scope {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return filterDuplicatePlayers(realPlayers)
        const filtered = realPlayers.filter(p =>
            (p.identity ?? "").toLowerCase().includes(preferred) ||
            (p.desktopEntry ?? "").toLowerCase().includes(preferred)
        )
        return filtered.length === 0 ? filterDuplicatePlayers(realPlayers) : filterDuplicatePlayers(filtered)
    }

    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: !barVertical ? (Config.options.bar.bottom ? "bottom" : "top") : (Config.options.bar.bottom ? "right" : "left")
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
    readonly property real gap: Config.options.bar.cornerStyle === 3 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property bool cornerStyleReducesGap: Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 2

    readonly property string mediaPosition: {
        if (Config.options.bar.layouts.leftLayout.includes("media")) return "left"
        if (Config.options.bar.layouts.middleLayout.includes("media")) return "center"
        if (Config.options.bar.layouts.rightLayout.includes("media")) return "right"
        return "center"
    }

    function calculatePopupX(screenWidth) {
        if (root.barEdge === "left") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap : root.gap)
        if (root.barEdge === "right") return screenWidth - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - root.widgetWidth
        if (root.mediaPosition === "left") return 0
        if (root.mediaPosition === "right") return screenWidth - root.widgetWidth - root.gap
        return (screenWidth - root.widgetWidth) / 2
    }

    function calculatePopupY(screenHeight, contentHeight) {
        if (root.barEdge === "top") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap - 6 : root.gap)
        if (root.barEdge === "bottom") return screenHeight - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - contentHeight
        if (root.mediaPosition === "left") return 0
        if (root.mediaPosition === "right") return screenHeight - contentHeight - root.gap
        return (screenHeight - contentHeight) / 2
    }

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i)) continue;
            let p1 = players[i];
            let group = [i];

            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if ((p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle))) ||
                    (p1.position - p2.position <= 2 && p1.length - p2.length <= 2)) {
                    group.push(j);
                }
            }

            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            filtered.push(players[chosenIdx ?? group[0]]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    property bool reallyOpen: false

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) {
                closeAnimTimer.stop();
                root.reallyOpen = true;
                Notifications.timeoutAll();
            } else {
                closeAnimTimer.restart();
            }
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 150
        onTriggered: root.reallyOpen = false
    }

    Process {
        id: cavaProc
        running: (GlobalStates.mediaControlsOpen ||
            GlobalStates.sidebarRightOpen ||
            (GlobalStates.sidebarLeftOpen && !GlobalStates.mediaLyricsVisible) ||
            Config.options.bar.layouts.leftLayout.includes("visualizer") ||
            Config.options.bar.layouts.middleLayout.includes("visualizer") ||
            Config.options.bar.layouts.rightLayout.includes("visualizer") ||
            Config.options.background.widgets.visualizer.enable)
            && MprisController.activePlayer !== null
        onRunningChanged: {
            if (!cavaProc.running) {
                GlobalStates.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                GlobalStates.visualizerPoints = points;
            }
        }
    }

    Loader {
        id: mediaControlsLoader
        active: root.reallyOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:mediaControls"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: GlobalStates.mediaControlsOpen = false
            }

            Item {
                id: playerContainer
                width: root.widgetWidth
                height: playerColumnLayout.implicitHeight
                x: root.calculatePopupX(panelWindow.width)
                y: root.calculatePopupY(panelWindow.height, playerColumnLayout.implicitHeight)

                opacity: GlobalStates.mediaControlsOpen ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: playerColumnLayout
                    anchors.fill: parent
                    spacing: -Appearance.sizes.elevationMargin

                    Repeater {
                        model: ScriptModel {
                            values: root.meaningfulPlayers
                        }
                        delegate: Player {
                            required property MprisPlayer modelData
                            player: modelData
                            visualizerPoints: GlobalStates.visualizerPoints  
                            implicitWidth: root.widgetWidth
                            implicitHeight: showLyrics ? 290 : Appearance.sizes.mediaControlsHeight
                            radius: root.popupRounding
                        }
                    }

                    Item {
                        visible: root.meaningfulPlayers.length === 0
                        implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                        implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin
                        Layout.alignment: {
                            if (root.mediaPosition === "left") return Qt.AlignLeft;
                            if (root.mediaPosition === "right") return Qt.AlignRight;
                            return Qt.AlignHCenter;
                        }
                        Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                        Layout.rightMargin: Appearance.sizes.hyprlandGapsOut

                        StyledRectangularShadow {
                            target: placeholderBackground
                        }

                        Rectangle {
                            id: placeholderBackground
                            anchors.centerIn: parent
                            color: Appearance.colors.colLayer0
                            radius: root.popupRounding
                            property real padding: 20
                            implicitWidth: placeholderLayout.implicitWidth + padding * 2
                            implicitHeight: placeholderLayout.implicitHeight + padding * 2

                            ColumnLayout {
                                id: placeholderLayout
                                anchors.centerIn: parent

                                StyledText {
                                    text: Translation.tr("No active player")
                                    font.pixelSize: Appearance.font.pixelSize.large
                                }
                                StyledText {
                                    color: Appearance.colors.colSubtext
                                    text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"
        function toggle(): void { GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen; }
        function close(): void { GlobalStates.mediaControlsOpen = false; }
        function open(): void { GlobalStates.mediaControlsOpen = true; }
    }

    CompositorGlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
    }

    CompositorGlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = true
    }

    CompositorGlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = false
    }
}
