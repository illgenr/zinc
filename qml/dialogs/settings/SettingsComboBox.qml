import QtQuick
import QtQuick.Controls
import zinc

ComboBox {
    id: root
    readonly property bool focusVisible: root.visualFocus || root.activeFocus

    background: Rectangle {
        implicitHeight: 32
        radius: ThemeManager.radiusSmall
        color: root.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
        border.width: root.focusVisible ? 2 : 1
        border.color: root.focusVisible ? ThemeManager.accent : ThemeManager.border
    }

    contentItem: Text {
        leftPadding: 8
        rightPadding: 18
        text: root.displayText
        font.pixelSize: ThemeManager.fontSizeSmall
        color: ThemeManager.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        text: "▼"
        color: ThemeManager.textMuted
        font.pixelSize: 10
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
    }
}
