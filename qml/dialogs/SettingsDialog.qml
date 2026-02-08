import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import zinc

Dialog {
    id: root
    
    signal pairDeviceRequested()
    signal manualDeviceAddRequested(string host, int port)
    property var syncController: null

    function isDescendantOf(node, ancestor) {
        let cur = node || null
        while (cur) {
            if (cur === ancestor) return true
            cur = cur.parent || null
        }
        return false
    }

    function activeFocusInDesktopTabList() {
        return isDescendantOf(root.activeFocusItem, desktopTabList)
    }

    function activeFocusInSettingsContent() {
        return isDescendantOf(root.activeFocusItem, settingsTabs)
    }

    function focusFirstSettingControl() {
        const page = settingsTabs.currentItem
        if (!page) return

        function findFocusable(node) {
            if (!node) return null
            const wantsFocus = node.visible !== false
                && node.enabled !== false
                && node.activeFocusOnTab === true
                && ("forceActiveFocus" in node)
            if (wantsFocus) return node
            const children = node.children || []
            for (let i = 0; i < children.length; i++) {
                const found = findFocusable(children[i])
                if (found) return found
            }
            return null
        }

        const target = findFocusable(page)
        if (target) {
            target.forceActiveFocus()
            return
        }
        if ("forceActiveFocus" in page) {
            page.forceActiveFocus()
        }
    }

    Keys.onPressed: function(event) {
        if (isMobile) return
        if (!root.visible) return

        const key = event.key
        const isShiftTab = key === Qt.Key_Backtab || (key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))
        if (isShiftTab && activeFocusInSettingsContent()) {
            event.accepted = true
            desktopTabList.forceActiveFocus()
            return
        }

        const isForwardTab = key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)
        const isEnter = key === Qt.Key_Return || key === Qt.Key_Enter
        if ((isForwardTab || isEnter) && activeFocusInDesktopTabList()) {
            event.accepted = true
            focusFirstSettingControl()
            return
        }
    }

    function openDevicesTab() {
        // Devices tab index matches tabModel ordering.
        settingsTabs.currentIndex = 3
    }
    function openManualAddDialog() {
        manualAddDialog.hostText = ""
        manualAddDialog.portText = ""
        manualAddDialog.statusText = ""
        manualAddDialog.open()
    }

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

        function onError(message) {
            console.log("SettingsDialog: sync error:", message)
            if (manualAddDialog.visible) manualAddDialog.statusText = message
            if (endpointEditDialog.visible) endpointEditDialog.statusText = message

            if (manualAddDialog.visible && manualAddDialog.pending && message && message.indexOf("closed the connection") >= 0) {
                manualAddDialog.statusText =
                    message + "\n\nTip: manual connections require both devices to already be in the same workspace (paired)."
            }
        }

        function onPeerApprovalRequired(deviceId, deviceName, host, port) {
            console.log("SettingsDialog: peerApprovalRequired", deviceId, deviceName, host, port)
            if (manualAddDialog.visible && manualAddDialog.pending) {
                manualAddDialog.statusText = "Awaiting confirmation on the other device…"
            }
        }

        function onPeerHelloReceived(deviceId, deviceName, host, port) {
            console.log("SettingsDialog: peerHelloReceived", deviceId, deviceName, host, port)
            if (DataStore && deviceId && deviceId !== "" && host && host !== "" && port && port > 0) {
                DataStore.updatePairedDeviceEndpoint(deviceId, host, port)
            }
            if (!manualAddDialog.visible) return
            if (!manualAddDialog.pending) return
            manualAddDialog.statusText = "Device responded. Check the other device for confirmation."
            manualAddDialog.pending = null
            manualAddDialog.close()
        }

        function onPeerIdentityMismatch(expectedDeviceId, actualDeviceId, deviceName, host, port) {
            console.log("SettingsDialog: peerIdentityMismatch expected=", expectedDeviceId,
                        "actual=", actualDeviceId, deviceName, host, port)
            if (manualAddDialog.visible && manualAddDialog.pending) {
                manualAddDialog.statusText = "Device was reset/reinstalled. Re-pair is required."
            }
            if (endpointEditDialog.visible) {
                endpointEditDialog.statusText = "Device was reset/reinstalled. Re-pair is required."
            }
        }

        function onPeerWorkspaceMismatch(deviceId, remoteWorkspaceId, localWorkspaceId, deviceName, host, port) {
            console.log("SettingsDialog: peerWorkspaceMismatch", deviceId, remoteWorkspaceId, localWorkspaceId, deviceName, host, port)
            if (manualAddDialog.visible && manualAddDialog.pending) {
                manualAddDialog.statusText = "Device is not in this workspace. Re-pair is required."
            }
            if (endpointEditDialog.visible) {
                endpointEditDialog.statusText = "Device is not in this workspace. Re-pair is required."
            }
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
        //{ label: "Security", icon: "🔒" },
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
                    id: desktopTabList
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: 2
                    focus: !isMobile && root.visible
                    activeFocusOnTab: !isMobile

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Down) {
                            event.accepted = true
                            settingsTabs.currentIndex = Math.min(tabModel.length - 1, settingsTabs.currentIndex + 1)
                            return
                        }
                        if (event.key === Qt.Key_Up) {
                            event.accepted = true
                            settingsTabs.currentIndex = Math.max(0, settingsTabs.currentIndex - 1)
                            return
                        }
                        if (event.key === Qt.Key_Tab
                                || event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Right) {
                            event.accepted = true
                            root.focusFirstSettingControl()
                            return
                        }
                    }
                    
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
                //SecuritySettings {}
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
                id: settingsMenuList
                anchors.fill: parent
                visible: settingsTabs.currentIndex < 0
                model: tabModel
                clip: true
                activeFocusOnTab: true
                
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
                //SecuritySettings {}
                DataSettings {}
                AboutSettings {}
            }
        }
    }
    
    onOpened: {
        refreshPairedDevices()
        refreshAvailableDevices()
        if (isMobile) {
            settingsTabs.currentIndex = -1  // Show menu first on mobile
            Qt.callLater(() => settingsMenuList.forceActiveFocus())
        } else {
            settingsTabs.currentIndex = 0
            Qt.callLater(() => desktopTabList.forceActiveFocus())
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
                label: "Workspace ID"

                TextField {
                    Layout.fillWidth: true
                    readOnly: true
                    text: (syncController && syncController.workspaceId && syncController.workspaceId !== "")
                        ? syncController.workspaceId
                        : "Not configured"
                    selectByMouse: true
                }
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

        function trimmed(text) { return text ? text.trim() : "" }

        function isDevicePaired(deviceId) {
            if (!deviceId) return false
            for (let i = 0; i < pairedDevicesModel.count; i++) {
                const d = pairedDevicesModel.get(i)
                if (d && d.deviceId === deviceId) return true
            }
            return false
        }
        
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

                        Button {
                            text: "Endpoint…"
                            enabled: DataStore && deviceId && deviceId !== ""
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 92
                            Layout.minimumWidth: 92

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

                            onClicked: {
                                endpointEditDialog.deviceId = deviceId
                                endpointEditDialog.deviceName = deviceName && deviceName !== "" ? deviceName : deviceId
                                endpointEditDialog.hostText = host && host !== "" ? host : ""
                                endpointEditDialog.portText = port && port > 0 ? ("" + port) : ""
                                endpointEditDialog.open()
                            }
                        }

                        Button {
                            text: "Connect"
                            enabled: syncController && syncController.syncing &&
                                     deviceId && deviceId !== "" &&
                                     host && host !== "" && port && port > 0
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 80
                            Layout.minimumWidth: 80

                            background: Rectangle {
                                radius: ThemeManager.radiusSmall
                                color: parent.pressed ? ThemeManager.accentHover : ThemeManager.accent
                            }

                            contentItem: Text {
                                text: parent.text
                                color: "white"
                                font.pixelSize: ThemeManager.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                console.log("SettingsDialog: connect to discovered peer", deviceId, host, port)
                                syncController.connectToPeer(deviceId, host, port)
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

                        Item {
                            Layout.preferredWidth: 172
                            Layout.minimumWidth: 172
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: actionFlow.implicitHeight

                            Flow {
                                id: actionFlow
                                width: parent.width
                                spacing: ThemeManager.spacingSmall
                                layoutDirection: Qt.LeftToRight
                                flow: Flow.LeftToRight

                                Button {
                                    text: "Rename…"
                                    width: 84
                                    height: 28

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

                                    onClicked: {
                                        deviceNameEditDialog.deviceId = deviceId
                                        deviceNameEditDialog.currentName = deviceName
                                        deviceNameEditDialog.nameText = deviceName
                                        deviceNameEditDialog.statusText = ""
                                        deviceNameEditDialog.open()
                                    }
                                }

                                Button {
                                    text: "Remove"
                                    width: 80
                                    height: 28

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
                
                onClicked: {
                    root.pairDeviceRequested()
                    root.close()
                }
            }
        }
    }

    Dialog {
        id: deviceNameEditDialog
        objectName: "deviceNameEditDialog"
        title: "Rename Device"
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, root.width - 40)
        standardButtons: Dialog.NoButton

        property string deviceId: ""
        property string currentName: ""
        property string nameText: ""
        property string statusText: ""

        function trimmed(text) { return text ? text.trim() : "" }

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusMedium
        }

        contentItem: ColumnLayout {
            spacing: ThemeManager.spacingMedium
            anchors.margins: ThemeManager.spacingMedium

            Text {
                Layout.fillWidth: true
                text: deviceNameEditDialog.currentName
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                font.weight: Font.Medium
                wrapMode: Text.Wrap
            }

            TextField {
                Layout.fillWidth: true
                placeholderText: "Device name"
                text: deviceNameEditDialog.nameText
                onTextChanged: deviceNameEditDialog.nameText = text
            }

            Text {
                Layout.fillWidth: true
                text: deviceNameEditDialog.statusText
                visible: deviceNameEditDialog.statusText !== ""
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            Flow {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Button {
                    text: "Cancel"
                    width: Math.max(120, (deviceNameEditDialog.width - ThemeManager.spacingMedium * 3) / 2)
                    onClicked: deviceNameEditDialog.close()
                }

                Button {
                    text: "Save"
                    objectName: "deviceNameEditSaveButton"
                    width: Math.max(120, (deviceNameEditDialog.width - ThemeManager.spacingMedium * 3) / 2)
                    enabled: DataStore && deviceNameEditDialog.trimmed(deviceNameEditDialog.nameText).length > 0
                    onClicked: {
                        const name = deviceNameEditDialog.trimmed(deviceNameEditDialog.nameText)
                        if (name === "") {
                            deviceNameEditDialog.statusText = "Device name is required"
                            return
                        }
                        DataStore.setPairedDeviceName(deviceNameEditDialog.deviceId, name)
                        deviceNameEditDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: endpointEditDialog
        objectName: "endpointEditDialog"
        title: "Set Manual Endpoint"
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, root.width - 40)
        standardButtons: Dialog.NoButton

        property string deviceId: ""
        property string deviceName: ""
        property string hostText: ""
        property string portText: ""
        property string statusText: ""

        function trimmed(text) { return text ? text.trim() : "" }
        function parsedPortOrDefault() {
            const t = trimmed(portText)
            if (t === "") return 47888
            const n = parseInt(t, 10)
            if (isNaN(n)) return -1
            return n
        }

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusMedium
        }

        contentItem: ColumnLayout {
            spacing: ThemeManager.spacingMedium
            anchors.margins: ThemeManager.spacingMedium

            Text {
                Layout.fillWidth: true
                text: endpointEditDialog.deviceName
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                font.weight: Font.Medium
                wrapMode: Text.Wrap
            }

            TextField {
                Layout.fillWidth: true
                placeholderText: "Host (MagicDNS or Tailscale IP)"
                text: endpointEditDialog.hostText
                onTextChanged: endpointEditDialog.hostText = text
            }

            TextField {
                Layout.fillWidth: true
                placeholderText: "Port (optional)"
                inputMethodHints: Qt.ImhDigitsOnly
                text: endpointEditDialog.portText
                onTextChanged: endpointEditDialog.portText = text
            }

            Text {
                Layout.fillWidth: true
                text: endpointEditDialog.statusText
                visible: endpointEditDialog.statusText !== ""
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Button {
                    Layout.fillWidth: true
                    text: "Cancel"
                    onClicked: endpointEditDialog.close()
                }

                Button {
                    Layout.fillWidth: true
                    text: "Save"
                    objectName: "endpointEditSaveButton"
                    enabled: DataStore && endpointEditDialog.trimmed(endpointEditDialog.hostText).length > 0
                    onClicked: {
                        const host = endpointEditDialog.trimmed(endpointEditDialog.hostText)
                        const port = endpointEditDialog.parsedPortOrDefault()
                        if (port <= 0 || port > 65535) {
                            endpointEditDialog.statusText = "Invalid port"
                            return
                        }
                        // Only meaningful for previously paired devices.
                        const paired = (function() {
                            for (let i = 0; i < pairedDevicesModel.count; i++) {
                                const d = pairedDevicesModel.get(i)
                                if (d && d.deviceId === endpointEditDialog.deviceId) return true
                            }
                            return false
                        })()
                        if (!paired) {
                            endpointEditDialog.statusText = "Device is not paired yet. Pair first, then set a manual endpoint."
                            return
                        }
                        if (DataStore.setPairedDevicePreferredEndpoint) {
                            DataStore.setPairedDevicePreferredEndpoint(endpointEditDialog.deviceId, host, port)
                        } else {
                            DataStore.updatePairedDeviceEndpoint(endpointEditDialog.deviceId, host, port)
                        }
                        endpointEditDialog.close()
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: "Save & Connect"
                    enabled: DataStore && syncController && syncController.syncing &&
                             endpointEditDialog.trimmed(endpointEditDialog.hostText).length > 0
                    onClicked: {
                        const host = endpointEditDialog.trimmed(endpointEditDialog.hostText)
                        const port = endpointEditDialog.parsedPortOrDefault()
                        if (port <= 0 || port > 65535) {
                            endpointEditDialog.statusText = "Invalid port"
                            return
                        }
                        const paired = (function() {
                            for (let i = 0; i < pairedDevicesModel.count; i++) {
                                const d = pairedDevicesModel.get(i)
                                if (d && d.deviceId === endpointEditDialog.deviceId) return true
                            }
                            return false
                        })()
                        if (!paired) {
                            endpointEditDialog.statusText = "Device is not paired yet. Pair first, then connect."
                            return
                        }
                        if (DataStore.setPairedDevicePreferredEndpoint) {
                            DataStore.setPairedDevicePreferredEndpoint(endpointEditDialog.deviceId, host, port)
                        } else {
                            DataStore.updatePairedDeviceEndpoint(endpointEditDialog.deviceId, host, port)
                        }
                        syncController.connectToPeer(endpointEditDialog.deviceId, host, port)
                        endpointEditDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: manualAddDialog
        title: "Add via Hostname"
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, root.width - 40)
        standardButtons: Dialog.NoButton

        property string hostText: ""
        property string portText: ""
        property string statusText: ""
        property var pending: null

        function trimmed(text) { return text ? text.trim() : "" }
        function parsedPortOrDefault() {
            const t = trimmed(portText)
            if (t === "") return 47888
            const n = parseInt(t, 10)
            if (isNaN(n)) return -1
            return n
        }

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusMedium
        }

        contentItem: Item {
            implicitWidth: 420
            implicitHeight: manualAddContentLayout.implicitHeight + ThemeManager.spacingMedium * 2

            ColumnLayout {
                id: manualAddContentLayout
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium

                Text {
                    Layout.fillWidth: true
                    text: "Enter a DNS name resolvable on this device (e.g. MagicDNS). If port is empty, 47888 is used."
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "devicename or devicename.tailnet.ts.net"
                    text: manualAddDialog.hostText
                    onTextChanged: manualAddDialog.hostText = text
                }

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "Port (optional)"
                    inputMethodHints: Qt.ImhDigitsOnly
                    text: manualAddDialog.portText
                    onTextChanged: manualAddDialog.portText = text
                }

                Text {
                    Layout.fillWidth: true
                    text: manualAddDialog.statusText
                    visible: manualAddDialog.statusText !== ""
                    color: ThemeManager.textMuted
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Button {
                        Layout.fillWidth: true
                        text: "Cancel"
                        onClicked: {
                            manualAddDialog.pending = null
                            manualAddDialog.close()
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Add Device"
                        enabled: manualAddDialog.trimmed(manualAddDialog.hostText).length > 0
                        onClicked: {
                            if (!syncController || !syncController.syncing) {
                                manualAddDialog.statusText = "Sync is not running. Pair devices first, then try again."
                                return
                            }
                            const host = manualAddDialog.trimmed(manualAddDialog.hostText)
                            const port = manualAddDialog.parsedPortOrDefault()
                            if (port <= 0 || port > 65535) {
                                manualAddDialog.statusText = "Invalid port"
                                return
                            }
                            console.log("SettingsDialog: manualDeviceAddRequested host=", host, "port=", port)
                            manualAddDialog.pending = { host: host, port: port, startedAt: Date.now() }
                            manualAddDialog.statusText = "Connecting…"
                            root.manualDeviceAddRequested(host, port)
                        }
                    }
                }
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
        property bool exportSucceeded: false
        property string exportFolderPickerStatus: ""
        property url folderPickerCurrentFolder: ""
        property url folderPickerSelectedFolder: ""
        property string exportFolderPickerPathText: ""
        property url importSourceFolder: ""
        property int importFormatIndex: 0 // 0=auto, 1=markdown, 2=html
        property bool importReplaceExisting: false
        property string importStatus: ""
        property bool importSucceeded: false
        property string importFolderPickerStatus: ""
        property url importFolderPickerCurrentFolder: ""
        property url importFolderPickerSelectedFolder: ""
        property string importFolderPickerPathText: ""
        property string newFolderName: ""
        property string newFolderTarget: "export" // export | import | db
        property string databaseStatus: ""
        property bool databaseSucceeded: false
        property string databaseFolderPickerStatus: ""
        property string databaseFolderPickerMode: "move" // move | select
        property url databaseFolderPickerCurrentFolder: ""
        property url databaseFolderPickerSelectedFolder: ""
        property string databaseFolderPickerPathText: ""
        property url databaseCreateFolder: ""
        property string newDbFileName: "zinc.db"
        property string databaseFilePickerStatus: ""
        property url databaseFilePickerCurrentFolder: ""
        property url databaseFilePickerSelectedFile: ""
        property string databaseFilePickerPathText: ""

        function _normalizePathText(text) {
            return text ? text.trim() : ""
        }

        function _localPathFromUrl(url) {
            if (!url || url === "") return ""
            const s = url.toString ? url.toString() : ("" + url)
            return s.replace("file://", "")
        }

        function _urlFromUserPathText(text) {
            const t = _normalizePathText(text)
            if (t === "") return ""
            if (t.indexOf("file:") === 0) return t
            return "file://" + t
        }

        function _looksLikeFilePath(pathText) {
            const t = _normalizePathText(pathText)
            if (t === "" || t.endsWith("/")) return false
            const lastSlash = Math.max(t.lastIndexOf("/"), t.lastIndexOf("\\"))
            const lastDot = t.lastIndexOf(".")
            return lastDot > lastSlash
        }

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
            exportFolderPickerStatus = ""
            folderPickerCurrentFolder = exportDestinationFolder
            folderPickerSelectedFolder = ""
            exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
            exportFolderPickerDialog.open()
        }

        function ensureImportSourceFolder() {
            const hasFolder = importSourceFolder && importSourceFolder !== "" &&
                importSourceFolder.toString().indexOf("file:") === 0
            if (hasFolder) return
            importSourceFolder = DataStore ? DataStore.exportLastFolder() : ""
        }

        function openImportFolderPicker() {
            ensureImportSourceFolder()
            importFolderPickerStatus = ""
            importFolderPickerCurrentFolder = importSourceFolder
            importFolderPickerSelectedFolder = ""
            importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
            importFolderPickerDialog.open()
        }

        function ensureDatabaseFolderPicker() {
            const folder = DataStore ? DataStore.databaseFolder() : ""
            const hasFolder = folder && folder !== "" && folder.toString().indexOf("file:") === 0
            databaseFolderPickerCurrentFolder = hasFolder ? folder : (DataStore ? DataStore.exportLastFolder() : "")
            databaseFolderPickerSelectedFolder = ""
            databaseFolderPickerStatus = ""
        }

        function openDatabaseFolderPicker() {
            databaseFolderPickerMode = "move"
            ensureDatabaseFolderPicker()
            databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
            databaseFolderPickerDialog.open()
        }

        function openDatabaseCreateFolderPicker() {
            databaseFolderPickerMode = "select"
            ensureDatabaseFolderPicker()
            databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
            databaseFolderPickerDialog.open()
        }

        function openDatabaseFilePicker() {
            const folder = DataStore ? DataStore.databaseFolder() : ""
            const hasFolder = folder && folder !== "" && folder.toString().indexOf("file:") === 0
            databaseFilePickerCurrentFolder = hasFolder ? folder : (DataStore ? DataStore.exportLastFolder() : "")
            databaseFilePickerSelectedFile = ""
            databaseFilePickerStatus = ""
            databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
            databaseFilePickerDialog.open()
        }

        Component.onCompleted: {
            refreshNotebooks()
            ensureExportDestinationFolder()
            ensureImportSourceFolder()
        }

        property Connections _dataStoreConnections: Connections {
            target: DataStore
            function onNotebooksChanged() { refreshNotebooks() }
            function onError(message) {
                if (newFolderDialog && newFolderDialog.visible) {
                    if (newFolderTarget === "import") {
                        importFolderPickerStatus = message
                    } else if (newFolderTarget === "db") {
                        if (databaseFilePickerDialog && databaseFilePickerDialog.visible) {
                            databaseFilePickerStatus = message
                        } else {
                            databaseFolderPickerStatus = message
                        }
                    } else {
                        exportFolderPickerStatus = message
                    }
                    return
                }
                if (databaseFolderPickerDialog && databaseFolderPickerDialog.visible) {
                    databaseFolderPickerStatus = message
                    return
                }
                if (databaseFilePickerDialog && databaseFilePickerDialog.visible) {
                    databaseFilePickerStatus = message
                    return
                }
                if (createDatabaseDialog && createDatabaseDialog.visible) {
                    databaseStatus = message
                    databaseSucceeded = false
                    return
                }
                if (importFolderPickerDialog && importFolderPickerDialog.visible) {
                    importFolderPickerStatus = message
                    return
                }
                if (exportFolderPickerDialog && exportFolderPickerDialog.visible) {
                    exportFolderPickerStatus = message
                    return
                }
                if (importDialog && importDialog.visible) {
                    importStatus = message
                    importSucceeded = false
                } else {
                    exportStatus = message
                    exportSucceeded = false
                }
            }
        }

        SettingsSection {
            title: "Database"
            
            Text {
                Layout.fillWidth: true
                text: "Path: " + (DataStore ? DataStore.databasePath : "N/A")
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.WrapAnywhere
            }
            
            Text {
                text: "Schema: " + (DataStore && DataStore.schemaVersion >= 0 ? ("v" + DataStore.schemaVersion) : "N/A")
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
            }

            Text {
                Layout.fillWidth: true
                visible: databaseStatus && databaseStatus.length > 0
                text: databaseStatus
                color: databaseSucceeded ? ThemeManager.success : ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            Button {
                Layout.fillWidth: true
                text: "Move Database…"

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
                    databaseStatus = ""
                    databaseSucceeded = false
                    openDatabaseFolderPicker()
                }
            }

            Button {
                Layout.fillWidth: true
                text: "Create New Database…"

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
                    databaseStatus = ""
                    databaseSucceeded = false
                    ensureDatabaseFolderPicker()
                    newDbFileName = "zinc.db"
                    databaseCreateFolder = DataStore ? DataStore.databaseFolder() : ""
                    createDatabaseDialog.open()
                }
            }

            Button {
                Layout.fillWidth: true
                text: "Open Database…"

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
                    databaseStatus = ""
                    databaseSucceeded = false
                    openDatabaseFilePicker()
                }
            }

            Button {
                Layout.fillWidth: true
                text: "Close Database"
                enabled: DataStore && DataStore.schemaVersion >= 0

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
                    if (!DataStore) return
                    DataStore.closeDatabase()
                    databaseSucceeded = true
                    databaseStatus = "Database closed."
                }
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
                    exportSucceeded = false
                    refreshNotebooks()
                    ensureExportDestinationFolder()
                    exportDialog.open()
                }
            }
        }

        SettingsSection {
            title: "Import"

            Button {
                Layout.fillWidth: true
                text: "Import Notebooks…"

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
                    importStatus = ""
                    importSucceeded = false
                    ensureImportSourceFolder()
                    importDialog.open()
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
                        onClicked: {
                            exportStatus = ""
                            exportSucceeded = false
                            openFolderPicker()
                        }
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
                    color: exportSucceeded ? ThemeManager.success : ThemeManager.danger
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
                            exportStatus = ""
                            exportSucceeded = false
                            const ids = exportAllNotebooks ? [] : selectedNotebookIds()
                            const fmt = exportFormatIndex === 0 ? "markdown" : "html"
                            DataStore.setExportLastFolder(exportDestinationFolder)
                            const ok = DataStore.exportNotebooks(ids, exportDestinationFolder, fmt, exportIncludeAttachments)
                            if (ok) {
                                exportSucceeded = true
                                exportStatus = "Export complete."
                            }
                        }
                    }
                }
            }
        }

        property Dialog _importDialog: Dialog {
            id: importDialog
            title: "Import Notebooks"
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
                        model: ["Auto", "Markdown (.md)", "HTML (.html)"]
                        currentIndex: importFormatIndex
                        onCurrentIndexChanged: importFormatIndex = currentIndex
                    }
                }

                SettingsRow {
                    label: "Behavior"
                    CheckBox {
                        text: "Replace existing data"
                        checked: importReplaceExisting
                        onToggled: importReplaceExisting = checked
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: importReplaceExisting
                    text: "Replacing existing data will erase your current notebooks and attachments before importing."
                    color: ThemeManager.danger
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Button {
                        text: "Choose Folder…"
                        onClicked: {
                            importStatus = ""
                            importSucceeded = false
                            openImportFolderPicker()
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: importSourceFolder && importSourceFolder !== ""
                            ? importSourceFolder.toString().replace("file://", "")
                            : "No folder selected"
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideMiddle
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: importStatus && importStatus.length > 0
                    text: importStatus
                    color: importSucceeded ? ThemeManager.success : ThemeManager.danger
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Cancel"
                        onClicked: importDialog.close()
                    }

                    Button {
                        text: "Import"
                        enabled: importSourceFolder && importSourceFolder !== ""
                        onClicked: {
                            if (!DataStore) return
                            importStatus = ""
                            importSucceeded = false
                            const fmt = importFormatIndex === 0 ? "auto" : (importFormatIndex === 1 ? "markdown" : "html")
                            const ok = DataStore.importNotebooks(importSourceFolder, fmt, importReplaceExisting)
                            if (ok) {
                                importSucceeded = true
                                importStatus = "Import complete."
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
                            exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
                        }
	                    }

	                    Button {
	                        text: "New Folder…"
	                        enabled: folderPickerCurrentFolder && folderPickerCurrentFolder !== ""
	                        onClicked: {
	                            newFolderName = ""
	                            newFolderTarget = "export"
	                            exportFolderPickerStatus = ""
	                            newFolderDialog.open()
	                        }
	                    }

                        TextField {
                            objectName: "exportFolderPickerPathField"
	                        Layout.fillWidth: true
                            placeholderText: "Path"
                            text: exportFolderPickerPathText
                            selectByMouse: true
                            onTextChanged: exportFolderPickerPathText = text
                            onAccepted: {
                                const url = _urlFromUserPathText(exportFolderPickerPathText)
                                if (!url || url === "") return
                                exportFolderPickerStatus = ""
                                folderPickerCurrentFolder = url
                                folderPickerSelectedFolder = ""
                            }
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
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
                            objectName: "exportFolderListModel"
                            folder: folderPickerCurrentFolder
                            showDirs: true
                            showFiles: false
                            showHidden: true
                            showDotAndDotDot: false
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
                                        exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
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

	                Text {
	                    Layout.fillWidth: true
	                    visible: exportFolderPickerStatus && exportFolderPickerStatus.length > 0
	                    text: exportFolderPickerStatus
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

        property Dialog _databaseFolderPickerDialog: Dialog {
            id: databaseFolderPickerDialog
            title: "Choose Database Folder"
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
                        enabled: DataStore && databaseFolderPickerCurrentFolder !== "" &&
                            DataStore.parentFolder(databaseFolderPickerCurrentFolder).toString() !== databaseFolderPickerCurrentFolder.toString()
                        onClicked: {
                            if (!DataStore) return
                            databaseFolderPickerCurrentFolder = DataStore.parentFolder(databaseFolderPickerCurrentFolder)
                            databaseFolderPickerSelectedFolder = ""
                            databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
                        }
                    }

                    Button {
                        text: "New Folder…"
                        enabled: databaseFolderPickerCurrentFolder && databaseFolderPickerCurrentFolder !== ""
                        onClicked: {
                            newFolderName = ""
                            newFolderTarget = "db"
                            databaseFolderPickerStatus = ""
                            newFolderDialog.open()
                        }
                    }

                    TextField {
                        objectName: "databaseFolderPickerPathField"
                        Layout.fillWidth: true
                        placeholderText: "Path"
                        text: databaseFolderPickerPathText
                        selectByMouse: true
                        onTextChanged: databaseFolderPickerPathText = text
                        onAccepted: {
                            const url = _urlFromUserPathText(databaseFolderPickerPathText)
                            if (!url || url === "") return
                            databaseFolderPickerStatus = ""
                            databaseFolderPickerCurrentFolder = url
                            databaseFolderPickerSelectedFolder = ""
                        }
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
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
                        anchors.fill: parent
                        anchors.margins: ThemeManager.spacingSmall
                        clip: true
                        model: FolderListModel {
                            objectName: "databaseFolderListModel"
                            folder: databaseFolderPickerCurrentFolder
                            showDirs: true
                            showFiles: false
                            showHidden: true
                            showDotAndDotDot: false
                            sortField: FolderListModel.Name
                        }

                        delegate: Rectangle {
                            readonly property string dirUrl: "file://" + filePath
                            width: ListView.view.width
                            height: 36
                            radius: ThemeManager.radiusSmall
                            color: (databaseFolderPickerSelectedFolder && databaseFolderPickerSelectedFolder.toString() === dirUrl)
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
                                onClicked: databaseFolderPickerSelectedFolder = dirUrl
                                onDoubleClicked: {
                                    databaseFolderPickerCurrentFolder = dirUrl
                                    databaseFolderPickerSelectedFolder = ""
                                    databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
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
                        text: databaseFolderPickerSelectedFolder && databaseFolderPickerSelectedFolder !== ""
                            ? ("Selected: " + databaseFolderPickerSelectedFolder.toString().replace("file://", ""))
                            : "Selected: (current folder)"
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideMiddle
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: databaseFolderPickerStatus && databaseFolderPickerStatus.length > 0
                    text: databaseFolderPickerStatus
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
                        onClicked: databaseFolderPickerDialog.close()
                    }

                    Button {
                        text: databaseFolderPickerMode === "move" ? "Move Here" : "Choose"
                        enabled: databaseFolderPickerCurrentFolder && databaseFolderPickerCurrentFolder !== ""
                        onClicked: {
                            if (!DataStore) return
                            const chosen = (databaseFolderPickerSelectedFolder && databaseFolderPickerSelectedFolder !== "")
                                ? databaseFolderPickerSelectedFolder
                                : databaseFolderPickerCurrentFolder
                            databaseFolderPickerStatus = ""
                            if (databaseFolderPickerMode === "move") {
                                const ok = DataStore.moveDatabaseToFolder(chosen)
                                if (ok) {
                                    databaseSucceeded = true
                                    databaseStatus = "Database moved."
                                    refreshNotebooks()
                                    databaseFolderPickerDialog.close()
                                }
                            } else {
                                databaseCreateFolder = chosen
                                databaseFolderPickerDialog.close()
                            }
                        }
                    }
                }
            }
        }

        property Dialog _newFolderDialog: Dialog {
            id: newFolderDialog
            title: "New Folder"
            anchors.centerIn: parent
            modal: true
            standardButtons: Dialog.NoButton

            width: isMobile ? parent.width * 0.95 : Math.min(420, parent.width * 0.9)

            background: Rectangle {
                color: ThemeManager.surface
                border.width: isMobile ? 0 : 1
                border.color: ThemeManager.border
                radius: ThemeManager.radiusLarge
            }

            contentItem: ColumnLayout {
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "Folder name"
                    text: newFolderName
                    onTextChanged: newFolderName = text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Cancel"
                        onClicked: newFolderDialog.close()
                    }

	                    Button {
	                        text: "Create"
	                        enabled: newFolderName && newFolderName.trim().length > 0
	                        onClicked: {
	                            if (!DataStore) return
	                            const parentUrl = newFolderTarget === "import"
	                                ? importFolderPickerCurrentFolder
	                                : (newFolderTarget === "db" ? databaseFolderPickerCurrentFolder : folderPickerCurrentFolder)
	                            const created = DataStore.createFolder(parentUrl, newFolderName)
	                            if (created && created.toString && created.toString() !== "") {
	                                if (newFolderTarget === "import") {
	                                    importFolderPickerCurrentFolder = created
	                                    importFolderPickerSelectedFolder = ""
	                                    importFolderPickerStatus = ""
                                        importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
	                                } else if (newFolderTarget === "db") {
	                                    if (databaseFilePickerDialog && databaseFilePickerDialog.visible) {
	                                        databaseFilePickerCurrentFolder = created
	                                        databaseFilePickerSelectedFile = ""
	                                        databaseFilePickerStatus = ""
                                            databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
	                                    } else {
	                                        databaseFolderPickerCurrentFolder = created
	                                        databaseFolderPickerSelectedFolder = ""
	                                        databaseFolderPickerStatus = ""
                                            databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
	                                    }
	                                } else {
	                                    folderPickerCurrentFolder = created
	                                    folderPickerSelectedFolder = ""
	                                    exportFolderPickerStatus = ""
                                        exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
	                                }
	                            } else {
	                                const msg = "Could not create folder."
	                                if (newFolderTarget === "import") importFolderPickerStatus = msg
	                                else if (newFolderTarget === "db") {
	                                    if (databaseFilePickerDialog && databaseFilePickerDialog.visible) databaseFilePickerStatus = msg
	                                    else databaseFolderPickerStatus = msg
	                                }
	                                else exportFolderPickerStatus = msg
	                            }
	                            newFolderDialog.close()
	                        }
	                    }
                }
            }
        }

        property Dialog _createDatabaseDialog: Dialog {
            id: createDatabaseDialog
            title: "Create New Database"
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
                    label: "Folder"
                    Button {
                        text: "Choose Folder…"
                        onClicked: {
                            databaseFolderPickerStatus = ""
                            openDatabaseCreateFolderPicker()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: databaseCreateFolder && databaseCreateFolder !== ""
                        ? databaseCreateFolder.toString().replace("file://", "")
                        : "(not selected)"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideMiddle
                }

                SettingsRow {
                    label: "File name"
                    TextField {
                        Layout.fillWidth: true
                        placeholderText: "zinc.db"
                        text: newDbFileName
                        onTextChanged: newDbFileName = text
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: databaseFolderPickerStatus && databaseFolderPickerStatus.length > 0
                    text: databaseFolderPickerStatus
                    color: ThemeManager.danger
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: databaseStatus && databaseStatus.length > 0
                    text: databaseStatus
                    color: databaseSucceeded ? ThemeManager.success : ThemeManager.danger
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Cancel"
                        onClicked: createDatabaseDialog.close()
                    }

                    Button {
                        text: "Create"
                        enabled: databaseCreateFolder && databaseCreateFolder !== "" && newDbFileName && newDbFileName.trim().length > 0
                        onClicked: {
                            if (!DataStore) return
                            databaseStatus = ""
                            databaseSucceeded = false
                            const ok = DataStore.createNewDatabase(databaseCreateFolder, newDbFileName)
                            if (ok) {
                                databaseSucceeded = true
                                databaseStatus = "Database created."
                                refreshNotebooks()
                                createDatabaseDialog.close()
                            }
                        }
                    }
                }
            }
        }

        property Dialog _databaseFilePickerDialog: Dialog {
            id: databaseFilePickerDialog
            title: "Open Database"
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
                        enabled: DataStore && databaseFilePickerCurrentFolder !== "" &&
                            DataStore.parentFolder(databaseFilePickerCurrentFolder).toString() !== databaseFilePickerCurrentFolder.toString()
                        onClicked: {
                            if (!DataStore) return
                            databaseFilePickerCurrentFolder = DataStore.parentFolder(databaseFilePickerCurrentFolder)
                            databaseFilePickerSelectedFile = ""
                            databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
                        }
                    }

                    Button {
                        text: "New Folder…"
                        enabled: databaseFilePickerCurrentFolder && databaseFilePickerCurrentFolder !== ""
                        onClicked: {
                            newFolderName = ""
                            newFolderTarget = "db"
                            databaseFilePickerStatus = ""
                            // Reuse new-folder dialog against current folder.
                            databaseFolderPickerCurrentFolder = databaseFilePickerCurrentFolder
                            databaseFolderPickerSelectedFolder = ""
                            newFolderDialog.open()
                        }
                    }

                    TextField {
                        objectName: "databaseFilePickerPathField"
                        Layout.fillWidth: true
                        placeholderText: "Path (folder or database file)"
                        text: databaseFilePickerPathText
                        selectByMouse: true
                        onTextChanged: databaseFilePickerPathText = text
                        onAccepted: {
                            if (!DataStore) return
                            const url = _urlFromUserPathText(databaseFilePickerPathText)
                            if (!url || url === "") return
                            databaseFilePickerStatus = ""
                            if (_looksLikeFilePath(databaseFilePickerPathText)) {
                                databaseFilePickerSelectedFile = url
                                databaseFilePickerCurrentFolder = DataStore.parentFolder(url)
                                return
                            }
                            databaseFilePickerCurrentFolder = url
                            databaseFilePickerSelectedFile = ""
                        }
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
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
                        anchors.fill: parent
                        anchors.margins: ThemeManager.spacingSmall
                        clip: true
                        model: FolderListModel {
                            objectName: "databaseFileListModel"
                            folder: databaseFilePickerCurrentFolder
                            showDirs: true
                            showFiles: true
                            showHidden: true
                            showDotAndDotDot: false
                            nameFilters: ["*.db", "*.sqlite", "*.sqlite3"]
                            sortField: FolderListModel.Name
                        }

                        delegate: Rectangle {
                            readonly property string itemUrl: "file://" + filePath
                            width: ListView.view.width
                            height: 36
                            radius: ThemeManager.radiusSmall
                            color: (databaseFilePickerSelectedFile && databaseFilePickerSelectedFile.toString() === itemUrl)
                                ? ThemeManager.surfaceHover
                                : (rowMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: ThemeManager.spacingSmall
                                anchors.rightMargin: ThemeManager.spacingSmall
                                spacing: ThemeManager.spacingSmall

                                Text {
                                    text: fileIsDir ? "📁" : "📄"
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
                                onClicked: {
                                    databaseFilePickerSelectedFile = itemUrl
                                    databaseFilePickerPathText = _localPathFromUrl(itemUrl)
                                }
                                onDoubleClicked: {
                                    if (fileIsDir) {
                                        databaseFilePickerCurrentFolder = itemUrl
                                        databaseFilePickerSelectedFile = ""
                                        databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
                                        return
                                    }
                                    databaseFilePickerSelectedFile = itemUrl
                                    databaseFilePickerPathText = _localPathFromUrl(itemUrl)
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: databaseFilePickerSelectedFile && databaseFilePickerSelectedFile !== ""
                        ? ("Selected: " + databaseFilePickerSelectedFile.toString().replace("file://", ""))
                        : "Selected: (none)"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideMiddle
                }

                Text {
                    Layout.fillWidth: true
                    visible: databaseFilePickerStatus && databaseFilePickerStatus.length > 0
                    text: databaseFilePickerStatus
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
                        onClicked: databaseFilePickerDialog.close()
                    }

                    Button {
                        text: "Open"
                        enabled: databaseFilePickerSelectedFile && databaseFilePickerSelectedFile !== "" && !databaseFilePickerSelectedFile.toString().endsWith("/")
                        onClicked: {
                            if (!DataStore) return
                            databaseFilePickerStatus = ""
                            const ok = DataStore.openDatabaseFile(databaseFilePickerSelectedFile)
                            if (ok) {
                                databaseSucceeded = true
                                databaseStatus = "Database opened."
                                refreshNotebooks()
                                databaseFilePickerDialog.close()
                            }
                        }
                    }
                }
            }
        }

        property Dialog _importFolderPickerDialog: Dialog {
            id: importFolderPickerDialog
            title: "Choose Import Folder"
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
                spacing: ThemeManager.spacingSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Button {
                        text: "Up"
                        enabled: DataStore && importFolderPickerCurrentFolder && importFolderPickerCurrentFolder !== "" &&
                                 DataStore.parentFolder(importFolderPickerCurrentFolder).toString() !== importFolderPickerCurrentFolder.toString()
                        onClicked: {
                            if (!DataStore) return
                            importFolderPickerCurrentFolder = DataStore.parentFolder(importFolderPickerCurrentFolder)
                            importFolderPickerSelectedFolder = ""
                            importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
                        }
	                    }

	                    Button {
	                        text: "New Folder…"
	                        enabled: importFolderPickerCurrentFolder && importFolderPickerCurrentFolder !== ""
	                        onClicked: {
	                            newFolderName = ""
	                            newFolderTarget = "import"
	                            importFolderPickerStatus = ""
	                            newFolderDialog.open()
	                        }
	                    }

	                    TextField {
                            objectName: "importFolderPickerPathField"
	                        Layout.fillWidth: true
                            placeholderText: "Path"
                            text: importFolderPickerPathText
                            selectByMouse: true
                            onTextChanged: importFolderPickerPathText = text
                            onAccepted: {
                                const url = _urlFromUserPathText(importFolderPickerPathText)
                                if (!url || url === "") return
                                importFolderPickerStatus = ""
                                importFolderPickerCurrentFolder = url
                                importFolderPickerSelectedFolder = ""
                            }
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                    }
                }

                FolderListModel {
                    id: importFolderListModel
                    objectName: "importFolderListModel"
                    folder: importFolderPickerCurrentFolder
                    showDirs: true
                    showFiles: false
                    showHidden: true
                    showDotAndDotDot: false
                    sortField: FolderListModel.Name
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 280
                    clip: true

                    ListView {
                        width: parent.width
                        model: importFolderListModel
                        spacing: 2

	                        delegate: Rectangle {
	                            readonly property string dirUrl: "file://" + filePath
	                            width: ListView.view.width
	                            height: 36
	                            radius: ThemeManager.radiusSmall
	                            color: (importFolderPickerSelectedFolder && importFolderPickerSelectedFolder.toString() === dirUrl)
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
	                                onClicked: importFolderPickerSelectedFolder = dirUrl
	                                onDoubleClicked: {
	                                    importFolderPickerCurrentFolder = dirUrl
	                                    importFolderPickerSelectedFolder = ""
                                        importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
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
                        text: importFolderPickerSelectedFolder && importFolderPickerSelectedFolder !== ""
                            ? ("Selected: " + importFolderPickerSelectedFolder.toString().replace("file://", ""))
                            : "Selected: (current folder)"
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideMiddle
	                    }
	                }

	                Text {
	                    Layout.fillWidth: true
	                    visible: importFolderPickerStatus && importFolderPickerStatus.length > 0
	                    text: importFolderPickerStatus
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
                        onClicked: importFolderPickerDialog.close()
                    }

                    Button {
                        text: "Choose"
                        enabled: importFolderPickerCurrentFolder && importFolderPickerCurrentFolder !== ""
                        onClicked: {
                            const chosen = (importFolderPickerSelectedFolder && importFolderPickerSelectedFolder !== "")
                                ? importFolderPickerSelectedFolder
                                : importFolderPickerCurrentFolder
                            importSourceFolder = chosen
                            if (DataStore) DataStore.setExportLastFolder(chosen)
                            importFolderPickerDialog.close()
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
                text: "Version 0.3.0"
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
