import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property var getState: null // () => { text, selectionStart, selectionEnd, cursorPosition }
    property var applyState: null // (result) => void; result from InlineFormatting.wrapSelection
    property bool collapsed: false

    // ToolBar's implicitHeight won't propagate through a custom Flickable contentItem unless we set it.
    implicitHeight: toolbar.implicitHeight

    function _safeCall(fn, fallback) {
        try { return fn ? fn() : fallback } catch (e) { return fallback }
    }

    function _stateOrNull() {
        const s = _safeCall(getState, null)
        if (!s) return null
        if (!("text" in s)) return null
        return s
    }

    function _apply(result) {
        if (!result) return
        if (applyState) applyState(result)
    }

    function wrap(prefix, suffix, toggle) {
        const s = _stateOrNull()
        if (!s) return
        const out = InlineFormatting.wrapSelection(
            s.text || "",
            ("selectionStart" in s) ? s.selectionStart : -1,
            ("selectionEnd" in s) ? s.selectionEnd : -1,
            ("cursorPosition" in s) ? s.cursorPosition : 0,
            prefix,
            suffix,
            toggle === true
        )
        _apply(out)
    }

    function spanStyle(styleText) {
        const style = (styleText || "").trim()
        if (style.length === 0) return
        wrap("<span style=\"" + style + "\">", "</span>", false)
    }

    function underline() { wrap("<u>", "</u>", true) }
    function bold() { wrap("**", "**", true) }
    function italic() { wrap("*", "*", true) }
    function strike() { wrap("<s>", "</s>", true) }

    function fontFamily(family) {
        const f = (family || "").replaceAll("'", "\\'")
        spanStyle("font-family: '" + f + "';")
    }

    function fontSize(px) {
        const n = parseInt(px, 10)
        if (!isFinite(n) || n <= 0) return
        const pt = Math.max(1, Math.round(n * 0.75))
        spanStyle("font-size: " + pt + "pt;")
    }

    function textColor(hex) {
        const c = (hex || "").trim()
        if (c.length === 0) return
        spanStyle("color: " + c + ";")
    }

    ToolBar {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: 40
        focusPolicy: Qt.NoFocus

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusSmall
        }

        contentItem: Flickable {
            clip: true
            contentWidth: root.collapsed ? collapsedRow.implicitWidth : fullRow.implicitWidth
            contentHeight: root.collapsed ? collapsedRow.implicitHeight : fullRow.implicitHeight
            implicitHeight: toolbar.implicitHeight
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: row
                spacing: 0
                height: toolbar.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: collapsedRow
                    visible: root.collapsed
                    spacing: ThemeManager.spacingSmall
                    height: toolbar.implicitHeight

                    ToolButton {
                        text: "Formatting"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.collapsed = false
                    }

                    ToolButton {
                        text: "▾"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.collapsed = false
                    }
                }

                Row {
                    id: fullRow
                    visible: !root.collapsed
                    spacing: ThemeManager.spacingSmall
                    height: toolbar.implicitHeight

                    ToolButton { text: "B"; font.bold: true; focusPolicy: Qt.NoFocus; onClicked: root.bold() }
                    ToolButton { text: "I"; font.italic: true; focusPolicy: Qt.NoFocus; onClicked: root.italic() }
                    ToolButton { text: "U"; focusPolicy: Qt.NoFocus; onClicked: root.underline() }
                    ToolButton { text: "S"; focusPolicy: Qt.NoFocus; onClicked: root.strike() }

                    ToolSeparator { }

                    ToolButton {
                        text: "Color"
                        focusPolicy: Qt.NoFocus
                        onClicked: colorMenu.open()
                    }

                    ComboBox {
                        id: fontCombo
                        width: 160
                        focusPolicy: Qt.NoFocus
                        model: [
                            ThemeManager.fontFamily,
                            ThemeManager.monoFontFamily,
                            "Sans Serif",
                            "Serif",
                            "Monospace"
                        ]
                        onActivated: root.fontFamily(currentText)
                    }

                    ComboBox {
                        id: sizeCombo
                        width: 90
                        focusPolicy: Qt.NoFocus
                        model: [10, 12, 14, 16, 18, 20, 24, 32]
                        onActivated: root.fontSize(currentText)
                    }

                    Item { width: 1; height: 1 }

                    ToolButton {
                        text: "▴"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.collapsed = true
                    }
                }
            }
        }
    }

    Menu {
        id: colorMenu
        y: toolbar.height
        x: 0

        function item(label, hex) {
            return { label: label, hex: hex }
        }

        Instantiator {
            model: [
                colorMenu.item("Black", "#000000"),
                colorMenu.item("Gray", "#6b7280"),
                colorMenu.item("Red", "#dc2626"),
                colorMenu.item("Orange", "#ea580c"),
                colorMenu.item("Green", "#16a34a"),
                colorMenu.item("Blue", "#2563eb"),
                colorMenu.item("Purple", "#7c3aed")
            ]
            delegate: MenuItem {
                text: modelData.label
                focusPolicy: Qt.NoFocus
                onTriggered: root.textColor(modelData.hex)
            }
            onObjectAdded: function(_, obj) { colorMenu.insertItem(colorMenu.count, obj) }
            onObjectRemoved: function(_, obj) { colorMenu.removeItem(obj) }
        }
    }
}
