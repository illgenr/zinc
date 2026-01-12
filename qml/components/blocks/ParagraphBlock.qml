import QtQuick
import QtQuick.Controls
import zinc

Item {
    id: root
    
    property string content: ""
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal indentRequested()
    signal outdentRequested()
    signal moveUpRequested()
    signal moveDownRequested()
    signal blockFocused()
    
    implicitHeight: Math.max(textEdit.contentHeight + ThemeManager.spacingSmall * 2, 32)
    
    TextEdit {
        id: textEdit
        
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        
        text: root.content
        color: ThemeManager.text
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeNormal
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        
        // Placeholder
        Text {
            anchors.fill: parent
            text: "Type '/' for commands..."
            color: ThemeManager.textPlaceholder
            font: parent.font
            visible: parent.text.length === 0 && !parent.activeFocus
        }
        
        onTextChanged: {
            if (text !== root.content) {
                root.contentEdited(text)
            }
        }
        
        onActiveFocusChanged: {
            if (activeFocus) {
                root.blockFocused()
            }
        }
        
        Keys.onReturnPressed: function(event) {
            if (event.modifiers & Qt.ShiftModifier) {
                // Shift+Enter: insert newline
                event.accepted = false
            } else {
                event.accepted = true
                root.enterPressed()
            }
        }
        
        Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && root.multiBlockSelectionActive && root.editor) {
                event.accepted = true
                root.editor.copyCrossBlockSelectionToClipboard()
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
                if (root.editor.pasteBlocksFromClipboard(root.blockIndex)) {
                    event.accepted = true
                }
            } else if (event.key === Qt.Key_Backspace && text.length === 0) {
                event.accepted = true
                root.backspaceOnEmpty()
            } else if (event.key === Qt.Key_Tab) {
                event.accepted = true
                if (event.modifiers & Qt.ShiftModifier) {
                    root.outdentRequested()
                } else {
                    root.indentRequested()
                }
            } else if (event.modifiers & Qt.AltModifier) {
                if (event.key === Qt.Key_Up) {
                    event.accepted = true
                    root.moveUpRequested()
                } else if (event.key === Qt.Key_Down) {
                    event.accepted = true
                    root.moveDownRequested()
                }
            }
        }
    }

    DragHandler {
        target: null
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        onActiveChanged: {
            if (!root.editor) return
            if (active) {
                const p = root.mapToItem(root.editor, centroid.pressPosition.x, centroid.pressPosition.y)
                root.editor.startCrossBlockSelection(p)
            } else {
                root.editor.endCrossBlockSelection()
            }
        }

        onTranslationChanged: {
            if (!active || !root.editor) return
            const p = root.mapToItem(root.editor, centroid.position.x, centroid.position.y)
            root.editor.updateCrossBlockSelection(p)
        }
    }

    property alias textControl: textEdit
}
