import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

ScrollView {
    id: root
    default property alias pageContent: pageColumn.children

    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    ColumnLayout {
        id: pageColumn
        width: root.availableWidth - ThemeManager.spacingLarge
        spacing: ThemeManager.spacingLarge
    }
}
