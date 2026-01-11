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

    property string mode: "select"  // select, qr_show, qr_scan, code, passphrase
    property string verificationCode: pairingController.verificationCode
    property string qrData: pairingController.qrCodeData
    property string statusOverride: ""
    property string statusMessage: statusOverride !== "" ? statusOverride : pairingController.status
    property bool cameraActive: false
    property bool cameraPermissionGranted: false
    property bool scanInProgress: false
    property string workspaceId: ""
    property string deviceName: "Zinc Device"

    PairingController {
        id: pairingController

        onPairingComplete: function() {
            statusOverride = ""
            scanInProgress = false
        }

        onPairingFailed: function(reason) {
            statusOverride = reason
            scanInProgress = false
            cameraActive = false
        }
    }

    SyncController {
        id: syncController

        onError: function(message) {
            statusOverride = message
            scanInProgress = false
            cameraActive = false
        }
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
                    if (mode === "code") return "Enter Code"
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
                            syncController.listeningPort())
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
                    label: "Enter Code"
                    description: "Type a 6-digit pairing code"
                    onClicked: {
                        statusOverride = ""
                        pairingController.configureLocalDevice(deviceName,
                            ensureWorkspaceId(), 0)
                        pairingController.startPairingAsInitiator("numeric")
                        mode = "code"
                    }
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    icon: "🔐"
                    label: "Use Passphrase"
                    description: "Enter a shared secret phrase"
                    onClicked: {
                        statusOverride = ""
                        pairingController.configureLocalDevice(deviceName,
                            ensureWorkspaceId(), 0)
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
                        item.syncController = syncController
                    }
                }
            }
            
            // Code entry
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium
                visible: mode === "code"
                
                // Your code display
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: ThemeManager.background
                    radius: ThemeManager.radiusSmall
                    border.width: 1
                    border.color: ThemeManager.border
                    
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
                    text: "Enter their code:"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                }
                
                TextField {
                    id: codeField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    
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
                    enabled: codeField.text.length === 6
                    
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

    function ensureWorkspaceId() {
        if (workspaceId === "") {
            workspaceId = normalizeUuid(Qt.createUuid().toString())
        }
        return workspaceId
    }

    function startSyncForWorkspace(wsId) {
        if (!syncController.configured || syncController.workspaceId !== wsId) {
            if (syncController.syncing) {
                syncController.stopSync()
            }
            if (!syncController.configure(wsId, deviceName)) {
                return false
            }
        }
        return syncController.startSync()
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
