import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "notes"
    hoverEnabled: true

    readonly property real cardWidth: 276
    readonly property real cardHeight: 120
    readonly property real cardSpacing: 12

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight * 2 + root.cardSpacing

    property string mode: "list" // "list" | "edit"
    property var pendingNoteId: null
    property string editingText: ""
    onModeChanged: {
        GlobalStates.desktopWidgetKeyboardFocus = (mode === "edit")
        if (mode === "edit") {
            Qt.callLater(() => {
                editTextArea.forceActiveFocus()
                editTextArea.cursorPosition = editTextArea.text.length
            })
        }
    }

    function formatTime(timestamp) {
        if (!timestamp) return ""
        const d = new Date(timestamp)
        const now = new Date()
        const isToday = d.toDateString() === now.toDateString()
        if (isToday) {
            return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        }
        return d.toLocaleDateString([], { month: 'short', day: 'numeric' })
    }

    function toggleFlip() { flipAnim.start() }

    function openNewNote() {
        root.pendingNoteId = null
        root.editingText = ""
        toggleFlip()
    }

    function openNote(note) {
        root.pendingNoteId = note.id
        root.editingText = note.content
        toggleFlip()
    }

    function deleteCurrentAndBack() {
        if (root.pendingNoteId) {
            Notes.deleteNote(root.pendingNoteId)
            root.pendingNoteId = null
        }
        toggleFlip()
    }

    function saveAndBack() {
        if (root.editingText.trim().length > 0) {
            if (root.pendingNoteId) {
                Notes.updateNote(root.pendingNoteId, root.editingText.trim())
            } else {
                Notes.addNote(root.editingText.trim())
            }
        }
        toggleFlip()
    }

    Item {
        id: cardWrapper
        anchors.fill: parent

        transform: Scale {
            id: flipScale
            origin.x: cardWrapper.width  / 2
            origin.y: cardWrapper.height / 2
            xScale: 1
        }

        SequentialAnimation {
            id: flipAnim
            NumberAnimation {
                target: flipScale; property: "xScale"
                to: 0; duration: 150; easing.type: Easing.InQuad
            }
            ScriptAction {
                script: root.mode = (root.mode === "list" ? "edit" : "list")
            }
            NumberAnimation {
                target: flipScale; property: "xScale"
                to: 1; duration: 150; easing.type: Easing.OutQuad
            }
        }

        StyledDropShadow { target: contentRect }

        Rectangle {
            id: contentRect
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            radius: Appearance.rounding?.verylarge ?? 30

            // List
            ColumnLayout {
                id: listPage
                anchors { fill: parent; margins: 12 }
                spacing: 10
                visible: root.mode === "list"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.topMargin: -4
                        Layout.leftMargin: 8
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                        text: "Notes"
                    }
                    Item { Layout.fillWidth: true }

                    ToolbarPairedFab {
                        Layout.rightMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "add"
                        onClicked: root.openNewNote()

                        StyledToolTip {
                            text: Translation.tr("New note")
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Empty placeholder
                    Item {
                        anchors.fill: parent
                        visible: (Notes.list ?? []).length === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                iconSize: 38
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.4
                                text: "edit_note"
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.65
                                text: Translation.tr("No notes yet")
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.45
                                text: Translation.tr("Click + to write a note")
                            }
                        }
                    }

                    StyledListView {
                        id: notesListView
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        visible: (Notes.list ?? []).length > 0
                        model: (Notes.list ?? []).slice(0).sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0))

                        delegate: SwipeDelegate {
                            id: noteCard
                            required property var modelData
                            required property int index

                            width: notesListView.width
                            implicitHeight: 56
                            padding: 0
                            background: null
                            clip: true

                            property color bg: {
                                const cyclePos = index % 3
                                if (cyclePos === 0) return Appearance.colors.colPrimary
                                if (cyclePos === 1) return Appearance.colors.colSecondary
                                return Appearance.colors.colTertiary
                            }
                            property color fg: {
                                const cyclePos = index % 3
                                if (cyclePos === 0) return Appearance.colors.colOnPrimary
                                if (cyclePos === 1) return Appearance.colors.colOnSecondary
                                return Appearance.colors.colOnTertiary
                            }

                            onClicked: root.openNote(noteCard.modelData)

                            contentItem: Rectangle {
                                id: cardBg
                                radius: Appearance.rounding.normal
                                color: noteCard.bg
                                width: parent.width - Math.abs(noteCard.swipe.position) * 6

                                readonly property var lines: (noteCard.modelData.content ?? "").split("\n").filter(l => l.trim().length > 0)
                                readonly property string titleText: lines.length > 0 ? lines[0] : (noteCard.modelData.content ?? "")
                                readonly property string bodyText: lines.length > 1 ? lines.slice(1).join(" ") : ""
                                readonly property bool hasBody: bodyText.length > 0

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 12; rightMargin: 8
                                        topMargin: 4; bottomMargin: 4
                                    }
                                    spacing: 4

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            color: noteCard.fg
                                            text: cardBg.titleText
                                            font.weight: Font.DemiBold
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            color: noteCard.fg
                                            opacity: 0.65
                                            text: cardBg.hasBody ? cardBg.bodyText : root.formatTime(noteCard.modelData.createdAt)
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }

                                    RippleButton {
                                        id: copyBtn
                                        padding: 0
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        Layout.alignment: Qt.AlignVCenter
                                        buttonRadius: 14
                                        colBackground: "transparent"
                                        colBackgroundHover: ColorUtils.transparentize(noteCard.fg, 0.8)
                                        colRipple: ColorUtils.transparentize(noteCard.fg, 0.6)
                                        property bool justCopied: false

                                        Timer {
                                            id: resetCopyTimer
                                            interval: 1200
                                            onTriggered: copyBtn.justCopied = false
                                        }

                                        onClicked: {
                                            Quickshell.clipboardText = noteCard.modelData.content
                                            justCopied = true
                                            resetCopyTimer.restart()
                                        }

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: copyBtn.justCopied ? "check" : "content_copy"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: noteCard.fg
                                        }

                                        StyledToolTip {
                                            text: copyBtn.justCopied ? Translation.tr("Copied!") : Translation.tr("Copy note")
                                        }
                                    }

                                    RippleButton {
                                        id: deleteBtn
                                        padding: 0
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        Layout.alignment: Qt.AlignVCenter
                                        buttonRadius: 14
                                        colBackground: "transparent"
                                        colBackgroundHover: ColorUtils.transparentize(noteCard.fg, 0.8)
                                        colRipple: ColorUtils.transparentize(noteCard.fg, 0.6)
                                        onClicked: Notes.deleteNote(noteCard.modelData.id)

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            text: "delete"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: noteCard.fg
                                        }

                                        StyledToolTip {
                                            text: Translation.tr("Delete note")
                                        }
                                    }
                                }
                            }

                            swipe.right: Rectangle {
                                width: 64
                                anchors.right: parent.right
                                height: parent.height
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colError

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnError
                                }

                                SwipeDelegate.onClicked: Notes.deleteNote(noteCard.modelData.id)
                            }
                        }
                    }
                }
            }

            // Edit
            ColumnLayout {
                id: editPage
                anchors { fill: parent; margins: 12 }
                spacing: 8
                visible: root.mode === "edit"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RippleButton {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.85)
                        colRipple: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.7)
                        onClicked: root.toggleFlip()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.normal
                            text: "arrow_back"
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledToolTip {
                            text: Translation.tr("Back")
                        }
                    }

                    StyledText {
                        Layout.leftMargin: 4
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                        text: root.pendingNoteId ? Translation.tr("Edit Note") : Translation.tr("New Note")
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        visible: root.pendingNoteId !== null
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                        colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                        onClicked: root.deleteCurrentAndBack()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.normal
                            text: "delete"
                            color: Appearance.colors.colError
                        }

                        StyledToolTip {
                            text: Translation.tr("Delete note")
                        }
                    }

                    ToolbarPairedFab {
                        Layout.rightMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "save"
                        onClicked: root.saveAndBack()

                        StyledToolTip {
                            text: Translation.tr("Save note")
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            TextArea {
                                id: editTextArea
                                width: parent.width
                                text: root.editingText
                                wrapMode: TextArea.Wrap
                                placeholderText: Translation.tr("Type your note here...")
                                placeholderTextColor: Appearance.colors.colSubtext
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.normal
                                background: null
                                selectByMouse: true
                                onTextChanged: root.editingText = text
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: `${root.editingText.trim().length} chars`
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: `${root.editingText.trim().split(/\s+/).filter(Boolean).length} words`
                            }
                        }
                    }
                }
            }
        }
    }
}