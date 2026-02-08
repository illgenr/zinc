import QtQuick
import QtQuick.Controls
import zinc

Switch {
    id: root
    readonly property bool focusVisible: root.visualFocus || root.activeFocus

    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 22
        radius: height / 2
        color: root.checked ? ThemeManager.accent : ThemeManager.surfaceHover
        border.width: root.focusVisible ? 2 : 1
        border.color: root.focusVisible ? ThemeManager.accent : ThemeManager.border

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: root.checked ? (parent.width - width - 3) : 3
            color: "white"
        }
    }
}
