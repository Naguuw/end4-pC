import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    property string messageId: ""
    property int messageIndex
    property var messageData
    property var messageInputField

    property real messagePadding: 7
    property real contentSpacing: 3

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false
    property string editDraft: ""

    property var messageBlocks: (root.messageData && root.messageData.content) ? StringUtils.splitMarkdownBlocks(root.messageData.content) : []
    readonly property var attachedFilePaths: (root.messageData && root.messageData.localFilePaths && root.messageData.localFilePaths.length > 0) ? root.messageData.localFilePaths : []

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.messagePadding * 2

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    function startEdit() {
        if (!root.messageData) return;
        root.editDraft = root.messageData.content ?? "";
        root.editing = true;
    }

    function cancelEdit() {
        root.editing = false;
        root.editDraft = "";
    }

    function saveMessage(resend = false) {
        if (!root.editing || !root.messageData) return;
        const newContent = root.editDraft;
        root.editing = false;
        root.messageData.content = newContent;
        root.messageData.rawContent = newContent;
        if (resend) {
            Ai.regenerate(root.messageId || root.messageIndex);
        }
    }


    ColumnLayout { // Main layout of the whole thing
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: messagePadding
        spacing: root.contentSpacing

        Rectangle {
            Layout.fillWidth: true
            implicitWidth: headerRowLayout.implicitWidth + 4 * 2
            implicitHeight: headerRowLayout.implicitHeight + 4 * 2
            color: Appearance.colors.colSecondaryContainer
            radius: Appearance.rounding.small
        
            RowLayout { // Header
                id: headerRowLayout
                anchors {
                    fill: parent
                    margins: 4
                }
                spacing: 18

                Item { // Name
                    id: nameWrapper
                    implicitHeight: Math.max(nameRowLayout.implicitHeight + 5 * 2, 30)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: nameRowLayout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillHeight: true
                            implicitWidth: messageData?.role == 'assistant' ? modelIcon.width : roleIcon.implicitWidth
                            implicitHeight: messageData?.role == 'assistant' ? modelIcon.height : roleIcon.implicitHeight

                            CustomIcon {
                                id: modelIcon
                                anchors.centerIn: parent
                                visible: messageData?.role == 'assistant' && Ai.models[messageData?.model].icon
                                width: Appearance.font.pixelSize.large
                                height: Appearance.font.pixelSize.large
                                source: messageData?.role == 'assistant' ? Ai.models[messageData?.model].icon :
                                    messageData?.role == 'user' ? 'arch-symbolic' : 'desktop-symbolic'

                                colorize: true
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }

                            MaterialSymbol {
                                id: roleIcon
                                anchors.centerIn: parent
                                visible: !modelIcon.visible
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.m3colors.m3onSecondaryContainer
                                text: messageData?.role == 'user' ? 'person' : 
                                    messageData?.role == 'interface' ? 'settings' : 
                                    messageData?.role == 'assistant' ? 'neurology' : 
                                    'computer'
                            }
                        }

                        StyledText {
                            id: providerName
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onSecondaryContainer
                            text: messageData?.role === 'assistant' 
                                ? (Config.options?.ai?.systemPromptPath ? Config.options.ai.systemPromptPath.split("/").pop().replace(".md", "") : (Ai.models[messageData?.model]?.name ?? Translation.tr("Assistant")))
                                : (messageData?.role === 'user' ? (Config.options?.profile?.displayName || SystemInfo.username) 
                                : Translation.tr("Interface"))
                        }
                    }
                }

                Button { // Not visible to model
                    id: modelVisibilityIndicator
                    visible: messageData?.role == 'interface'
                    implicitWidth: 16
                    implicitHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    background: Item

                    MaterialSymbol {
                        id: notVisibleToModelText
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: "visibility_off"
                    }
                    StyledToolTip {
                        text: Translation.tr("Not visible to model")
                    }
                }

                ButtonGroup {
                    spacing: 5

                    AiMessageControlButton {
                        id: regenButton
                        buttonIcon: "refresh"
                        visible: !root.editing && messageData?.role === 'assistant'

                        onClicked: {
                            Ai.regenerate(root.messageId || root.messageIndex)
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Regenerate")
                        }
                    }

                    AiMessageControlButton {
                        id: copyButton
                        buttonIcon: activated ? "inventory" : "content_copy"

                        onClicked: {
                            Quickshell.clipboardText = root.editing ? root.editDraft : root.messageData?.content
                            copyButton.activated = true
                            copyIconTimer.restart()
                        }

                        Timer {
                            id: copyIconTimer
                            interval: 1500
                            repeat: false
                            onTriggered: {
                                copyButton.activated = false
                            }
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }

                    AiMessageControlButton {
                        id: editButton
                        activated: root.editing
                        enabled: root.messageData?.done ?? false
                        buttonIcon: root.editing ? "close" : "edit"
                        onClicked: {
                            if (root.editing) {
                                root.cancelEdit();
                            } else {
                                root.startEdit();
                            }
                        }
                        StyledToolTip {
                            text: root.editing ? Translation.tr("Cancel edit") : Translation.tr("Edit")
                        }
                    }

                    AiMessageControlButton {
                        id: toggleMarkdownButton
                        visible: !root.editing
                        activated: !root.renderMarkdown
                        buttonIcon: "code"
                        onClicked: {
                            root.renderMarkdown = !root.renderMarkdown
                        }
                        StyledToolTip {
                            text: Translation.tr("View Markdown source")
                        }
                    }

                    AiMessageControlButton {
                        id: deleteButton
                        visible: !root.editing
                        buttonIcon: "close"
                        onClicked: {
                            Ai.removeMessage(root.messageId || root.messageIndex)
                        }
                        StyledToolTip {
                            text: Translation.tr("Delete")
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            visible: root.attachedFilePaths.length > 0

            Repeater {
                model: root.attachedFilePaths
                delegate: AttachedFileIndicator {
                    Layout.fillWidth: true
                    showImagePreview: root.attachedFilePaths.length === 1
                    filePath: modelData
                    canRemove: false
                }
            }
        }

        ColumnLayout { // Message content (viewing mode)
            id: messageContentColumnLayout
            visible: !root.editing
            Layout.fillWidth: true
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                implicitWidth: loadingIndicatorLoader.implicitWidth
                visible: implicitHeight > 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                FadeLoader {
                    id: loadingIndicatorLoader
                    anchors.centerIn: parent
                    shown: (root.messageBlocks.length < 1) && (!root.messageData.done)
                    sourceComponent: MaterialLoadingIndicator {
                        loading: true
                    }
                }
            }
            Repeater {
                model: ScriptModel {
                    values: root.messageBlocks
                }
                delegate: DelegateChooser {
                    id: messageDelegate
                    role: "type"

                    DelegateChoice { roleValue: "code"; MessageCodeBlock {
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        segmentLang: modelData.lang
                        messageData: root.messageData
                    } }
                    DelegateChoice { roleValue: "think"; MessageThinkBlock {
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: modelData.completed ?? false
                    } }
                    DelegateChoice { roleValue: "text"; MessageTextBlock {
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                    } }
                }
            }
        }

        ColumnLayout { // Message editor (editing mode)
            id: messageEditorLayout
            visible: root.editing
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer2Active
                implicitHeight: Math.min(320, Math.max(80, editorTextArea.implicitHeight + 16))

                ScrollView {
                    id: editorScrollView
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea {
                        id: editorTextArea
                        anchors.left: parent.left
                        anchors.right: parent.right
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        padding: 8
                        background: null
                        font.family: Appearance.font.family.reading
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        textFormat: TextEdit.PlainText
                        text: root.editDraft
                        placeholderText: Translation.tr("Edit message content...")

                        Keys.priority: Keys.BeforeItem

                        onTextChanged: {
                            if (root.editing && root.editDraft !== text) {
                                root.editDraft = text;
                            }
                        }

                        Keys.onPressed: (event) => {
                            const isCtrl = (event.modifiers & Qt.ControlModifier) !== 0;
                            if (event.key === Qt.Key_Escape) {
                                root.cancelEdit();
                                event.accepted = true;
                            } else if (isCtrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                root.saveMessage(root.messageData && root.messageData.role === "user");
                                event.accepted = true;
                            } else if (isCtrl && event.key === Qt.Key_S) {
                                root.saveMessage(false);
                                event.accepted = true;
                            } else if (isCtrl && (event.key === Qt.Key_Backspace || event.key === Qt.Key_W)) {
                                // Delete one word backwards
                                if (editorTextArea.selectedText.length > 0) {
                                    const selStart = editorTextArea.selectionStart;
                                    const selEnd = editorTextArea.selectionEnd;
                                    editorTextArea.text = editorTextArea.text.substring(0, selStart) + editorTextArea.text.substring(selEnd);
                                    editorTextArea.cursorPosition = selStart;
                                } else {
                                    const pos = editorTextArea.cursorPosition;
                                    if (pos > 0) {
                                        const curText = editorTextArea.text;
                                        const textBefore = curText.substring(0, pos);
                                        const match = textBefore.match(/(?:\s+|[^\s\w]+|\w+)\s*$/);
                                        if (match && match[0].length > 0) {
                                            const deleteLen = match[0].length;
                                            const newPos = pos - deleteLen;
                                            editorTextArea.text = curText.substring(0, newPos) + curText.substring(pos);
                                            editorTextArea.cursorPosition = newPos;
                                        }
                                    }
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                const cursor = editorTextArea.cursorPosition;
                                editorTextArea.insert(cursor, "    ");
                                editorTextArea.cursorPosition = cursor + 4;
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
                                // Absorb modifier keys so parent does NOT steal focus to main message input
                                event.accepted = true;
                            }
                        }

                        Connections {
                            target: root
                            function onEditingChanged() {
                                if (root.editing) {
                                    editorTextArea.text = root.editDraft;
                                    Qt.callLater(() => {
                                        editorTextArea.forceActiveFocus();
                                        editorTextArea.cursorPosition = editorTextArea.text.length;
                                    });
                                }
                            }
                        }
                    }
                }
            }

            Shortcut {
                enabled: root.editing
                sequence: "Ctrl+Return"
                onActivated: root.saveMessage(root.messageData && root.messageData.role === "user")
            }
            Shortcut {
                enabled: root.editing
                sequence: "Ctrl+Enter"
                onActivated: root.saveMessage(root.messageData && root.messageData.role === "user")
            }
            Shortcut {
                enabled: root.editing
                sequence: "Ctrl+S"
                onActivated: root.saveMessage(false)
            }
            Shortcut {
                enabled: root.editing
                sequence: "Escape"
                onActivated: root.cancelEdit()
            }

            RowLayout { // Editor bottom action buttons
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: (root.messageData && root.messageData.role === "user")
                        ? Translation.tr("Ctrl+Enter to submit")
                        : Translation.tr("Ctrl+S to save • Esc to cancel")
                    elide: Text.ElideRight
                }

                ButtonGroup {
                    GroupButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.cancelEdit()
                    }
                    GroupButton {
                        buttonText: Translation.tr("Save")
                        onClicked: root.saveMessage(false)
                    }
                    GroupButton {
                        visible: root.messageData && root.messageData.role === "user"
                        buttonText: Translation.tr("Save & Submit")
                        toggled: true
                        onClicked: root.saveMessage(true)
                        contentItem: StyledText {
                            text: Translation.tr("Save & Submit")
                            color: Appearance.colors.colOnPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Flow { // Annotations
            visible: !root.editing && root.messageData?.annotationSources?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                }
            }
        }

        Flow { // Search queries
            visible: !root.editing && root.messageData?.searchQueries?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    required property var modelData
                    query: modelData
                }
            }
        }

    }
}

