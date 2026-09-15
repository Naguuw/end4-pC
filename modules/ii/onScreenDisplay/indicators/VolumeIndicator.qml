import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay

OsdValueIndicator {
    id: osdValues
    value: Math.min(1.0, Audio.sink?.audio.volume ?? 0)
    icon: Audio.sink?.audio.muted ? "volume_off" : "volume_up"
    name: Translation.tr("Volume")
}
