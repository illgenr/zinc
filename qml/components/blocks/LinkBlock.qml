import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property string content: ""  // Format: "pageId|pageTitle"
    property string linkedPageId: content.split("|")[0] || ""
    property string linkedPageTitle: content.split("|")[1] || "Untitled"
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()
    signal linkClicked(string pageId)
    
    implicitHeight: 40
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        radius: ThemeManager.radiusSmall
        color: linkMouse.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: ThemeManager.spacingSmall
            spacing: ThemeManager.spacingSmall
            
            Text {
                text: "📄"
                font.pixelSize: 16
            }
            
            Text {
                Layout.fillWidth: true
                text: linkedPageTitle || "Select a page..."
                color: linkedPageId ? ThemeManager.accent : ThemeManager.textPlaceholder
                font.pixelSize: ThemeManager.fontSizeNormal
                font.underline: linkedPageId !== ""
                elide: Text.ElideRight
            }
            
            Text {
                text: "↗"
                color: ThemeManager.textSecondary
                font.pixelSize: 14
                visible: linkedPageId !== ""
            }
        }
        
        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            
            onClicked: {
                if (linkedPageId) {
                    root.linkClicked(linkedPageId)
                }
            }
        }
    }
    
    // Set link data
    function setLink(pageId, pageTitle) {
        root.contentEdited(pageId + "|" + pageTitle)
    }
    
    // Handle key events
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            root.enterPressed()
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            event.accepted = true
            root.backspaceOnEmpty()
        }
    }
    
    // Make focusable
    focus: true
}

