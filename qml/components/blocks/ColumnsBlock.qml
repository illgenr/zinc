import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property string content: ""
    property var editor: null
    property int blockIndex: -1

    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()

    property bool updatingFromModel: false
    property var colTexts: []

    function normalizeCols(cols) {
        if (!cols || cols.length < 1) return ["", ""]
        return cols.map(v => (v === null || v === undefined) ? "" : String(v))
    }

    function loadFromContent() {
        updatingFromModel = true
        try {
            const obj = JSON.parse(root.content || "")
            colTexts = normalizeCols(obj && obj.cols ? obj.cols : null)
        } catch (e) {
            colTexts = ["", ""]
        }
        updatingFromModel = false
    }

    function emitContent() {
        if (updatingFromModel) return
        const json = JSON.stringify({ cols: colTexts })
        if (json !== root.content) {
            root.contentEdited(json)
        }
    }

    Component.onCompleted: loadFromContent()
    onContentChanged: loadFromContent()

    implicitHeight: Math.max(columnsRow.implicitHeight + ThemeManager.spacingSmall * 2, 80)

    Rectangle {
        anchors.fill: parent
        radius: ThemeManager.radiusSmall
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
    }

    RowLayout {
        id: columnsRow
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingMedium

        Repeater {
            model: root.colTexts.length

            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: ThemeManager.radiusSmall
                color: ThemeManager.background
                border.width: 1
                border.color: ThemeManager.border

                TextEdit {
                    id: colEdit
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: ThemeManager.text
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeNormal
                    text: root.colTexts[index] || ""

                    onTextChanged: {
                        if (root.updatingFromModel) return
                        root.colTexts[index] = text
                        root.emitContent()
                    }

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.blockFocused()
                        }
                    }

                    Keys.onReturnPressed: function(event) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false
                        } else {
                            event.accepted = true
                            root.enterPressed()
                        }
                    }

                    Keys.onPressed: function(event) {
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
                            if (root.editor.pasteFromClipboard(root.blockIndex)) {
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Backspace && text.length === 0 && root.colTexts.length === 1) {
                            event.accepted = true
                            root.backspaceOnEmpty()
                        }
                    }
                }
            }
        }
    }

    DragHandler {
        target: null
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        onActiveChanged: {
            if (!root.editor) return
            if (active) {
                const p = root.mapToItem(root.editor, centroid.pressPosition.x, centroid.pressPosition.y)
                root.editor.startCrossBlockSelection(p)
            } else {
                root.editor.endCrossBlockSelection()
            }
        }

        onTranslationChanged: {
            if (!active || !root.editor) return
            const p = root.mapToItem(root.editor, centroid.position.x, centroid.position.y)
            root.editor.updateCrossBlockSelection(p)
        }
    }

    // We expose a dummy control so cross-block selection logic can safely iterate.
    TextEdit {
        id: keyCatcher
        visible: false
        text: ""
    }

    property alias textControl: keyCatcher
}

