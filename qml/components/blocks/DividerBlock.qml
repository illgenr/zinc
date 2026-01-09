import QtQuick
import zinc

Item {
    id: root
    
    implicitHeight: 24
    
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: 1
        color: ThemeManager.border
    }
}
