import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import zinc
import Zinc 1.0
import "../components"

Dialog {
    id: root
    
    title: "Pair Device"
    anchors.centerIn: parent
    modal: true
    standardButtons: Dialog.Cancel
    
    // Responsive sizing
    property bool isMobile: Qt.platform.os === "android" || parent.width < 600
    width: isMobile ? parent.width * 0.95 : Math.min(420, parent.width * 0.9)
    height: isMobile ? parent.height * 0.85 : Math.min(520, parent.height * 0.9)
    
    readonly property bool qrEnabled: FeatureFlags.qrEnabled
    property var qrCamera: null

    property string mode: "select"  // select, qr_show, qr_scan, code_show, code_enter, passphrase
    property string verificationCode: pairingController.verificationCode
    property string qrData: pairingController.qrCodeData
    property string statusOverride: ""
    property string statusMessage: statusOverride !== "" ? statusOverride : pairingController.status
    property bool cameraActive: false
    property bool cameraPermissionGranted: false
    property bool scanInProgress: false
    property string workspaceId: ""
    property string deviceName: "Zinc Device"
    property bool suppressOutgoingSnapshots: false
    property SyncController externalSyncController: null
    readonly property SyncController activeSyncController: externalSyncController ? externalSyncController : internalSyncController
    property string pagesCursorAt: ""
    property string pagesCursorId: ""
    property string deletedPagesCursorAt: ""
    property string deletedPagesCursorId: ""

    PairingController {
        id: pairingController

        onPairingComplete: function() {
            statusOverride = ""
            scanInProgress = false
            var deviceId = pairingController.peerDeviceId
            if (deviceId !== "") {
                var name = pairingController.peerName
                if (name === "") {
                    name = "Paired device"
                }
                var wsId = pairingController.workspaceId
                if (wsId === "") {
                    wsId = workspaceId
                }
                if (wsId !== "") {
                    DataStore.savePairedDevice(deviceId, name, wsId)
                    DataStore.updatePairedDeviceEndpoint(deviceId, pairingController.peerHost, pairingController.peerPort)
                }
            }
            Qt.callLater(function() { root.close() })
        }

        onPairingFailed: function(reason) {
            statusOverride = reason
            scanInProgress = false
            cameraActive = false
        }
    }

    SyncController {
        id: internalSyncController

        onError: function(message) {
            statusOverride = message
            scanInProgress = false
            cameraActive = false
        }
    }

    Connections {
        target: activeSyncController

        function onPeerCountChanged() {
            if (activeSyncController.peerCount > 0 &&
                (mode === "code_show" || mode === "qr_show")) {
                statusOverride = "Pairing complete!"
            }
        }

        function onPeerDiscovered(deviceId, deviceName, workspaceId, host, port) {
            if (deviceId === "" || workspaceId === "") {
                return
            }
            var name = deviceName
            if (name === "") {
                name = "Paired device"
            }
            DataStore.savePairedDevice(deviceId, name, workspaceId)
            if (host && host !== "" && port && port > 0) {
                DataStore.updatePairedDeviceEndpoint(deviceId, host, port)
            }
        }

        function onPeerConnected(deviceName) {
            console.log("PairingDialog: peer connected", deviceName)
            pagesCursorAt = ""
            pagesCursorId = ""
            deletedPagesCursorAt = ""
            deletedPagesCursorId = ""
            sendLocalPagesSnapshot(true)
        }

        function onPageSnapshotReceivedPages(pages) {
            if (!pages) {
                return
            }
            console.log("PairingDialog: received snapshot pages", pages.length)
            suppressOutgoingSnapshots = true
            DataStore.applyPageUpdates(pages)
            Qt.callLater(function() { suppressOutgoingSnapshots = false })
        }

        function onDeletedPageSnapshotReceivedPages(deletedPages) {
            if (!deletedPages) {
                return
            }
            console.log("PairingDialog: received deleted pages", deletedPages.length)
            suppressOutgoingSnapshots = true
            DataStore.applyDeletedPageUpdates(deletedPages)
            Qt.callLater(function() { suppressOutgoingSnapshots = false })
        }
    }

    onStatusMessageChanged: {
        if (statusMessage === "Pairing complete!") {
            Qt.callLater(function() { root.close() })
        }
    }

    Connections {
        target: DataStore

        function onPagesChanged() {
            if (activeSyncController.syncing && !suppressOutgoingSnapshots) {
                scheduleOutgoingSnapshot()
            }
        }

        function onPageContentChanged(pageId) {
            if (activeSyncController.syncing && !suppressOutgoingSnapshots) {
                scheduleOutgoingSnapshot()
            }
        }
    }

    Timer {
        id: outgoingSnapshotTimer
        interval: 150
        repeat: false
        onTriggered: sendLocalPagesSnapshot(false)
    }

    function scheduleOutgoingSnapshot() {
        outgoingSnapshotTimer.restart()
    }

    function advanceCursorFrom(items, cursorAtKey, cursorIdKey, cursorAtField, idField) {
        var cursorAt = root[cursorAtKey]
        var cursorId = root[cursorIdKey]
        for (var i = 0; i < items.length; i++) {
            var entry = items[i]
            var updatedAt = entry[cursorAtField] || ""
            var entryId = entry[idField] || ""
            if (cursorAt === "" || updatedAt > cursorAt || (updatedAt === cursorAt && entryId > cursorId)) {
                cursorAt = updatedAt
                cursorId = entryId
            }
        }
        root[cursorAtKey] = cursorAt
        root[cursorIdKey] = cursorId
    }

    function sendLocalPagesSnapshot(full) {
        if (!activeSyncController.syncing) {
            return
        }
        var pages = full ? DataStore.getPagesForSync()
                         : DataStore.getPagesForSyncSince(pagesCursorAt, pagesCursorId)
        var deletedPages = full ? DataStore.getDeletedPagesForSync()
                                : DataStore.getDeletedPagesForSyncSince(deletedPagesCursorAt, deletedPagesCursorId)
        if (!full && (!pages || pages.length === 0) &&
            (!deletedPages || deletedPages.length === 0)) {
            return
        }
        var payload = JSON.stringify({
            v: 2,
            workspaceId: activeSyncController.workspaceId,
            full: full === true,
            pages: pages,
            deletedPages: deletedPages
        })
        console.log("PairingDialog: sending snapshot full=", full === true, "pages", pages.length, "deleted", deletedPages.length)
        activeSyncController.sendPageSnapshot(payload)

        advanceCursorFrom(pages, "pagesCursorAt", "pagesCursorId", "updatedAt", "pageId")
        advanceCursorFrom(deletedPages, "deletedPagesCursorAt", "deletedPagesCursorId", "deletedAt", "pageId")
    }
    
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
            anchors.margins: ThemeManager.spacingMedium
            
            ToolButton {
                visible: mode !== "select"
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
                    cameraActive = false
                    mode = "select"
                    statusOverride = ""
                    scanInProgress = false
                    pairingController.cancel()
                }
            }
            
            Text {
                Layout.fillWidth: true
                text: {
                    if (mode === "select") return "Pair Device"
                    if (mode === "qr_show") return "Show QR Code"
                    if (mode === "qr_scan") return "Scan QR Code"
                    if (mode === "code_show") return "Share Code"
                    if (mode === "code_enter") return "Enter Code"
                    if (mode === "passphrase") return "Enter Passphrase"
                    return "Pair Device"
                }
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeLarge
                font.weight: Font.Medium
                horizontalAlignment: mode === "select" ? Text.AlignHCenter : Text.AlignLeft
            }
            
            Item { width: mode !== "select" ? 32 : 0 }
        }
        
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: ThemeManager.border
        }
    }
    
    contentItem: Flickable {
        contentHeight: contentColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        
        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: ThemeManager.spacingMedium
            
            // Mode selection
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall
                visible: mode === "select"
                
                Text {
                    text: "How would you like to pair?"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    visible: qrEnabled
                    icon: "📱"
                    label: "Show QR Code"
                    description: "Let another device scan your code"
                    onClicked: {
                        statusOverride = ""
                        scanInProgress = false
                        cameraActive = false
                        var wsId = ensureWorkspaceId()
                        if (!startSyncForWorkspace(wsId)) {
                            statusOverride = "Failed to start sync"
                            return
                        }
                        pairingController.configureLocalDevice(deviceName, wsId,
                            activeSyncController.listeningPort())
                        pairingController.startPairingAsInitiator("qr")
                        mode = "qr_show"
                    }
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    visible: qrEnabled
                    icon: "📷"
                    label: "Scan QR Code"
                    description: "Scan a code from another device"
                    onClicked: {
                        statusOverride = "Scanning for QR..."
                        scanInProgress = false
                        workspaceId = ""
                        mode = "qr_scan"
                        pairingController.configureLocalDevice(deviceName, "", 0)
                        pairingController.startPairingAsResponder()
                        requestCameraPermission()
                    }
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    icon: "🔢"
                    label: "Show Pairing Code"
                    description: "Share a 6-digit code to join your workspace"
                    onClicked: {
                        statusOverride = ""
                        scanInProgress = false
                        cameraActive = false
                        workspaceId = ""
                        pairingController.configureLocalDevice(deviceName, "", 0)
                        pairingController.startPairingAsInitiator("numeric")
                        workspaceId = pairingController.workspaceId
                        if (!startSyncForWorkspace(workspaceId)) {
                            statusOverride = "Failed to start sync"
                            return
                        }
                        mode = "code_show"
                    }
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    icon: "⌨️"
                    label: "Enter Pairing Code"
                    description: "Join a workspace using a 6-digit code"
                    onClicked: {
                        statusOverride = ""
                        scanInProgress = false
                        cameraActive = false
                        workspaceId = ""
                        codeField.text = ""
                        pairingController.configureLocalDevice(deviceName, "", 0)
                        pairingController.startPairingAsResponder()
                        mode = "code_enter"
                    }
                }

                PairingOption {
                    Layout.fillWidth: true
                    icon: "🔐"
                    label: "Use Passphrase"
                    description: "Join using a shared phrase"
                    onClicked: {
                        statusOverride = ""
                        scanInProgress = false
                        cameraActive = false
                        workspaceId = ""
                        passphraseField.text = ""
                        pairingController.configureLocalDevice(deviceName, "", 0)
                        pairingController.startPairingAsInitiator("passphrase")
                        mode = "passphrase"
                    }
                }
            }
            
            Loader {
                id: qrPaneLoader
                Layout.fillWidth: true
                active: qrEnabled
                source: qrEnabled ? "PairingDialogQrPane.qml" : ""

                onStatusChanged: {
                    if (status === Loader.Ready && item) {
                        item.dialog = root
                        item.pairingController = pairingController
                        item.syncController = activeSyncController
                    }
                }
            }
            
            // Code entry
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium
                visible: mode === "code_show" || mode === "code_enter"
                
                // Your code display
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: ThemeManager.background
                    radius: ThemeManager.radiusSmall
                    border.width: 1
                    border.color: ThemeManager.border
                    visible: mode === "code_show"
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: ThemeManager.spacingSmall
                        spacing: 2
                        
                        Text {
                            text: "Your code (share this)"
                            color: ThemeManager.textSecondary
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                        
                        Text {
                            Layout.fillWidth: true
                            text: verificationCode
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeH2
                            font.weight: Font.Bold
                            font.family: ThemeManager.monoFontFamily
                            font.letterSpacing: 4
                        }
                    }
                }
                
                Text {
                    visible: mode === "code_enter"
                    text: "Enter pairing code:"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                }
                
                TextField {
                    id: codeField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    visible: mode === "code_enter"
                    
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: ThemeManager.fontSizeH2
                    font.family: ThemeManager.monoFontFamily
                    font.letterSpacing: 8
                    color: ThemeManager.text
                    maximumLength: 6
                    validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
                    inputMethodHints: Qt.ImhDigitsOnly
                    placeholderText: "000000"
                    
                    background: Rectangle {
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.background
                        border.width: 2
                        border.color: parent.activeFocus ? ThemeManager.accent : ThemeManager.border
                    }
                }
                
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "Connect"
                    visible: mode === "code_enter"
                    enabled: mode === "code_enter" && codeField.text.length === 6
                    
                    background: Rectangle {
                        radius: ThemeManager.radiusSmall
                        color: parent.enabled 
                            ? (parent.pressed ? ThemeManager.accentHover : ThemeManager.accent)
                            : ThemeManager.surfaceActive
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "white" : ThemeManager.textMuted
                        font.pixelSize: ThemeManager.fontSizeNormal
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        statusOverride = ""
                        pairingController.submitCode(codeField.text)
                        workspaceId = pairingController.workspaceId
                        if (!startSyncForWorkspace(workspaceId)) {
                            statusOverride = "Failed to start sync"
                        }
                    }
                }
            }
            
            // Passphrase entry
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium
                visible: mode === "passphrase"
                
                Text {
                    Layout.fillWidth: true
                    text: "Enter a shared passphrase known to both devices"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                    wrapMode: Text.Wrap
                }
                
                TextField {
                    id: passphraseField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    
                    font.pixelSize: ThemeManager.fontSizeNormal
                    color: ThemeManager.text
                    placeholderText: "Enter passphrase..."
                    echoMode: showPassphrase.checked ? TextInput.Normal : TextInput.Password
                    
                    background: Rectangle {
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.background
                        border.width: 1
                        border.color: parent.activeFocus ? ThemeManager.accent : ThemeManager.border
                    }
                }
                
                CheckBox {
                    id: showPassphrase
                    text: "Show passphrase"
                    
                    contentItem: Text {
                        text: parent.text
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        leftPadding: parent.indicator.width + parent.spacing
                    }
                    
                    indicator: Rectangle {
                        implicitWidth: 20
                        implicitHeight: 20
                        x: parent.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 4
                        border.width: 1
                        border.color: ThemeManager.border
                        color: parent.checked ? ThemeManager.accent : "transparent"
                        
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            color: "white"
                            font.pixelSize: 12
                            visible: parent.parent.checked
                        }
                    }
                }
                
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "Connect"
                    enabled: passphraseField.text.length >= 4
                    
                    background: Rectangle {
                        radius: ThemeManager.radiusSmall
                        color: parent.enabled 
                            ? (parent.pressed ? ThemeManager.accentHover : ThemeManager.accent)
                            : ThemeManager.surfaceActive
                    }
                    
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? "white" : ThemeManager.textMuted
                        font.pixelSize: ThemeManager.fontSizeNormal
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        statusOverride = ""
                        pairingController.submitCode(passphraseField.text)
                        workspaceId = pairingController.workspaceId
                        if (!startSyncForWorkspace(workspaceId)) {
                            statusOverride = "Failed to start sync"
                        }
                    }
                }
            }
            
            // Status indicator
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall
                visible: statusMessage !== "Ready"
                
                BusyIndicator {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    running: pairingController.pairing
                }
                
                Text {
                    text: statusMessage
                    color: statusMessage === "Pairing complete!" ? ThemeManager.success : ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                }
            }
        }
    }
    
    // Request camera permission (Android)
    function requestCameraPermission() {
        if (Qt.platform.os === "android" && AndroidUtils) {
            // First check if we already have permission
            if (AndroidUtils.hasCameraPermission()) {
                cameraPermissionGranted = true
                cameraActive = true
            } else {
                // Request permission - system will show dialog
                AndroidUtils.requestCameraPermission()
            }
        } else {
            // Non-Android, just try to use camera
            cameraPermissionGranted = true
            cameraActive = true
        }
        
        // Check if camera actually works after a short delay
        Qt.callLater(function() {
            if (qrCamera && qrCamera.error !== Camera.NoError) {
                cameraPermissionGranted = false
            }
        })
    }
    
    // Handle permission result from Android
    Connections {
        target: AndroidUtils
        enabled: Qt.platform.os === "android" && AndroidUtils !== null
        
        function onCameraPermissionGranted() {
            console.log("Camera permission granted!")
            cameraPermissionGranted = true
            cameraActive = true
        }
        
        function onCameraPermissionDenied() {
            console.log("Camera permission denied")
            cameraPermissionGranted = false
        }
    }
    
    function normalizeUuid(uuidString) {
        return uuidString.replace(/[{}]/g, "")
    }

    function createUuidV4() {
        // Qt.createUuid() is not available on all Qt/QML versions we target.
        // This is sufficient for generating a local workspace id.
        function hex(n) { return n.toString(16).padStart(2, "0") }
        var bytes = []
        for (var i = 0; i < 16; i++) bytes.push(Math.floor(Math.random() * 256))
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        var s = ""
        for (var j = 0; j < 16; j++) {
            s += hex(bytes[j])
            if (j === 3 || j === 5 || j === 7 || j === 9) s += "-"
        }
        return s
    }

    function ensureWorkspaceId() {
        if (workspaceId === "") {
            workspaceId = createUuidV4()
        }
        return workspaceId
    }

    function startSyncForWorkspace(wsId) {
        if (!activeSyncController.configured || activeSyncController.workspaceId !== wsId) {
            if (activeSyncController.syncing) {
                activeSyncController.stopSync()
            }
            if (!activeSyncController.configure(wsId, deviceName)) {
                return false
            }
        }
        return activeSyncController.startSync()
    }

    onOpened: {
        mode = "select"
        statusOverride = ""
        codeField.text = ""
        passphraseField.text = ""
        cameraActive = false
        scanInProgress = false
        pairingController.cancel()
    }
    
    onClosed: {
        cameraActive = false
        scanInProgress = false
        statusOverride = ""
        pairingController.cancel()
    }
    
    // Pairing option button component
    component PairingOption: Rectangle {
        id: pairingOption
        
        property string icon: ""
        property string label: ""
        property string description: ""
        
        signal clicked()
        
        height: 72
        radius: ThemeManager.radiusSmall
        color: optionMouse.containsMouse ? ThemeManager.surfaceHover : ThemeManager.background
        border.width: 1
        border.color: ThemeManager.border
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingMedium
            
            Rectangle {
                width: 44
                height: 44
                radius: ThemeManager.radiusSmall
                color: ThemeManager.accentLight
                
                Text {
                    anchors.centerIn: parent
                    text: pairingOption.icon
                    font.pixelSize: 22
                }
            }
            
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                
                Text {
                    text: pairingOption.label
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    font.weight: Font.Medium
                }
                
                Text {
                    text: pairingOption.description
                    color: ThemeManager.textMuted
                    font.pixelSize: ThemeManager.fontSizeSmall
                }
            }
            
            Text {
                text: "→"
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeLarge
            }
        }
        
        MouseArea {
            id: optionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pairingOption.clicked()
        }
    }
}
