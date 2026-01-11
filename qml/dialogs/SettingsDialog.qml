import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Dialog {
    id: root
    
    signal pairDeviceRequested()

    ListModel {
        id: pairedDevicesModel
    }

    function refreshPairedDevices() {
        pairedDevicesModel.clear()
        var devices = DataStore.getPairedDevices()
        for (var i = 0; i < devices.length; i++) {
            pairedDevicesModel.append(devices[i])
        }
    }

    Connections {
        target: DataStore

        function onPairedDevicesChanged() {
            refreshPairedDevices()
        }
    }
    
    title: "Settings"
    anchors.centerIn: parent
    modal: true
    standardButtons: Dialog.Close
    
    // Responsive sizing
    property bool isMobile: Qt.platform.os === "android" || parent.width < 600
    width: isMobile ? parent.width * 0.95 : Math.min(550, parent.width * 0.9)
    height: isMobile ? parent.height * 0.9 : Math.min(500, parent.height * 0.85)
    
    background: Rectangle {
        color: ThemeManager.surface
        border.width: isMobile ? 0 : 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusLarge
    }
    
    header: Rectangle {
        height: 52
        color: "transparent"
        
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: ThemeManager.spacingMedium
            anchors.rightMargin: ThemeManager.spacingMedium
            
            // Back button for mobile (when not on main menu)
            ToolButton {
                visible: isMobile && settingsTabs.currentIndex >= 0
                contentItem: Text {
                    text: "←"
                    color: ThemeManager.text
                    font.pixelSize: 20
                }
                background: Rectangle {
                    color: parent.pressed ? ThemeManager.surfaceActive : "transparent"
                    radius: ThemeManager.radiusSmall
                }
                onClicked: {
                    if (isMobile) {
                        settingsTabs.currentIndex = -1
                    }
                }
            }
            
            Text {
                Layout.fillWidth: true
                text: {
                    if (isMobile && settingsTabs.currentIndex >= 0) {
                        return tabModel[settingsTabs.currentIndex].label
                    }
                    return root.title
                }
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeLarge
                font.weight: Font.Medium
                horizontalAlignment: isMobile ? Text.AlignLeft : Text.AlignHCenter
            }
            
            Item { width: isMobile ? 32 : 0 }
        }
        
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: ThemeManager.border
        }
    }
    
    // Tab model
    property var tabModel: [
        { label: "General", icon: "⚙️" },
        { label: "Sync", icon: "🔄" },
        { label: "Devices", icon: "📱" },
        { label: "Security", icon: "🔒" },
        { label: "Data", icon: "💾" },
        { label: "About", icon: "ℹ️" }
    ]
    
    contentItem: Item {
        // Desktop layout: sidebar + content
        RowLayout {
            anchors.fill: parent
            spacing: 0
            visible: !isMobile
            
            // Sidebar
            Rectangle {
                Layout.preferredWidth: 130
                Layout.fillHeight: true
                color: ThemeManager.background
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: 2
                    
                    Repeater {
                        model: tabModel
                        
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: ThemeManager.radiusSmall
                            color: settingsTabs.currentIndex === index ? ThemeManager.surfaceHover : (tabMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: ThemeManager.spacingSmall
                                spacing: ThemeManager.spacingSmall
                                
                                Text {
                                    text: modelData.icon
                                    font.pixelSize: 12
                                }
                                
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: ThemeManager.text
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                }
                            }
                            
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
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
            
            // Content area
            StackLayout {
                id: settingsTabs
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: 0
                
                GeneralSettings {}
                SyncSettings {}
                DevicesSettings { onPairDevice: { root.pairDeviceRequested(); root.close() } }
                SecuritySettings {}
                DataSettings {}
                AboutSettings {}
            }
        }
        
        // Mobile layout: list or content
        Item {
            anchors.fill: parent
            visible: isMobile
            
            // Menu list
            ListView {
                anchors.fill: parent
                visible: settingsTabs.currentIndex < 0
                model: tabModel
                clip: true
                
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 56
                    color: mobileTabMouse.pressed ? ThemeManager.surfaceHover : "transparent"
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: ThemeManager.spacingLarge
                        anchors.rightMargin: ThemeManager.spacingLarge
                        spacing: ThemeManager.spacingMedium
                        
                        Text {
                            text: modelData.icon
                            font.pixelSize: 20
                        }
                        
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeNormal
                        }
                        
                        Text {
                            text: "→"
                            color: ThemeManager.textMuted
                            font.pixelSize: 16
                        }
                    }
                    
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 56
                        height: 1
                        color: ThemeManager.borderLight
                    }
                    
                    MouseArea {
                        id: mobileTabMouse
                        anchors.fill: parent
                        onClicked: settingsTabs.currentIndex = index
                    }
                }
            }
            
            // Content area for mobile
            StackLayout {
                anchors.fill: parent
                visible: settingsTabs.currentIndex >= 0
                currentIndex: Math.max(0, settingsTabs.currentIndex)
                
                GeneralSettings {}
                SyncSettings {}
                DevicesSettings { onPairDevice: { root.pairDeviceRequested(); root.close() } }
                SecuritySettings {}
                DataSettings {}
                AboutSettings {}
            }
        }
    }
    
    onOpened: {
        if (isMobile) {
            settingsTabs.currentIndex = -1  // Show menu first on mobile
        } else {
            settingsTabs.currentIndex = 0
        }
    }
    
    // Confirmation dialog for reset
    Dialog {
        id: resetConfirmDialog
        title: "Reset Database?"
        anchors.centerIn: parent
        modal: true
        width: Math.min(300, root.width - 40)
        
        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusMedium
        }
        
        contentItem: ColumnLayout {
            spacing: ThemeManager.spacingLarge
            
            Text {
                Layout.fillWidth: true
                text: "Are you sure you want to reset?\n\nThis will delete all your notes."
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                wrapMode: Text.Wrap
            }
            
            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall
                
                Button {
                    Layout.fillWidth: true
                    text: "Cancel"
                    
                    background: Rectangle {
                        implicitHeight: 40
                        radius: ThemeManager.radiusSmall
                        color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                        border.width: 1
                        border.color: ThemeManager.border
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: resetConfirmDialog.close()
                }
                
                Button {
                    Layout.fillWidth: true
                    text: "Reset"
                    
                    background: Rectangle {
                        implicitHeight: 40
                        radius: ThemeManager.radiusSmall
                        color: parent.pressed ? "#7a2020" : ThemeManager.danger
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        font.pixelSize: ThemeManager.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        DataStore.resetDatabase()
                        resetConfirmDialog.close()
                        root.close()
                    }
                }
            }
        }
    }
    
    // Settings page components
    component SettingsPage: ScrollView {
        id: settingsPage
        default property alias pageContent: pageColumn.children
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        
        ColumnLayout {
            id: pageColumn
            width: settingsPage.width - ThemeManager.spacingLarge
            spacing: ThemeManager.spacingLarge
        }
    }
    
    component SettingsSection: ColumnLayout {
        property string title: ""
        default property alias content: sectionContent.children
        
        Layout.fillWidth: true
        Layout.margins: ThemeManager.spacingMedium
        spacing: ThemeManager.spacingSmall
        
        Text {
            text: title
            color: ThemeManager.text
            font.pixelSize: ThemeManager.fontSizeNormal
            font.weight: Font.Medium
        }
        
        ColumnLayout {
            id: sectionContent
            Layout.fillWidth: true
            spacing: ThemeManager.spacingSmall
        }
    }
    
    component SettingsRow: RowLayout {
        property string label: ""
        default property alias control: rowControl.children
        
        Layout.fillWidth: true
        spacing: ThemeManager.spacingSmall
        
        Text {
            Layout.fillWidth: true
            text: label
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeNormal
            wrapMode: Text.Wrap
        }
        
        Item {
            id: rowControl
            Layout.preferredWidth: 110
            Layout.preferredHeight: 32
        }
    }
    
    // General Settings
    component GeneralSettings: SettingsPage {
        SettingsSection {
            title: "Appearance"
            
            SettingsRow {
                label: "Theme"
                ComboBox {
                    id: themeCombo
                    width: parent.width
                    model: ["Dark", "Light", "System"]
                    currentIndex: ThemeManager.currentMode
                    
                    background: Rectangle {
                        implicitHeight: 32
                        radius: ThemeManager.radiusSmall
                        color: themeCombo.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                        border.width: 1
                        border.color: ThemeManager.border
                    }
                    
                    contentItem: Text {
                        leftPadding: 8
                        text: themeCombo.displayText
                        font.pixelSize: ThemeManager.fontSizeSmall
                        color: ThemeManager.text
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onCurrentIndexChanged: ThemeManager.setMode(currentIndex)
                }
            }
            
            SettingsRow {
                label: "Font size"
                ComboBox {
                    id: fontCombo
                    width: parent.width
                    model: ["Small", "Medium", "Large"]
                    currentIndex: ThemeManager.fontSizeScale
                    
                    background: Rectangle {
                        implicitHeight: 32
                        radius: ThemeManager.radiusSmall
                        color: fontCombo.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                        border.width: 1
                        border.color: ThemeManager.border
                    }
                    
                    contentItem: Text {
                        leftPadding: 8
                        text: fontCombo.displayText
                        font.pixelSize: ThemeManager.fontSizeSmall
                        color: ThemeManager.text
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onCurrentIndexChanged: ThemeManager.setFontScale(currentIndex)
                }
            }
        }
    }
    
    // Sync Settings
    component SyncSettings: SettingsPage {
        SettingsSection {
            title: "Sync Settings"
            
            SettingsRow {
                label: "Enable sync"
                Switch { checked: true }
            }
            
            SettingsRow {
                label: "Auto-connect"
                Switch { checked: true }
            }
        }
    }
    
    // Devices Settings
    component DevicesSettings: SettingsPage {
        signal pairDevice()
        
        Component.onCompleted: root.refreshPairedDevices()
        onVisibleChanged: if (visible) root.refreshPairedDevices()
        
        SettingsSection {
            title: "Paired Devices"
            
            Text {
                text: "No devices paired"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeNormal
                visible: pairedDevicesModel.count === 0
            }

            Repeater {
                model: pairedDevicesModel

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    implicitHeight: deviceRow.implicitHeight + ThemeManager.spacingSmall * 2
                    radius: ThemeManager.radiusSmall
                    color: ThemeManager.surfaceHover
                    border.width: 1
                    border.color: ThemeManager.border

                    RowLayout {
                        id: deviceRow
                        anchors.fill: parent
                        anchors.margins: ThemeManager.spacingSmall
                        spacing: ThemeManager.spacingSmall

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2
                            clip: true

                            Text {
                                text: deviceName
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeNormal
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }

                            Text {
                                text: workspaceId
                                color: ThemeManager.textMuted
                                font.pixelSize: ThemeManager.fontSizeSmall
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }
                        }

                        Button {
                            text: "Remove"
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 80
                            Layout.minimumWidth: 80

                            background: Rectangle {
                                radius: ThemeManager.radiusSmall
                                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
                                border.width: 1
                                border.color: ThemeManager.border
                            }

                            contentItem: Text {
                                text: parent.text
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: DataStore.removePairedDevice(deviceId)
                        }
                    }
                }
            }

            Button {
                Layout.fillWidth: true
                text: "Remove All Devices"
                visible: pairedDevicesModel.count > 0

                background: Rectangle {
                    implicitHeight: 44
                    radius: ThemeManager.radiusSmall
                    color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
                    border.width: 1
                    border.color: ThemeManager.border
                }

                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: DataStore.clearPairedDevices()
            }
            
            Button {
                Layout.fillWidth: true
                text: "+ Pair New Device"
                
                background: Rectangle {
                    implicitHeight: 44
                    radius: ThemeManager.radiusSmall
                    color: parent.pressed ? ThemeManager.accentHover : ThemeManager.accent
                }
                
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: ThemeManager.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: pairDevice()
            }
        }
    }
    
    // Security Settings
    component SecuritySettings: SettingsPage {
        SettingsSection {
            title: "Encryption"
            
            SettingsRow {
                label: "Encrypt database"
                Switch { checked: false }
            }
            
            Text {
                Layout.fillWidth: true
                text: "Database encryption protects your notes at rest"
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }
        }
    }
    
    // Data Settings
    component DataSettings: SettingsPage {
        SettingsSection {
            title: "Database"
            
            Text {
                Layout.fillWidth: true
                text: "Path: " + (DataStore ? DataStore.databasePath() : "N/A")
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.WrapAnywhere
            }
            
            Text {
                text: "Schema: v" + (DataStore ? DataStore.schemaVersion() : "?")
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
            }
            
            Button {
                Layout.fillWidth: true
                text: "Run Migrations"
                
                background: Rectangle {
                    implicitHeight: 40
                    radius: ThemeManager.radiusSmall
                    color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                    border.width: 1
                    border.color: ThemeManager.border
                }
                
                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    if (DataStore && DataStore.runMigrations()) {
                        console.log("Migrations complete")
                    }
                }
            }
        }
        
        SettingsSection {
            title: "⚠️ Danger Zone"
            
            Button {
                Layout.fillWidth: true
                text: "Reset All Data"
                
                background: Rectangle {
                    implicitHeight: 44
                    radius: ThemeManager.radiusSmall
                    color: parent.pressed ? "#7a2020" : "transparent"
                    border.width: 2
                    border.color: ThemeManager.danger
                }
                
                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.danger
                    font.pixelSize: ThemeManager.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: resetConfirmDialog.open()
            }
        }
    }
    
    // About Settings
    component AboutSettings: SettingsPage {
        SettingsSection {
            title: "About Zinc"
            
            Text {
                text: "Zinc Notes"
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeXLarge
                font.weight: Font.Bold
            }
            
            Text {
                text: "Version 0.1.0"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeNormal
            }
            
            Text {
                Layout.fillWidth: true
                text: "A local-first, peer-to-peer note-taking app with real-time collaboration."
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }
        }
    }
}
