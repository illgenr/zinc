import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property bool collapsed: false
    
    signal pageSelected(string pageId, string title)
    
    // UUID generator
    function generateUuid() {
        function s4() {
            return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        }
        return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4()
    }
    
    function createPage(parentId) {
        let id = generateUuid()
        pageModel.append({
            pageId: id,
            title: "Untitled",
            parentId: parentId || "",
            expanded: true,
            depth: 0
        })
        pageSelected(id, "Untitled")
    }
    
    function ensureInitialPage() {
        if (pageModel.count > 0) {
            let first = pageModel.get(0)
            pageSelected(first.pageId, first.title)
        }
    }
    
    ListModel {
        id: pageModel
        
        // Sample data
        ListElement {
            pageId: "1"
            title: "Getting Started"
            parentId: ""
            expanded: true
            depth: 0
        }
        ListElement {
            pageId: "2"
            title: "Projects"
            parentId: ""
            expanded: true
            depth: 0
        }
        ListElement {
            pageId: "3"
            title: "Work Project"
            parentId: "2"
            expanded: true
            depth: 1
        }
        ListElement {
            pageId: "4"
            title: "Personal"
            parentId: ""
            expanded: true
            depth: 0
        }
    }
    
    ListView {
        id: pageList
        
        anchors.fill: parent
        model: pageModel
        clip: true
        spacing: 2
        
        delegate: Rectangle {
            width: pageList.width
            height: collapsed ? 32 : 28
            radius: ThemeManager.radiusSmall
            color: mouseArea.containsMouse ? ThemeManager.surfaceHover : "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: collapsed ? ThemeManager.spacingSmall : ThemeManager.spacingSmall + model.depth * ThemeManager.spacingMedium
                anchors.rightMargin: ThemeManager.spacingSmall
                spacing: ThemeManager.spacingSmall
                
                // Expand/collapse arrow (for pages with children)
                Text {
                    text: "▶"
                    color: ThemeManager.textMuted
                    font.pixelSize: 8
                    visible: !collapsed && hasChildren(model.pageId)
                    rotation: model.expanded ? 90 : 0
                    
                    Behavior on rotation {
                        NumberAnimation { duration: ThemeManager.animationFast }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: model.expanded = !model.expanded
                    }
                    
                    function hasChildren(id) {
                        for (let i = 0; i < pageModel.count; i++) {
                            if (pageModel.get(i).parentId === id) {
                                return true
                            }
                        }
                        return false
                    }
                }
                
                // Page icon
                Text {
                    text: "📄"
                    font.pixelSize: collapsed ? 16 : 14
                }
                
                // Page title
                Text {
                    Layout.fillWidth: true
                    text: model.title
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideRight
                    visible: !collapsed
                }
                
                // Actions (appear on hover)
                RowLayout {
                    spacing: 2
                    visible: mouseArea.containsMouse && !collapsed
                    
                    ToolButton {
                        width: 20
                        height: 20
                        
                        contentItem: Text {
                            text: "+"
                            color: ThemeManager.textSecondary
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.hovered ? ThemeManager.surfaceActive : "transparent"
                        }
                        
                        onClicked: root.createPage(model.pageId)
                    }
                    
                    ToolButton {
                        width: 20
                        height: 20
                        
                        contentItem: Text {
                            text: "⋯"
                            color: ThemeManager.textSecondary
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.hovered ? ThemeManager.surfaceActive : "transparent"
                        }
                        
                        onClicked: {
                            // Show context menu
                        }
                    }
                }
            }
            
            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                
                onClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        root.pageSelected(model.pageId, model.title)
                    } else {
                        // Show context menu
                    }
                }
            }
        }
    }
}
