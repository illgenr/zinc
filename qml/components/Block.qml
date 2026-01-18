import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc
import "blocks"

Item {
    id: root

    property int blockIndex: 0
    property string blockType: "paragraph"
    property string content: ""
    property int depth: 0
    property bool checked: false
    property bool collapsed: false
    property string language: ""
    property int headingLevel: 1
    property var editor: null
    property var textControl: (blockLoader.item && blockLoader.item.textControl) ? blockLoader.item.textControl : null
    readonly property bool rangeSelected: editor &&
        editor.selectionStartBlockIndex >= 0 &&
        blockIndex >= editor.selectionStartBlockIndex &&
        blockIndex <= editor.selectionEndBlockIndex
    readonly property bool searchHighlighted: editor && editor.searchHighlightBlockIndex === blockIndex

    signal contentEdited(string newContent)
    signal blockEnterPressed()
    signal blockBackspaceOnEmpty()
    signal requestIndent()
    signal requestOutdent()
    signal requestMoveUp()
    signal requestMoveDown()
    signal blockCheckedToggled()
    signal blockCollapseToggled()
    signal blockFocused()
    signal linkClicked(string pageId)

    implicitHeight: blockLoader.height

    Rectangle {
        anchors.fill: parent
        color: root.rangeSelected ? ThemeManager.accentLight : (root.searchHighlighted ? ThemeManager.accentLight : "transparent")
        border.width: root.searchHighlighted ? 1 : 0
        border.color: ThemeManager.accent
        radius: ThemeManager.radiusSmall
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Indent spacing
        Item {
            width: depth * ThemeManager.blockIndent
        }

        // Selection gutter (drag to select a range of blocks)
        Item {
            width: 14
            height: parent.height

            MouseArea {
                id: selectionGutter
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
                preventStealing: true

                onPressed: function(mouse) {
                    if (!root.editor) return
                    root.editor.startBlockRangeSelection(root.blockIndex)
                    const p = selectionGutter.mapToItem(root.editor, mouse.x, mouse.y)
                    root.editor.updateBlockRangeSelectionByEditorY(p.y)
                    mouse.accepted = true
                }

                onPositionChanged: function(mouse) {
                    if (!pressed || !root.editor) return
                    const p = selectionGutter.mapToItem(root.editor, mouse.x, mouse.y)
                    root.editor.updateBlockRangeSelectionByEditorY(p.y)
                    mouse.accepted = true
                }

                onReleased: {
                    if (root.editor) root.editor.endBlockRangeSelection()
                }
            }
        }

        // Drag handle (appears on hover)
        Item {
            width: 24
            height: parent.height

            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: ThemeManager.radiusSmall
                color: dragHandle.containsMouse ? ThemeManager.surfaceHover : "transparent"
                visible: blockHover.containsMouse || dragHandle.containsMouse

                Text {
                    anchors.centerIn: parent
                    text: "⋮⋮"
                    color: ThemeManager.textMuted
                    font.pixelSize: 10
                }

                MouseArea {
                    id: dragHandle
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeAllCursor
                    preventStealing: true

                    onPressed: function(mouse) {
                        if (!root.editor) return
                        root.editor.startReorderBlock(root.blockIndex)
                        var p = dragHandle.mapToItem(root.editor, mouse.x, mouse.y)
                        root.editor.updateReorderBlockByEditorY(p.y)
                    }

                    onPositionChanged: function(mouse) {
                        if (!pressed || !root.editor) return
                        var p = dragHandle.mapToItem(root.editor, mouse.x, mouse.y)
                        root.editor.updateReorderBlockByEditorY(p.y)
                    }

                    onReleased: {
                        if (root.editor) root.editor.endReorderBlock()
                    }
                }
            }
        }

        // Block content
        Loader {
            id: blockLoader

            Layout.fillWidth: true

            sourceComponent: {
                switch (blockType) {
                    case "heading": return headingComponent
                    case "todo": return todoComponent
                    case "image": return imageComponent
                    case "columns": return columnsComponent
                    case "code": return codeComponent
                    case "quote": return quoteComponent
                    case "divider": return dividerComponent
                    case "toggle": return toggleComponent
                    case "link": return linkComponent
                    default: return paragraphComponent
                }
            }
        }
    }

    MouseArea {
        id: blockHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Block type components
    Component {
        id: paragraphComponent
        ParagraphBlock {
            content: root.content
            editor: root.editor
            blockIndex: root.blockIndex
            multiBlockSelectionActive: root.editor ? root.editor.hasCrossBlockSelection : false
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onBackspaceOnEmpty: root.blockBackspaceOnEmpty()
            onIndentRequested: root.requestIndent()
            onOutdentRequested: root.requestOutdent()
            onMoveUpRequested: root.requestMoveUp()
            onMoveDownRequested: root.requestMoveDown()
            onBlockFocused: root.blockFocused()
        }
    }

    Component {
        id: headingComponent
        HeadingBlock {
            level: root.headingLevel
            content: root.content
            editor: root.editor
            blockIndex: root.blockIndex
            multiBlockSelectionActive: root.editor ? root.editor.hasCrossBlockSelection : false
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onBackspaceOnEmpty: root.blockBackspaceOnEmpty()
            onBlockFocused: root.blockFocused()
        }
    }

    Component {
        id: todoComponent
        TodoBlock {
            content: root.content
            isChecked: root.checked
            editor: root.editor
            blockIndex: root.blockIndex
            multiBlockSelectionActive: root.editor ? root.editor.hasCrossBlockSelection : false
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onBackspaceOnEmpty: root.blockBackspaceOnEmpty()
            onCheckedToggled: root.blockCheckedToggled()
            onBlockFocused: root.blockFocused()
        }
    }

    Component {
        id: imageComponent
        ImageBlock {
            content: root.content
            editor: root.editor
            blockIndex: root.blockIndex
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onBackspaceOnEmpty: root.blockBackspaceOnEmpty()
            onBlockFocused: root.blockFocused()
        }
    }

    Component {
        id: columnsComponent
        ColumnsBlock {
            content: root.content
            editor: root.editor
            blockIndex: root.blockIndex
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onBackspaceOnEmpty: root.blockBackspaceOnEmpty()
            onBlockFocused: root.blockFocused()
        }
    }

    Component {
        id: codeComponent
        CodeBlock {
            content: root.content
            codeLanguage: root.language
            editor: root.editor
            blockIndex: root.blockIndex
            multiBlockSelectionActive: root.editor ? root.editor.hasCrossBlockSelection : false
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onBlockFocused: root.blockFocused()
        }
    }

    Component {
        id: quoteComponent
        QuoteBlock {
            content: root.content
            editor: root.editor
            blockIndex: root.blockIndex
            multiBlockSelectionActive: root.editor ? root.editor.hasCrossBlockSelection : false
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onBackspaceOnEmpty: root.blockBackspaceOnEmpty()
            onBlockFocused: root.blockFocused()
        }
    }

    Component {
        id: dividerComponent
        DividerBlock { editor: root.editor }
    }

    Component {
        id: toggleComponent
        ToggleBlock {
            content: root.content
            isCollapsed: root.collapsed
            editor: root.editor
            blockIndex: root.blockIndex
            multiBlockSelectionActive: root.editor ? root.editor.hasCrossBlockSelection : false
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onCollapseToggled: root.blockCollapseToggled()
            onBlockFocused: root.blockFocused()
        }
    }
    
    Component {
        id: linkComponent
        LinkBlock {
            content: root.content
            editor: root.editor
            blockIndex: root.blockIndex
            multiBlockSelectionActive: root.editor ? root.editor.hasCrossBlockSelection : false
            onContentEdited: (newContent) => root.contentEdited(newContent)
            onEnterPressed: root.blockEnterPressed()
            onBackspaceOnEmpty: root.blockBackspaceOnEmpty()
            onBlockFocused: root.blockFocused()
            onLinkClicked: (pageId) => root.linkClicked(pageId)
        }
    }
}
