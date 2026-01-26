pragma Singleton
import QtQuick
import QtCore

Item {
    id: root

    readonly property bool settingsEnabled: Qt.application.name !== "zinc_qml_tests"
    property var settings: settingsLoader.item

    property int gutterPositionPx: 0

    Loader {
        id: settingsLoader
        active: settingsEnabled
        sourceComponent: Settings {
            category: "Editor"
            property int gutterPositionPx: 0
        }

        onLoaded: {
            if (item) {
                root.gutterPositionPx = item.gutterPositionPx
            }
        }
    }

    Connections {
        target: settingsLoader.item
        enabled: settingsLoader.item

        function onGutterPositionPxChanged() {
            if (root.gutterPositionPx !== settingsLoader.item.gutterPositionPx) {
                root.gutterPositionPx = settingsLoader.item.gutterPositionPx
            }
        }
    }

    Connections {
        target: root
        enabled: settingsLoader.item

        function onGutterPositionPxChanged() {
            if (settingsLoader.item && settingsLoader.item.gutterPositionPx !== root.gutterPositionPx) {
                settingsLoader.item.gutterPositionPx = root.gutterPositionPx
            }
        }
    }
}

