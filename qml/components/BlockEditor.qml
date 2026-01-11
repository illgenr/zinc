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
    property double lastLocalEditMs: 0
    property bool pendingRemoteRefresh: false
    
    signal blockFocused(int index)
    signal titleEdited(string newTitle)
    signal navigateToPage(string targetPageId)
    signal showPagePicker(int blockIndex)
    
    property var availablePages: []  // Set by parent to provide page list for linking
    
    function loadPage(id) {
        // Save current page first if we have one
        if (pageId && pageId !== "" && pageId !== id) {
            saveBlocks()
        }
        
        pageId = id
        blockModel.clear()
        
        // Try to load blocks from storage
        if (!loadBlocksFromStorage(id)) {
            // Add initial empty paragraph if nothing saved
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
    
    function saveBlocks() {
        if (!pageId || pageId === "") return
        
        try {
            let blocks = []
            for (let i = 0; i < blockModel.count; i++) {
                let b = blockModel.get(i)
                blocks.push({
                    blockId: b.blockId,
                    blockType: b.blockType,
                    content: b.content,
                    depth: b.depth,
                    checked: b.checked,
                    collapsed: b.collapsed,
                    language: b.language,
                    headingLevel: b.headingLevel
                })
            }
            
            if (DataStore) DataStore.saveBlocksForPage(pageId, blocks)
        } catch (e) {
            console.log("Error saving blocks:", e)
        }
    }
    
    function loadBlocksFromStorage(id) {
        try {
            let blocks = DataStore ? DataStore.getBlocksForPage(id) : []
            if (blocks && blocks.length > 0) {
                for (let b of blocks) {
                    blockModel.append({
                        blockId: b.blockId || generateUuid(),
                        blockType: b.blockType || "paragraph",
                        content: b.content || "",
                        depth: b.depth || 0,
                        checked: b.checked || false,
                        collapsed: b.collapsed || false,
                        language: b.language || "",
                        headingLevel: b.headingLevel || 0
                    })
                }
                return true
            }
        } catch (e) {
            console.log("Error loading blocks:", e)
        }
        return false
    }
    
    // Auto-save timer
    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: saveBlocks()
    }
    
    function scheduleAutosave() {
        lastLocalEditMs = Date.now()
        saveTimer.restart()
    }

    function mergeBlocksFromStorage() {
        if (!pageId || pageId === "") return

        let stored = DataStore ? DataStore.getBlocksForPage(pageId) : []
        if (!stored) stored = []

        let byId = {}
        for (let i = 0; i < stored.length; i++) {
            let b = stored[i]
            if (b && b.blockId) {
                byId[b.blockId] = b
            }
        }

        // Update existing blocks in place
        for (let i = 0; i < blockModel.count; i++) {
            let local = blockModel.get(i)
            let remote = byId[local.blockId]
            if (!remote) continue

            if (remote.blockType !== undefined && remote.blockType !== local.blockType) {
                blockModel.setProperty(i, "blockType", remote.blockType)
            }
            if (remote.content !== undefined && remote.content !== local.content) {
                blockModel.setProperty(i, "content", remote.content)
            }
            if (remote.depth !== undefined && remote.depth !== local.depth) {
                blockModel.setProperty(i, "depth", remote.depth)
            }
            if (remote.checked !== undefined && remote.checked !== local.checked) {
                blockModel.setProperty(i, "checked", remote.checked)
            }
            if (remote.collapsed !== undefined && remote.collapsed !== local.collapsed) {
                blockModel.setProperty(i, "collapsed", remote.collapsed)
            }
            if (remote.language !== undefined && remote.language !== local.language) {
                blockModel.setProperty(i, "language", remote.language)
            }
            if (remote.headingLevel !== undefined && remote.headingLevel !== local.headingLevel) {
                blockModel.setProperty(i, "headingLevel", remote.headingLevel)
            }
        }

        // Append blocks we don't have yet
        for (let i = 0; i < stored.length; i++) {
            let remote = stored[i]
            if (!remote || !remote.blockId) continue

            let found = false
            for (let j = 0; j < blockModel.count; j++) {
                if (blockModel.get(j).blockId === remote.blockId) {
                    found = true
                    break
                }
            }
            if (found) continue

            blockModel.append({
                blockId: remote.blockId,
                blockType: remote.blockType || "paragraph",
                content: remote.content || "",
                depth: remote.depth || 0,
                checked: remote.checked || false,
                collapsed: remote.collapsed || false,
                language: remote.language || "",
                headingLevel: remote.headingLevel || 0
            })
        }
    }

    onActiveFocusChanged: {
        if (!activeFocus && pendingRemoteRefresh) {
            pendingRemoteRefresh = false
            mergeBlocksFromStorage()
        }
    }

    Connections {
        target: DataStore

        function onBlocksChanged(changedPageId) {
            if (!changedPageId || changedPageId === "") return
            if (changedPageId !== pageId) return

            // Don't disrupt active local edits; apply when focus is lost.
            if (activeFocus || (Date.now() - lastLocalEditMs) < 1500) {
                pendingRemoteRefresh = true
                return
            }
            mergeBlocksFromStorage()
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
                
                onTextChanged: {
                    if (text !== pageTitle) {
                        root.titleEdited(text)
                    }
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
                        scheduleAutosave()
                        
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
                        // For list types (todo), create another of the same type
                        // unless the current block is empty (then convert to paragraph)
                        let newBlockType = "paragraph"
                        let newChecked = false
                        
                        if (model.blockType === "todo") {
                            if (model.content.length === 0) {
                                // Empty todo - convert current to paragraph and don't add new
                                blockModel.setProperty(index, "blockType", "paragraph")
                                return
                            }
                            newBlockType = "todo"
                        }
                        
                        let newBlock = {
                            blockId: generateUuid(),
                            blockType: newBlockType,
                            content: "",
                            depth: model.depth,
                            checked: newChecked,
                            collapsed: false,
                            language: "",
                            headingLevel: 0
                        }
                        blockModel.insert(index + 1, newBlock)
                        
                        // Focus the new block after a brief delay
                        focusTimer.targetIndex = index + 1
                        focusTimer.start()
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
                    
                    onLinkClicked: function(linkedPageId) {
                        root.navigateToPage(linkedPageId)
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
                        cursorShape: Qt.PointingHandCursor
                        
                        onClicked: {
                            let newIdx = blockModel.count
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
                            // Focus the new block
                            focusTimer.targetIndex = newIdx
                            focusTimer.start()
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
            let idx = slashMenu.currentBlockIndex
            if (idx >= 0 && idx < blockModel.count) {
                if (command.type === "link") {
                    // Show page picker for link blocks
                    blockModel.setProperty(idx, "blockType", "link")
                    blockModel.setProperty(idx, "content", "")
                    pendingLinkBlockIndex = idx
                    root.showPagePicker(idx)
                } else {
                    // Transform current block
                    blockModel.setProperty(idx, "blockType", command.type)
                    blockModel.setProperty(idx, "content", "")
                    if (command.type === "heading") {
                        blockModel.setProperty(idx, "headingLevel", command.level || 1)
                    }
                }
                scheduleAutosave()
            }
        }
    }
    
    property int pendingLinkBlockIndex: -1
    
    // Called when user selects a page from page picker
    function setLinkTarget(pageId, pageTitle) {
        if (pendingLinkBlockIndex >= 0 && pendingLinkBlockIndex < blockModel.count) {
            blockModel.setProperty(pendingLinkBlockIndex, "content", pageId + "|" + pageTitle)
            scheduleAutosave()
        }
        pendingLinkBlockIndex = -1
    }
    
    property int currentBlockIndex: -1
    
    // Timer to focus blocks after they're created
    Timer {
        id: focusTimer
        property int targetIndex: -1
        interval: 50
        onTriggered: {
            if (targetIndex >= 0 && targetIndex < blockRepeater.count) {
                let item = blockRepeater.itemAt(targetIndex)
                if (item) {
                    item.forceActiveFocus()
                }
            }
        }
    }
    
    // Focus a specific block by index
    function focusBlock(idx) {
        if (idx >= 0 && idx < blockRepeater.count) {
            let item = blockRepeater.itemAt(idx)
            if (item) {
                item.forceActiveFocus()
            }
        }
    }
}
