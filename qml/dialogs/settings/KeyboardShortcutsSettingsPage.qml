import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

SettingsPage {
    id: page

    readonly property var shortcutRows: [
        { key: "newPageShortcut", label: "New page" },
        { key: "findShortcut", label: "Find" },
        { key: "toggleSidebarShortcut", label: "Toggle sidebar" },
        { key: "focusPageTreeShortcut", label: "Focus page tree" },
        { key: "openSettingsShortcut", label: "Open settings" },
        { key: "showShortcutHelpShortcut", label: "Show keyboard shortcuts" },
        { key: "focusDocumentEndShortcut", label: "Focus document end" },
        { key: "boldShortcut", label: "Bold (hybrid editor)" },
        { key: "italicShortcut", label: "Italic (hybrid editor)" },
        { key: "underlineShortcut", label: "Underline (hybrid editor)" },
        { key: "linkShortcut", label: "Insert link (hybrid editor)" },
        { key: "toggleFormatBarShortcut", label: "Toggle formatting bar (hybrid editor)" }
    ]

    property string editingShortcutKey: ""

    function focusFirstControl() {
        if (!firstChangeButton || !firstChangeButton.visible || !firstChangeButton.enabled) return false
        firstChangeButton.forceActiveFocus()
        return true
    }

    function sequenceForKey(prefKey) {
        switch (prefKey) {
        case "newPageShortcut": return ShortcutPreferences.newPageShortcut
        case "findShortcut": return ShortcutPreferences.findShortcut
        case "toggleSidebarShortcut": return ShortcutPreferences.toggleSidebarShortcut
        case "focusPageTreeShortcut": return ShortcutPreferences.focusPageTreeShortcut
        case "openSettingsShortcut": return ShortcutPreferences.openSettingsShortcut
        case "showShortcutHelpShortcut": return ShortcutPreferences.showShortcutHelpShortcut
        case "focusDocumentEndShortcut": return ShortcutPreferences.focusDocumentEndShortcut
        case "boldShortcut": return ShortcutPreferences.boldShortcut
        case "italicShortcut": return ShortcutPreferences.italicShortcut
        case "underlineShortcut": return ShortcutPreferences.underlineShortcut
        case "linkShortcut": return ShortcutPreferences.linkShortcut
        case "toggleFormatBarShortcut": return ShortcutPreferences.toggleFormatBarShortcut
        default: return ""
        }
    }

    function setSequenceForKey(prefKey, sequence) {
        switch (prefKey) {
        case "newPageShortcut": ShortcutPreferences.newPageShortcut = sequence; break
        case "findShortcut": ShortcutPreferences.findShortcut = sequence; break
        case "toggleSidebarShortcut": ShortcutPreferences.toggleSidebarShortcut = sequence; break
        case "focusPageTreeShortcut": ShortcutPreferences.focusPageTreeShortcut = sequence; break
        case "openSettingsShortcut": ShortcutPreferences.openSettingsShortcut = sequence; break
        case "showShortcutHelpShortcut": ShortcutPreferences.showShortcutHelpShortcut = sequence; break
        case "focusDocumentEndShortcut": ShortcutPreferences.focusDocumentEndShortcut = sequence; break
        case "boldShortcut": ShortcutPreferences.boldShortcut = sequence; break
        case "italicShortcut": ShortcutPreferences.italicShortcut = sequence; break
        case "underlineShortcut": ShortcutPreferences.underlineShortcut = sequence; break
        case "linkShortcut": ShortcutPreferences.linkShortcut = sequence; break
        case "toggleFormatBarShortcut": ShortcutPreferences.toggleFormatBarShortcut = sequence; break
        default: break
        }
    }

    function keyToString(key) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + (key - Qt.Key_F1 + 1)
        switch (key) {
        case Qt.Key_Backslash: return "\\"
        case Qt.Key_Slash: return "/"
        case Qt.Key_Question: return "?"
        case Qt.Key_Plus: return "+"
        case Qt.Key_Minus: return "-"
        case Qt.Key_Period: return "."
        case Qt.Key_Comma: return ","
        case Qt.Key_Semicolon: return ";"
        case Qt.Key_Apostrophe: return "'"
        case Qt.Key_BracketLeft: return "["
        case Qt.Key_BracketRight: return "]"
        case Qt.Key_Equal: return "="
        case Qt.Key_Space: return "Space"
        case Qt.Key_Tab: return "Tab"
        case Qt.Key_Return:
        case Qt.Key_Enter: return "Enter"
        case Qt.Key_Escape: return "Esc"
        case Qt.Key_Home: return "Home"
        case Qt.Key_End: return "End"
        case Qt.Key_PageUp: return "PgUp"
        case Qt.Key_PageDown: return "PgDown"
        case Qt.Key_Left: return "Left"
        case Qt.Key_Right: return "Right"
        case Qt.Key_Up: return "Up"
        case Qt.Key_Down: return "Down"
        default: return ""
        }
    }

    function sequenceFromEvent(event) {
        const parts = []
        const mods = event.modifiers
        if (mods & Qt.ControlModifier) parts.push("Ctrl")
        if (mods & Qt.AltModifier) parts.push("Alt")
        if (mods & Qt.ShiftModifier) parts.push("Shift")
        if (mods & Qt.MetaModifier) parts.push("Meta")

        const keyText = keyToString(event.key)
        if (keyText === "") return ""
        parts.push(keyText)
        return parts.join("+")
    }

    SettingsSection {
        title: "Keyboard Shortcuts"

        Text {
            Layout.fillWidth: true
            text: "Edit app and editor shortcuts. Select a row, press Change, then press the new key sequence."
            color: ThemeManager.textMuted
            font.pixelSize: ThemeManager.fontSizeSmall
            wrapMode: Text.Wrap
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: tableColumn.implicitHeight + ThemeManager.spacingSmall * 2
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusSmall

            Column {
                id: tableColumn
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingSmall
                spacing: ThemeManager.spacingSmall

                Repeater {
                    model: page.shortcutRows

                    delegate: Item {
                        width: parent.width
                        height: rowColumn.implicitHeight

                        Column {
                            id: rowColumn
                            width: parent.width
                            spacing: ThemeManager.spacingSmall

                            Rectangle {
                                width: parent.width
                                color: ThemeManager.background
                                radius: ThemeManager.radiusSmall
                                implicitHeight: rowFlow.implicitHeight + ThemeManager.spacingSmall * 2

                                Flow {
                                    id: rowFlow
                                    x: ThemeManager.spacingSmall
                                    y: ThemeManager.spacingSmall
                                    width: parent.width - ThemeManager.spacingSmall * 2
                                    spacing: ThemeManager.spacingSmall

                                    Text {
                                        width: Math.min(Math.max(190, rowFlow.width * 0.45), rowFlow.width)
                                        text: modelData.label
                                        color: ThemeManager.text
                                        font.pixelSize: ThemeManager.fontSizeNormal
                                        wrapMode: Text.Wrap
                                    }

                                    Rectangle {
                                        width: Math.min(Math.max(140, rowFlow.width * 0.30), rowFlow.width)
                                        height: 32
                                        radius: ThemeManager.radiusSmall
                                        color: ThemeManager.surfaceHover
                                        border.width: 1
                                        border.color: ThemeManager.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: page.sequenceForKey(modelData.key)
                                            color: ThemeManager.text
                                            font.family: ThemeManager.monoFontFamily
                                            font.pixelSize: ThemeManager.fontSizeSmall
                                        }
                                    }

                                    SettingsButton {
                                        id: changeButton
                                        objectName: index === 0 ? "keyboardShortcutFirstChangeButton" : ""
                                        width: 92
                                        text: "Change"
                                        onClicked: {
                                            page.editingShortcutKey = modelData.key
                                            shortcutCaptureDialog.capturedSequence = page.sequenceForKey(modelData.key)
                                            shortcutCaptureDialog.open()
                                        }
                                        Component.onCompleted: {
                                            if (index === 0) firstChangeButton = changeButton
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: index < page.shortcutRows.length - 1
                                width: parent.width
                                height: 1
                                color: ThemeManager.borderLight
                            }
                        }
                    }
                }
            }
        }
    }

    property var firstChangeButton: null

    property var shortcutCaptureDialogInstance: Dialog {
        id: shortcutCaptureDialog
        title: "Set Shortcut"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(420, page.width - ThemeManager.spacingLarge * 2)
        standardButtons: Dialog.NoButton
        focus: visible

        property string capturedSequence: ""

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusMedium
        }

        onOpened: captureScope.forceActiveFocus()

        contentItem: ColumnLayout {
            spacing: ThemeManager.spacingMedium

            Text {
                Layout.fillWidth: true
                text: "Press the keyboard sequence now."
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                wrapMode: Text.Wrap
            }

            FocusScope {
                id: captureScope
                Layout.fillWidth: true
                implicitHeight: 64
                focus: true

                Rectangle {
                    anchors.fill: parent
                    radius: ThemeManager.radiusSmall
                    color: ThemeManager.background
                    border.width: 1
                    border.color: captureScope.activeFocus ? ThemeManager.accent : ThemeManager.border
                }

                Text {
                    anchors.centerIn: parent
                    text: shortcutCaptureDialog.capturedSequence === "" ? "Waiting for keys..." : shortcutCaptureDialog.capturedSequence
                    color: ThemeManager.text
                    font.family: ThemeManager.monoFontFamily
                    font.pixelSize: ThemeManager.fontSizeNormal
                }

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        shortcutCaptureDialog.close()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift
                            || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
                        event.accepted = true
                        return
                    }
                    const sequence = page.sequenceFromEvent(event)
                    if (sequence !== "") {
                        shortcutCaptureDialog.capturedSequence = sequence
                    }
                    event.accepted = true
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                RowLayout {
                    width: parent.width
                    spacing: ThemeManager.spacingSmall

                    SettingsButton {
                        Layout.fillWidth: true
                        text: "Set"
                        enabled: shortcutCaptureDialog.capturedSequence !== ""
                        onClicked: {
                            page.setSequenceForKey(page.editingShortcutKey, shortcutCaptureDialog.capturedSequence)
                            shortcutCaptureDialog.close()
                        }
                    }

                    SettingsButton {
                        Layout.fillWidth: true
                        text: "Cancel"
                        onClicked: shortcutCaptureDialog.close()
                    }
                }
            }
        }
    }
}
