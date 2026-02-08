import QtQuick
import QtQuick.Layouts
import zinc

SettingsPage {
    function focusFirstControl() {
        console.log("AboutSettingsPage focus: no interactive control")
        return false
    }

    SettingsSection {
        title: "About Zinc"

        Text {
            text: "Zinc Notes"
            color: ThemeManager.text
            font.pixelSize: ThemeManager.fontSizeXLarge
            font.weight: Font.Bold
        }

        Text {
            text: "Version 0.4.0"
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeNormal
        }

        Text {
            Layout.fillWidth: true
            text: "A local-first, peer-to-peer note-taking app with real-time collaboration."
            color: ThemeManager.textMuted
            font.pixelSize: ThemeManager.fontSizeSmall
            wrapMode: Text.Wrap
        }
    }
}
