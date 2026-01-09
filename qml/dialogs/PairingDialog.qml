import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Dialog {
    id: root
    
    title: "Pair Device"
    anchors.centerIn: parent
    width: 400
    modal: true
    standardButtons: Dialog.Cancel
    
    property string mode: "select"  // select, qr, code, passphrase
    property string verificationCode: ""
    property string status: "Ready"
    
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
    
    contentItem: ColumnLayout {
        spacing: ThemeManager.spacingLarge
        
        // Mode selection
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingSmall
            visible: mode === "select"
            
            Text {
                text: "How would you like to pair?"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeNormal
            }
            
            Button {
                Layout.fillWidth: true
                text: "📱 Scan QR Code"
                
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
                
                onClicked: mode = "qr"
            }
            
            Button {
                Layout.fillWidth: true
                text: "🔢 Enter Code"
                
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
                
                onClicked: mode = "code"
            }
            
            Button {
                Layout.fillWidth: true
                text: "🔐 Use Passphrase"
                
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
                
                onClicked: mode = "passphrase"
            }
        }
        
        // QR Code display
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingMedium
            visible: mode === "qr"
            
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 200
                height: 200
                color: "white"
                radius: ThemeManager.radiusSmall
                
                // QR code would be rendered here
                Text {
                    anchors.centerIn: parent
                    text: "QR Code"
                    color: ThemeManager.textMuted
                }
            }
            
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Scan this code with another device"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeNormal
            }
            
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Or enter code: " + verificationCode
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeLarge
                font.weight: Font.Bold
            }
        }
        
        // Code entry
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingMedium
            visible: mode === "code"
            
            Text {
                text: "Enter the 6-digit code from the other device"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeNormal
            }
            
            TextField {
                id: codeField
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: ThemeManager.fontSizeH2
                font.family: ThemeManager.monoFontFamily
                color: ThemeManager.text
                maximumLength: 6
                validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
                
                background: Rectangle {
                    radius: ThemeManager.radiusSmall
                    color: ThemeManager.background
                    border.width: 1
                    border.color: parent.activeFocus ? ThemeManager.accent : ThemeManager.border
                }
            }
            
            Button {
                Layout.fillWidth: true
                text: "Pair"
                enabled: codeField.text.length === 6
                
                background: Rectangle {
                    radius: ThemeManager.radiusSmall
                    color: parent.enabled ? ThemeManager.accent : ThemeManager.surfaceActive
                }
                
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: ThemeManager.fontSizeNormal
                    horizontalAlignment: Text.AlignHCenter
                }
                
                onClicked: {
                    // Submit pairing code
                    status = "Connecting..."
                }
            }
        }
        
        // Status
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: status
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeSmall
            visible: status !== "Ready"
        }
        
        // Back button
        Button {
            Layout.alignment: Qt.AlignLeft
            text: "← Back"
            visible: mode !== "select"
            flat: true
            
            contentItem: Text {
                text: parent.text
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
            }
            
            background: Item {}
            
            onClicked: mode = "select"
        }
    }
    
    onOpened: {
        mode = "select"
        verificationCode = Math.floor(100000 + Math.random() * 900000).toString()
    }
}
