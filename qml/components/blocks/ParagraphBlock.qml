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
    signal indentRequested()
    signal outdentRequested()
    signal moveUpRequested()
    signal moveDownRequested()
    signal blockFocused()
    
    readonly property bool showRendered: root.editor && root.editor.renderBlocksWhenNotFocused && !textEdit.activeFocus

    function markdownForRender() {
        return root.content || ""
    }

    implicitHeight: Math.max((showRendered ? rendered.implicitHeight : textEdit.contentHeight) + ThemeManager.spacingSmall * 2, 32)
    
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
                if (mouse.modifiers & Qt.ControlModifier) {
                    const link = rendered.linkAt(mouse.x, mouse.y)
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
        font.pixelSize: ThemeManager.fontSizeNormal
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        visible: !root.showRendered
        
        // Placeholder
        Text {
            anchors.fill: parent
            text: "Type '/' for commands..."
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
                // Shift+Enter: insert newline
                event.accepted = false
            } else {
                event.accepted = true
                root.enterPressed()
            }
        }
        
        Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && root.multiBlockSelectionActive && root.editor) {
                event.accepted = true
                root.editor.copyCrossBlockSelectionToClipboard()
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
                if (root.editor.pasteBlocksFromClipboard(root.blockIndex)) {
                    event.accepted = true
                }
            } else if (event.key === Qt.Key_Backspace && text.length === 0) {
                event.accepted = true
                root.backspaceOnEmpty()
            } else if (event.key === Qt.Key_Tab) {
                event.accepted = true
                if (event.modifiers & Qt.ShiftModifier) {
                    root.outdentRequested()
                } else {
                    root.indentRequested()
                }
            } else if (event.modifiers & Qt.AltModifier) {
                if (event.key === Qt.Key_Up) {
                    event.accepted = true
                    root.moveUpRequested()
                } else if (event.key === Qt.Key_Down) {
                    event.accepted = true
                    root.moveDownRequested()
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

    property alias textControl: textEdit
}
