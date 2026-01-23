import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property string content: ""
    property bool isChecked: false
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal checkedToggled()
    signal blockFocused()
    
    readonly property bool showRendered: root.editor && root.editor.renderBlocksWhenNotFocused && !textEdit.activeFocus

    function markdownForRender() {
        // Render just the content; the checkbox UI is already shown separately.
        return root.content || ""
    }

    implicitHeight: Math.max((showRendered ? rendered.implicitHeight : rowLayout.height) + ThemeManager.spacingSmall * 2, 32)
    
    RowLayout {
        id: rowLayout
        
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingSmall
        
        // Checkbox
        Rectangle {
            width: 18
            height: 18
            radius: ThemeManager.radiusSmall
            color: isChecked ? ThemeManager.accent : "transparent"
            border.width: isChecked ? 0 : 2
            border.color: ThemeManager.border
            
            Text {
                anchors.centerIn: parent
                text: "✓"
                color: "white"
                font.pixelSize: 12
                font.bold: true
                visible: isChecked
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.checkedToggled()
            }
        }
        
        TextEdit {
            id: rendered

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            textFormat: Text.RichText
            text: Cmark.toHtml(root.markdownForRender())
            color: isChecked ? ThemeManager.textSecondary : ThemeManager.text
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: false
            visible: root.showRendered

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: function(mouse) {
                    if (!root.editor) return
                    const link = rendered.linkAt(mouse.x, mouse.y)
                    if (link && link.indexOf("zinc://date/") === 0 && "openDateEditor" in root.editor) {
                        root.editor.openDateEditor(root.blockIndex, link.substring("zinc://date/".length))
                        return
                    }
                    if (mouse.modifiers & Qt.ControlModifier) {
                        if (link && link.indexOf("zinc://page/") === 0) {
                            root.editor.navigateToPage(link.substring("zinc://page/".length))
                            return
                        }
                    }
                    textEdit.forceActiveFocus()
                }
            }
        }

        // Text
        TextEdit {
            id: textEdit
            
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            
            text: root.content
            color: isChecked ? ThemeManager.textSecondary : ThemeManager.text
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeNormal
            font.strikeout: isChecked
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            visible: !root.showRendered
            
            // Placeholder
            Text {
                anchors.fill: parent
                text: "To-do"
                color: ThemeManager.textPlaceholder
                font: parent.font
                visible: parent.text.length === 0 && !parent.activeFocus
            }
            
            onTextChanged: {
                if (text !== root.content) {
                    root.contentEdited(text)
                }
            }
            
            onActiveFocusChanged: {
                if (activeFocus) {
                    root.blockFocused()
                }
            }
            
            Keys.onReturnPressed: function(event) {
                event.accepted = true
                root.enterPressed()
            }
            
            Keys.onPressed: function(event) {
                if (root.editor && root.editor.handleEditorKeyEvent && root.editor.handleEditorKeyEvent(event)) {
                    return
                }
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && root.multiBlockSelectionActive && root.editor) {
                    event.accepted = true
                    root.editor.copyCrossBlockSelectionToClipboard()
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
                    if (root.editor.pasteFromClipboard(root.blockIndex)) {
                        event.accepted = true
                    }
                } else if (event.modifiers === 0 && root.editor && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                    const nav = root.editor.adjacentBlockNavigation(root.blockIndex, event.key, cursorPosition, text.length)
                    if (nav && nav.handled) {
                        event.accepted = true
                        root.editor.focusBlockAt(nav.targetIndex, nav.targetPos)
                    }
                } else if (event.key === Qt.Key_Backspace && text.length === 0) {
                    event.accepted = true
                    root.backspaceOnEmpty()
                }
            }
        }
    }

    Timer {
        id: selectionDelayTimer
        interval: (AndroidUtils.isAndroid() && root.editor) ? root.editor.blockSelectDelayMs : 0
        repeat: false
        onTriggered: {
            if (!selectionDrag.active || !root.editor) return
            selectionDrag.selectionArmed = true
            const p = root.mapToItem(root.editor, selectionDrag.centroid.pressPosition.x, selectionDrag.centroid.pressPosition.y)
            root.editor.startCrossBlockSelection(p)
        }
    }

    DragHandler {
        id: selectionDrag
        target: null
        acceptedButtons: Qt.LeftButton
        grabPermissions: (AndroidUtils.isAndroid() && root.editor && root.editor.blockSelectDelayMs > 0)
            ? PointerHandler.ApprovesTakeOverByAnything
            : PointerHandler.CanTakeOverFromAnything

        property bool selectionArmed: false

        onActiveChanged: {
            if (!root.editor) return
            if (active) {
                selectionArmed = !(AndroidUtils.isAndroid() && root.editor.blockSelectDelayMs > 0)
                if (selectionArmed) {
                    const p = root.mapToItem(root.editor, centroid.pressPosition.x, centroid.pressPosition.y)
                    root.editor.startCrossBlockSelection(p)
                } else {
                    selectionDelayTimer.restart()
                }
            } else {
                selectionDelayTimer.stop()
                if (selectionArmed) {
                    root.editor.endCrossBlockSelection()
                }
                selectionArmed = false
            }
        }

        onTranslationChanged: {
            if (!active || !root.editor || !selectionArmed) return
            const p = root.mapToItem(root.editor, centroid.position.x, centroid.position.y)
            root.editor.updateCrossBlockSelection(p)
        }
    }

    property alias textControl: textEdit
}
