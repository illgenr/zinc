import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import zinc
import Zinc 1.0
import "../components"

ColumnLayout {
    id: qrPane

    required property var dialog
    required property var pairingController
    required property var syncController

    Layout.fillWidth: true

    Component.onCompleted: {
        dialog.qrCamera = camera
    }

    Component.onDestruction: {
        if (dialog.qrCamera === camera) {
            dialog.qrCamera = null
        }
    }

    Connections {
        target: dialog

        function onOpened() {
            qrPasteField.text = ""
        }

        function onClosed() {
            qrPasteField.text = ""
        }

        function onModeChanged() {
            if (dialog.mode !== "qr_scan") {
                qrPasteField.text = ""
            }
        }
    }

    // QR Code display
    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: ThemeManager.spacingMedium
        Layout.visible: dialog.mode === "qr_show"
        spacing: ThemeManager.spacingMedium
        visible: Layout.visible

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
                    data: dialog.qrData
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
            Layout.preferredWidth: Math.min(320, dialog.width - 60)
            Layout.preferredHeight: qrPayloadText.implicitHeight + 16
            color: ThemeManager.surfaceAlt
            radius: ThemeManager.radiusSmall
            border.width: 1
            border.color: ThemeManager.border
            visible: dialog.qrData.length > 0

            TextArea {
                id: qrPayloadText
                anchors.fill: parent
                anchors.margins: 8
                text: dialog.qrData
                readOnly: true
                selectByMouse: true
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
                font.family: ThemeManager.monoFontFamily
                wrapMode: TextEdit.WordWrap
                background: Item {}
            }
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
                text: dialog.verificationCode
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
        Layout.visible: dialog.mode === "qr_scan"
        spacing: ThemeManager.spacingMedium
        visible: Layout.visible

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(280, dialog.width - 60)
            Layout.preferredHeight: Layout.preferredWidth
            color: "#000000"
            radius: ThemeManager.radiusSmall
            clip: true

            // Camera viewfinder
            CaptureSession {
                id: captureSession
                camera: Camera {
                    id: camera
                    active: dialog.cameraActive && dialog.cameraPermissionGranted

                    onActiveChanged: {
                        console.log("Camera active:", active)
                    }

                    onErrorOccurred: function(error, errorString) {
                        console.log("Camera error:", error, errorString)
                        dialog.cameraPermissionGranted = false
                    }
                }
                videoOutput: videoOutput
            }

            QrScanner {
                id: qrScanner
                videoSink: videoOutput.videoSink
                active: dialog.cameraActive && dialog.cameraPermissionGranted
                    && dialog.mode === "qr_scan" && !dialog.scanInProgress

                onQrCodeDetected: function(payload) {
                    handleQrCodeDetected(payload)
                }
                onError: function(message) {
                    dialog.statusOverride = message
                }
            }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }

            // Viewfinder overlay
            Item {
                anchors.fill: parent
                visible: dialog.cameraActive && dialog.cameraPermissionGranted

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
                        running: dialog.cameraActive
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
                visible: !dialog.cameraPermissionGranted || !camera.active

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

                    onClicked: dialog.requestCameraPermission()
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Position the QR code in the frame"
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeNormal
            visible: dialog.cameraActive && dialog.cameraPermissionGranted
        }

        TextField {
            id: qrPasteField
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(300, dialog.width - 60)
            placeholderText: "Paste QR payload"
            visible: dialog.mode === "qr_scan"

            background: Rectangle {
                radius: ThemeManager.radiusSmall
                color: ThemeManager.background
                border.width: 1
                border.color: parent.activeFocus ? ThemeManager.accent : ThemeManager.border
            }
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Use QR data"
            enabled: qrPasteField.text.length > 0
            visible: dialog.mode === "qr_scan"

            background: Rectangle {
                implicitWidth: 140
                implicitHeight: 40
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

            onClicked: handleQrCodeDetected(qrPasteField.text)
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
	                dialog.cameraActive = false
	                dialog.statusOverride = ""
	                pairingController.configureLocalDevice(dialog.deviceName, "", 0)
	                pairingController.startPairingAsInitiator("numeric")
	                var wsId = pairingController.workspaceId
	                dialog.workspaceId = wsId
	                if (!dialog.startSyncForWorkspace(wsId)) {
	                    dialog.statusOverride = "Failed to start sync"
	                    return
	                }
	                dialog.mode = "code_show"
	            }
	        }
	    }

    function handleQrCodeDetected(qrData) {
        if (dialog.scanInProgress) {
            return
        }
        dialog.scanInProgress = true
        dialog.statusOverride = ""

        pairingController.submitQrCodeData(qrData)
        var wsId = pairingController.workspaceId
        if (wsId === "") {
            dialog.statusOverride = "QR code missing workspace ID"
            dialog.scanInProgress = false
            return
        }
        dialog.workspaceId = wsId
        if (!dialog.startSyncForWorkspace(wsId)) {
            dialog.statusOverride = "Failed to start sync"
            dialog.scanInProgress = false
            return
        }
        if (pairingController.peerHost === "" || pairingController.peerPort <= 0) {
            dialog.statusOverride = "QR code missing peer endpoint"
            dialog.scanInProgress = false
            return
        }
        syncController.connectToPeer(pairingController.peerDeviceId,
            pairingController.peerHost, pairingController.peerPort)
        dialog.cameraActive = false
        qrPasteField.text = ""
    }
}
