pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland

Variants {
    id: wallpaperBackdropRoot
    model: Quickshell.screens

    Loader {
        id: loader
        required property var modelData
        active: WM.compositor === "niri"

        sourceComponent: PanelWindow {
            id: backdrop
            screen: loader.modelData

            property string wallpaperPath: Config.options.background.wallpaperPath

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:wallpaper"
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Item {
                id: sourceImage
                anchors.fill: parent
                clip: true
                visible: false
                layer.enabled: true

                Image {
                    source: backdrop.wallpaperPath
                    fillMode: Image.Stretch
                    asynchronous: true
                    cache: true
                    smooth: true

                    readonly property real baseScale: {
                        if (sourceSize.width <= 0 || sourceSize.height <= 0 || sourceImage.width <= 0 || sourceImage.height <= 0) return 1.0;
                        return Math.max(sourceImage.width / sourceSize.width, sourceImage.height / sourceSize.height) * (Config.options.background.wallpaperScale ?? 1.0);
                    }
                    width: sourceSize.width > 0 ? Math.ceil(sourceSize.width * baseScale) : sourceImage.width
                    height: sourceSize.height > 0 ? Math.ceil(sourceSize.height * baseScale) : sourceImage.height

                    x: Math.round((sourceImage.width - width) * (Config.options.background.wallpaperOffsetX ?? 0.5))
                    y: Math.round((sourceImage.height - height) * (Config.options.background.wallpaperOffsetY ?? 0.5))
                }
            }

            FastBlur {
                anchors.fill: parent
                source: sourceImage
                radius: 48 // fixme variable
                transparentBorder: false
            }
        }
    }
}
