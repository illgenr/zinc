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
    property bool selectionDragging: false
    property int selectionAnchorBlockIndex: -1
    property int selectionFocusBlockIndex: -1
    property int selectionAnchorPos: -1
    property int selectionFocusPos: -1
    property point lastSelectionPoint: Qt.point(0, 0)

    property bool reorderDragging: false
    property int reorderBlockIndex: -1
    property point lastReorderPoint: Qt.point(0, 0)

    property bool debugSelection: Qt.application.arguments.indexOf("--debug-selection") !== -1

    readonly property bool hasCrossBlockSelection: selectionAnchorBlockIndex >= 0 &&
                                                  selectionFocusBlockIndex >= 0 &&
                                                  selectionAnchorBlockIndex !== selectionFocusBlockIndex
    readonly property int selectionStartBlockIndex: selectionAnchorBlockIndex >= 0 && selectionFocusBlockIndex >= 0
        ? Math.min(selectionAnchorBlockIndex, selectionFocusBlockIndex) : -1
    readonly property int selectionEndBlockIndex: selectionAnchorBlockIndex >= 0 && selectionFocusBlockIndex >= 0
        ? Math.max(selectionAnchorBlockIndex, selectionFocusBlockIndex) : -1

    function blockIndexAtEditorY(editorY) {
        if (blockRepeater.count <= 0) {
            return -1
        }
        for (let i = 0; i < blockRepeater.count; i++) {
            const item = blockRepeater.itemAt(i)
            if (!item) continue
            const top = item.mapToItem(root, 0, 0).y
            const bottom = top + item.height
            if (editorY >= top && editorY <= bottom) {
                return i
            }
        }

        const first = blockRepeater.itemAt(0)
        const last = blockRepeater.itemAt(blockRepeater.count - 1)
        if (first && editorY < first.mapToItem(root, 0, 0).y) return 0
        if (last && editorY > (last.mapToItem(root, 0, 0).y + last.height)) return blockRepeater.count - 1
        return selectionFocusBlockIndex
    }

    function clearCrossBlockSelection() {
        selectionAnchorBlockIndex = -1
        selectionFocusBlockIndex = -1
        selectionAnchorPos = -1
        selectionFocusPos = -1
        for (let i = 0; i < blockRepeater.count; i++) {
            const item = blockRepeater.itemAt(i)
            if (!item || !item.textControl) continue
            item.textControl.select(0, 0)
        }
    }

    function autoscrollForEditorPoint(editorPoint) {
        const margin = 24
        const speed = 18
        const y = editorPoint.y
        const top = flickable.contentY
        const bottom = flickable.contentY + flickable.height
        if (flickable.contentHeight <= flickable.height) return
        if (y < top + margin) {
            flickable.contentY = Math.max(0, flickable.contentY - speed)
        } else if (y > bottom - margin) {
            flickable.contentY = Math.min(flickable.contentHeight - flickable.height, flickable.contentY + speed)
        }
    }

    function blockTextControlAtEditorPoint(editorPoint) {
        const idx = blockIndexAtEditorY(editorPoint.y)
        if (idx < 0) return { index: -1, pos: -1 }
        const item = blockRepeater.itemAt(idx)
        if (!item || !item.textControl) return { index: idx, pos: 0 }
        const local = item.textControl.mapFromItem(root, editorPoint.x, editorPoint.y)
        const pos = item.textControl.positionAt(local.x, local.y)
        return { index: idx, pos: pos }
    }

    function applyCrossBlockSelection() {
        if (selectionAnchorBlockIndex < 0 || selectionFocusBlockIndex < 0) return
        const startBlock = selectionAnchorBlockIndex
        const endBlock = selectionFocusBlockIndex
        const forward = endBlock >= startBlock

        const firstBlock = forward ? startBlock : endBlock
        const lastBlock = forward ? endBlock : startBlock
        const firstPos = forward ? selectionAnchorPos : selectionFocusPos
        const lastPos = forward ? selectionFocusPos : selectionAnchorPos

        for (let i = 0; i < blockRepeater.count; i++) {
            const item = blockRepeater.itemAt(i)
            if (!item || !item.textControl) continue
            const textLen = (item.textControl.text || "").length
            if (i < firstBlock || i > lastBlock) {
                item.textControl.select(0, 0)
                continue
            }
            if (i === firstBlock && i === lastBlock) {
                const a = Math.max(0, Math.min(firstPos, lastPos))
                const b = Math.max(0, Math.max(firstPos, lastPos))
                item.textControl.select(a, b)
                continue
            }
            if (i === firstBlock) {
                const a = Math.max(0, firstPos)
                item.textControl.select(a, textLen)
            } else if (i === lastBlock) {
                const b = Math.max(0, lastPos)
                item.textControl.select(0, b)
            } else {
                item.textControl.select(0, textLen)
            }
        }
    }

    function startCrossBlockSelection(editorPoint) {
        selectionDragging = true
        lastSelectionPoint = editorPoint
        const hit = blockTextControlAtEditorPoint(editorPoint)
        selectionAnchorBlockIndex = hit.index
        selectionFocusBlockIndex = hit.index
        selectionAnchorPos = hit.pos
        selectionFocusPos = hit.pos
        if (debugSelection) console.log("BlockEditor: selection start", hit.index, hit.pos)
        applyCrossBlockSelection()
    }

    function updateCrossBlockSelection(editorPoint) {
        if (!selectionDragging) return
        lastSelectionPoint = editorPoint
        autoscrollForEditorPoint(editorPoint)
        const hit = blockTextControlAtEditorPoint(editorPoint)
        if (hit.index < 0) return
        selectionFocusBlockIndex = hit.index
        selectionFocusPos = hit.pos
        if (debugSelection) console.log("BlockEditor: selection update", hit.index, hit.pos)
        applyCrossBlockSelection()
    }

    function endCrossBlockSelection() {
        selectionDragging = false
        if (debugSelection) console.log("BlockEditor: selection end")
    }

    function selectedBlocksForMarkdown() {
        if (selectionAnchorBlockIndex < 0 || selectionFocusBlockIndex < 0) return []

        const firstBlock = selectionStartBlockIndex
        const lastBlock = selectionEndBlockIndex

        let blocks = []
        for (let i = firstBlock; i <= lastBlock; i++) {
            const model = blockModel.get(i)
            const item = blockRepeater.itemAt(i)
            let text = model.content || ""
            if (item && item.textControl) {
                const a = Math.min(item.textControl.selectionStart, item.textControl.selectionEnd)
                const b = Math.max(item.textControl.selectionStart, item.textControl.selectionEnd)
                if (a !== b) {
                    text = text.substring(a, b)
                }
            }
            blocks.push({
                blockType: model.blockType,
                content: text,
                depth: model.depth,
                checked: model.checked,
                collapsed: model.collapsed,
                language: model.language,
                headingLevel: model.headingLevel
            })
        }
        return blocks
    }

    function copyCrossBlockSelectionToClipboard() {
        if (selectionAnchorBlockIndex < 0 || selectionFocusBlockIndex < 0) return
        Clipboard.setText(MarkdownBlocks.serialize(selectedBlocksForMarkdown()))
    }

    function pasteBlocksFromClipboard(atIndex) {
        const markdown = Clipboard.text()
        if (!MarkdownBlocks.isZincBlocksPayload(markdown)) {
            return false
        }
        const parsed = MarkdownBlocks.parse(markdown)
        if (!parsed || parsed.length === 0) {
            return false
        }

        const blocks = []
        for (let i = 0; i < parsed.length; i++) {
            const b = parsed[i]
            blocks.push({
                blockId: generateUuid(),
                blockType: b.blockType || "paragraph",
                content: b.content || "",
                depth: b.depth || 0,
                checked: b.checked || false,
                collapsed: b.collapsed || false,
                language: b.language || "",
                headingLevel: b.headingLevel || 0
            })
        }

        const target = (atIndex >= 0 && atIndex < blockModel.count) ? atIndex : currentBlockIndex
        let insertAt = Math.max(0, target + 1)
        if (target >= 0 && target < blockModel.count) {
            const current = blockModel.get(target)
            if (current.blockType === "paragraph" && (current.content || "") === "") {
                blockModel.remove(target)
                blockModel.insert(target, blocks[0])
                insertAt = target + 1
                blocks.shift()
            }
        }

        for (let i = 0; i < blocks.length; i++) {
            blockModel.insert(insertAt + i, blocks[i])
        }
        scheduleAutosave()
        clearCrossBlockSelection()
        focusTimer.targetIndex = target >= 0 ? target : 0
        focusTimer.start()
        return true
    }

    function startReorderBlock(index) {
        reorderDragging = true
        reorderBlockIndex = index
        if (debugSelection) console.log("BlockEditor: reorder start", index)
    }

    function updateReorderBlockByEditorY(editorY) {
        if (!reorderDragging) return
        lastReorderPoint = Qt.point(0, editorY)
        autoscrollForEditorPoint(Qt.point(0, editorY))
        const to = blockIndexAtEditorY(editorY)
        if (to < 0 || to === reorderBlockIndex) return
        blockModel.move(reorderBlockIndex, to, 1)
        reorderBlockIndex = to
        scheduleAutosave()
    }

    function endReorderBlock() {
        reorderDragging = false
        reorderBlockIndex = -1
        if (debugSelection) console.log("BlockEditor: reorder end")
    }
    
    function loadPage(id) {
        // Save current page first if we have one
        if (pageId && pageId !== "" && pageId !== id) {
            saveBlocks()
        }
        
        pageId = id
        blockModel.clear()
        
        // Try to load markdown from storage
        if (!loadMarkdownFromStorage(id)) {
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
    
    function blocksForMarkdown() {
        let blocks = []
        for (let i = 0; i < blockModel.count; i++) {
            let b = blockModel.get(i)
            blocks.push({
                blockType: b.blockType,
                content: b.content,
                depth: b.depth,
                checked: b.checked,
                collapsed: b.collapsed,
                language: b.language,
                headingLevel: b.headingLevel
            })
        }
        return blocks
    }

    function saveBlocks() {
        if (!pageId || pageId === "") return
        
        try {
            const markdown = MarkdownBlocks.serializeContent(blocksForMarkdown())
            if (DataStore) DataStore.savePageContentMarkdown(pageId, markdown)
        } catch (e) {
            console.log("Error saving blocks:", e)
        }
    }
    
    function loadFromMarkdown(markdown) {
        blockModel.clear()
        const parsed = MarkdownBlocks.parse(markdown || "")
        if (!parsed || parsed.length === 0) {
            return false
        }
        for (let i = 0; i < parsed.length; i++) {
            const b = parsed[i]
            blockModel.append({
                blockId: generateUuid(),
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

    function loadMarkdownFromStorage(id) {
        try {
            const markdown = DataStore ? DataStore.getPageContentMarkdown(id) : ""
            if (markdown && markdown !== "") {
                return loadFromMarkdown(markdown)
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
        try {
            const markdown = DataStore ? DataStore.getPageContentMarkdown(pageId) : ""
            if (!markdown) return
            loadFromMarkdown(markdown)
        } catch (e) {
            console.log("Error merging markdown:", e)
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

        function onPageContentChanged(changedPageId) {
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
        interactive: !(root.selectionDragging || root.reorderDragging)
        
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
            editor: root
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

    Shortcut {
        enabled: root.hasCrossBlockSelection
        sequence: StandardKey.Copy
        context: Qt.ApplicationShortcut
        onActivated: root.copyCrossBlockSelectionToClipboard()
    }

    Timer {
        id: autoscrollTimer
        interval: 16
        repeat: true
        running: root.selectionDragging || root.reorderDragging
        onTriggered: {
            if (root.selectionDragging) {
                root.updateCrossBlockSelection(root.lastSelectionPoint)
            } else if (root.reorderDragging) {
                root.updateReorderBlockByEditorY(root.lastReorderPoint.y)
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
