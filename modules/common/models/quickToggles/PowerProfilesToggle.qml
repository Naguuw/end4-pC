import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Power Profile")
    toggled: PowerProfileService.activeProfile !== "balanced"
    icon: PowerProfileService.icon
    statusText: PowerProfileService.statusText
    tooltipText: PowerProfileService.tooltipText
    mainAction: () => PowerProfileService.cycle()
}
