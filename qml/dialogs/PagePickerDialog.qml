import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Dialog {
    id: root
    
    property var pages: []  // Array of {pageId, title, depth}
    
    signal pageSelected(string pageId, string pageTitle)
    
    title: "Link to Page"
    modal: true
    standardButtons: Dialog.Cancel
    
    width: Math.min(400, parent.width * 0.9)
    height: Math.min(500, parent.height * 0.8)
    
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    
    background: Rectangle {
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusMedium
    }
    
    header: ColumnLayout {
        spacing: 0
        
        // Title bar
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: ThemeManager.spacingMedium
            
            Text {
                text: "🔗"
                font.pixelSize: 20
            }
            
            Text {
                Layout.fillWidth: true
                text: "Link to Page"
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeLarge
                font.weight: Font.Medium
            }
        }
        
        // Search box
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.leftMargin: ThemeManager.spacingMedium
            Layout.rightMargin: ThemeManager.spacingMedium
            Layout.bottomMargin: ThemeManager.spacingSmall
            radius: ThemeManager.radiusSmall
            color: ThemeManager.background
            border.width: searchInput.activeFocus ? 2 : 1
            border.color: searchInput.activeFocus ? ThemeManager.accent : ThemeManager.border
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingSmall
                
                Text {
                    text: "🔍"
                    font.pixelSize: 14
                    color: ThemeManager.textMuted
                }
                
                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    selectByMouse: true
                    
                    Text {
                        anchors.fill: parent
                        text: "Search pages..."
                        color: ThemeManager.textPlaceholder
                        font: parent.font
                        visible: parent.text.length === 0 && !parent.activeFocus
                    }
                    
                    onTextChanged: filterPages()
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: ThemeManager.border
        }
    }
    
    property var filteredPages: pages
    
    function filterPages() {
        let filter = searchInput.text.toLowerCase()
        if (filter.length === 0) {
            filteredPages = pages
        } else {
            filteredPages = pages.filter(p => p.title.toLowerCase().includes(filter))
        }
    }
    
    contentItem: ListView {
        id: pagesList
        clip: true
        model: filteredPages
        
        delegate: Rectangle {
            width: pagesList.width
            height: 48
            color: pageMouse.containsMouse ? ThemeManager.surfaceHover : "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ThemeManager.spacingMedium + (modelData.depth * 16)
                anchors.rightMargin: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall
                
                Text {
                    text: modelData.depth > 0 ? "📑" : "📄"
                    font.pixelSize: 16
                }
                
                Text {
                    Layout.fillWidth: true
                    text: modelData.title
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    elide: Text.ElideRight
                }
            }
            
            MouseArea {
                id: pageMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                
                onClicked: {
                    root.pageSelected(modelData.pageId, modelData.title)
                    root.close()
                }
            }
        }
        
        // Empty state
        Text {
            anchors.centerIn: parent
            text: filteredPages.length === 0 ? "No pages found" : ""
            color: ThemeManager.textMuted
            font.pixelSize: ThemeManager.fontSizeNormal
            visible: filteredPages.length === 0
        }
    }
    
    onOpened: {
        searchInput.text = ""
        searchInput.forceActiveFocus()
        filterPages()
    }
}

