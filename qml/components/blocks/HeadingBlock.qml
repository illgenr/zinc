import QtQuick
import QtQuick.Controls
import zinc

Item {
    id: root
    
    property int level: 1
    property string content: ""
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()
    
    implicitHeight: Math.max(textEdit.contentHeight + ThemeManager.spacingSmall * 2, 40)
    
    TextEdit {
        id: textEdit
        
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        
        text: root.content
        color: ThemeManager.text
        font.family: ThemeManager.fontFamily
        font.pixelSize: level === 1 ? ThemeManager.fontSizeH1 : 
                       level === 2 ? ThemeManager.fontSizeH2 : ThemeManager.fontSizeH3
        font.weight: Font.Bold
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        
        // Placeholder
        Text {
            anchors.fill: parent
            text: "Heading " + level
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
            event.accepted = true
            root.enterPressed()
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
