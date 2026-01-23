import QtQuick
import QtQuick.Controls
import zinc

Item {
    id: root
    
    property string content: ""
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()
    
    readonly property bool showRendered: root.editor && root.editor.renderBlocksWhenNotFocused && !textEdit.activeFocus

    function markdownForRender() {
        const raw = root.content || ""
        if (raw === "") return ""
        return raw.split("\n").map(line => "> " + line).join("\n")
    }

    implicitHeight: Math.max((showRendered ? rendered.implicitHeight : textEdit.contentHeight) + ThemeManager.spacingSmall * 2, 32)
    
    // Left border
    Rectangle {
        width: 3
        height: parent.height
        color: ThemeManager.textMuted
        radius: 1.5
    }

    TextEdit {
        id: rendered

        anchors.fill: parent
        anchors.leftMargin: ThemeManager.spacingMedium
        anchors.rightMargin: ThemeManager.spacingSmall
        anchors.topMargin: ThemeManager.spacingSmall
        anchors.bottomMargin: ThemeManager.spacingSmall

        textFormat: Text.RichText
        text: Cmark.toHtml(root.markdownForRender())
        color: ThemeManager.textSecondary
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
    
    TextEdit {
        id: textEdit
        
        anchors.fill: parent
        anchors.leftMargin: ThemeManager.spacingMedium
        anchors.rightMargin: ThemeManager.spacingSmall
        anchors.topMargin: ThemeManager.spacingSmall
        anchors.bottomMargin: ThemeManager.spacingSmall
        
        text: root.content
        color: ThemeManager.textSecondary
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeNormal
        font.italic: true
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        visible: !root.showRendered
        
        // Placeholder
        Text {
            anchors.fill: parent
            text: "Quote"
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
            if (event.modifiers & Qt.ShiftModifier) {
                event.accepted = false
            } else {
                event.accepted = true
                root.enterPressed()
            }
        }
        
        Keys.onPressed: function(event) {
            const ctrl = (event.modifiers & Qt.ControlModifier) || (event.modifiers & Qt.MetaModifier)
            if (ctrl && root.editor && root.editor.blocksModel) {
                if (event.key === Qt.Key_Z) {
                    event.accepted = true
                    if (event.modifiers & Qt.ShiftModifier) {
                        root.editor.blocksModel.redo()
                    } else {
                        root.editor.blocksModel.undo()
                    }
                    return
                } else if (event.key === Qt.Key_Y) {
                    event.accepted = true
                    root.editor.blocksModel.redo()
                    return
                }
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
