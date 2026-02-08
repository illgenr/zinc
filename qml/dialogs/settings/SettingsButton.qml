import QtQuick
import QtQuick.Controls
import zinc

Button {
    id: root
    property color textColor: ThemeManager.text
    readonly property bool focusVisible: root.visualFocus || root.activeFocus

    background: Rectangle {
        implicitHeight: 36
        radius: ThemeManager.radiusSmall
        color: root.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
        border.width: root.focusVisible ? 2 : 1
        border.color: root.focusVisible ? ThemeManager.accent : ThemeManager.border
    }

    contentItem: Text {
        text: root.text
        color: root.enabled ? root.textColor : ThemeManager.textMuted
        font.pixelSize: ThemeManager.fontSizeNormal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
