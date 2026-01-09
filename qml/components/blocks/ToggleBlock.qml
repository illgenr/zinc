import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property string content: ""
    property bool isCollapsed: true
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal collapseToggled()
    signal blockFocused()
    
    implicitHeight: Math.max(rowLayout.height + ThemeManager.spacingSmall * 2, 32)
    
    RowLayout {
        id: rowLayout
        
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingSmall
        
        // Toggle arrow
        Text {
            text: isCollapsed ? "▶" : "▼"
            color: ThemeManager.textSecondary
            font.pixelSize: 10
            
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.collapseToggled()
            }
        }
        
        // Summary text
        TextEdit {
            id: textEdit
            
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            
            text: root.content
            color: ThemeManager.text
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeNormal
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            
            // Placeholder
            Text {
                anchors.fill: parent
                text: "Toggle"
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
        }
    }
}
