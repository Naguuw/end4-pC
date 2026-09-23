import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.calendar

Item {
    id: root
    anchors.fill: parent

    property int fabMargins: 14
    property bool showDialog: false

    readonly property var dayNames: [
        Translation.tr("Monday"),
        Translation.tr("Tuesday"),
        Translation.tr("Wednesday"),
        Translation.tr("Thursday"),
        Translation.tr("Friday"),
        Translation.tr("Saturday"),
        Translation.tr("Sunday")
    ]
    readonly property var shortDayNames: [
        Translation.tr("Mo"),
        Translation.tr("Tu"),
        Translation.tr("We"),
        Translation.tr("Th"),
        Translation.tr("Fr"),
        Translation.tr("Sa"),
        Translation.tr("Su")
    ]

    readonly property int todayDayIndex: {
        const d = DateTime.clock.date.getDay()
        return (d + 6) % 7
    }

    property int selectedDay: root.todayDayIndex
    property int currentDayWatch: root.todayDayIndex
    onCurrentDayWatchChanged: {
        root.selectedDay = root.todayDayIndex
    }

    // Editing state
    property var editingId: null
    property int editingDay: root.selectedDay
    property string editingTitle: ""
    property string editingStartTime: ""
    property string editingEndTime: ""
    property string editingRoom: ""
    property string editingLecturer: ""

    function parseTimeString(str) {
        if (!str) return { valid: false, formatted: "", minutes: -1 }
        const clean = str.replace(/[^0-9]/g, "")
        let h = -1, m = -1
        if (clean.length === 3) {
            h = parseInt(clean.substring(0, 1), 10)
            m = parseInt(clean.substring(1, 3), 10)
        } else if (clean.length === 4) {
            h = parseInt(clean.substring(0, 2), 10)
            m = parseInt(clean.substring(2, 4), 10)
        } else if (str.indexOf(":") !== -1) {
            const parts = str.split(":")
            h = parseInt(parts[0], 10)
            m = parseInt(parts[1], 10)
        }
        if (isNaN(h) || isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) {
            return { valid: false, formatted: "", minutes: -1 }
        }
        const formatted = (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m)
        return { valid: true, formatted: formatted, minutes: h * 60 + m }
    }

    readonly property var parsedStart: parseTimeString(root.editingStartTime)
    readonly property var parsedEnd: parseTimeString(root.editingEndTime)

    readonly property bool isFormValid: {
        if (root.editingTitle.trim().length === 0) return false
        if (!root.parsedStart.valid) return false
        if (!root.parsedEnd.valid) return false
        if (root.parsedEnd.minutes <= root.parsedStart.minutes) return false
        return true
    }

    function openAddDialog() {
        root.editingId = null
        root.editingDay = root.selectedDay
        root.editingTitle = ""
        root.editingStartTime = ""
        root.editingEndTime = ""
        root.editingRoom = ""
        root.editingLecturer = ""
        root.showDialog = true
    }

    function openEditDialog(item) {
        root.editingId = item.id
        root.editingDay = item.day
        root.editingTitle = item.title ?? ""
        root.editingStartTime = item.startTime ?? ""
        root.editingEndTime = item.endTime ?? ""
        root.editingRoom = item.room ?? ""
        root.editingLecturer = item.lecturer ?? ""
        root.showDialog = true
    }

    function saveSchedule() {
        if (!root.isFormValid) return

        const formattedStart = root.parsedStart.formatted
        const formattedEnd = root.parsedEnd.formatted

        if (root.editingId) {
            Schedule.updateItem(
                root.editingId,
                root.editingDay,
                root.editingTitle.trim(),
                formattedStart,
                formattedEnd,
                root.editingRoom.trim(),
                root.editingLecturer.trim(),
                ""
            )
        } else {
            Schedule.addItem(
                root.editingDay,
                root.editingTitle.trim(),
                formattedStart,
                formattedEnd,
                root.editingRoom.trim(),
                root.editingLecturer.trim(),
                ""
            )
        }
        root.showDialog = false
    }

    function deleteSchedule() {
        if (root.editingId) {
            Schedule.deleteItem(root.editingId)
        }
        root.showDialog = false
    }

    function timeToMinutes(timeStr) {
        if (!timeStr || timeStr.indexOf(":") === -1) return -1
        const parts = timeStr.split(":")
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10)
    }

    function getClassStatus(item) {
        if (root.selectedDay !== root.todayDayIndex) return "none"
        const nowMinutes = DateTime.hour24 * 60 + DateTime.clock.date.getMinutes()
        const startMinutes = timeToMinutes(item.startTime)
        const endMinutes = timeToMinutes(item.endTime)
        if (startMinutes < 0 || endMinutes < 0) return "none"

        if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
            return "ongoing"
        } else if (nowMinutes < startMinutes && (startMinutes - nowMinutes) <= 60) {
            return "upcoming"
        } else if (nowMinutes >= endMinutes) {
            return "passed"
        }
        return "none"
    }

    function getUpcomingDiff(item) {
        const nowMinutes = DateTime.hour24 * 60 + DateTime.clock.date.getMinutes()
        const startMinutes = timeToMinutes(item.startTime)
        return Math.max(0, startMinutes - nowMinutes)
    }

    function cleanSingleLine(text) {
        if (!text) return ""
        return String(text)
            .replace(/,\s*<br\s*\/?>/gi, ", ")
            .replace(/<br\s*\/?>/gi, ", ")
            .replace(/[\r\n]+/g, ", ")
            .replace(/<[^>]*>/g, "")
            .replace(/\s+/g, " ")
            .replace(/,\s*,/g, ",")
            .trim()
    }

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.selectedDay = (root.selectedDay + 1) % 7
            } else if (event.key === Qt.Key_PageUp) {
                root.selectedDay = (root.selectedDay + 6) % 7
            }
            event.accepted = true
        } else if (event.key === Qt.Key_N && !root.showDialog) {
            root.openAddDialog()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && root.showDialog) {
            root.showDialog = false
            event.accepted = true
        }
    }

    // ==================== MAIN CONTENT ====================
    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 10
        spacing: 6

        // Minimalist Top Navigation Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            CalendarHeaderButton {
                clip: true
                buttonText: `${root.selectedDay !== root.todayDayIndex ? "• " : ""}${root.dayNames[root.selectedDay] ?? "Monday"}`
                tooltipText: root.selectedDay !== root.todayDayIndex ? Translation.tr("Jump to today") : ""
                downAction: () => {
                    root.selectedDay = root.todayDayIndex;
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    root.selectedDay = (root.selectedDay + 6) % 7;
                }
                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    root.selectedDay = (root.selectedDay + 1) % 7;
                }
                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // Clean Weekday Strip (Mo, Tu, We, Th, Fr, Sa, Su)
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: 7
                delegate: Item {
                    id: dayCell
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 28

                    readonly property bool isSelected: dayCell.index === root.selectedDay
                    readonly property bool isToday: dayCell.index === root.todayDayIndex
                    readonly property bool hasClasses: Schedule.hasScheduleOnDay(dayCell.index)

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: dayCell.isSelected
                            ? Appearance.colors.colPrimary
                            : (dayCell.isToday
                                ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)
                                : Appearance.colors.colLayer2)

                        border.width: dayCell.isToday && !dayCell.isSelected ? 1 : 0
                        border.color: Appearance.colors.colPrimary

                        StyledText {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: dayCell.hasClasses ? -2 : 0
                            text: root.shortDayNames[dayCell.index] ?? ""
                            font.pixelSize: 11
                            font.weight: dayCell.isSelected || dayCell.isToday ? Font.Bold : Font.Normal
                            color: dayCell.isSelected
                                ? Appearance.colors.colOnPrimary
                                : (dayCell.isToday
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext)
                        }

                        // Class presence indicator dot
                        Rectangle {
                            visible: dayCell.hasClasses
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                bottom: parent.bottom
                                bottomMargin: 3
                            }
                            width: 3
                            height: 3
                            radius: 1.5
                            color: dayCell.isSelected
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedDay = dayCell.index
                    }
                }
            }
        }

        // Classes List View
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty state placeholder
            Item {
                anchors.fill: parent
                visible: Schedule.getScheduleForDay(root.selectedDay).length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        iconSize: 40
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.3
                        text: "event_available"
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.7
                        text: Translation.tr("No Classes Today")
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        opacity: 0.6
                        text: Translation.tr("Free day! Tap + to add schedule")
                    }
                }
            }

            // Course items
            StyledListView {
                id: scheduleListView
                anchors.fill: parent
                clip: true
                spacing: 6
                visible: Schedule.getScheduleForDay(root.selectedDay).length > 0
                model: Schedule.getScheduleForDay(root.selectedDay)

                // Extra padding at bottom so FAB doesn't obscure the last card
                bottomMargin: fabButton.baseSize + root.fabMargins

                delegate: Rectangle {
                    id: classCard
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    implicitHeight: 52
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    opacity: classCard.isPassed ? 0.55 : 1

                    readonly property string status: root.getClassStatus(classCard.modelData)
                    readonly property bool isOngoing: status === "ongoing"
                    readonly property bool isUpcoming: status === "upcoming"
                    readonly property bool isPassed: status === "passed"

                    property color accentColor: {
                        const cycle = index % 3
                        if (cycle === 0) return Appearance.colors.colPrimary
                        if (cycle === 1) return Appearance.colors.colSecondary
                        return Appearance.colors.colTertiary
                    }

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            margins: 8
                        }
                        spacing: 8

                        // Vertical color bar
                        Rectangle {
                            Layout.preferredWidth: 3
                            Layout.minimumWidth: 3
                            Layout.maximumWidth: 3
                            Layout.fillHeight: true
                            radius: 1.5
                            color: classCard.accentColor
                        }

                        // Time Column
                        ColumnLayout {
                            Layout.preferredWidth: 48
                            Layout.minimumWidth: 48
                            Layout.maximumWidth: 48
                            Layout.alignment: Qt.AlignVCenter
                            spacing: -2

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer1
                                text: classCard.modelData.startTime || "--:--"
                            }

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: 10
                                color: Appearance.colors.colSubtext
                                text: classCard.modelData.endTime || "--:--"
                            }
                        }

                        // Course & Details
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    Layout.fillWidth: true
                                    color: Appearance.colors.colOnLayer1
                                    text: root.cleanSingleLine(classCard.modelData.title || "")
                                    textFormat: Text.PlainText
                                    font.weight: Font.DemiBold
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                // LIVE ongoing badge
                                Rectangle {
                                    visible: classCard.isOngoing
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colPrimary
                                    implicitWidth: ongoingText.implicitWidth + 8
                                    implicitHeight: 15

                                    StyledText {
                                        id: ongoingText
                                        anchors.centerIn: parent
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimary
                                        text: Translation.tr("LIVE")
                                    }
                                }

                                // Upcoming countdown badge
                                Rectangle {
                                    visible: classCard.isUpcoming
                                    radius: Appearance.rounding.full
                                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                                    implicitWidth: upcomingText.implicitWidth + 8
                                    implicitHeight: 15

                                    StyledText {
                                        id: upcomingText
                                        anchors.centerIn: parent
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colPrimary
                                        text: root.getUpcomingDiff(classCard.modelData) + "m"
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Room
                                RowLayout {
                                    visible: (classCard.modelData.room || "").length > 0
                                    Layout.preferredWidth: 54
                                    Layout.minimumWidth: 54
                                    Layout.maximumWidth: 54
                                    spacing: 2

                                    MaterialSymbol {
                                        text: "location_on"
                                        iconSize: 11
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        font.pixelSize: 10
                                        color: Appearance.colors.colSubtext
                                        text: root.cleanSingleLine(classCard.modelData.room || "")
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }

                                // Lecturer
                                RowLayout {
                                    visible: (classCard.modelData.lecturer || "").length > 0
                                    Layout.fillWidth: true
                                    spacing: 2

                                    MaterialSymbol {
                                        text: "person"
                                        iconSize: 11
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        font.pixelSize: 10
                                        color: Appearance.colors.colSubtext
                                        text: root.cleanSingleLine(classCard.modelData.lecturer || "")
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        z: -1
                        onClicked: root.openEditDialog(classCard.modelData)
                    }
                }
            }
        }
    }

    // ==================== + FAB (Matching To Do) ====================
    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: fabButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins

        onClicked: root.openAddDialog()
        iconText: "add"
    }

    // ==================== CLEAN MODAL DIALOG (Matching To Do) ====================
    Item {
        id: dialogOverlay
        anchors.fill: parent
        z: 9999
        visible: opacity > 0
        opacity: root.showDialog ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        // Scrim
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                propagateComposedEvents: false
                onClicked: root.showDialog = false
            }
        }

        // Modal Card
        Rectangle {
            id: dialogCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 16
            implicitHeight: dialogCol.implicitHeight + 24
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                propagateComposedEvents: false
            }

            ColumnLayout {
                id: dialogCol
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 10

                // Dialog Header
                StyledText {
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Bold
                    text: root.editingId ? Translation.tr("Edit Class") : Translation.tr("New Class")
                }

                // Day Selector Row
                Row {
                    Layout.fillWidth: true
                    spacing: 3

                    Repeater {
                        model: 7
                        delegate: Rectangle {
                            id: dayDialogBtn
                            required property int index
                            width: (dialogCol.width - (6 * 3)) / 7
                            height: 24
                            radius: 12
                            color: root.editingDay === dayDialogBtn.index
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer2

                            StyledText {
                                anchors.centerIn: parent
                                text: root.shortDayNames[dayDialogBtn.index] ?? ""
                                font.pixelSize: 10
                                font.weight: root.editingDay === dayDialogBtn.index ? Font.Bold : Font.Normal
                                color: root.editingDay === dayDialogBtn.index
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colSubtext
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editingDay = dayDialogBtn.index
                            }
                        }
                    }
                }

                // Course Name Field
                TextField {
                    id: courseInput
                    Layout.fillWidth: true
                    padding: 8
                    text: root.editingTitle
                    color: Appearance.m3colors.m3onSurface
                    renderType: Text.NativeRendering
                    placeholderText: Translation.tr("Course name...")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    font.pixelSize: 12
                    selectByMouse: true
                    onTextChanged: root.editingTitle = text

                    background: Rectangle {
                        radius: Appearance.rounding.verysmall
                        border.width: 1
                        border.color: courseInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: Appearance.colors.colLayer2
                    }
                }

                // Start & End Time Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    TextField {
                        id: startInput
                        Layout.fillWidth: true
                        padding: 8
                        text: root.editingStartTime
                        color: Appearance.m3colors.m3onSurface
                        renderType: Text.NativeRendering
                        placeholderText: "Start (07:50)"
                        placeholderTextColor: Appearance.m3colors.m3outline
                        font.pixelSize: 12
                        selectByMouse: true
                        inputMethodHints: Qt.ImhDigitsOnly
                        onTextChanged: root.editingStartTime = text

                        background: Rectangle {
                            radius: Appearance.rounding.verysmall
                            border.width: 1
                            border.color: (root.editingStartTime.length > 0 && !root.parsedStart.valid)
                                ? Appearance.colors.colError
                                : (startInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline)
                            color: Appearance.colors.colLayer2
                        }
                    }

                    TextField {
                        id: endInput
                        Layout.fillWidth: true
                        padding: 8
                        text: root.editingEndTime
                        color: Appearance.m3colors.m3onSurface
                        renderType: Text.NativeRendering
                        placeholderText: "End (10:20)"
                        placeholderTextColor: Appearance.m3colors.m3outline
                        font.pixelSize: 12
                        selectByMouse: true
                        inputMethodHints: Qt.ImhDigitsOnly
                        onTextChanged: root.editingEndTime = text

                        background: Rectangle {
                            radius: Appearance.rounding.verysmall
                            border.width: 1
                            border.color: (root.editingEndTime.length > 0 && (!root.parsedEnd.valid || root.parsedEnd.minutes <= root.parsedStart.minutes))
                                ? Appearance.colors.colError
                                : (endInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline)
                            color: Appearance.colors.colLayer2
                        }
                    }
                }

                // Room & Lecturer Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    TextField {
                        id: roomInput
                        Layout.preferredWidth: (dialogCol.width - 8) * 0.4
                        padding: 8
                        text: root.editingRoom
                        color: Appearance.m3colors.m3onSurface
                        renderType: Text.NativeRendering
                        placeholderText: Translation.tr("Room (e.g. Lab 3, Hall B)")
                        placeholderTextColor: Appearance.m3colors.m3outline
                        font.pixelSize: 12
                        selectByMouse: true
                        onTextChanged: root.editingRoom = text

                        background: Rectangle {
                            radius: Appearance.rounding.verysmall
                            border.width: 1
                            border.color: roomInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                            color: Appearance.colors.colLayer2
                        }
                    }

                    TextField {
                        id: lecturerInput
                        Layout.fillWidth: true
                        padding: 8
                        text: root.editingLecturer
                        color: Appearance.m3colors.m3onSurface
                        renderType: Text.NativeRendering
                        placeholderText: Translation.tr("Lecturer (e.g. Prof. Smith)")
                        placeholderTextColor: Appearance.m3colors.m3outline
                        font.pixelSize: 12
                        selectByMouse: true
                        onTextChanged: root.editingLecturer = text

                        background: Rectangle {
                            radius: Appearance.rounding.verysmall
                            border.width: 1
                            border.color: lecturerInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                            color: Appearance.colors.colLayer2
                        }
                    }
                }

                // Action Buttons Row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 6

                    // Delete button (visible when editing)
                    DialogButton {
                        visible: root.editingId !== null
                        buttonText: Translation.tr("Delete")
                        colEnabled: Appearance.colors.colError
                        onClicked: root.deleteSchedule()
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showDialog = false
                    }

                    DialogButton {
                        buttonText: root.editingId ? Translation.tr("Save") : Translation.tr("Add")
                        enabled: root.isFormValid
                        onClicked: root.saveSchedule()
                    }
                }
            }
        }
    }
}
