import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import "settings" as SettingsPages
import zinc

Dialog {
    id: root
    
    signal pairDeviceRequested()
    signal manualDeviceAddRequested(string host, int port)
    property var syncController: null
    property bool focusDebugLogging: true
    property bool connectProbeDebugLogging: true
    property var connectProbePending: null

    function logConnectProbe(eventName, details) {
        if (!connectProbeDebugLogging) return
        console.log("SettingsDialog connect probe:", eventName, details ? details : "")
    }

    function resolveConnectProbe(reachable, detail) {
        if (!connectProbePending) return
        logConnectProbe("resolve", {
                            reachable: reachable,
                            detail: detail,
                            pending: connectProbePending
                        })
        connectProbeTimer.stop()
        const pending = connectProbePending
        connectProbePending = null
        const label = (pending.deviceName && pending.deviceName !== "") ? pending.deviceName : pending.deviceId
        connectResultDialog.standardButtons = Dialog.Ok
        connectResultDialog.title = reachable ? "Device Reachable" : "Device Unreachable"
        connectResultDialog.resultText = reachable
                ? (label + " responded at " + pending.host + ":" + pending.port + ".")
                : (label + " did not respond at " + pending.host + ":" + pending.port + ".")
        connectResultDialog.detailText = detail ? detail : ""
        connectResultDialog.open()
    }

    function startConnectProbe(deviceId, deviceName, host, port) {
        if (syncController && syncController.isPeerConnected && syncController.isPeerConnected(deviceId)) {
            connectProbePending = {
                deviceId: deviceId,
                deviceName: deviceName ? deviceName : "",
                host: host ? host : "",
                port: port
            }
            resolveConnectProbe(true, "Peer is already connected.")
            return
        }
        connectProbePending = {
            deviceId: deviceId,
            deviceName: deviceName ? deviceName : "",
            host: host ? host : "",
            port: port
        }
        logConnectProbe("start", connectProbePending)
        const label = (deviceName && deviceName !== "") ? deviceName : deviceId
        connectResultDialog.title = "Checking Device"
        connectResultDialog.resultText = "Trying " + label + " at " + host + ":" + port + "…"
        connectResultDialog.detailText = ""
        connectResultDialog.standardButtons = Dialog.NoButton
        connectResultDialog.open()
        connectProbeTimer.restart()
    }

    function isCurrentConnectProbe(deviceId, host, port) {
        if (!connectProbePending) return false
        if (!deviceId || connectProbePending.deviceId !== deviceId) {
            logConnectProbe("match-miss-device", {
                                probeDeviceId: connectProbePending.deviceId,
                                signalDeviceId: deviceId
                            })
            return false
        }
        if (host && host !== "" && connectProbePending.host && connectProbePending.host !== host) {
            logConnectProbe("match-miss-host", {
                                probeHost: connectProbePending.host,
                                signalHost: host
                            })
            return false
        }
        if (port && port > 0 && connectProbePending.port > 0 && connectProbePending.port !== port) {
            logConnectProbe("match-miss-port", {
                                probePort: connectProbePending.port,
                                signalPort: port
                            })
            return false
        }
        logConnectProbe("match-hit", {
                            deviceId: deviceId,
                            host: host,
                            port: port
                        })
        return true
    }

    function currentWindowFocusItem() {
        const win = Window.window ? Window.window : Qt.application.activeWindow
        if (win && win.activeFocusItem) return win.activeFocusItem
        return null
    }

    function hasActiveFocusWithin(node) {
        if (!node) return false
        if (node.activeFocus === true) return true
        const descendents = []
        const children = node.children || []
        for (let i = 0; i < children.length; i++) descendents.push(children[i])
        const contentChildren = node.contentChildren || []
        for (let i = 0; i < contentChildren.length; i++) descendents.push(contentChildren[i])
        const data = node.data || []
        for (let i = 0; i < data.length; i++) descendents.push(data[i])
        for (let i = 0; i < descendents.length; i++) {
            if (hasActiveFocusWithin(descendents[i])) return true
        }
        return false
    }

    function settingsPageAt(index) {
        if (!settingsTabs || index < 0) return null
        const pages = []
        const children = settingsTabs.children || []
        for (let i = 0; i < children.length; i++) {
            const child = children[i]
            if (!child) continue
            // Keep only actual page items, skip layout internals.
            if (typeof child.focusFirstControl === "function" || "forceActiveFocus" in child) {
                pages.push(child)
            }
        }
        return (index >= 0 && index < pages.length) ? pages[index] : null
    }

    function isDescendantOf(node, ancestor) {
        let cur = node || null
        while (cur) {
            if (cur === ancestor) return true
            cur = cur.parent || null
        }
        return false
    }

    function activeFocusInDesktopTabList() {
        const focusItem = currentWindowFocusItem()
        return isDescendantOf(focusItem, desktopTabList) || hasActiveFocusWithin(desktopTabList)
    }

    function activeFocusInSettingsContent() {
        const focusItem = currentWindowFocusItem()
        return isDescendantOf(focusItem, settingsTabs) || hasActiveFocusWithin(settingsTabs)
    }

    function focusFirstSettingControl() {
        const page = settingsPageAt(settingsTabs.currentIndex)
        if (!page) {
            if (focusDebugLogging) {
                console.log("SettingsDialog focus: no current page for index=", settingsTabs.currentIndex,
                            "children=", settingsTabs.children ? settingsTabs.children.length : 0)
            }
            return
        }

        if (focusDebugLogging) {
            console.log("SettingsDialog focus: current page=", page, "objectName=", page.objectName ? page.objectName : "")
        }

        if (typeof page.focusFirstControl === "function") {
            const handled = page.focusFirstControl()
            if (focusDebugLogging) {
                console.log("SettingsDialog focus: page.focusFirstControl handled=", handled,
                            "activeFocusItem=", currentWindowFocusItem())
            }
            if (handled) return
        }

        function findFocusable(node) {
            if (!node) return null
            const wantsFocus = node.visible !== false
                && node.enabled !== false
                && node.activeFocusOnTab === true
                && ("forceActiveFocus" in node)
            if (wantsFocus) return node
            const descendents = []
            const children = node.children || []
            for (let i = 0; i < children.length; i++) descendents.push(children[i])
            const contentChildren = node.contentChildren || []
            for (let i = 0; i < contentChildren.length; i++) descendents.push(contentChildren[i])
            const data = node.data || []
            for (let i = 0; i < data.length; i++) descendents.push(data[i])
            for (let i = 0; i < descendents.length; i++) {
                const found = findFocusable(descendents[i])
                if (found) return found
            }
            return null
        }

        const target = findFocusable(page)
        if (target) {
            if (focusDebugLogging) {
                console.log("SettingsDialog focus: fallback target=", target,
                            "objectName=", target.objectName ? target.objectName : "")
            }
            target.forceActiveFocus()
            if (focusDebugLogging) {
                console.log("SettingsDialog focus: fallback focused activeFocusItem=", currentWindowFocusItem())
            }
            return
        }
        if ("forceActiveFocus" in page) {
            if (focusDebugLogging) console.log("SettingsDialog focus: focusing page directly")
            page.forceActiveFocus()
            if (focusDebugLogging) {
                console.log("SettingsDialog focus: page focused activeFocusItem=", currentWindowFocusItem())
            }
            return
        }
        if (focusDebugLogging) console.log("SettingsDialog focus: no focusable target found")
    }

    Keys.onPressed: function(event) {
        if (isMobile) return
        if (!root.visible) return

        const key = event.key
        const isShiftTab = key === Qt.Key_Backtab || (key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))
        if (isShiftTab && activeFocusInSettingsContent()) {
            if (focusDebugLogging) {
                console.log("SettingsDialog keys: reverse transfer requested key=", key,
                            "activeFocusItem=", currentWindowFocusItem())
            }
            event.accepted = true
            desktopTabList.forceActiveFocus()
            return
        }

        const isForwardTab = key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)
        const isEnter = key === Qt.Key_Return || key === Qt.Key_Enter
        if ((isForwardTab || isEnter) && activeFocusInDesktopTabList()) {
            if (focusDebugLogging) {
                console.log("SettingsDialog keys: transfer requested key=", key,
                            "activeFocusItem=", currentWindowFocusItem())
            }
            event.accepted = true
            focusFirstSettingControl()
            return
        }
    }

    Shortcut {
        sequence: "Shift+Tab"
        context: Qt.WindowShortcut
        enabled: !isMobile && root.visible
        onActivated: {
            if (!root.activeFocusInSettingsContent()) return
            if (root.focusDebugLogging) {
                console.log("SettingsDialog shortcut: Shift+Tab -> sidebar",
                            "activeFocusItem=", root.currentWindowFocusItem())
            }
            desktopTabList.forceActiveFocus()
        }
    }

    function openDevicesTab() {
        // Devices tab index matches tabModel ordering.
        settingsTabs.currentIndex = 4
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
        var pairedNames = {}
        var pairedDevices = DataStore ? DataStore.getPairedDevices() : []
        for (var j = 0; j < pairedDevices.length; j++) {
            var paired = pairedDevices[j]
            if (!paired) continue
            if (!paired.deviceId || paired.deviceId === "") continue
            if (!paired.deviceName || paired.deviceName === "") continue
            pairedNames[paired.deviceId] = paired.deviceName
        }
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            if (!d) continue
            // Filter out other workspaces if we know ours.
            if (syncController.workspaceId && syncController.workspaceId !== "" &&
                d.workspaceId && d.workspaceId !== "" &&
                d.workspaceId !== syncController.workspaceId) {
                continue
            }
            availableDevicesModel.append({
                deviceId: d.deviceId,
                deviceName: d.deviceName,
                pairedDeviceName: pairedNames[d.deviceId] ? pairedNames[d.deviceId] : "",
                workspaceId: d.workspaceId,
                host: d.host,
                port: d.port,
                lastSeen: d.lastSeen
            })
        }
    }

    Timer {
        id: connectProbeTimer
        interval: 8000
        repeat: false
        running: false
        onTriggered: {
            if (!connectProbePending) return
            logConnectProbe("timeout", connectProbePending)
            resolveConnectProbe(false, "No response was received before timeout.")
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
            logConnectProbe("signal-error", message)
            if (manualAddDialog.visible) manualAddDialog.statusText = message
            if (endpointEditDialog.visible) endpointEditDialog.statusText = message
            if (connectProbePending) {
                resolveConnectProbe(false, message)
            }

            if (manualAddDialog.visible && manualAddDialog.pending && message && message.indexOf("closed the connection") >= 0) {
                manualAddDialog.statusText =
                    message + "\n\nTip: manual connections require both devices to already be in the same workspace (paired)."
            }
        }

        function onPeerApprovalRequired(deviceId, deviceName, host, port) {
            console.log("SettingsDialog: peerApprovalRequired", deviceId, deviceName, host, port)
            logConnectProbe("signal-peerApprovalRequired", {
                                deviceId: deviceId, deviceName: deviceName, host: host, port: port
                            })
            if (manualAddDialog.visible && manualAddDialog.pending) {
                manualAddDialog.statusText = "Awaiting confirmation on the other device…"
            }
            if (isCurrentConnectProbe(deviceId, host, port)) {
                resolveConnectProbe(true, "The device responded and requires approval on the remote side.")
            }
        }

        function onPeerHelloReceived(deviceId, deviceName, host, port) {
            console.log("SettingsDialog: peerHelloReceived", deviceId, deviceName, host, port)
            logConnectProbe("signal-peerHelloReceived", {
                                deviceId: deviceId, deviceName: deviceName, host: host, port: port
                            })
            if (DataStore && deviceId && deviceId !== "" && host && host !== "" && port && port > 0) {
                DataStore.updatePairedDeviceEndpoint(deviceId, host, port)
            }
            if (isCurrentConnectProbe(deviceId, host, port)) {
                resolveConnectProbe(true, "Handshake succeeded.")
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
            logConnectProbe("signal-peerIdentityMismatch", {
                                expectedDeviceId: expectedDeviceId,
                                actualDeviceId: actualDeviceId,
                                deviceName: deviceName,
                                host: host,
                                port: port
                            })
            if (manualAddDialog.visible && manualAddDialog.pending) {
                manualAddDialog.statusText = "Device was reset/reinstalled. Re-pair is required."
            }
            if (endpointEditDialog.visible) {
                endpointEditDialog.statusText = "Device was reset/reinstalled. Re-pair is required."
            }
            if (isCurrentConnectProbe(expectedDeviceId, host, port)) {
                resolveConnectProbe(true, "Device responded, but identity mismatch means re-pairing is required.")
            }
        }

        function onPeerWorkspaceMismatch(deviceId, remoteWorkspaceId, localWorkspaceId, deviceName, host, port) {
            console.log("SettingsDialog: peerWorkspaceMismatch", deviceId, remoteWorkspaceId, localWorkspaceId, deviceName, host, port)
            logConnectProbe("signal-peerWorkspaceMismatch", {
                                deviceId: deviceId,
                                remoteWorkspaceId: remoteWorkspaceId,
                                localWorkspaceId: localWorkspaceId,
                                deviceName: deviceName,
                                host: host,
                                port: port
                            })
            if (manualAddDialog.visible && manualAddDialog.pending) {
                manualAddDialog.statusText = "Device is not in this workspace. Re-pair is required."
            }
            if (endpointEditDialog.visible) {
                endpointEditDialog.statusText = "Device is not in this workspace. Re-pair is required."
            }
            if (isCurrentConnectProbe(deviceId, host, port)) {
                resolveConnectProbe(true, "Device responded, but it belongs to a different workspace.")
            }
        }

        function onPeerConnected(deviceId) {
            logConnectProbe("signal-peerConnected", { deviceId: deviceId })
            if (isCurrentConnectProbe(deviceId, "", 0)) {
                resolveConnectProbe(true, "Connection established.")
            }
        }

        function onPeerDisconnected(deviceId) {
            logConnectProbe("signal-peerDisconnected", { deviceId: deviceId })
            if (isCurrentConnectProbe(deviceId, "", 0)) {
                resolveConnectProbe(false, "Connection failed or was closed before handshake completed.")
            }
        }

        function onPageSnapshotReceived(jsonPayload) {
            if (!connectProbePending) return
            logConnectProbe("signal-pageSnapshotReceived", {
                                bytes: jsonPayload ? jsonPayload.length : 0
                            })
            resolveConnectProbe(true, "Sync traffic received from a connected peer.")
        }

        function onPageSnapshotReceivedPages(pages) {
            if (!connectProbePending) return
            logConnectProbe("signal-pageSnapshotReceivedPages", {
                                count: pages ? pages.length : 0
                            })
            resolveConnectProbe(true, "Sync data was received from a connected peer.")
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
        border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
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
        { label: "Shortcuts", icon: "⌨️" },
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
                        if (root.focusDebugLogging) {
                            console.log("SettingsDialog tablist keys: key=", event.key,
                                        "currentIndex=", settingsTabs.currentIndex,
                                        "activeFocusItem=", root.currentWindowFocusItem())
                        }
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
                                onClicked: {
                                    settingsTabs.currentIndex = index
                                    desktopTabList.forceActiveFocus()
                                }
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

                SettingsPages.GeneralSettingsPage {}
                SettingsPages.EditorSettingsPage {}
                SettingsPages.KeyboardShortcutsSettingsPage {}
                SettingsPages.SyncSettingsPage { syncController: root.syncController }
                SettingsPages.DevicesSettingsPage {
                    pairedDevicesModel: pairedDevicesModel
                    availableDevicesModel: availableDevicesModel
                    syncController: root.syncController
                    refreshPairedDevices: root.refreshPairedDevices
                    refreshAvailableDevices: root.refreshAvailableDevices
                    connectToPeer: function(deviceId, deviceName, host, port) {
                        if (!root.syncController) return
                        root.startConnectProbe(deviceId, deviceName, host, port)
                        root.syncController.connectToPeer(deviceId, host, port)
                    }
                    openEndpointEditor: function(deviceId, deviceName, host, portText) {
                        endpointEditDialog.deviceId = deviceId
                        endpointEditDialog.deviceName = deviceName
                        endpointEditDialog.hostText = host
                        endpointEditDialog.portText = portText
                        endpointEditDialog.open()
                    }
                    openRenameDeviceDialog: function(deviceId, deviceName) {
                        deviceNameEditDialog.deviceId = deviceId
                        deviceNameEditDialog.currentName = deviceName
                        deviceNameEditDialog.nameText = deviceName
                        deviceNameEditDialog.statusText = ""
                        deviceNameEditDialog.open()
                    }
                    onPairDevice: { root.pairDeviceRequested(); root.close() }
                }
                SettingsPages.DataSettingsPage {
                    isMobile: root.isMobile
                    onResetAllDataRequested: resetConfirmDialog.open()
                }
                SettingsPages.AboutSettingsPage {}
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

                SettingsPages.GeneralSettingsPage {}
                SettingsPages.EditorSettingsPage {}
                SettingsPages.KeyboardShortcutsSettingsPage {}
                SettingsPages.SyncSettingsPage { syncController: root.syncController }
                SettingsPages.DevicesSettingsPage {
                    pairedDevicesModel: pairedDevicesModel
                    availableDevicesModel: availableDevicesModel
                    syncController: root.syncController
                    refreshPairedDevices: root.refreshPairedDevices
                    refreshAvailableDevices: root.refreshAvailableDevices
                    connectToPeer: function(deviceId, deviceName, host, port) {
                        if (!root.syncController) return
                        root.startConnectProbe(deviceId, deviceName, host, port)
                        root.syncController.connectToPeer(deviceId, host, port)
                    }
                    openEndpointEditor: function(deviceId, deviceName, host, portText) {
                        endpointEditDialog.deviceId = deviceId
                        endpointEditDialog.deviceName = deviceName
                        endpointEditDialog.hostText = host
                        endpointEditDialog.portText = portText
                        endpointEditDialog.open()
                    }
                    openRenameDeviceDialog: function(deviceId, deviceName) {
                        deviceNameEditDialog.deviceId = deviceId
                        deviceNameEditDialog.currentName = deviceName
                        deviceNameEditDialog.nameText = deviceName
                        deviceNameEditDialog.statusText = ""
                        deviceNameEditDialog.open()
                    }
                    onPairDevice: { root.pairDeviceRequested(); root.close() }
                }
                SettingsPages.DataSettingsPage {
                    isMobile: root.isMobile
                    onResetAllDataRequested: resetConfirmDialog.open()
                }
                SettingsPages.AboutSettingsPage {}
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
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
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
                
                SettingsPages.SettingsButton {
                    Layout.fillWidth: true
                    text: "Cancel"
                    
                    background: Rectangle {
                        implicitHeight: 40
                        radius: ThemeManager.radiusSmall
                        color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                        border.width: 1
                        border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
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
                
                SettingsPages.SettingsButton {
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
    Dialog {
        id: connectResultDialog
        objectName: "connectResultDialog"
        modal: true
        anchors.centerIn: parent
        width: Math.min(420, root.width - 40)
        standardButtons: Dialog.Ok
        property string resultText: ""
        property string detailText: ""

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusMedium
        }

        contentItem: ColumnLayout {
            spacing: ThemeManager.spacingSmall
            anchors.margins: ThemeManager.spacingMedium

            Text {
                Layout.fillWidth: true
                text: connectResultDialog.resultText
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                text: connectResultDialog.detailText
                visible: connectResultDialog.detailText !== ""
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
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
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
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

                SettingsPages.SettingsButton {
                    text: "Cancel"
                    width: Math.max(120, (deviceNameEditDialog.width - ThemeManager.spacingMedium * 3) / 2)
                    onClicked: deviceNameEditDialog.close()
                }

                SettingsPages.SettingsButton {
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
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
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

                SettingsPages.SettingsButton {
                    Layout.fillWidth: true
                    text: "Cancel"
                    onClicked: endpointEditDialog.close()
                }

                SettingsPages.SettingsButton {
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

                SettingsPages.SettingsButton {
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
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
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

                    SettingsPages.SettingsButton {
                        Layout.fillWidth: true
                        text: "Cancel"
                        onClicked: {
                            manualAddDialog.pending = null
                            manualAddDialog.close()
                        }
                    }

                    SettingsPages.SettingsButton {
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
}
