import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property string sortMode: "alphabetical" // "alphabetical" | "updatedAt" | "createdAt"
    property bool canCreate: true

    signal newPageRequested()
    signal findRequested()
    signal newNotebookRequested()
    signal sortModeRequested(string mode)

    readonly property int _buttonHeight: 44

    implicitHeight: grid.implicitHeight

    GridLayout {
        id: grid

        width: root.width
        columns: 2
        columnSpacing: ThemeManager.spacingSmall
        rowSpacing: ThemeManager.spacingSmall

        Rectangle {
            objectName: "mobileNewPageButton"
            Layout.fillWidth: true
            Layout.preferredHeight: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: newPageMouse.pressed ? ThemeManager.accentHover : ThemeManager.accent
            opacity: root.canCreate ? 1.0 : 0.45

            RowLayout {
                anchors.centerIn: parent
                spacing: ThemeManager.spacingSmall

                Text {
                    text: "🗎"
                    color: "white"
                    font.pixelSize: ThemeManager.fontSizeNormal
                }

                Text {
                    text: "New Page"
                    color: "white"
                    font.pixelSize: ThemeManager.fontSizeNormal
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            Accessible.name: "New Page"

            MouseArea {
                id: newPageMouse
                anchors.fill: parent
                enabled: root.canCreate
                onClicked: root.newPageRequested()
            }
        }

        Rectangle {
            objectName: "mobileFindButton"
            Layout.fillWidth: true
            Layout.preferredHeight: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: findMouse.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover

            RowLayout {
                anchors.centerIn: parent
                spacing: ThemeManager.spacingSmall

                Text {
                    text: "🔍"
                    font.pixelSize: ThemeManager.fontSizeNormal
                }

                Text {
                    text: "Find"
                    color: ThemeManager.text
                    font.weight: Font.Medium
                    font.pixelSize: ThemeManager.fontSizeNormal
                    elide: Text.ElideRight
                }
            }

            Accessible.name: "Find"

            MouseArea {
                id: findMouse
                anchors.fill: parent
                onClicked: root.findRequested()
            }
        }

        Rectangle {
            objectName: "mobileNewNotebookButton"
            Layout.fillWidth: true
            Layout.preferredHeight: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: newNotebookMouse.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            opacity: root.canCreate ? 1.0 : 0.45

            RowLayout {
                anchors.centerIn: parent
                spacing: ThemeManager.spacingSmall

                Text {
                    text: "📁"
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                }

                Text {
                    text: "New Notebook"
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            Accessible.name: "New Notebook"

            MouseArea {
                id: newNotebookMouse
                anchors.fill: parent
                enabled: root.canCreate
                onClicked: root.newNotebookRequested()
            }
        }

        Rectangle {
            objectName: "mobileSortButton"
            Layout.fillWidth: true
            Layout.preferredHeight: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: sortMouse.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border

            RowLayout {
                anchors.centerIn: parent
                spacing: ThemeManager.spacingSmall

                Text {
                    text: "⇅"
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                }

                Text {
                    text: "Sort"
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            Accessible.name: "Sort"

            MouseArea {
                id: sortMouse
                anchors.fill: parent
                onClicked: sortMenu.popup()
            }

            Menu {
                id: sortMenu
                modal: true

                MenuItem {
                    text: "Alphabetical"
                    checkable: true
                    checked: root.sortMode === "alphabetical"
                    onTriggered: root.sortModeRequested("alphabetical")
                }
                MenuItem {
                    text: "Updated at"
                    checkable: true
                    checked: root.sortMode === "updatedAt"
                    onTriggered: root.sortModeRequested("updatedAt")
                }
                MenuItem {
                    text: "Created at"
                    checkable: true
                    checked: root.sortMode === "createdAt"
                    onTriggered: root.sortModeRequested("createdAt")
                }
            }
        }
    }
}
