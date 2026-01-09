import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc
import "components"
import "dialogs"

ApplicationWindow {
    id: root
    
    width: 1200
    height: 800
    minimumWidth: 800
    minimumHeight: 600
    visible: true
    title: currentPage ? currentPage.title + " - Zinc" : "Zinc"
    color: ThemeManager.background
    
    property var currentPage: null
    property bool sidebarCollapsed: false
    
    // Keyboard shortcuts
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: pageTree.createPage()
    }
    
    Shortcut {
        sequence: "Ctrl+P"
        onActivated: searchDialog.open()
    }
    
    Shortcut {
        sequence: "Ctrl+\\"
        onActivated: sidebarCollapsed = !sidebarCollapsed
    }
    
    SplitView {
        anchors.fill: parent
        orientation: Qt.Horizontal
        
        handle: Rectangle {
            implicitWidth: 1
            color: ThemeManager.border
        }
        
        // Sidebar
        Rectangle {
            id: sidebar
            
            SplitView.preferredWidth: sidebarCollapsed ? ThemeManager.sidebarCollapsedWidth : ThemeManager.sidebarWidth
            SplitView.minimumWidth: ThemeManager.sidebarCollapsedWidth
            SplitView.maximumWidth: 400
            
            color: ThemeManager.surface
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingSmall
                spacing: ThemeManager.spacingSmall
                
                // Workspace header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall
                    
                    Rectangle {
                        width: 28
                        height: 28
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.accent
                        
                        Text {
                            anchors.centerIn: parent
                            text: "Z"
                            color: "white"
                            font.pixelSize: ThemeManager.fontSizeLarge
                            font.bold: true
                        }
                    }
                    
                    Text {
                        Layout.fillWidth: true
                        text: "My Notes"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        visible: !sidebarCollapsed
                    }
                    
                    ToolButton {
                        width: 24
                        height: 24
                        visible: !sidebarCollapsed
                        
                        contentItem: Text {
                            text: "⚙"
                            color: ThemeManager.textSecondary
                            font.pixelSize: ThemeManager.fontSizeNormal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.hovered ? ThemeManager.surfaceHover : "transparent"
                        }
                        
                        onClicked: settingsDialog.open()
                    }
                }
                
                // Search button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: ThemeManager.radiusMedium
                    color: ThemeManager.surfaceHover
                    visible: !sidebarCollapsed
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: ThemeManager.spacingSmall
                        anchors.rightMargin: ThemeManager.spacingSmall
                        
                        Text {
                            text: "🔍"
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                        
                        Text {
                            Layout.fillWidth: true
                            text: "Search"
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                        
                        Text {
                            text: "Ctrl+P"
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchDialog.open()
                    }
                }
                
                // Page tree
                PageTree {
                    id: pageTree
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !sidebarCollapsed
                    
                    onPageSelected: function(pageId, title) {
                        root.currentPage = { id: pageId, title: title }
                        blockEditor.loadPage(pageId)
                    }
                }
                
                // Collapsed sidebar icon
                Item {
                    Layout.fillHeight: true
                    visible: sidebarCollapsed
                }
            }
        }
        
        // Main content
        Rectangle {
            SplitView.fillWidth: true
            color: ThemeManager.background
            
            BlockEditor {
                id: blockEditor
                anchors.fill: parent
                pageTitle: currentPage ? currentPage.title : ""
            }
        }
    }
    
    // Dialogs
    SearchDialog {
        id: searchDialog
        
        onResultSelected: function(pageId, blockId) {
            // TODO: Implement proper page loading
            blockEditor.loadPage(pageId)
            if (blockId) {
                blockEditor.scrollToBlock(blockId)
            }
        }
    }
    
    PairingDialog {
        id: pairingDialog
    }
    
    SettingsDialog {
        id: settingsDialog
        
        onPairDeviceRequested: {
            pairingDialog.open()
        }
    }
    
    // Initial page
    Component.onCompleted: {
        // Create initial page if none exists
        pageTree.ensureInitialPage()
    }
}
