import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Dialog {
    id: root
    
    signal pairDeviceRequested()
    
    title: "Settings"
    anchors.centerIn: parent
    width: 500
    height: 400
    modal: true
    standardButtons: Dialog.Close
    
    background: Rectangle {
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusLarge
    }
    
    header: Rectangle {
        height: 48
        color: "transparent"
        
        Text {
            anchors.centerIn: parent
            text: root.title
            color: ThemeManager.text
            font.pixelSize: ThemeManager.fontSizeLarge
            font.weight: Font.Medium
        }
    }
    
    contentItem: RowLayout {
        spacing: 0
        
        // Sidebar
        Rectangle {
            Layout.preferredWidth: 140
            Layout.fillHeight: true
            color: ThemeManager.background
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingSmall
                spacing: 2
                
                Repeater {
                    model: [
                        { label: "General", icon: "⚙️" },
                        { label: "Sync", icon: "🔄" },
                        { label: "Devices", icon: "📱" },
                        { label: "Security", icon: "🔒" },
                        { label: "About", icon: "ℹ️" }
                    ]
                    
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 32
                        radius: ThemeManager.radiusSmall
                        color: settingsTabs.currentIndex === index ? ThemeManager.surfaceHover : "transparent"
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: ThemeManager.spacingSmall
                            spacing: ThemeManager.spacingSmall
                            
                            Text {
                                text: modelData.icon
                                font.pixelSize: 14
                            }
                            
                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeSmall
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: settingsTabs.currentIndex = index
                        }
                    }
                }
                
                Item { Layout.fillHeight: true }
            }
        }
        
        Rectangle {
            width: 1
            Layout.fillHeight: true
            color: ThemeManager.border
        }
        
        // Content
        StackLayout {
            id: settingsTabs
            
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            // General
            ScrollView {
                ColumnLayout {
                    width: parent.width
                    spacing: ThemeManager.spacingLarge
                    
                    SettingsSection {
                        title: "Appearance"
                        
                        ColumnLayout {
                            spacing: ThemeManager.spacingSmall
                            
                            SettingsRow {
                                label: "Theme"
                                
                                ComboBox {
                                    id: themeCombo
                                    model: ["Dark", "Light", "System"]
                                    currentIndex: ThemeManager.currentMode
                                    
                                    background: Rectangle {
                                        implicitWidth: 120
                                        implicitHeight: 32
                                        radius: ThemeManager.radiusSmall
                                        color: themeCombo.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                                        border.width: 1
                                        border.color: ThemeManager.border
                                    }
                                    
                                    contentItem: Text {
                                        leftPadding: ThemeManager.spacingSmall
                                        text: themeCombo.displayText
                                        font.pixelSize: ThemeManager.fontSizeSmall
                                        color: ThemeManager.text
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    
                                    onCurrentIndexChanged: {
                                        ThemeManager.setMode(currentIndex)
                                    }
                                }
                            }
                            
                            SettingsRow {
                                label: "Font size"
                                
                                ComboBox {
                                    id: fontSizeCombo
                                    model: ["Small", "Medium", "Large"]
                                    currentIndex: 1
                                    
                                    background: Rectangle {
                                        implicitWidth: 120
                                        implicitHeight: 32
                                        radius: ThemeManager.radiusSmall
                                        color: fontSizeCombo.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                                        border.width: 1
                                        border.color: ThemeManager.border
                                    }
                                    
                                    contentItem: Text {
                                        leftPadding: ThemeManager.spacingSmall
                                        text: fontSizeCombo.displayText
                                        font.pixelSize: ThemeManager.fontSizeSmall
                                        color: ThemeManager.text
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Sync
            ScrollView {
                ColumnLayout {
                    width: parent.width
                    spacing: ThemeManager.spacingLarge
                    
                    SettingsSection {
                        title: "Sync Settings"
                        
                        ColumnLayout {
                            spacing: ThemeManager.spacingSmall
                            
                            SettingsRow {
                                label: "Enable sync"
                                
                                Switch {
                                    checked: true
                                }
                            }
                            
                            SettingsRow {
                                label: "Auto-connect to peers"
                                
                                Switch {
                                    checked: true
                                }
                            }
                        }
                    }
                }
            }
            
            // Devices
            ScrollView {
                ColumnLayout {
                    width: parent.width
                    spacing: ThemeManager.spacingLarge
                    
                    SettingsSection {
                        title: "Paired Devices"
                        
                        ColumnLayout {
                            spacing: ThemeManager.spacingSmall
                            
                            Text {
                                text: "No devices paired"
                                color: ThemeManager.textSecondary
                                font.pixelSize: ThemeManager.fontSizeNormal
                            }
                            
                            Button {
                                text: "+ Pair New Device"
                                
                                background: Rectangle {
                                    radius: ThemeManager.radiusSmall
                                    color: parent.hovered ? ThemeManager.surfaceHover : ThemeManager.background
                                    border.width: 1
                                    border.color: ThemeManager.border
                                }
                                
                                contentItem: Text {
                                    text: parent.text
                                    color: ThemeManager.text
                                    font.pixelSize: ThemeManager.fontSizeNormal
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                
                                onClicked: {
                                    root.pairDeviceRequested()
                                    root.close()
                                }
                            }
                        }
                    }
                }
            }
            
            // Security
            ScrollView {
                ColumnLayout {
                    width: parent.width
                    spacing: ThemeManager.spacingLarge
                    
                    SettingsSection {
                        title: "Encryption"
                        
                        ColumnLayout {
                            spacing: ThemeManager.spacingSmall
                            
                            SettingsRow {
                                label: "Encrypt database"
                                
                                Switch {
                                    checked: false
                                }
                            }
                            
                            Text {
                                text: "Database encryption protects your notes at rest"
                                color: ThemeManager.textSecondary
                                font.pixelSize: ThemeManager.fontSizeSmall
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
            
            // About
            ScrollView {
                ColumnLayout {
                    width: parent.width
                    spacing: ThemeManager.spacingLarge
                    
                    SettingsSection {
                        title: "About Zinc"
                        
                        ColumnLayout {
                            spacing: ThemeManager.spacingSmall
                            
                            Text {
                                text: "Zinc Notes"
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeLarge
                                font.weight: Font.Bold
                            }
                            
                            Text {
                                text: "Version 0.1.0"
                                color: ThemeManager.textSecondary
                                font.pixelSize: ThemeManager.fontSizeNormal
                            }
                            
                            Text {
                                text: "A local-first, peer-to-peer note-taking app"
                                color: ThemeManager.textSecondary
                                font.pixelSize: ThemeManager.fontSizeSmall
                            }
                        }
                    }
                }
            }
        }
    }
    
    component SettingsSection: ColumnLayout {
        property string title: ""
        default property alias content: contentColumn.children
        
        Layout.fillWidth: true
        Layout.margins: ThemeManager.spacingLarge
        spacing: ThemeManager.spacingMedium
        
        Text {
            text: title
            color: ThemeManager.text
            font.pixelSize: ThemeManager.fontSizeNormal
            font.weight: Font.Medium
        }
        
        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
        }
    }
    
    component SettingsRow: RowLayout {
        property string label: ""
        default property alias control: controlContainer.children
        
        Layout.fillWidth: true
        spacing: ThemeManager.spacingMedium
        
        Text {
            Layout.fillWidth: true
            text: label
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeNormal
        }
        
        Item {
            id: controlContainer
            Layout.preferredWidth: 120
            Layout.preferredHeight: 32
        }
    }
}
