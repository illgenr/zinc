import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property bool collapsed: false
    property string sortMode: "alphabetical" // "alphabetical" | "updatedAt" | "createdAt"
    property bool canCreate: true

    signal newPageRequested()
    signal findRequested()
    signal newNotebookRequested()
    signal sortModeRequested(string mode)

    readonly property int _buttonHeight: 32
    readonly property int _minPrimaryButtonWidth: 132 // New Page / New Notebook
    readonly property int _minSecondaryButtonWidth: 92 // Find / Sort

    visible: !collapsed
    implicitHeight: actionsFlow.implicitHeight

    Flow {
        id: actionsFlow

        readonly property int _twoColumnMinWidth: root._minPrimaryButtonWidth + spacing + root._minSecondaryButtonWidth
        readonly property bool twoColumns: root.width >= _twoColumnMinWidth

        width: twoColumns ? _twoColumnMinWidth : root.width
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: ThemeManager.spacingSmall

        readonly property real primaryButtonWidth: twoColumns ? root._minPrimaryButtonWidth : width
        readonly property real secondaryButtonWidth: twoColumns ? root._minSecondaryButtonWidth : width

        Rectangle {
            objectName: "desktopNewPageButton"
            width: actionsFlow.primaryButtonWidth
            height: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: newPageMouse.containsMouse || newPageMouse.pressed ? ThemeManager.surfaceHover : ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            opacity: root.canCreate ? 1.0 : 0.45

            Text {
                anchors.centerIn: parent
                text: "🗎 New Page"
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                elide: Text.ElideRight
            }

            ToolTip.visible: newPageMouse.containsMouse
            ToolTip.text: "New page (Ctrl+N)"

            Accessible.name: "New Page"

            MouseArea {
                id: newPageMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.canCreate
                onClicked: root.newPageRequested()
            }
        }

        Rectangle {
            objectName: "desktopFindButton"
            width: actionsFlow.secondaryButtonWidth
            height: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: findMouse.containsMouse || findMouse.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover

            RowLayout {
                anchors.centerIn: parent
                spacing: ThemeManager.spacingSmall

                Text {
                    text: "🔍"
                    font.pixelSize: ThemeManager.fontSizeSmall
                }

                Text {
                    text: "Find"
                    color: ThemeManager.textMuted
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideRight
                }
            }

            ToolTip.visible: findMouse.containsMouse
            ToolTip.text: "Find (Ctrl+F)"

            Accessible.name: "Find"

            MouseArea {
                id: findMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.findRequested()
            }
        }

        Rectangle {
            objectName: "desktopNewNotebookButton"
            width: actionsFlow.primaryButtonWidth
            height: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: newNotebookMouse.containsMouse || newNotebookMouse.pressed ? ThemeManager.surfaceHover : ThemeManager.surface
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
                    elide: Text.ElideRight
                }
            }

            ToolTip.visible: newNotebookMouse.containsMouse
            ToolTip.text: "New notebook"

            Accessible.name: "New Notebook"

            MouseArea {
                id: newNotebookMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.canCreate
                onClicked: root.newNotebookRequested()
            }
        }

        Rectangle {
            objectName: "desktopSortButton"
            width: actionsFlow.secondaryButtonWidth
            height: root._buttonHeight
            radius: ThemeManager.radiusMedium
            color: sortMouse.containsMouse || sortMouse.pressed ? ThemeManager.surfaceHover : ThemeManager.surface
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
                    elide: Text.ElideRight
                }
            }

            Accessible.name: "Sort"

            MouseArea {
                id: sortMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
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
