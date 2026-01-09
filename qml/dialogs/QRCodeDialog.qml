import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Dialog {
    id: root
    
    property string data: ""
    
    title: "QR Code"
    anchors.centerIn: parent
    width: 300
    modal: true
    standardButtons: Dialog.Close
    
    background: Rectangle {
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusLarge
    }
    
    contentItem: ColumnLayout {
        spacing: ThemeManager.spacingLarge
        
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 200
            height: 200
            color: "white"
            radius: ThemeManager.radiusSmall
            
            // QR code would be rendered here using a QR library
            Text {
                anchors.centerIn: parent
                text: "QR"
                color: "#333"
                font.pixelSize: 48
                font.bold: true
            }
        }
        
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Scan with another device to pair"
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeNormal
        }
    }
}
