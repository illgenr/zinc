import QtQuick
import QtQuick.Controls
import zinc

Item {
    id: root
    
    property string content: ""
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()
    
    implicitHeight: Math.max(textEdit.contentHeight + ThemeManager.spacingSmall * 2, 32)
    
    // Left border
    Rectangle {
        width: 3
        height: parent.height
        color: ThemeManager.textMuted
        radius: 1.5
    }
    
    TextEdit {
        id: textEdit
        
        anchors.fill: parent
        anchors.leftMargin: ThemeManager.spacingMedium
        anchors.rightMargin: ThemeManager.spacingSmall
        anchors.topMargin: ThemeManager.spacingSmall
        anchors.bottomMargin: ThemeManager.spacingSmall
        
        text: root.content
        color: ThemeManager.textSecondary
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeNormal
        font.italic: true
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        
        // Placeholder
        Text {
            anchors.fill: parent
            text: "Quote"
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
                event.accepted = false
            } else {
                event.accepted = true
                root.enterPressed()
            }
        }
        
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Backspace && text.length === 0) {
                event.accepted = true
                root.backspaceOnEmpty()
            }
        }
    }
}
