import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property var getState: null // () => { text, selectionStart, selectionEnd, cursorPosition }
    property var applyState: null // (result) => void; result from InlineFormatting.wrapSelection
    property bool collapsed: false
    readonly property bool _isMobile: Qt.platform.os === "android" || Qt.platform.os === "ios"

    readonly property int _mobileRowHeight: 44
    readonly property int _mobilePadding: 4

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

    function _format(fmt, opts) {
        const s = _stateOrNull()
        if (!s) return
        const out = InlineRichText.applyFormat(
            s.text || "",
            ("runs" in s) ? (s.runs || []) : [],
            ("selectionStart" in s) ? s.selectionStart : -1,
            ("selectionEnd" in s) ? s.selectionEnd : -1,
            ("cursorPosition" in s) ? s.cursorPosition : 0,
            fmt || ({}),
            ("typingAttrs" in s) ? (s.typingAttrs || ({})) : ({})
        )
        if (out && opts && opts.focusTarget) out.focusTarget = opts.focusTarget
        _apply(out)
    }

    function underline() { _format({ type: "underline", toggle: true }) }
    function bold() { _format({ type: "bold", toggle: true }) }
    function italic() { _format({ type: "italic", toggle: true }) }
    function strike() { _format({ type: "strike", toggle: true }) }
    function link() {
        const s = _stateOrNull()
        if (!s) return
        const text = s.text || ""
        const selectionStart = ("selectionStart" in s) ? s.selectionStart : -1
        const selectionEnd = ("selectionEnd" in s) ? s.selectionEnd : -1
        const cursorPosition = ("cursorPosition" in s) ? s.cursorPosition : 0

        const hasSelection = selectionStart >= 0 && selectionEnd >= 0 && selectionStart !== selectionEnd
        const a = hasSelection ? Math.max(0, Math.min(selectionStart, selectionEnd)) : Math.max(0, cursorPosition)
        const b = hasSelection ? Math.max(0, Math.max(selectionStart, selectionEnd)) : Math.max(0, cursorPosition)
        const selected = hasSelection ? text.substring(a, b) : ""

        const label = selected
        const href = selected
        const before = text.substring(0, a)
        const after = text.substring(b)
        const inserted = "[" + (label || "") + "](" + (href || "") + ")"
        const outText = before + inserted + after

        const hrefStart = before.length + inserted.indexOf("(") + 1
        const hrefEnd = before.length + inserted.indexOf(")")

        _apply({
            text: outText,
            selectionStart: hrefStart,
            selectionEnd: Math.max(hrefStart, hrefEnd),
            cursorPosition: hrefStart
        })
    }

    function fontFamily(family) {
        const f = (family || "").trim()
        if (f.length === 0) return
        _format({ type: "fontFamily", value: f }, { focusTarget: "toolbar" })
    }

    function fontSize(px) {
        const n = parseInt(px, 10)
        if (!isFinite(n) || n <= 0) return
        const pt = Math.max(1, Math.round(n * 0.75))
        _format({ type: "fontSizePt", value: pt }, { focusTarget: "toolbar" })
    }

    function textColor(hex) {
        const c = (hex || "").trim()
        if (c.length === 0) return
        _format({ type: "color", value: c })
    }

    ToolBar {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: root._isMobile
            ? ((contentLoader.item ? contentLoader.item.implicitHeight : root._mobileRowHeight) + root._mobilePadding * 2)
            : (contentLoader.item ? contentLoader.item.implicitHeight : 32)
        focusPolicy: Qt.NoFocus

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusSmall
        }

        contentItem: Loader {
            id: contentLoader
            anchors.fill: parent
            anchors.margins: root._isMobile ? root._mobilePadding : 0
            sourceComponent: root._isMobile ? mobileContent : desktopContent
        }
    }

    Component {
        id: desktopContent

        Item {
            implicitHeight: root.collapsed ? collapsedRow.implicitHeight : fullFlow.implicitHeight

            Row {
                id: collapsedRow
                visible: root.collapsed
                spacing: ThemeManager.spacingSmall
                height: 32

                ToolButton {
                    text: "Formatting"
                    height: 28
                    focusPolicy: Qt.NoFocus
                    onClicked: root.collapsed = false
                }

                ToolButton {
                    text: "▾"
                    height: 28
                    focusPolicy: Qt.NoFocus
                    onClicked: root.collapsed = false
                }
            }

            Flow {
                id: fullFlow
                visible: !root.collapsed
                width: parent.width
                spacing: ThemeManager.spacingSmall
                flow: Flow.LeftToRight

                property int controlHeight: 28

                ToolButton { text: "B"; height: fullFlow.controlHeight; font.bold: true; focusPolicy: Qt.NoFocus; onClicked: root.bold() }
                ToolButton { text: "I"; height: fullFlow.controlHeight; font.italic: true; focusPolicy: Qt.NoFocus; onClicked: root.italic() }
                ToolButton { text: "U"; height: fullFlow.controlHeight; focusPolicy: Qt.NoFocus; onClicked: root.underline() }
                ToolButton { text: "S"; height: fullFlow.controlHeight; focusPolicy: Qt.NoFocus; onClicked: root.strike() }
                ToolButton { text: "Link"; height: fullFlow.controlHeight; focusPolicy: Qt.NoFocus; onClicked: root.link() }

                ToolButton {
                    text: "Color"
                    height: fullFlow.controlHeight
                    focusPolicy: Qt.NoFocus
                    onClicked: colorMenu.open()
                }

                ComboBox {
                    id: fontCombo
                    width: 220
                    height: fullFlow.controlHeight
                    focusPolicy: Qt.StrongFocus
                    model: FontUtils.systemFontFamilies()
                    onActivated: function(index) {
                        root.fontFamily(fontCombo.textAt(index))
                        Qt.callLater(() => fontCombo.forceActiveFocus())
                    }
                }

                ComboBox {
                    id: sizeCombo
                    width: 90
                    height: fullFlow.controlHeight
                    focusPolicy: Qt.StrongFocus
                    model: [10, 12, 14, 16, 18, 20, 24, 32]
                    onActivated: function(index) {
                        root.fontSize(sizeCombo.textAt(index))
                        Qt.callLater(() => sizeCombo.forceActiveFocus())
                    }
                }

                ToolButton {
                    text: "▴"
                    height: fullFlow.controlHeight
                    focusPolicy: Qt.NoFocus
                    onClicked: root.collapsed = true
                }
            }
        }
    }

    Component {
        id: mobileContent

        ColumnLayout {
            anchors.fill: parent
            spacing: root._mobilePadding

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root._mobileRowHeight
                spacing: root._mobilePadding

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root._mobilePadding
                    visible: root.collapsed

                    Label {
                        Layout.fillWidth: true
                        text: "Formatting"
                        color: ThemeManager.text
                        verticalAlignment: Text.AlignVCenter
                    }

                    ToolButton {
                        text: "v"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.collapsed = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: root._mobilePadding
                    visible: !root.collapsed

                    ToolButton { text: "B"; font.bold: true; focusPolicy: Qt.NoFocus; onClicked: root.bold() }
                    ToolButton { text: "I"; font.italic: true; focusPolicy: Qt.NoFocus; onClicked: root.italic() }
                    ToolButton { text: "U"; focusPolicy: Qt.NoFocus; onClicked: root.underline() }
                    ToolButton { text: "S"; focusPolicy: Qt.NoFocus; onClicked: root.strike() }

                    ToolButton {
                        text: "Color"
                        focusPolicy: Qt.NoFocus
                        onClicked: colorMenu.open()
                    }

                    Item { Layout.fillWidth: true }

                    ToolButton {
                        text: "^"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.collapsed = true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root._mobileRowHeight
                spacing: root._mobilePadding
                visible: !root.collapsed

                ComboBox {
                    id: fontCombo
                    Layout.fillWidth: true
                    focusPolicy: Qt.NoFocus
                    implicitHeight: root._mobileRowHeight
                    popup.z: 20000
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
                    Layout.preferredWidth: 120
                    focusPolicy: Qt.NoFocus
                    implicitHeight: root._mobileRowHeight
                    popup.z: 20000
                    model: [10, 12, 14, 16, 18, 20, 24, 32]
                    onActivated: root.fontSize(currentText)
                }
            }

            implicitHeight: root._mobileRowHeight + (root.collapsed ? 0 : (root._mobilePadding + root._mobileRowHeight))
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
