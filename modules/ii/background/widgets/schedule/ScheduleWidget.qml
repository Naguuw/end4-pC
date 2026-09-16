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

//2x2
AbstractBackgroundWidget {
    id: root
    configEntryName: "schedule"
    hoverEnabled: true

    readonly property real cardWidth: 276
    readonly property real cardHeight: 120
    readonly property real cardSpacing: 12

    //2x3 coming soon
    // readonly property real cardHeight2x3: root.cardHeight * 3 + root.cardSpacing * 2

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight * 2 + root.cardSpacing

    property string mode: "list" // "list" | "edit"

    readonly property var dayNames: [
        Translation.tr("Monday"),
        Translation.tr("Tuesday"),
        Translation.tr("Wednesday"),
        Translation.tr("Thursday"),
        Translation.tr("Friday"),
        Translation.tr("Saturday"),
        Translation.tr("Sunday")
    ]
    readonly property var shortDayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    readonly property int todayDayIndex: {
        const d = DateTime.clock.date.getDay() // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
        return (d + 6) % 7 // 0 = Monday, 6 = Sunday
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
    property string editingStartTime: "08:00"
    property string editingEndTime: "09:40"
    property string editingRoom: ""
    property string editingLecturer: ""

    onModeChanged: {
        GlobalStates.desktopWidgetKeyboardFocus = (mode === "edit")
        if (mode === "edit") {
            Qt.callLater(() => {
                titleField.forceActiveFocus()
            })
        }
    }

    function toggleFlip() {
        flipAnim.start()
    }

    function openNewSchedule() {
        root.editingId = null
        root.editingDay = root.selectedDay
        root.editingTitle = ""
        root.editingStartTime = "08:00"
        root.editingEndTime = "09:40"
        root.editingRoom = ""
        root.editingLecturer = ""
        toggleFlip()
    }

    function openEditSchedule(item) {
        root.editingId = item.id
        root.editingDay = Number(item.day ?? root.selectedDay)
        root.editingTitle = item.title ?? ""
        root.editingStartTime = item.startTime ?? ""
        root.editingEndTime = item.endTime ?? ""
        root.editingRoom = item.room ?? ""
        root.editingLecturer = item.lecturer ?? ""
        toggleFlip()
    }

    function deleteCurrentAndBack() {
        if (root.editingId) {
            Schedule.deleteItem(root.editingId)
            root.editingId = null
        }
        toggleFlip()
    }

    function parseTime(input) {
        if (!input) return null
        let s = input.trim().replace(".", ":")

        // Single or double digit hour (e.g. "1" -> "01:00", "8" -> "08:00", "12" -> "12:00")
        if (/^\d{1,2}$/.test(s)) {
            let h = parseInt(s, 10)
            if (h >= 0 && h <= 23) {
                return {
                    h: h,
                    m: 0,
                    formatted: (h < 10 ? "0" + h : "" + h) + ":00",
                    minutes: h * 60
                }
            }
            return null
        }

        // 3 or 4 digits without colon (e.g. "830" -> "08:30", "1330" -> "13:30")
        if (/^\d{3,4}$/.test(s)) {
            let h = parseInt(s.slice(0, s.length - 2), 10)
            let m = parseInt(s.slice(s.length - 2), 10)
            if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
                return {
                    h: h,
                    m: m,
                    formatted: (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m),
                    minutes: h * 60 + m
                }
            }
            return null
        }

        // "H:MM" or "HH:MM"
        let parts = s.split(":")
        if (parts.length === 2) {
            let h = parseInt(parts[0], 10)
            let m = parseInt(parts[1], 10)
            if (!isNaN(h) && !isNaN(m) && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
                return {
                    h: h,
                    m: m,
                    formatted: (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m),
                    minutes: h * 60 + m
                }
            }
        }
        return null
    }

    readonly property var parsedStart: parseTime(root.editingStartTime)
    readonly property var parsedEnd: parseTime(root.editingEndTime)
    readonly property bool isStartValid: root.parsedStart !== null
    readonly property bool isEndValid: root.parsedEnd !== null
    readonly property bool isTimeOrderValid: root.isStartValid && root.isEndValid && (root.parsedStart.minutes < root.parsedEnd.minutes)
    readonly property bool isFormValid: root.editingTitle.trim().length > 0 && root.isStartValid && root.isEndValid && root.isTimeOrderValid

    function saveAndBack() {
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
        toggleFlip()
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

        StyledRectangularShadow {
            target: contentRect
            z: -2
        }

        Rectangle {
            id: contentRect
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            radius: (Appearance.rounding && Appearance.rounding.verylarge !== undefined) ? Appearance.rounding.verylarge : 30

            FastBlurred {
                anchors.fill: parent
                blurSource: root.wallpaperItem
                cardRadius: contentRect.radius
                tint: Appearance.colors.colLayer1
                tintOpacity: 0.55
                trackX: root.x
                trackY: root.y
                visible: Config.options.background.widgets.blurWidgets
            }

            // ==================== LIST VIEW (2x2) ====================
            ColumnLayout {
                id: listPage
                anchors { fill: parent; margins: 12 }
                spacing: 8
                visible: root.mode === "list"

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialShapeWrappedMaterialSymbol {
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: Appearance.colors.colPrimary
                        colSymbol: Appearance.colors.colOnPrimary
                        text: "school"
                        iconSize: 18
                        fill: 1
                        padding: 6
                        implicitWidth: 34
                        implicitHeight: 34
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: -3

                        StyledText {
                            text: Translation.tr("SCHEDULE")
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                            opacity: 0.85
                        }

                        StyledText {
                            text: root.dayNames[root.selectedDay] ?? "Monday"
                            font.pixelSize: Appearance.font.pixelSize.normal + 1
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                            elide: Text.ElideRight
                        }
                    }

                    // Uniform circular action buttons (all 28x28)
                    RowLayout {
                        spacing: 4

                        // Prev day
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: prevMouse.containsPress
                                ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.7)
                                : (prevMouse.containsMouse
                                    ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.85)
                                    : "transparent")
                            border.width: 1
                            border.color: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.75)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_left"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimaryContainer
                            }

                            MouseArea {
                                id: prevMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedDay = (root.selectedDay + 6) % 7
                            }
                        }

                        // Jump to today (if not on today)
                        Rectangle {
                            visible: root.selectedDay !== root.todayDayIndex
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: todayMouse.containsPress
                                ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                                : (todayMouse.containsMouse
                                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)
                                    : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85))
                            border.width: 1
                            border.color: Appearance.colors.colPrimary

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "today"
                                iconSize: 14
                                color: Appearance.colors.colPrimary
                            }

                            MouseArea {
                                id: todayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedDay = root.todayDayIndex
                            }
                        }

                        // Next day
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: nextMouse.containsPress
                                ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.7)
                                : (nextMouse.containsMouse
                                    ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.85)
                                    : "transparent")
                            border.width: 1
                            border.color: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.75)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "chevron_right"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimaryContainer
                            }

                            MouseArea {
                                id: nextMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedDay = (root.selectedDay + 1) % 7
                            }
                        }

                        // Add class button
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: addMouse.containsPress
                                ? Appearance.colors.colPrimaryActive
                                : (addMouse.containsMouse
                                    ? Appearance.colors.colPrimaryHover
                                    : Appearance.colors.colPrimary)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "add"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimary
                            }

                            MouseArea {
                                id: addMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNewSchedule()
                            }
                        }
                    }
                }

                // Mini Week Row (Mo, Tu, We, Th, Fr, Sa, Su)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: 7
                        delegate: Item {
                            id: dayCell
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 26

                            readonly property bool isSelected: dayCell.index === root.selectedDay
                            readonly property bool isToday: dayCell.index === root.todayDayIndex
                            readonly property bool hasClasses: Schedule.hasScheduleOnDay(dayCell.index)

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: dayCell.isSelected
                                    ? Appearance.colors.colPrimary
                                    : (dayCell.isToday
                                        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                                        : "transparent")

                                border.width: dayCell.isToday && !dayCell.isSelected ? 1 : 0
                                border.color: Appearance.colors.colPrimary

                                StyledText {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: root.shortDayNames[dayCell.index]
                                    font.pixelSize: 10
                                    font.weight: dayCell.isSelected || dayCell.isToday ? Font.Bold : Font.Normal
                                    color: dayCell.isSelected
                                        ? Appearance.colors.colOnPrimary
                                        : (dayCell.isToday
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colOnPrimaryContainer)
                                    opacity: dayCell.isSelected || dayCell.isToday ? 1.0 : 0.6
                                }

                                Rectangle {
                                    visible: dayCell.hasClasses
                                    anchors {
                                        horizontalCenter: parent.horizontalCenter
                                        bottom: parent.bottom
                                        bottomMargin: 2
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

                // Course List Body
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Empty Placeholder
                    Item {
                        anchors.fill: parent
                        visible: Schedule.getScheduleForDay(root.selectedDay).length === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                iconSize: 32
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.35
                                text: "event_available"
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
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

                    // Scheduled Classes List
                    StyledListView {
                        id: scheduleListView
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        visible: Schedule.getScheduleForDay(root.selectedDay).length > 0
                        model: Schedule.getScheduleForDay(root.selectedDay)

                        delegate: SwipeDelegate {
                            id: classCard
                            required property var modelData
                            required property int index

                            width: scheduleListView.width
                            implicitHeight: 52
                            padding: 0
                            background: null
                            clip: true

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

                            onClicked: root.openEditSchedule(classCard.modelData)

                            contentItem: Rectangle {
                                id: cardBg
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer1
                                opacity: classCard.isPassed ? 0.55 : 1

                                border.width: classCard.isOngoing ? 1.5 : 1
                                border.color: classCard.isOngoing
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer0Border

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 8; rightMargin: 8
                                        topMargin: 4; bottomMargin: 4
                                    }
                                    spacing: 8

                                    // Accent color stripe
                                    Rectangle {
                                        Layout.preferredWidth: 3
                                        Layout.minimumWidth: 3
                                        Layout.maximumWidth: 3
                                        Layout.fillHeight: true
                                        radius: 1.5
                                        color: classCard.accentColor
                                    }

                                    // Time Column (fixed width for perfect symmetry)
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
                                            color: Appearance.colors.colOnPrimaryContainer
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
                                                color: Appearance.colors.colOnPrimaryContainer
                                                text: classCard.modelData.title || ""
                                                font.weight: Font.DemiBold
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }

                                            // Ongoing live badge
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
                                                    text: "LIVE"
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

                                            // Room (fixed width so lecturer aligns symmetrically across cards)
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
                                                    text: classCard.modelData.room || ""
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
                                                    text: classCard.modelData.lecturer || ""
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            swipe.right: Rectangle {
                                visible: classCard.swipe.position < -0.05
                                width: 50
                                anchors.right: parent.right
                                height: parent.height
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colError

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnError
                                }

                                SwipeDelegate.onClicked: Schedule.deleteItem(classCard.modelData.id)
                            }
                        }
                    }
                }
            }

            // ==================== EDIT / ADD VIEW (Flip Page) ====================
            ColumnLayout {
                id: editPage
                anchors { fill: parent; margins: 12 }
                spacing: 8
                visible: root.mode === "edit"

                // Edit Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Back button
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: backMouse.containsPress
                            ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.7)
                            : (backMouse.containsMouse
                                ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.85)
                                : "transparent")
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.75)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            iconSize: 16
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        MouseArea {
                            id: backMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleFlip()
                        }
                    }

                    // Mini Cookie Badge
                    MaterialShapeWrappedMaterialSymbol {
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimary
                        colSymbol: Appearance.colors.colOnPrimary
                        text: root.editingId ? "edit" : "add"
                        iconSize: 14
                        fill: 1
                        padding: 4
                        implicitWidth: 26
                        implicitHeight: 26
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: -3

                        StyledText {
                            text: Translation.tr("CLASS DETAILS")
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                            opacity: 0.85
                        }

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                            text: root.editingId ? Translation.tr("Edit Class") : Translation.tr("New Class")
                        }
                    }

                    // Delete button (if editing)
                    Rectangle {
                        visible: root.editingId !== null
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: delMouse.containsPress
                            ? ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                            : (delMouse.containsMouse
                                ? ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                                : "transparent")
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colError, 0.75)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "delete"
                            iconSize: 16
                            color: Appearance.colors.colError
                        }

                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.deleteCurrentAndBack()
                        }
                    }

                    // Save button
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        opacity: root.isFormValid ? 1 : 0.4
                        color: !root.isFormValid
                            ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.85)
                            : (saveMouse.containsPress
                                ? Appearance.colors.colPrimaryActive
                                : (saveMouse.containsMouse
                                    ? Appearance.colors.colPrimaryHover
                                    : Appearance.colors.colPrimary))

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: 16
                            color: root.isFormValid ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }

                        MouseArea {
                            id: saveMouse
                            anchors.fill: parent
                            enabled: root.isFormValid
                            hoverEnabled: true
                            cursorShape: root.isFormValid ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.saveAndBack()
                        }
                    }
                }

                // Form Scroll Area - using rock-solid Flickable with Column
                Flickable {
                    id: formFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: formCol.implicitHeight + 8
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: formCol
                        width: formFlick.width
                        spacing: 8

                        // Day Selector Row
                        Row {
                            width: formCol.width
                            spacing: 3

                            Repeater {
                                model: 7
                                delegate: Rectangle {
                                    id: dayBtn
                                    required property int index
                                    width: (formCol.width - (6 * 3)) / 7
                                    height: 24
                                    radius: 12
                                    color: root.editingDay === dayBtn.index
                                        ? Appearance.colors.colPrimary
                                        : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)

                                    border.width: root.editingDay === dayBtn.index ? 0 : 1
                                    border.color: Appearance.colors.colLayer0Border

                                    StyledText {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: root.shortDayNames[dayBtn.index]
                                        font.pixelSize: 10
                                        font.weight: root.editingDay === dayBtn.index ? Font.Bold : Font.Normal
                                        color: root.editingDay === dayBtn.index
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnPrimaryContainer
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.editingDay = dayBtn.index
                                    }
                                }
                            }
                        }

                        // Course Title Input
                        Rectangle {
                            width: formCol.width
                            height: 34
                            radius: 10
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: titleField.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border

                            MaterialSymbol {
                                id: titleIco
                                anchors {
                                    left: parent.left
                                    leftMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "school"
                                iconSize: 15
                                color: titleField.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                            }

                            TextField {
                                id: titleField
                                anchors {
                                    left: titleIco.right
                                    leftMargin: 6
                                    right: parent.right
                                    rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                padding: 0
                                background: null
                                text: root.editingTitle
                                placeholderText: Translation.tr("Course name...")
                                placeholderTextColor: Appearance.colors.colSubtext
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: 12
                                selectByMouse: true
                                onTextChanged: root.editingTitle = text
                            }
                        }

                        // Start & End Time Row
                        Row {
                            width: formCol.width
                            spacing: 6

                            // Start Time
                            Rectangle {
                                width: (formCol.width - 6) / 2
                                height: 34
                                radius: 10
                                color: Appearance.colors.colLayer1
                                border.width: !root.isStartValid ? 1.5 : 1
                                border.color: !root.isStartValid
                                    ? Appearance.colors.colError
                                    : (startField.activeFocus
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colLayer0Border)

                                MaterialSymbol {
                                    id: startIco
                                    anchors {
                                        left: parent.left
                                        leftMargin: 8
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "schedule"
                                    iconSize: 15
                                    color: !root.isStartValid
                                        ? Appearance.colors.colError
                                        : (startField.activeFocus
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSubtext)
                                }

                                TextField {
                                    id: startField
                                    anchors {
                                        left: startIco.right
                                        leftMargin: 6
                                        right: parent.right
                                        rightMargin: 8
                                        verticalCenter: parent.verticalCenter
                                    }
                                    padding: 0
                                    background: null
                                    text: root.editingStartTime
                                    placeholderText: "08:00"
                                    placeholderTextColor: Appearance.colors.colSubtext
                                    color: !root.isStartValid ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                    font.pixelSize: 12
                                    selectByMouse: true
                                    onTextChanged: root.editingStartTime = text
                                    onEditingFinished: {
                                        const p = root.parseTime(text)
                                        if (p) root.editingStartTime = p.formatted
                                    }
                                }
                            }

                            // End Time
                            Rectangle {
                                width: (formCol.width - 6) / 2
                                height: 34
                                radius: 10
                                color: Appearance.colors.colLayer1
                                border.width: (!root.isEndValid || !root.isTimeOrderValid) ? 1.5 : 1
                                border.color: (!root.isEndValid || !root.isTimeOrderValid)
                                    ? Appearance.colors.colError
                                    : (endField.activeFocus
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colLayer0Border)

                                MaterialSymbol {
                                    id: endIco
                                    anchors {
                                        left: parent.left
                                        leftMargin: 8
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "update"
                                    iconSize: 15
                                    color: (!root.isEndValid || !root.isTimeOrderValid)
                                        ? Appearance.colors.colError
                                        : (endField.activeFocus
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSubtext)
                                }

                                TextField {
                                    id: endField
                                    anchors {
                                        left: endIco.right
                                        leftMargin: 6
                                        right: parent.right
                                        rightMargin: 8
                                        verticalCenter: parent.verticalCenter
                                    }
                                    padding: 0
                                    background: null
                                    text: root.editingEndTime
                                    placeholderText: "09:40"
                                    placeholderTextColor: Appearance.colors.colSubtext
                                    color: (!root.isEndValid || !root.isTimeOrderValid) ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                    font.pixelSize: 12
                                    selectByMouse: true
                                    onTextChanged: root.editingEndTime = text
                                    onEditingFinished: {
                                        const p = root.parseTime(text)
                                        if (p) root.editingEndTime = p.formatted
                                    }
                                }
                            }
                        }

                        // Time validation error hint
                        StyledText {
                            visible: !root.isStartValid || !root.isEndValid || !root.isTimeOrderValid
                            font.pixelSize: 10
                            color: Appearance.colors.colError
                            text: {
                                if (!root.isStartValid) return Translation.tr("Invalid start time (00:00 - 23:59)")
                                if (!root.isEndValid) return Translation.tr("Invalid end time (00:00 - 23:59)")
                                if (!root.isTimeOrderValid) return Translation.tr("End time must be after start time")
                                return ""
                            }
                        }

                        // Room Input Box
                        Rectangle {
                            width: formCol.width
                            height: 32
                            radius: 10
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: roomField.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border

                            MaterialSymbol {
                                id: roomIco
                                anchors {
                                    left: parent.left
                                    leftMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "location_on"
                                iconSize: 14
                                color: roomField.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                            }

                            TextField {
                                id: roomField
                                anchors {
                                    left: roomIco.right
                                    leftMargin: 6
                                    right: parent.right
                                    rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                padding: 0
                                background: null
                                text: root.editingRoom
                                placeholderText: Translation.tr("Room (e.g. Lab 3, Hall B)")
                                placeholderTextColor: Appearance.colors.colSubtext
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: 11
                                selectByMouse: true
                                onTextChanged: root.editingRoom = text
                            }
                        }

                        // Lecturer Input Box
                        Rectangle {
                            width: formCol.width
                            height: 32
                            radius: 10
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: lecturerField.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border

                            MaterialSymbol {
                                id: lecturerIco
                                anchors {
                                    left: parent.left
                                    leftMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "person"
                                iconSize: 14
                                color: lecturerField.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                            }

                            TextField {
                                id: lecturerField
                                anchors {
                                    left: lecturerIco.right
                                    leftMargin: 6
                                    right: parent.right
                                    rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                padding: 0
                                background: null
                                text: root.editingLecturer
                                placeholderText: Translation.tr("Lecturer (e.g. Prof. Smith)")
                                placeholderTextColor: Appearance.colors.colSubtext
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: 11
                                selectByMouse: true
                                onTextChanged: root.editingLecturer = text
                            }
                        }
                    }
                }
            }
        }
    }
}
