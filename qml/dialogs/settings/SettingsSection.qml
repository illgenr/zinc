import QtQuick
import QtQuick.Layouts
import zinc

ColumnLayout {
    id: root
    property string title: ""
    default property alias content: sectionContent.children

    Layout.fillWidth: true
    Layout.margins: ThemeManager.spacingMedium
    spacing: ThemeManager.spacingSmall

    Text {
        text: root.title
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
