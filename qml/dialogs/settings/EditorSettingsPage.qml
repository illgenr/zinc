import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

SettingsPage {
    function focusFirstControl() {
        if (!gutterPositionField || !gutterPositionField.visible || !gutterPositionField.enabled) {
            console.log("EditorSettingsPage focus: gutterPositionField unavailable visible=",
                        gutterPositionField ? gutterPositionField.visible : "n/a",
                        "enabled=", gutterPositionField ? gutterPositionField.enabled : "n/a")
            return false
        }
        console.log("EditorSettingsPage focus: focusing gutterPositionField")
        gutterPositionField.forceActiveFocus()
        return true
    }

    SettingsSection {
        title: "Layout"

        SettingsRow {
            label: "Gutter position (px)"

            TextField {
                id: gutterPositionField
                width: parent.width
                text: "" + EditorPreferences.gutterPositionPx
                inputMethodHints: Qt.ImhPreferNumbers
                validator: IntValidator { bottom: -9999; top: 9999 }

                background: Rectangle {
                    implicitHeight: 32
                    radius: ThemeManager.radiusSmall
                    color: gutterPositionField.activeFocus ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                    border.width: 1
                    border.color: ThemeManager.border
                }

                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeSmall
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8

                onEditingFinished: {
                    const parsed = parseInt(text, 10)
                    EditorPreferences.gutterPositionPx = isNaN(parsed) ? 0 : parsed
                    text = "" + EditorPreferences.gutterPositionPx
                }

                Connections {
                    target: EditorPreferences
                    function onGutterPositionPxChanged() {
                        if (gutterPositionField.activeFocus) return
                        gutterPositionField.text = "" + EditorPreferences.gutterPositionPx
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Positive values move the gutter right; negative values move it left."
            color: ThemeManager.textMuted
            font.pixelSize: ThemeManager.fontSizeSmall
            wrapMode: Text.Wrap
        }
    }
}
