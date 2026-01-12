import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property string content: ""
    property bool isChecked: false
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal checkedToggled()
    signal blockFocused()
    
    implicitHeight: Math.max(rowLayout.height + ThemeManager.spacingSmall * 2, 32)
    
    RowLayout {
        id: rowLayout
        
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingSmall
        
        // Checkbox
        Rectangle {
            width: 18
            height: 18
            radius: ThemeManager.radiusSmall
            color: isChecked ? ThemeManager.accent : "transparent"
            border.width: isChecked ? 0 : 2
            border.color: ThemeManager.border
            
            Text {
                anchors.centerIn: parent
                text: "✓"
                color: "white"
                font.pixelSize: 12
                font.bold: true
                visible: isChecked
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.checkedToggled()
            }
        }
        
        // Text
        TextEdit {
            id: textEdit
            
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            
            text: root.content
            color: isChecked ? ThemeManager.textSecondary : ThemeManager.text
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeNormal
            font.strikeout: isChecked
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            
            // Placeholder
            Text {
                anchors.fill: parent
                text: "To-do"
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
