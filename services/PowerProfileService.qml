pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import QtQuick
import Quickshell.Io

Singleton {
    id: root

    // "power-saver" | "balanced" | "performance"
    property string activeProfile: "balanced"

    readonly property string icon: switch(activeProfile) {
        case "power-saver":
        case "powersave":
        case "eco": return "energy_savings_leaf"
        case "balanced": return "airwave"
        case "performance": return "local_fire_department"
        default: return "airwave"
    }

    readonly property string statusText: switch(activeProfile) {
        case "power-saver":
        case "powersave":
        case "eco": return Translation.tr("Power Saver")
        case "balanced": return Translation.tr("Balanced")
        case "performance": return Translation.tr("Performance")
        default: return Translation.tr("Balanced")
    }

    readonly property string tooltipText: Translation.tr("Click to cycle through power profiles")

    function setProfile(profile) {
        root.activeProfile = profile
        Quickshell.execDetached([Directories.powerProfileScriptPath, profile])
    }

    function cycle() {
        let nextProfile = "balanced"
        switch(root.activeProfile) {
            case "power-saver":
            case "powersave":
            case "eco": nextProfile = "balanced"; break;
            case "balanced": nextProfile = "performance"; break;
            case "performance": nextProfile = "power-saver"; break;
            default: nextProfile = "balanced"; break;
        }
        root.setProfile(nextProfile)
    }

    Component.onCompleted: {
        Quickshell.exec([Directories.powerProfileScriptPath, "get"], (output) => {
            let p = output.trim()
            if (p === "power-saver" || p === "powersave" || p === "eco" || p === "balanced" || p === "performance") {
                root.activeProfile = (p === "eco" || p === "powersave") ? "power-saver" : p
            }
        })
    }
}
