pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets

Item {
    id: root

    readonly property int columns: 2
    readonly property int maxRows: 4
    readonly property int presetCount: Presets.folderModel.count
    readonly property int visibleRows: Math.min(maxRows, Math.max(1, Math.ceil(presetCount / columns)))
    readonly property int gridTopMargin: 8
    implicitHeight: presetCount === 0
        ? emptyText.implicitHeight + 40
        : gridTopMargin * 2 + visibleRows * grid.cellHeight

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    StyledText {
        id: emptyText
        visible: root.presetCount === 0
        anchors { fill: parent; margins: 12 }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: Appearance.colors.colOnLayer1
        opacity: 0.6
        text: Translation.tr("No presets yet")
    }

    GridView {
        id: grid
        visible: root.presetCount > 0
        anchors.fill: parent
        anchors.margins: root.gridTopMargin
        clip: true
        cellWidth: width / root.columns
        cellHeight: 124
        model: Presets.folderModel
        boundsBehavior: Flickable.StopAtBounds
        maximumFlickVelocity: 3000
        ScrollIndicator.vertical: ScrollIndicator {}

        delegate: Item {
            id: tileWrapper
            required property string fileName
            required property string filePath

            property string presetRawWallpaper: ""
            property string presetThumbnail: ""
            readonly property string presetName: fileName.replace(/\.json$/, "")
            readonly property string imageSource: presetThumbnail !== "" ? presetThumbnail : presetRawWallpaper

            width: grid.cellWidth
            height: grid.cellHeight

            FileView {
                path: tileWrapper.filePath
                onLoaded: {
                    try {
                        const data = JSON.parse(text())
                        const rawWallpaper = data?.background?.wallpaperPath ?? ""
                        const isVideo = /\.(mp4|webm|mkv|avi|mov)$/i.test(rawWallpaper)
                        tileWrapper.presetRawWallpaper = rawWallpaper
                        tileWrapper.presetThumbnail = isVideo ? (data?.background?.thumbnailPath ?? "") : rawWallpaper
                    } catch (e) {
                        console.log("Failed to parse preset:", e)
                    }
                }
            }

            RippleButton {
                id: tile
                anchors.fill: parent
                anchors.margins: 4
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colPrimary

                contentItem: ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    Item {
                        id: imageRect
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer2

                            StyledImage {
                                anchors.fill: parent
                                visible: tileWrapper.imageSource !== ""
                                fillMode: Image.PreserveAspectCrop
                                source: tileWrapper.imageSource !== "" ? "file://" + FileUtils.trimFileProtocol(tileWrapper.imageSource) : ""
                                cache: false
                                antialiasing: true
                                sourceSize.width: imageRect.width * 2
                                sourceSize.height: imageRect.height * 2
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: tileWrapper.imageSource === ""
                                text: "wallpaper"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: tileWrapper.presetName
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: tile.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                onClicked: {
                    GlobalStates.desktopMenuOpen = false
                    Presets.apply(tileWrapper.presetName, tileWrapper.presetRawWallpaper)
                }
            }
        }
    }
}
