import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay

OsdValueIndicator {
    id: root

    readonly property real rawVolume: Audio.sink?.audio.volume ?? 0
    value: Math.min(1.0, Math.max(0.0, (rawVolume - 1.0) / 0.5))
    displayText: Math.round(rawVolume * 100)

    icon: "volume_up"
    name: Translation.tr("Volume Boost")
}
