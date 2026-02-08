import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Dialog {
    id: root

    title: "Keyboard shortcuts"
    anchors.centerIn: parent
    modal: true
    standardButtons: Dialog.Close

    property bool isMobile: Qt.platform.os === "android" || parent.width < 600
    width: isMobile ? parent.width * 0.95 : Math.min(560, parent.width * 0.9)
    height: isMobile ? parent.height * 0.9 : Math.min(520, parent.height * 0.85)

    readonly property var shortcuts: [
        { key: "Ctrl+N", desc: "New page" },
        { key: "Ctrl+F", desc: "Find" },
        { key: "Ctrl+\\", desc: "Toggle sidebar" },
        { key: "Ctrl+E", desc: "Focus page tree" },
        { key: "Ctrl+Alt+S", desc: "Open settings" },
        { key: "Ctrl+B", desc: "Bold (hybrid editor)" },
        { key: "Ctrl+I", desc: "Italic (hybrid editor)" },
        { key: "Ctrl+U", desc: "Underline (hybrid editor)" },
        { key: "Ctrl+L", desc: "Insert link (hybrid editor)" },
        { key: "Ctrl+Shift+M", desc: "Toggle formatting bar (hybrid editor)" },
        { key: "Ctrl+Shift+?", desc: "Show this screen" },
        { key: "Shift+Enter", desc: "Insert newline in text blocks" },
        { key: "Alt+↑ / Alt+↓", desc: "Move block up/down" }
    ]

    background: Rectangle {
        color: ThemeManager.surface
        border.width: isMobile ? 0 : 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusLarge
    }

    contentItem: ScrollView {
        clip: true

        Item {
            width: root.width
            implicitHeight: column.implicitHeight + ThemeManager.spacingMedium * 2

            Column {
                id: column

                anchors.fill: parent
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall

                Repeater {
                    model: root.shortcuts

                    delegate: Rectangle {
                        width: column.width
                        height: row.implicitHeight + ThemeManager.spacingSmall * 2
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.background

                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.margins: ThemeManager.spacingSmall
                            spacing: ThemeManager.spacingMedium

                            Rectangle {
                                Layout.preferredWidth: 140
                                Layout.preferredHeight: 28
                                radius: ThemeManager.radiusSmall
                                color: ThemeManager.surfaceHover

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.key
                                    color: ThemeManager.text
                                    font.family: ThemeManager.monoFontFamily
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.desc
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeNormal
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }
}
