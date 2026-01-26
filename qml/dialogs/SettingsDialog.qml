import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import zinc

Dialog {
    id: root
    
    signal pairDeviceRequested()
    property var syncController: null

    ListModel {
        id: pairedDevicesModel
    }

    ListModel {
        id: availableDevicesModel
    }

    function refreshPairedDevices() {
        pairedDevicesModel.clear()
        var devices = DataStore.getPairedDevices()
        for (var i = 0; i < devices.length; i++) {
            pairedDevicesModel.append(devices[i])
        }
    }

    function refreshAvailableDevices() {
        availableDevicesModel.clear()
        if (!syncController) return
        var devices = syncController.discoveredPeers
        if (!devices) return
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            if (!d) continue
            // Filter out other workspaces if we know ours.
            if (syncController.workspaceId && syncController.workspaceId !== "" &&
                d.workspaceId && d.workspaceId !== "" &&
                d.workspaceId !== syncController.workspaceId) {
                continue
            }
            availableDevicesModel.append(d)
        }
    }

    Connections {
        target: DataStore

        function onPairedDevicesChanged() {
            refreshPairedDevices()
        }
    }

    Connections {
        target: syncController
        enabled: syncController !== null

        function onDiscoveredPeersChanged() {
            refreshAvailableDevices()
        }

        function onConfiguredChanged() {
            refreshAvailableDevices()
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
        { label: "Editor", icon: "✍️" },
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
                EditorSettings {}
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
                EditorSettings {}
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

    // Editor Settings
    component EditorSettings: SettingsPage {
        SettingsSection {
            title: "Layout"

            SettingsRow {
                label: "Gutter position (px)"

                TextField {
                    id: gutterPositionField
                    width: parent.width
                    text: "" + EditorPreferences.gutterPositionPx
                    inputMethodHints: Qt.ImhPreferNumbers
                    validator: IntValidator { bottom: -9999; top: 9999 }

                    background: Rectangle {
                        implicitHeight: 32
                        radius: ThemeManager.radiusSmall
                        color: gutterPositionField.activeFocus ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                        border.width: 1
                        border.color: ThemeManager.border
                    }

                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeSmall
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 8

                    onEditingFinished: {
                        const parsed = parseInt(text, 10)
                        EditorPreferences.gutterPositionPx = isNaN(parsed) ? 0 : parsed
                        text = "" + EditorPreferences.gutterPositionPx
                    }

                    Connections {
                        target: EditorPreferences
                        function onGutterPositionPxChanged() {
                            if (gutterPositionField.activeFocus) return
                            gutterPositionField.text = "" + EditorPreferences.gutterPositionPx
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Positive values move the gutter right; negative values move it left."
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }
        }
    }

    // General Settings
    component GeneralSettings: SettingsPage {
        property ListModel startupPagesModel: ListModel {}

        function refreshStartupPages() {
            startupPagesModel.clear()
            const pages = DataStore ? DataStore.getAllPages() : []
            for (let i = 0; i < pages.length; i++) {
                const p = pages[i] || {}
                const depth = p.depth || 0
                let prefix = ""
                for (let d = 0; d < depth; d++) prefix += "  "
                if (p.pageId) {
                    startupPagesModel.append({
                        pageId: p.pageId,
                        title: prefix + (p.title || "Untitled")
                    })
                }
            }

            const fixedId = DataStore ? DataStore.startupFixedPageId() : ""
            if (!fixedId || fixedId === "") return
            if (!startupPageCombo) return
            for (let i = 0; i < startupPagesModel.count; i++) {
                if (startupPagesModel.get(i).pageId === fixedId) {
                    startupPageCombo.currentIndex = i
                    break
                }
            }
        }

        Component.onCompleted: refreshStartupPages()

        property Connections _dataStoreConnections: Connections {
            target: DataStore
            function onPagesChanged() {
                refreshStartupPages()
            }
        }

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

        SettingsSection {
            title: "Navigation"

            SettingsRow {
                label: "Jump to new page on creation"

                Switch {
                    id: jumpToNewPageSwitch
                    checked: GeneralPreferences.jumpToNewPageOnCreate
                    onToggled: GeneralPreferences.jumpToNewPageOnCreate = checked
                }
            }
        }

        SettingsSection {
            title: "Startup"

            SettingsRow {
                label: "Open on launch"
                ComboBox {
                    id: startupModeCombo
                    width: parent.width
                    model: ["Last viewed page", "Always open a page"]
                    Component.onCompleted: {
                        startupModeCombo.currentIndex = DataStore ? DataStore.startupPageMode() : 0
                    }

                    onActivated: {
                        if (DataStore) DataStore.setStartupPageMode(currentIndex)
                    }
                }
            }

            SettingsRow {
                visible: startupModeCombo.currentIndex === 1
                label: "Page"
                ComboBox {
                    id: startupPageCombo
                    width: parent.width
                    model: startupPagesModel
                    textRole: "title"
                    valueRole: "pageId"

                    Component.onCompleted: {
                        const fixedId = DataStore ? DataStore.startupFixedPageId() : ""
                        for (let i = 0; i < startupPagesModel.count; i++) {
                            if (startupPagesModel.get(i).pageId === fixedId) {
                                startupPageCombo.currentIndex = i
                                break
                            }
                        }
                    }

                    onActivated: {
                        if (DataStore) DataStore.setStartupFixedPageId(currentValue)
                    }
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
                label: "Auto sync"

                Switch {
                    checked: SyncPreferences.autoSyncEnabled
                    onToggled: SyncPreferences.autoSyncEnabled = checked
                }
            }

            SettingsRow {
                label: "Deleted pages history"

                SpinBox {
                    id: deletedPagesRetentionSpin
                    from: 0
                    to: 10000
                    value: DataStore ? DataStore.deletedPagesRetentionLimit() : 100
                    editable: true

                    onValueModified: {
                        if (DataStore) {
                            DataStore.setDeletedPagesRetentionLimit(value)
                        }
                    }
                }
            }
        }
    }
    
    // Devices Settings
    component DevicesSettings: SettingsPage {
        signal pairDevice()
        
        Component.onCompleted: {
            root.refreshPairedDevices()
            root.refreshAvailableDevices()
        }
        onVisibleChanged: if (visible) {
            root.refreshPairedDevices()
            root.refreshAvailableDevices()
        }

        SettingsSection {
            title: "Available Devices"

            Text {
                text: "No devices discovered"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeNormal
                visible: availableDevicesModel.count === 0
            }

            Repeater {
                model: availableDevicesModel

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
                                text: deviceName && deviceName !== "" ? deviceName : deviceId
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeNormal
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }

                            Text {
                                Layout.fillWidth: true
                                color: ThemeManager.textSecondary
                                font.pixelSize: ThemeManager.fontSizeSmall
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                text: (host && host !== "" && port && port > 0) ? (host + ":" + port) : "unknown"
                            }
                        }
                    }
                }
            }
        }
        
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

                            Text {
                                Layout.fillWidth: true
                                color: ThemeManager.textSecondary
                                font.pixelSize: ThemeManager.fontSizeSmall
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1

                function isOnline(lastSeen) {
                    if (!lastSeen || lastSeen === "") return false
                    // Stored as "yyyy-MM-dd HH:mm:ss" (UTC) or ISO; normalize for JS Date parsing.
                    var iso = lastSeen.indexOf("T") >= 0 ? lastSeen : lastSeen.replace(" ", "T") + "Z"
                    var t = Date.parse(iso)
                    if (isNaN(t)) return false
                    return (Date.now() - t) < 15000
                }

                                text: {
                                    var online = isOnline(lastSeen)
                                    var endpoint = (host && host !== "" && port && port > 0) ? (host + ":" + port) : "unknown"
                                    return online ? ("Available (" + endpoint + ")") : ("Offline (" + endpoint + ")")
                                }
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
        property ListModel notebooksModel: ListModel {}
        property bool exportAllNotebooks: true
        property bool exportIncludeAttachments: true
        property url exportDestinationFolder: ""
        property int exportFormatIndex: 0 // 0=markdown, 1=html
        property string exportStatus: ""
        property url folderPickerCurrentFolder: ""
        property url folderPickerSelectedFolder: ""

        function refreshNotebooks() {
            notebooksModel.clear()
            const notebooks = DataStore ? DataStore.getAllNotebooks() : []
            for (let i = 0; i < notebooks.length; i++) {
                const nb = notebooks[i] || {}
                if (!nb.notebookId) continue
                notebooksModel.append({
                    notebookId: nb.notebookId,
                    name: nb.name || "Untitled Notebook",
                    selected: true
                })
            }
        }

        function selectedNotebookIds() {
            const ids = []
            for (let i = 0; i < notebooksModel.count; i++) {
                const nb = notebooksModel.get(i)
                if (nb.selected) ids.push(nb.notebookId)
            }
            return ids
        }

        function canExport() {
            if (!exportDestinationFolder || exportDestinationFolder === "") return false
            if (exportAllNotebooks) return true
            return selectedNotebookIds().length > 0
        }

        function ensureExportDestinationFolder() {
            const hasFolder = exportDestinationFolder && exportDestinationFolder !== "" &&
                exportDestinationFolder.toString().indexOf("file:") === 0
            if (hasFolder) return
            exportDestinationFolder = DataStore ? DataStore.exportLastFolder() : ""
        }

        function openFolderPicker() {
            ensureExportDestinationFolder()
            folderPickerCurrentFolder = exportDestinationFolder
            folderPickerSelectedFolder = ""
            exportFolderPickerDialog.open()
        }

        Component.onCompleted: {
            refreshNotebooks()
            ensureExportDestinationFolder()
        }

        property Connections _dataStoreConnections: Connections {
            target: DataStore
            function onNotebooksChanged() { refreshNotebooks() }
            function onError(message) {
                exportStatus = message
            }
        }

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
            title: "Export"

            Button {
                Layout.fillWidth: true
                text: "Export Notebooks…"

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
                    exportStatus = ""
                    refreshNotebooks()
                    ensureExportDestinationFolder()
                    exportDialog.open()
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

        property Dialog _exportDialog: Dialog {
            id: exportDialog
            title: "Export Notebooks"
            anchors.centerIn: parent
            modal: true
            standardButtons: Dialog.NoButton

            width: isMobile ? parent.width * 0.95 : Math.min(520, parent.width * 0.9)

            background: Rectangle {
                color: ThemeManager.surface
                border.width: isMobile ? 0 : 1
                border.color: ThemeManager.border
                radius: ThemeManager.radiusLarge
            }

            contentItem: ColumnLayout {
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium

                SettingsRow {
                    label: "Format"
                    ComboBox {
                        width: parent.width
                        model: ["Markdown (.md)", "HTML (.html)"]
                        currentIndex: exportFormatIndex
                        onCurrentIndexChanged: exportFormatIndex = currentIndex
                    }
                }

                SettingsRow {
                    label: "Notebooks"
                    CheckBox {
                        text: "All notebooks"
                        checked: exportAllNotebooks
                        onToggled: exportAllNotebooks = checked
                    }
                }

                SettingsRow {
                    label: "Attachments"
                    CheckBox {
                        text: "Include attachments"
                        checked: exportIncludeAttachments
                        onToggled: exportIncludeAttachments = checked
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    visible: !exportAllNotebooks
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: notebooksModel
                            delegate: CheckBox {
                                text: model.name
                                checked: model.selected
                                onToggled: notebooksModel.setProperty(index, "selected", checked)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Button {
                        text: "Choose Folder…"
                        onClicked: openFolderPicker()
                    }

                    Text {
                        Layout.fillWidth: true
                        text: exportDestinationFolder && exportDestinationFolder !== ""
                            ? exportDestinationFolder.toString().replace("file://", "")
                            : "No folder selected"
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideMiddle
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: exportStatus && exportStatus.length > 0
                    text: exportStatus
                    color: ThemeManager.danger
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Cancel"
                        onClicked: exportDialog.close()
                    }

                    Button {
                        text: "Export"
                        enabled: canExport()
                        onClicked: {
                            if (!DataStore) return
                            const ids = exportAllNotebooks ? [] : selectedNotebookIds()
                            const fmt = exportFormatIndex === 0 ? "markdown" : "html"
                            DataStore.setExportLastFolder(exportDestinationFolder)
                            const ok = DataStore.exportNotebooks(ids, exportDestinationFolder, fmt, exportIncludeAttachments)
                            if (ok) {
                                exportDialog.close()
                            }
                        }
                    }
                }
            }
        }

        property Dialog _exportFolderPickerDialog: Dialog {
            id: exportFolderPickerDialog
            title: "Choose Export Folder"
            anchors.centerIn: parent
            modal: true
            standardButtons: Dialog.NoButton

            width: isMobile ? parent.width * 0.95 : Math.min(560, parent.width * 0.9)
            height: isMobile ? parent.height * 0.85 : Math.min(520, parent.height * 0.85)

            background: Rectangle {
                color: ThemeManager.surface
                border.width: isMobile ? 0 : 1
                border.color: ThemeManager.border
                radius: ThemeManager.radiusLarge
            }

            contentItem: ColumnLayout {
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Button {
                        text: "Up"
                        enabled: DataStore && folderPickerCurrentFolder !== "" &&
                            DataStore.parentFolder(folderPickerCurrentFolder).toString() !== folderPickerCurrentFolder.toString()
                        onClicked: {
                            if (!DataStore) return
                            folderPickerCurrentFolder = DataStore.parentFolder(folderPickerCurrentFolder)
                            folderPickerSelectedFolder = ""
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: folderPickerCurrentFolder && folderPickerCurrentFolder !== ""
                            ? folderPickerCurrentFolder.toString().replace("file://", "")
                            : ""
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideMiddle
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: ThemeManager.background
                    radius: ThemeManager.radiusSmall
                    border.width: 1
                    border.color: ThemeManager.border

                    ListView {
                        id: folderListView
                        anchors.fill: parent
                        anchors.margins: ThemeManager.spacingSmall
                        clip: true
                        model: FolderListModel {
                            folder: folderPickerCurrentFolder
                            showDirs: true
                            showFiles: false
                            sortField: FolderListModel.Name
                        }

                        delegate: Rectangle {
                            readonly property string dirUrl: "file://" + filePath
                            width: ListView.view.width
                            height: 36
                            radius: ThemeManager.radiusSmall
                            color: (folderPickerSelectedFolder && folderPickerSelectedFolder.toString() === dirUrl)
                                ? ThemeManager.surfaceHover
                                : (rowMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: ThemeManager.spacingSmall
                                anchors.rightMargin: ThemeManager.spacingSmall
                                spacing: ThemeManager.spacingSmall

                                Text {
                                    text: "📁"
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: fileName
                                    color: ThemeManager.text
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: folderPickerSelectedFolder = dirUrl
                                onDoubleClicked: {
                                    folderPickerCurrentFolder = dirUrl
                                    folderPickerSelectedFolder = ""
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Text {
                        Layout.fillWidth: true
                        text: folderPickerSelectedFolder && folderPickerSelectedFolder !== ""
                            ? ("Selected: " + folderPickerSelectedFolder.toString().replace("file://", ""))
                            : "Selected: (current folder)"
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Cancel"
                        onClicked: exportFolderPickerDialog.close()
                    }

                    Button {
                        text: "Export"
                        enabled: folderPickerCurrentFolder && folderPickerCurrentFolder !== ""
                        onClicked: {
                            const chosen = (folderPickerSelectedFolder && folderPickerSelectedFolder !== "")
                                ? folderPickerSelectedFolder
                                : folderPickerCurrentFolder
                            exportDestinationFolder = chosen
                            if (DataStore) DataStore.setExportLastFolder(chosen)
                            exportFolderPickerDialog.close()
                        }
                    }
                }
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
                text: "Version 0.2.0"
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
