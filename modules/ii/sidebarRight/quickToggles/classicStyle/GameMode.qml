import qs.modules.common.models.quickToggles
import qs.modules.common.widgets

QuickToggleButton {
    id: root

    property QuickToggleModel toggleModel: GameModeToggle {}

    buttonIcon: toggleModel.icon
    toggled: toggleModel.toggled

    onClicked: toggleModel.mainAction()

    StyledToolTip {
        text: toggleModel.tooltipText
    }
}
