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
            } else if (event.key === Qt.Key_Backspace && text.length === 0) {
                event.accepted = true
                root.backspaceOnEmpty()
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
