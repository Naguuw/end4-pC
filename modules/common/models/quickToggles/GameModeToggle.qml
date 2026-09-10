import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.modules.common.models.hyprland
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: confOpt.value !== undefined ? !confOpt.value : false
    icon: "gamepad"

    mainAction: () => {
        const nextState = !root.toggled;
        root.toggled = nextState;
        if (nextState) {
            HyprlandConfig.setMany({
                "animations:enabled": 0,
                "general:gaps_in": 0,
                "general:gaps_out": 0,
                "general:border_size": 1,
                "decoration:rounding": 0,
                "general:allow_tearing": 1
            });
        } else {
            const h = Config.options.hyprland;
            HyprlandConfig.setMany({
                "animations:enabled": h.animations.enable ? 1 : 0,
                "general:gaps_in": h.general.gapsIn,
                "general:gaps_out": h.general.gapsOut,
                "general:border_size": h.general.borderSize,
                "decoration:rounding": h.decoration.rounding
            }, ["general:allow_tearing"]);
        }
    }

    HyprlandConfigOption {
        id: confOpt
        key: "animations:enabled"
        onValueChanged: {
            if (confOpt.value !== undefined) {
                root.toggled = !confOpt.value;
            }
        }
    }

    tooltipText: Translation.tr("Game mode")
}
