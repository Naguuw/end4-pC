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

AbstractBackgroundWidget {
    id: root
    configEntryName: "todo"
    hoverEnabled: true

    readonly property real cardWidth: 276
    readonly property real cardHeight: 120
    readonly property real cardSpacing: 12

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight * 2 + root.cardSpacing

    property string mode: "list" // "list" | "edit"
    property var pendingTaskIndex: null
    property string editingText: ""
    onModeChanged: {
        GlobalStates.desktopWidgetKeyboardFocus = (mode === "edit")
        if (mode === "edit") {
            Qt.callLater(() => {
                editTextArea.forceActiveFocus()
                editTextArea.cursorPosition = editTextArea.text.length
            })
        }
    }

    function toggleFlip() { flipAnim.start() }

    function openNewTask() {
        root.pendingTaskIndex = null
        root.editingText = ""
        toggleFlip()
    }

    function openTask(task) {
        root.pendingTaskIndex = task.originalIndex
        root.editingText = task.content
        toggleFlip()
    }

    function deleteCurrentAndBack() {
        if (root.pendingTaskIndex !== null) {
            Todo.deleteItem(root.pendingTaskIndex)
            root.pendingTaskIndex = null
        }
        toggleFlip()
    }

    function saveAndBack() {
        if (root.editingText.trim().length > 0) {
            if (root.pendingTaskIndex !== null) {
                Todo.updateTask(root.pendingTaskIndex, root.editingText.trim())
            } else {
                Todo.addTask(root.editingText.trim())
            }
        }
        toggleFlip()
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

        StyledDropShadow { target: contentRect }

        Rectangle {
            id: contentRect
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            radius: Appearance.rounding?.verylarge ?? 30

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

            // List
            ColumnLayout {
                id: listPage
                anchors { fill: parent; margins: 12 }
                spacing: 10
                visible: root.mode === "list"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.topMargin: -4
                        Layout.leftMargin: 8
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                        text: "To-Do"
                    }
                    Item { Layout.fillWidth: true }

                    ToolbarPairedFab {
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "delete_sweep"
                        visible: opacity > 0
                        opacity: (Todo.list ?? []).some(t => t.done) ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        onClicked: Todo.clearDone()

                        StyledToolTip {
                            text: Translation.tr("Clear completed tasks")
                        }
                    }

                    ToolbarPairedFab {
                        Layout.rightMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "add"
                        onClicked: root.openNewTask()

                        StyledToolTip {
                            text: Translation.tr("Add task")
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Empty placeholder
                    Item {
                        anchors.fill: parent
                        visible: (Todo.list ?? []).length === 0

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                iconSize: 38
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.4
                                text: "checklist"
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.65
                                text: Translation.tr("No tasks yet")
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.45
                                text: Translation.tr("Click + to add a task")
                            }
                        }
                    }

                    StyledListView {
                        id: todoListView
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        visible: (Todo.list ?? []).length > 0
                        model: (Todo.list ?? [])
                            .map((item, i) => Object.assign({}, item, { originalIndex: i }))
                            .sort((a, b) => (a.done === b.done ? 0 : a.done ? 1 : -1))

                        delegate: SwipeDelegate {
                            id: taskCard
                            required property var modelData
                            required property int index

                            width: todoListView.width
                            implicitHeight: 56
                            padding: 0
                            background: null
                            clip: true

                            property color bg: {
                                const cyclePos = index % 3
                                if (cyclePos === 0) return Appearance.colors.colPrimary
                                if (cyclePos === 1) return Appearance.colors.colSecondary
                                return Appearance.colors.colTertiary
                            }
                            property color fg: {
                                const cyclePos = index % 3
                                if (cyclePos === 0) return Appearance.colors.colOnPrimary
                                if (cyclePos === 1) return Appearance.colors.colOnSecondary
                                return Appearance.colors.colOnTertiary
                            }

                            onClicked: root.openTask(taskCard.modelData)

                            contentItem: Rectangle {
                                id: cardBg
                                radius: Appearance.rounding.normal
                                color: taskCard.bg
                                width: parent.width - Math.abs(taskCard.swipe.position) * 6
                                opacity: taskCard.modelData.done ? 0.6 : 1

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 12; rightMargin: 12
                                        topMargin: 4; bottomMargin: 4
                                    }
                                    spacing: 8

                                    RippleButton {
                                        id: checkBtn
                                        padding: 0
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        buttonRadius: Appearance.rounding.full
                                        border: true
                                        borderWidth: 2
                                        colBorder: taskCard.fg
                                        colBackground: taskCard.modelData.done
                                            ? ColorUtils.transparentize(taskCard.fg, 0.8)
                                            : "transparent"
                                        colBackgroundHover: ColorUtils.transparentize(taskCard.fg, 0.75)
                                        colRipple: ColorUtils.transparentize(taskCard.fg, 0.6)
                                        onClicked: {
                                            if (taskCard.modelData.done)
                                                Todo.markUnfinished(taskCard.modelData.originalIndex)
                                            else
                                                Todo.markDone(taskCard.modelData.originalIndex)
                                        }

                                        contentItem: MaterialSymbol {
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            visible: taskCard.modelData.done
                                            text: "check"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: taskCard.fg
                                        }

                                        StyledToolTip {
                                            text: taskCard.modelData.done ? Translation.tr("Mark unfinished") : Translation.tr("Mark done")
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        color: taskCard.fg
                                        text: taskCard.modelData.content
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.strikeout: taskCard.modelData.done
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            swipe.right: Rectangle {
                                width: 64
                                anchors.right: parent.right
                                height: parent.height
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colError

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnError
                                }

                                SwipeDelegate.onClicked: Todo.deleteItem(taskCard.modelData.originalIndex)
                            }
                        }
                    }
                }
            }

            // Edit
            ColumnLayout {
                id: editPage
                anchors { fill: parent; margins: 12 }
                spacing: 8
                visible: root.mode === "edit"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RippleButton {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.85)
                        colRipple: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.7)
                        onClicked: root.toggleFlip()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.normal
                            text: "arrow_back"
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledToolTip {
                            text: Translation.tr("Back")
                        }
                    }

                    StyledText {
                        Layout.leftMargin: 4
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                        text: root.pendingTaskIndex !== null ? Translation.tr("Edit Task") : Translation.tr("New Task")
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        visible: root.pendingTaskIndex !== null
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                        colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                        onClicked: root.deleteCurrentAndBack()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.normal
                            text: "delete"
                            color: Appearance.colors.colError
                        }

                        StyledToolTip {
                            text: Translation.tr("Delete task")
                        }
                    }

                    ToolbarPairedFab {
                        Layout.rightMargin: 4
                        Layout.alignment: Qt.AlignVCenter
                        baseSize: 38
                        iconText: "save"
                        onClicked: root.saveAndBack()

                        StyledToolTip {
                            text: Translation.tr("Save task")
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            TextArea {
                                id: editTextArea
                                width: parent.width
                                text: root.editingText
                                wrapMode: TextArea.Wrap
                                placeholderText: Translation.tr("Type your task here...")
                                placeholderTextColor: Appearance.colors.colSubtext
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.normal
                                background: null
                                selectByMouse: true
                                onTextChanged: root.editingText = text
                                Keys.onReturnPressed: (event) => {
                                    if (event.modifiers === Qt.NoModifier) {
                                        root.saveAndBack()
                                        event.accepted = true
                                    } else {
                                        event.accepted = false
                                    }
                                }
                                Keys.onEnterPressed: (event) => {
                                    if (event.modifiers === Qt.NoModifier) {
                                        root.saveAndBack()
                                        event.accepted = true
                                    } else {
                                        event.accepted = false
                                    }
                                }
                                Keys.onEscapePressed: (event) => {
                                    root.toggleFlip()
                                    event.accepted = true
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: `${root.editingText.trim().length} chars`
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: `${root.editingText.trim().split(/\s+/).filter(Boolean).length} words`
                            }
                        }
                    }
                }
            }
        }
    }
}