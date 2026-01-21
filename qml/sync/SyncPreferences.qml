pragma Singleton
import QtQuick
import QtCore

Item {
    id: root

    readonly property bool settingsEnabled: Qt.application.name !== "zinc_qml_tests"
    property var settings: settingsLoader.item

    property bool autoSyncEnabled: true

    Loader {
        id: settingsLoader
        active: settingsEnabled
        sourceComponent: Settings {
            category: "Sync"
            property bool autoSyncEnabled: true
        }

        onLoaded: {
            if (item) {
                root.autoSyncEnabled = item.autoSyncEnabled
            }
        }
    }

    Connections {
        target: settingsLoader.item
        enabled: settingsLoader.item

        function onAutoSyncEnabledChanged() {
            if (root.autoSyncEnabled !== settingsLoader.item.autoSyncEnabled) {
                root.autoSyncEnabled = settingsLoader.item.autoSyncEnabled
            }
        }
    }

    Connections {
        target: root
        enabled: settingsLoader.item

        function onAutoSyncEnabledChanged() {
            if (settingsLoader.item && settingsLoader.item.autoSyncEnabled !== root.autoSyncEnabled) {
                settingsLoader.item.autoSyncEnabled = root.autoSyncEnabled
            }
        }
    }
}

