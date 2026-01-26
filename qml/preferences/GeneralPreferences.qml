pragma Singleton
import QtQuick
import QtCore

Item {
    id: root

    readonly property bool settingsEnabled: Qt.application.name !== "zinc_qml_tests"
    property var settings: settingsLoader.item

    // When a page is created (new page / new child page), jump to it or stay on the current page.
    property bool jumpToNewPageOnCreate: true

    Loader {
        id: settingsLoader
        active: settingsEnabled
        sourceComponent: Settings {
            category: "General"
            property bool jumpToNewPageOnCreate: true
        }

        onLoaded: {
            if (item) {
                root.jumpToNewPageOnCreate = item.jumpToNewPageOnCreate
            }
        }
    }

    Connections {
        target: settingsLoader.item
        enabled: settingsLoader.item

        function onJumpToNewPageOnCreateChanged() {
            if (root.jumpToNewPageOnCreate !== settingsLoader.item.jumpToNewPageOnCreate) {
                root.jumpToNewPageOnCreate = settingsLoader.item.jumpToNewPageOnCreate
            }
        }
    }

    Connections {
        target: root
        enabled: settingsLoader.item

        function onJumpToNewPageOnCreateChanged() {
            if (settingsLoader.item && settingsLoader.item.jumpToNewPageOnCreate !== root.jumpToNewPageOnCreate) {
                settingsLoader.item.jumpToNewPageOnCreate = root.jumpToNewPageOnCreate
            }
        }
    }
}

