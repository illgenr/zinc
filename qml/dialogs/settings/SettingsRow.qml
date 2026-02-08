import QtQuick
import QtQuick.Layouts
import zinc

RowLayout {
    id: root
    property string label: ""
    default property alias control: rowControl.children

    Layout.fillWidth: true
    spacing: ThemeManager.spacingSmall

    Text {
        Layout.fillWidth: true
        text: root.label
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
