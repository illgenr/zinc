import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    // UUID generator (Qt.uuidCreate requires Qt 6.4+)
    function generateUuid() {
        function s4() {
            return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        }
        return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4()
    }
    
    property string pageTitle: ""
    property string pageId: ""
    
    signal blockFocused(int index)
    
    function loadPage(id) {
        pageId = id
        blockModel.clear()
        // Add initial empty paragraph if page is empty
        if (blockModel.count === 0) {
            blockModel.append({
                blockId: generateUuid(),
                blockType: "paragraph",
                content: "",
                depth: 0,
                checked: false,
                collapsed: false,
                language: "",
                headingLevel: 0
            })
        }
    }
    
    function scrollToBlock(blockId) {
        for (let i = 0; i < blockModel.count; i++) {
            if (blockModel.get(i).blockId === blockId) {
                blockList.positionViewAtIndex(i, ListView.Center)
                break
            }
        }
    }
    
    ListModel {
        id: blockModel
    }
    
    Flickable {
        id: flickable
        
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.height + 200
        clip: true
        
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        
        ColumnLayout {
            id: contentColumn
            
            width: Math.min(ThemeManager.editorMaxWidth, parent.width - ThemeManager.spacingXXLarge * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0
            
            // Page title
            TextInput {
                id: titleInput
                
                Layout.fillWidth: true
                Layout.topMargin: ThemeManager.spacingXLarge
                Layout.bottomMargin: ThemeManager.spacingLarge
                
                text: pageTitle
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeH1
                font.weight: Font.Bold
                selectByMouse: true
                
                Text {
                    anchors.fill: parent
                    text: "Untitled"
                    color: ThemeManager.textPlaceholder
                    font: parent.font
                    visible: parent.text.length === 0 && !parent.activeFocus
                }
            }
            
            // Blocks
            Repeater {
                id: blockRepeater
                model: blockModel
                
                delegate: Block {
                    Layout.fillWidth: true
                    
                    blockIndex: index
                    blockType: model.blockType
                    content: model.content
                    depth: model.depth
                    checked: model.checked
                    collapsed: model.collapsed
                    language: model.language
                    headingLevel: model.headingLevel
                    
                    onContentEdited: function(newContent) {
                        model.content = newContent
                        currentBlockIndex = index
                        
                        // Check for slash command
                        if (newContent === "/" || (newContent.startsWith("/") && !newContent.includes(" "))) {
                            slashMenu.currentBlockIndex = index
                            slashMenu.filterText = newContent.substring(1)
                            slashMenu.x = Qt.binding(() => contentColumn.x + ThemeManager.spacingLarge)
                            slashMenu.y = Qt.binding(() => contentColumn.y + titleInput.height + index * 40 + 40)
                            slashMenu.open()
                        } else {
                            slashMenu.close()
                        }
                    }
                    
                    onBlockEnterPressed: {
                        // Insert new block after this one
                        let newBlock = {
                            blockId: generateUuid(),
                            blockType: "paragraph",
                            content: "",
                            depth: model.depth,
                            checked: false,
                            collapsed: false,
                            language: "",
                            headingLevel: 0
                        }
                        blockModel.insert(index + 1, newBlock)
                        // Focus will be handled by the new block
                    }
                    
                    onBlockBackspaceOnEmpty: {
                        if (index > 0) {
                            blockModel.remove(index)
                        }
                    }
                    
                    onRequestIndent: {
                        if (model.depth < 5) {
                            model.depth = model.depth + 1
                        }
                    }
                    
                    onRequestOutdent: {
                        if (model.depth > 0) {
                            model.depth = model.depth - 1
                        }
                    }
                    
                    onRequestMoveUp: {
                        if (index > 0) {
                            blockModel.move(index, index - 1, 1)
                        }
                    }
                    
                    onRequestMoveDown: {
                        if (index < blockModel.count - 1) {
                            blockModel.move(index, index + 1, 1)
                        }
                    }
                    
                    onBlockCheckedToggled: {
                        model.checked = !model.checked
                    }
                    
                    onBlockCollapseToggled: {
                        model.collapsed = !model.collapsed
                    }
                    
                    onBlockFocused: {
                        currentBlockIndex = index
                        root.blockFocused(index)
                    }
                }
            }
            
            // Add block button (appears at end)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Layout.topMargin: ThemeManager.spacingMedium
                
                Rectangle {
                    anchors.fill: parent
                    color: addBlockMouse.containsMouse ? ThemeManager.surfaceHover : "transparent"
                    radius: ThemeManager.radiusSmall
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: ThemeManager.spacingMedium
                        
                        Text {
                            text: "+"
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeLarge
                        }
                        
                        Text {
                            text: "Add a block"
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeNormal
                            visible: addBlockMouse.containsMouse
                        }
                    }
                    
                    MouseArea {
                        id: addBlockMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        
                        onClicked: {
                            blockModel.append({
                                blockId: generateUuid(),
                                blockType: "paragraph",
                                content: "",
                                depth: 0,
                                checked: false,
                                collapsed: false,
                                language: "",
                                headingLevel: 0
                            })
                        }
                    }
                }
            }
        }
    }
    
    // Slash command menu
    SlashMenu {
        id: slashMenu
        
        onCommandSelected: function(command) {
            // Transform current block
            let idx = slashMenu.currentBlockIndex
            if (idx >= 0 && idx < blockModel.count) {
                blockModel.setProperty(idx, "blockType", command.type)
                blockModel.setProperty(idx, "content", "")
                if (command.type === "heading") {
                    blockModel.setProperty(idx, "headingLevel", command.level || 1)
                }
            }
        }
    }
    
    property int currentBlockIndex: -1
}
