import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import zinc

Popup {
    id: root

    property date selectedDate: new Date()
    property bool includeTime: false
    property date viewDate: new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
    readonly property bool debugLayout: Qt.application.arguments.indexOf("--debug-date-picker") !== -1
    signal accepted(date selectedDate)
    signal canceled()

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    width: 340
    padding: ThemeManager.spacingMedium

    onSelectedDateChanged: {
        if (viewDate.getFullYear() !== selectedDate.getFullYear() || viewDate.getMonth() !== selectedDate.getMonth()) {
            viewDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
        }
        if (debugLayout) {
            console.log("DatePickerPopup: selectedDate=", selectedDate)
        }
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(value, maxValue))
    }

    function keyboardTopY() {
        const kb = Qt.inputMethod.keyboardRectangle
        if (!Qt.inputMethod.visible || !kb || kb.height <= 0) {
            return parent ? parent.height : 0
        }
        console.debug(kb.y)
        return kb.y
    }

    function updatePosition() {
        if (!parent) return
        const margin = ThemeManager.spacingMedium
        const kbTop = keyboardTopY()

        const centerX = (parent.width - root.width) / 2
        const maxX = parent.width - root.width - margin
        root.x = clamp(centerX, margin, Math.max(margin, maxX))

        const desiredY = (kbTop - root.height) / 2
        const maxY = kbTop - root.height - margin
        root.y = clamp(desiredY, margin, Math.max(margin, maxY))
    }

    onOpened: updatePosition()
    onWidthChanged: updatePosition()
    onHeightChanged: updatePosition()

    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() { root.updatePosition() }
        function onKeyboardRectangleChanged() { root.updatePosition() }
    }

    background: Rectangle {
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusMedium
    }

    contentItem: ColumnLayout {
        spacing: ThemeManager.spacingMedium

        Text {
            text: "Pick a date"
            color: ThemeManager.text
            font.pixelSize: ThemeManager.fontSizeNormal
            font.weight: Font.DemiBold
        }

        CheckBox {
            id: includeTimeCheckbox
            text: "Include time"
            checked: root.includeTime
            onToggled: root.includeTime = checked
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingSmall
            visible: root.includeTime

            Text {
                text: "Time"
                color: ThemeManager.textSecondary
            }

            SpinBox {
                id: hourSpin
                from: 0
                to: 23
                value: root.selectedDate.getHours()
                editable: true
            }

            Text { text: ":"; color: ThemeManager.textSecondary }

            SpinBox {
                id: minuteSpin
                from: 0
                to: 59
                value: root.selectedDate.getMinutes()
                editable: true
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingSmall

            ToolButton {
                text: "‹"
                onClicked: {
                    const d = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth(), 1)
                    d.setMonth(d.getMonth() - 1)
                    root.viewDate = d
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: monthGrid.title
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
            }

            ToolButton {
                text: "›"
                onClicked: {
                    const d = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth(), 1)
                    d.setMonth(d.getMonth() + 1)
                    root.viewDate = d
                }
            }
        }

        Basic.DayOfWeekRow {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingMedium
        }

        Basic.MonthGrid {
            id: monthGrid
            Layout.fillWidth: true
            Layout.preferredHeight: topPadding + bottomPadding + (6 * cellHeight) + (5 * spacing)
            Layout.minimumHeight: Layout.preferredHeight
            spacing: 0
            topPadding: 0
            bottomPadding: 0
            leftPadding: 0
            rightPadding: 0
            font.pixelSize: ThemeManager.fontSizeSmall

            readonly property real cellWidth: Math.max(
                36,
                Math.floor((width - leftPadding - rightPadding - 6 * spacing) / 7)
            )
            readonly property real cellHeight: 48
            onWidthChanged: if (root.debugLayout) console.log("MonthGrid size=", width, "x", height, "cell=", cellWidth, "x", cellHeight)

            month: root.viewDate.getMonth()
            year: root.viewDate.getFullYear()

            delegate: Item {
                required property var model
                visible: model.month === monthGrid.month
                implicitWidth: monthGrid.cellWidth
                implicitHeight: monthGrid.cellHeight
                width: implicitWidth
                height: implicitHeight

                readonly property int dayNumber: Number(model.day)
                readonly property bool isSelected: root.selectedDate.getFullYear() === root.viewDate.getFullYear() &&
                    root.selectedDate.getMonth() === root.viewDate.getMonth() &&
                    root.selectedDate.getDate() === dayNumber

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: ThemeManager.radiusSmall
                    color: parent.isSelected
                        ? ThemeManager.accentLight
                        : (dayMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")
                    border.width: parent.isSelected ? 2 : 0
                    border.color: ThemeManager.accent
                }

                Text {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: dayNumber
                    color: parent.isSelected ? ThemeManager.accent : ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeSmall
                }

                MouseArea {
                    id: dayMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onPressed: {
                        root.selectedDate = new Date(
                            root.viewDate.getFullYear(),
                            root.viewDate.getMonth(),
                            dayNumber,
                            root.selectedDate.getHours(),
                            root.selectedDate.getMinutes()
                        )
                        if (root.debugLayout) {
                            console.log("DatePickerPopup: press day=", dayNumber, "delegate=", width, "x", height, "mouse=", dayMouse.width, "x", dayMouse.height)
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.debugLayout
                    color: "transparent"
                    border.width: 1
                    border.color: dayMouse.containsMouse ? "#ff00ff" : "#00ff00"
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingSmall

            Item { Layout.fillWidth: true }

            Button {
                text: "Cancel"
                onClicked: {
                    root.close()
                    root.canceled()
                }
            }

            Button {
                text: "OK"
                onClicked: {
                    const d = root.selectedDate
                    const out = new Date(
                        d.getFullYear(),
                        d.getMonth(),
                        d.getDate(),
                        root.includeTime ? hourSpin.value : 0,
                        root.includeTime ? minuteSpin.value : 0
                    )
                    root.close()
                    root.accepted(out)
                }
            }
        }
    }
}
