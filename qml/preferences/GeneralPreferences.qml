pragma Singleton
import QtQuick
import QtCore

Item {
    id: root

    readonly property bool settingsEnabled: Qt.application.name !== "zinc_qml_tests"
    property var settings: settingsLoader.item

    // When a page is created (new page / new child page), jump to it or stay on the current page.
    property bool jumpToNewPageOnCreate: true
    // Future settings toggle: page-tree keyboard typeahead title matching mode.
    property bool pageTreeTypeaheadCaseSensitive: false

    Loader {
        id: settingsLoader
        active: settingsEnabled
        sourceComponent: Settings {
            category: "General"
            property bool jumpToNewPageOnCreate: true
            property bool pageTreeTypeaheadCaseSensitive: false
        }

        onLoaded: {
            if (item) {
                root.jumpToNewPageOnCreate = item.jumpToNewPageOnCreate
                root.pageTreeTypeaheadCaseSensitive = item.pageTreeTypeaheadCaseSensitive
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

        function onPageTreeTypeaheadCaseSensitiveChanged() {
            if (root.pageTreeTypeaheadCaseSensitive !== settingsLoader.item.pageTreeTypeaheadCaseSensitive) {
                root.pageTreeTypeaheadCaseSensitive = settingsLoader.item.pageTreeTypeaheadCaseSensitive
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

        function onPageTreeTypeaheadCaseSensitiveChanged() {
            if (settingsLoader.item
                    && settingsLoader.item.pageTreeTypeaheadCaseSensitive !== root.pageTreeTypeaheadCaseSensitive) {
                settingsLoader.item.pageTreeTypeaheadCaseSensitive = root.pageTreeTypeaheadCaseSensitive
            }
        }
    }
}
