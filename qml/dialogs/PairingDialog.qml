import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import zinc
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
    
    property string mode: "select"  // select, qr_show, qr_scan, code, passphrase
    property string verificationCode: ""
    property string qrData: ""
    property string status: "Ready"
    property bool cameraActive: false
    property bool cameraPermissionGranted: false
    
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
                    status = "Ready"
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
                    icon: "📱"
                    label: "Show QR Code"
                    description: "Let another device scan your code"
                    onClicked: {
                        generatePairingData()
                        mode = "qr_show"
                    }
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    icon: "📷"
                    label: "Scan QR Code"
                    description: "Scan a code from another device"
                    onClicked: {
                        mode = "qr_scan"
                        requestCameraPermission()
                    }
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    icon: "🔢"
                    label: "Enter Code"
                    description: "Type a 6-digit pairing code"
                    onClicked: {
                        generatePairingData()
                        mode = "code"
                    }
                }
                
                PairingOption {
                    Layout.fillWidth: true
                    icon: "🔐"
                    label: "Use Passphrase"
                    description: "Enter a shared secret phrase"
                    onClicked: mode = "passphrase"
                }
            }
            
            // QR Code display
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium
                visible: mode === "qr_show"
                
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 200
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "white"
                        radius: ThemeManager.radiusSmall
                        
                        QRCodeImage {
                            anchors.fill: parent
                            anchors.margins: 8
                            data: qrData
                            foregroundColor: "#000000"
                            backgroundColor: "#ffffff"
                        }
                    }
                }
                
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Scan this code with another device"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                }
                
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: codeText.width + ThemeManager.spacingLarge * 2
                    Layout.preferredHeight: 48
                    color: ThemeManager.background
                    radius: ThemeManager.radiusSmall
                    border.width: 1
                    border.color: ThemeManager.border
                    
                    Text {
                        id: codeText
                        anchors.centerIn: parent
                        text: verificationCode
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeH2
                        font.weight: Font.Bold
                        font.family: ThemeManager.monoFontFamily
                        font.letterSpacing: 4
                    }
                }
                
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Or enter this code manually"
                    color: ThemeManager.textMuted
                    font.pixelSize: ThemeManager.fontSizeSmall
                }
            }
            
            // QR Code scanner
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium
                visible: mode === "qr_scan"
                
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Math.min(280, root.width - 60)
                    Layout.preferredHeight: Layout.preferredWidth
                    color: "#000000"
                    radius: ThemeManager.radiusSmall
                    clip: true
                    
                    // Camera viewfinder
                    CaptureSession {
                        id: captureSession
                        camera: Camera {
                            id: camera
                            active: cameraActive && cameraPermissionGranted
                            
                            onActiveChanged: {
                                console.log("Camera active:", active)
                            }
                            
                            onErrorOccurred: function(error, errorString) {
                                console.log("Camera error:", error, errorString)
                                cameraPermissionGranted = false
                            }
                        }
                        videoOutput: videoOutput
                    }
                    
                    VideoOutput {
                        id: videoOutput
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                    }
                    
                    // Viewfinder overlay
                    Item {
                        anchors.fill: parent
                        visible: cameraActive && cameraPermissionGranted
                        
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.7
                            height: width
                            color: "transparent"
                            border.width: 2
                            border.color: ThemeManager.accent
                            radius: 4
                        }
                        
                        // Scanning animation
                        Rectangle {
                            id: scanLine
                            width: parent.width * 0.7
                            height: 2
                            color: ThemeManager.accent
                            anchors.horizontalCenter: parent.horizontalCenter
                            
                            SequentialAnimation on y {
                                loops: Animation.Infinite
                                running: cameraActive
                                NumberAnimation {
                                    from: parent.height * 0.15
                                    to: parent.height * 0.85
                                    duration: 2000
                                    easing.type: Easing.InOutQuad
                                }
                                NumberAnimation {
                                    from: parent.height * 0.85
                                    to: parent.height * 0.15
                                    duration: 2000
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }
                    
                    // No camera permission message
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: ThemeManager.spacingMedium
                        visible: !cameraPermissionGranted || !camera.active
                        
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "📷"
                            font.pixelSize: 48
                        }
                        
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Camera not available"
                            color: "white"
                            font.pixelSize: ThemeManager.fontSizeNormal
                            font.weight: Font.Medium
                        }
                        
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 200
                            text: Qt.platform.os === "android" 
                                ? "Please grant camera permission in Settings"
                                : "Check if camera is connected"
                            color: "#aaaaaa"
                            font.pixelSize: ThemeManager.fontSizeSmall
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        
                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            visible: Qt.platform.os === "android"
                            text: "Open App Settings"
                            
                            background: Rectangle {
                                implicitWidth: 180
                                implicitHeight: 40
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
                                // Try to open app settings using AndroidUtils
                                if (typeof AndroidUtils !== 'undefined' && AndroidUtils && AndroidUtils.isAndroid()) {
                                    AndroidUtils.openAppSettings()
                                } else if (Qt.platform.os === "android") {
                                    // Try using Qt.openUrlExternally as fallback
                                    // This works on some Android versions
                                    Qt.openUrlExternally("package:org.qtproject.example.appzinc")
                                    permissionInstructions.visible = true
                                } else {
                                    // Fallback: show instructions
                                    permissionInstructions.visible = true
                                }
                            }
                        }
                        
                        // Instructions for manual navigation to settings
                        ColumnLayout {
                            id: permissionInstructions
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 240
                            visible: false
                            spacing: ThemeManager.spacingSmall
                            
                            Text {
                                Layout.fillWidth: true
                                text: "If the settings didn't open automatically:"
                                color: ThemeManager.textSecondary
                                font.pixelSize: ThemeManager.fontSizeSmall
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: instructionsText.implicitHeight + 16
                                color: ThemeManager.surfaceAlt
                                radius: ThemeManager.radiusSmall
                                
                                Text {
                                    id: instructionsText
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    text: "1. Open Android Settings\n2. Go to Apps → Zinc Notes\n3. Tap Permissions\n4. Enable Camera"
                                    color: ThemeManager.text
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                    font.family: "monospace"
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.4
                                }
                            }
                        }
                        
                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            visible: Qt.platform.os === "android"
                            text: "I've granted permission"
                            flat: true
                            
                            contentItem: Text {
                                text: parent.text
                                color: ThemeManager.accent
                                font.pixelSize: ThemeManager.fontSizeSmall
                                font.underline: true
                            }
                            
                            background: Item {}
                            
                            onClicked: requestCameraPermission()
                        }
                    }
                }
                
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Position the QR code in the frame"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                    visible: cameraActive && cameraPermissionGranted
                }
                
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Enter code manually instead"
                    flat: true
                    
                    contentItem: Text {
                        text: parent.text
                        color: ThemeManager.accent
                        font.pixelSize: ThemeManager.fontSizeSmall
                        font.underline: true
                    }
                    
                    background: Item {}
                    
                    onClicked: {
                        cameraActive = false
                        generatePairingData()
                        mode = "code"
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
                        status = "Connecting..."
                        connectTimer.start()
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
                        status = "Connecting..."
                        connectTimer.start()
                    }
                }
            }
            
            // Status indicator
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall
                visible: status !== "Ready"
                
                BusyIndicator {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    running: status === "Connecting..." || status === "Verifying..."
                }
                
                Text {
                    text: status
                    color: status === "Connected!" ? ThemeManager.success : ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                }
            }
        }
    }
    
    // Connection simulation timers
    Timer {
        id: connectTimer
        interval: 1500
        onTriggered: {
            status = "Verifying..."
            verifyTimer.start()
        }
    }
    
    Timer {
        id: verifyTimer
        interval: 1000
        onTriggered: {
            status = "Connected!"
            successTimer.start()
        }
    }
    
    Timer {
        id: successTimer
        interval: 1000
        onTriggered: root.close()
    }
    
    // Request camera permission (Android)
    function requestCameraPermission() {
        if (Qt.platform.os === "android" && AndroidUtils) {
            // First check if we already have permission
            if (AndroidUtils.hasPermission("android.permission.CAMERA")) {
                cameraPermissionGranted = true
                cameraActive = true
            } else {
                // Request permission - system will show dialog
                AndroidUtils.requestPermission("android.permission.CAMERA")
            }
        } else {
            // Non-Android, just try to use camera
            cameraPermissionGranted = true
            cameraActive = true
        }
        
        // Check if camera actually works after a short delay
        Qt.callLater(function() {
            if (camera.error !== Camera.NoError) {
                cameraPermissionGranted = false
            }
        })
    }
    
    // Handle permission result from Android
    Connections {
        target: AndroidUtils
        enabled: Qt.platform.os === "android" && AndroidUtils !== null
        
        function onPermissionGranted(permission) {
            if (permission === "android.permission.CAMERA") {
                console.log("Camera permission granted!")
                cameraPermissionGranted = true
                cameraActive = true
            }
        }
        
        function onPermissionDenied(permission) {
            if (permission === "android.permission.CAMERA") {
                console.log("Camera permission denied")
                cameraPermissionGranted = false
            }
        }
    }
    
    // Generate pairing data
    function generatePairingData() {
        verificationCode = String(Math.floor(100000 + Math.random() * 900000))
        
        var pairingInfo = {
            "v": 1,
            "code": verificationCode,
            "name": "Zinc Device",
            "ts": Date.now()
        }
        qrData = JSON.stringify(pairingInfo)
        console.log("Generated QR data:", qrData)
    }
    
    onOpened: {
        mode = "select"
        status = "Ready"
        codeField.text = ""
        passphraseField.text = ""
        cameraActive = false
        generatePairingData()
    }
    
    onClosed: {
        cameraActive = false
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
