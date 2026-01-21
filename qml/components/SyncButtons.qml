import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

RowLayout {
    id: root

    required property bool autoSyncEnabled
    property bool compact: false

    signal settingsRequested()
    signal manualSyncRequested()

    ToolButton {
        id: manualSync
        objectName: "manualSyncButton"
        visible: !root.autoSyncEnabled

        width: root.compact ? 24 : implicitWidth
        height: root.compact ? 24 : implicitHeight

        contentItem: Text {
            text: "🔄"
            color: root.compact ? ThemeManager.textSecondary : ThemeManager.text
            font.pixelSize: root.compact ? ThemeManager.fontSizeNormal : 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: ThemeManager.radiusSmall
            color: root.compact
                ? (parent.hovered ? ThemeManager.surfaceHover : "transparent")
                : (parent.pressed ? ThemeManager.surfaceActive : "transparent")
        }

        onClicked: root.manualSyncRequested()
    }

    ToolButton {
        id: settings
        objectName: "settingsButton"

        width: root.compact ? 24 : implicitWidth
        height: root.compact ? 24 : implicitHeight

        contentItem: Text {
            text: "⚙"
            color: root.compact ? ThemeManager.textSecondary : ThemeManager.text
            font.pixelSize: root.compact ? ThemeManager.fontSizeNormal : 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: ThemeManager.radiusSmall
            color: root.compact
                ? (parent.hovered ? ThemeManager.surfaceHover : "transparent")
                : (parent.pressed ? ThemeManager.surfaceActive : "transparent")
        }

        onClicked: root.settingsRequested()
    }
}
