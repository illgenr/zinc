import QtQuick
import QtQuick.Controls
import zinc

Item {
    id: root
    
    property int level: 1
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
        const hashes = level === 1 ? "#" : level === 2 ? "##" : "###"
        return hashes + " " + (root.content || "")
    }

    implicitHeight: Math.max((showRendered ? rendered.implicitHeight : textEdit.contentHeight) + ThemeManager.spacingSmall * 2, 40)
    
    TextEdit {
        id: rendered

        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall

        textFormat: Text.RichText
        text: Cmark.toHtml(root.markdownForRender())
        color: ThemeManager.text
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
        anchors.margins: ThemeManager.spacingSmall
        
        text: root.content
        color: ThemeManager.text
        font.family: ThemeManager.fontFamily
        font.pixelSize: level === 1 ? ThemeManager.fontSizeH1 : 
                       level === 2 ? ThemeManager.fontSizeH2 : ThemeManager.fontSizeH3
        font.weight: Font.Bold
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        visible: !root.showRendered
        
        // Placeholder
        Text {
            anchors.fill: parent
            text: "Heading " + level
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
