import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc
import "ScrollMath.js" as ScrollMath

FocusScope {
    id: root
    
    // UUID generator (Qt.uuidCreate requires Qt 6.4+)
    function generateUuid() {
        function s4() {
            return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        }
        return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4()
    }

    function pad2(n) {
        const s = "" + n
        return s.length === 1 ? "0" + s : s
    }

    function formatLocalDate(d) {
        return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    }

    function formatLocalDateTime(d) {
        return formatLocalDate(d) + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
    }

    function parseLocalDateOrDateTime(s) {
        const raw = (s || "").trim().replace("T", " ")
        const parts = raw.split(" ")
        const datePart = parts[0] || ""
        const m = datePart.match(/^(\\d{4})-(\\d{2})-(\\d{2})$/)
        if (!m) return null
        const y = parseInt(m[1], 10)
        const mo = parseInt(m[2], 10) - 1
        const d = parseInt(m[3], 10)
        let h = 0
        let min = 0
        let hasTime = false
        if (parts.length > 1) {
            const tm = (parts[1] || "").match(/^(\\d{2}):(\\d{2})/)
            if (tm) {
                h = parseInt(tm[1], 10)
                min = parseInt(tm[2], 10)
                hasTime = true
            }
        }
        return { date: new Date(y, mo, d, h, min), hasTime: hasTime }
    }

    function openDateEditor(blockIndex, initialValue) {
        if (blockIndex < 0 || blockIndex >= blockModel.count) return
        const parsed = parseLocalDateOrDateTime(initialValue)
        pendingDateInsertBlockIndex = blockIndex
        datePicker.selectedDate = parsed ? parsed.date : new Date()
        datePicker.includeTime = parsed ? parsed.hasTime : false
        datePicker.open()
    }
    
    property string pageTitle: ""
    property string pageId: ""
    property double lastLocalEditMs: 0
    property bool pendingRemoteRefresh: false
    property bool renderBlocksWhenNotFocused: true
    property int blockSelectDelayMs: AndroidUtils.isAndroid() ? 250 : 0
    property bool realtimeSyncEnabled: false
    property bool dirty: false
    property bool debugSyncUi: false
    property string lastSavedMarkdown: ""
    property double lastSavedAtMs: 0
    
    signal blockFocused(int index)
    signal cursorMoved(int blockIndex, int cursorPos)
    signal contentSaved(string pageId)
    signal titleEdited(string newTitle)
    signal navigateToPage(string targetPageId)
    signal showPagePicker(int blockIndex)
    signal createChildPageRequested(string title, int blockIndex)

    property bool showRemoteCursor: false
    property string remoteCursorPageId: ""
    property int remoteCursorBlockIndex: -1
    property int remoteCursorPos: -1
    
    property var availablePages: []  // Set by parent to provide page list for linking
    property bool selectionDragging: false
    property bool blockRangeSelecting: false
    property int selectionAnchorBlockIndex: -1
    property int selectionFocusBlockIndex: -1
    property int selectionAnchorPos: -1
    property int selectionFocusPos: -1
    property point lastSelectionPoint: Qt.point(0, 0)

    property bool reorderDragging: false
    property int reorderBlockIndex: -1
    property point lastReorderPoint: Qt.point(0, 0)

    property bool debugSelection: Qt.application.arguments.indexOf("--debug-selection") !== -1
    property int pendingDateInsertBlockIndex: -1

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

    function updateCrossBlockSelection(editorPoint, opts) {
        if (!selectionDragging) return
        lastSelectionPoint = editorPoint
        const allowAutoscroll = !(opts && opts.autoscroll === false)
        if (allowAutoscroll) {
            autoscrollForEditorPoint(editorPoint)
        }
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

    function startBlockRangeSelection(startIndex) {
        blockRangeSelecting = true
        selectionAnchorBlockIndex = startIndex
        selectionFocusBlockIndex = startIndex
        selectionAnchorPos = 0
        selectionFocusPos = 0
        applyCrossBlockSelection()
    }

    function extendBlockRangeSelectionToIndex(targetIndex) {
        if (targetIndex < 0 || targetIndex >= blockRepeater.count) return
        const anchor = selectionAnchorBlockIndex >= 0 ? selectionAnchorBlockIndex : targetIndex
        selectionAnchorBlockIndex = anchor
        selectionFocusBlockIndex = targetIndex
        selectionAnchorPos = 0
        selectionFocusPos = 1e9
        applyCrossBlockSelection()
    }

    function updateBlockRangeSelectionByEditorY(editorY, opts) {
        if (!blockRangeSelecting) return
        lastSelectionPoint = Qt.point(0, editorY)
        const idx = blockIndexAtEditorY(editorY)
        if (idx < 0) return
        selectionFocusBlockIndex = idx
        selectionAnchorPos = 0
        selectionFocusPos = 1e9
        applyCrossBlockSelection()
        const allowAutoscroll = !(opts && opts.autoscroll === false)
        if (allowAutoscroll) {
            autoscrollForEditorPoint(Qt.point(0, editorY))
        }
    }

    function endBlockRangeSelection() {
        blockRangeSelecting = false
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

    function pasteFromClipboard(atIndex) {
        if (pasteBlocksFromClipboard(atIndex)) {
            return true
        }
        if (Clipboard.hasImage && Clipboard.hasImage()) {
            return pasteImageFromClipboard(atIndex)
        }
        return false
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

    function pasteImageFromClipboard(atIndex) {
        if (!Clipboard.saveClipboardImage) return false
        const dataUrl = Clipboard.saveClipboardImage()
        if (!dataUrl || dataUrl.length === 0) return false
        if (!DataStore || !DataStore.saveAttachmentFromDataUrl) return false
        const attachmentId = DataStore.saveAttachmentFromDataUrl(dataUrl)
        if (!attachmentId || attachmentId.length === 0) return false
        const imageContent = JSON.stringify({ src: "image://attachments/" + attachmentId, w: 0, h: 0 })

        const imageBlock = {
            blockId: generateUuid(),
            blockType: "image",
            content: imageContent,
            depth: 0,
            checked: false,
            collapsed: false,
            language: "",
            headingLevel: 0
        }

        const target = (atIndex >= 0 && atIndex < blockModel.count) ? atIndex : currentBlockIndex
        let insertAt = Math.max(0, target + 1)
        if (target >= 0 && target < blockModel.count) {
            const current = blockModel.get(target)
            if (current.blockType === "paragraph" && (current.content || "") === "") {
                blockModel.remove(target)
                blockModel.insert(target, imageBlock)
                insertAt = target + 1
            } else {
                blockModel.insert(insertAt, imageBlock)
            }
        } else {
            blockModel.append(imageBlock)
        }

        scheduleAutosave()
        clearCrossBlockSelection()
        focusTimer.targetIndex = Math.max(0, target)
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

    property int pendingImageUploadBlockIndex: -1

    function startImageUpload(atIndex) {
        pendingImageUploadBlockIndex = atIndex
        openImageFileDialog()
    }

    function deleteBlockAt(blockIndex) {
        if (blockIndex < 0 || blockIndex >= blockModel.count) return
        blockModel.remove(blockIndex)
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
        scheduleAutosave()
        const next = Math.max(0, Math.min(blockIndex - 1, blockModel.count - 1))
        focusTimer.targetIndex = next
        focusTimer.start()
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
            lastSavedMarkdown = markdown
            lastSavedAtMs = Date.now()
            if (DataStore) {
                DataStore.savePageContentMarkdown(pageId, markdown)
                if (debugSyncUi) {
                    console.log("SYNCUI: BlockEditor contentSaved pageId=", pageId, "ts=", Date.now())
                }
                root.contentSaved(pageId)
            }
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
        interval: root.realtimeSyncEnabled ? 150 : 1000
        onTriggered: root.flushIfDirty()
    }

    // Ensure we still flush periodically even during continuous typing (debounce-only can starve).
    Timer {
        id: maxFlushTimer
        interval: root.realtimeSyncEnabled ? 250 : 2000
        repeat: true
        running: root.dirty
        onTriggered: root.flushIfDirty()
    }

    function flushIfDirty() {
        if (!dirty) return
        if (debugSyncUi) {
            console.log("SYNCUI: BlockEditor flushIfDirty pageId=", pageId, "realtime=", realtimeSyncEnabled, "ts=", Date.now())
        }
        saveBlocks()
        dirty = false
    }
    
    function scheduleAutosave() {
        lastLocalEditMs = Date.now()
        dirty = true
        if (debugSyncUi) {
            console.log("SYNCUI: BlockEditor scheduleAutosave pageId=", pageId, "realtime=", realtimeSyncEnabled, "ts=", lastLocalEditMs)
        }
        saveTimer.restart()
    }

    function mergeBlocksFromStorage() {
        if (!pageId || pageId === "") return
        try {
            const markdown = DataStore ? DataStore.getPageContentMarkdown(pageId) : ""
            if (!markdown) return
            const restoreFocus = activeFocus && currentBlockIndex >= 0
            const restoreIndex = currentBlockIndex
            let restorePos = -1
            if (restoreFocus) {
                const item = blockRepeater.itemAt(restoreIndex)
                if (item && item.textControl && ("cursorPosition" in item.textControl)) {
                    restorePos = item.textControl.cursorPosition
                }
            }
            loadFromMarkdown(markdown)
            if (restoreFocus) {
                const idx = Math.max(0, Math.min(restoreIndex, blockModel.count - 1))
                const pos = restorePos
                Qt.callLater(() => root.focusBlockAt(idx, pos))
            }
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

            const now = Date.now()
            const echoWindowMs = root.realtimeSyncEnabled ? 800 : 2000
            if (lastSavedAtMs > 0 && (now - lastSavedAtMs) < echoWindowMs && DataStore) {
                const currentMarkdown = DataStore.getPageContentMarkdown(pageId) || ""
                if (currentMarkdown === lastSavedMarkdown) {
                    if (debugSyncUi) {
                        console.log("SYNCUI: BlockEditor ignore local echo pageId=", pageId,
                                    "realtime=", realtimeSyncEnabled,
                                    "dtSinceSave=", (now - lastSavedAtMs))
                    }
                    return
                }
            }

            const graceMs = root.realtimeSyncEnabled ? 350 : 1500
            const recentlyEdited = (now - lastLocalEditMs) < graceMs
            const shouldDeferForFocus = !root.realtimeSyncEnabled && activeFocus
            const shouldDefer = dirty || recentlyEdited || shouldDeferForFocus

            if (shouldDefer) {
                pendingRemoteRefresh = true
                if (debugSyncUi) {
                    console.log("SYNCUI: BlockEditor defer remote refresh pageId=", pageId,
                                "realtime=", realtimeSyncEnabled,
                                "dirty=", dirty,
                                "activeFocus=", activeFocus,
                                "recentlyEdited=", recentlyEdited,
                                "dt=", (now - lastLocalEditMs))
                }
                return
            }

            if (debugSyncUi) {
                console.log("SYNCUI: BlockEditor apply remote refresh pageId=", pageId,
                            "realtime=", realtimeSyncEnabled,
                            "activeFocus=", activeFocus,
                            "dt=", (now - lastLocalEditMs))
            }

            mergeBlocksFromStorage()
        }
    }
    
    function scrollToBlock(blockId) {
        if (!blockId || blockId === "") return
        for (let i = 0; i < blockModel.count; i++) {
            if (blockModel.get(i).blockId === blockId) {
                revealSearchBlockIndex(i)
                break
            }
        }
    }
    
    ListModel {
        id: blockModel
        objectName: "blockModel"
    }

    property alias blocksModel: blockModel

    property int searchHighlightBlockIndex: -1

    Timer {
        id: searchHighlightClearTimer
        interval: 1500
        onTriggered: root.searchHighlightBlockIndex = -1
    }

    property real keyboardTopYOverride: NaN

    function windowHeight() {
        if (root.Window && root.Window.height > 0) return root.Window.height
        if (root.parent && root.parent.height > 0) return root.parent.height
        return root.height
    }

    function keyboardHeightInWindow() {
        const winH = windowHeight()
        if (!isNaN(root.keyboardTopYOverride)) {
            return Math.max(0, Math.min(winH, winH - root.keyboardTopYOverride))
        }
        const kb = Qt.inputMethod.keyboardRectangle
        const kbUsable = kb && kb.height > 0 && (Qt.inputMethod.visible || AndroidUtils.isAndroid() || Qt.platform.os === "ios")
        if (!kbUsable) return 0
        return Math.max(0, Math.min(winH, kb.height))
    }

    function keyboardTopYInWindow() {
        const winH = windowHeight()
        return winH - keyboardHeightInWindow()
    }

    readonly property real keyboardInset: keyboardHeightInWindow()

    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() { root.scheduleEnsureFocusedCursorVisible() }
        function onKeyboardRectangleChanged() { root.scheduleEnsureFocusedCursorVisible() }
    }

    Timer {
        id: cursorRevealTimer
        interval: 0
        repeat: false
        onTriggered: root.ensureFocusedCursorVisible()
    }

    function scheduleEnsureFocusedCursorVisible() {
        cursorRevealTimer.restart()
    }

    function clampContentY(y) {
        return Math.max(0, Math.min(y, flickable.contentHeight - flickable.height))
    }

    function ensureFocusedCursorVisible() {
        if (root.selectionDragging || root.blockRangeSelecting || root.reorderDragging) return
        if (flickable.dragging || flickable.flicking) return
        if (root.currentBlockIndex < 0 || root.currentBlockIndex >= blockRepeater.count) return

        const block = blockRepeater.itemAt(root.currentBlockIndex)
        if (!block || !block.textControl || !("cursorRectangle" in block.textControl)) return

        const textControl = block.textControl
        const cursor = textControl.cursorRectangle
        const cursorHalfH = cursor.height * 0.5

        function clamp(v, lo, hi) { return Math.max(lo, Math.min(v, hi)) }

        // Mobile: do math in global coordinates because Android's window-panning can make
        // window/scene-relative math lie about what is actually visible on-screen.
        if (AndroidUtils.isAndroid() || Qt.platform.os === "ios") {
            if (!("mapToGlobal" in textControl) || !("mapToGlobal" in flickable)) return

            const cursorGlobal = textControl.mapToGlobal(cursor.x, cursor.y)
            const cursorTopGlobal = cursorGlobal.y
            const cursorBottomGlobal = cursorGlobal.y + cursor.height

            const viewportTopGlobal = flickable.mapToGlobal(0, 0).y
            const viewportBottomGlobal = viewportTopGlobal + flickable.height

            const kb = Qt.inputMethod.keyboardRectangle
            const kbActive = kb && kb.height > 0 && (Qt.inputMethod.visible || AndroidUtils.isAndroid() || Qt.platform.os === "ios")
            const kbTopGlobal = kbActive ? (kb.y > 0 ? kb.y : (Screen.height - kb.height)) : viewportBottomGlobal
            const visibleBottomGlobal = Math.min(viewportBottomGlobal, kbTopGlobal)
            const visibleHeightGlobal = Math.max(0, visibleBottomGlobal - viewportTopGlobal)
            if (visibleHeightGlobal <= 0) return

            const margin = ThemeManager.spacingMedium
            const visibleTopWithMargin = viewportTopGlobal + margin
            const visibleBottomWithMargin = visibleBottomGlobal - margin
            const cursorFullyVisible = cursorTopGlobal >= visibleTopWithMargin && cursorBottomGlobal <= visibleBottomWithMargin
            if (cursorFullyVisible) return

            const minCenter = margin + cursorHalfH
            const maxCenter = Math.max(minCenter, visibleHeightGlobal - margin - cursorHalfH)
            const desiredCenterInViewport = clamp(visibleHeightGlobal * 0.4, minCenter, maxCenter)
            const desiredCenterGlobal = viewportTopGlobal + desiredCenterInViewport
            const cursorCenterGlobal = (cursorTopGlobal + cursorBottomGlobal) * 0.5

            // Positive delta => cursor is too low => scroll down (increase contentY).
            let dy = cursorCenterGlobal - desiredCenterGlobal

            // Ensure it ends up fully visible even when the center target is constrained.
            const projectedTop = cursorTopGlobal - dy
            const projectedBottom = cursorBottomGlobal - dy
            if (projectedBottom > visibleBottomWithMargin) {
                dy += projectedBottom - visibleBottomWithMargin
            } else if (projectedTop < visibleTopWithMargin) {
                dy -= visibleTopWithMargin - projectedTop
            }

            flickable.contentY = clampContentY(flickable.contentY + dy)
            return
        }

        const flickableTopInWindow = flickable.mapToItem(null, 0, 0).y
        const flickableBottomInWindow = flickableTopInWindow + flickable.height
        const margin = ThemeManager.spacingMedium
        const visibleTopInWindow = Math.max(0, flickableTopInWindow)
        const visibleBottomInWindow = Math.min(flickableBottomInWindow, root.keyboardTopYInWindow())
        const visibleViewportHeight = Math.max(0, visibleBottomInWindow - visibleTopInWindow)
        if (visibleViewportHeight <= 0) return

        const cutTop = Math.max(0, visibleTopInWindow - flickableTopInWindow)
        const visibleTopYInContent = flickable.contentY + cutTop
        const visibleBottomYInContent = visibleTopYInContent + visibleViewportHeight

        const cursorTopLeftInContent = textControl.mapToItem(flickable.contentItem, cursor.x, cursor.y)
        const regionTop = cursorTopLeftInContent.y
        const regionBottom = cursorTopLeftInContent.y + cursor.height

        const visibleTopWithMargin = visibleTopYInContent + margin
        const visibleBottomWithMargin = visibleBottomYInContent - margin
        const cursorFullyVisible = regionTop >= visibleTopWithMargin && regionBottom <= visibleBottomWithMargin
        if (cursorFullyVisible) return

        const minCenter = margin + cursorHalfH
        const maxCenter = Math.max(minCenter, visibleViewportHeight - margin - cursorHalfH)
        const desiredCenter = Math.max(minCenter, Math.min(maxCenter, visibleViewportHeight * 0.4))

        let desiredVisibleTopY = ScrollMath.contentYToPlaceRegionCenter(regionTop, regionBottom, desiredCenter)
        desiredVisibleTopY = ScrollMath.contentYToRevealRegion(desiredVisibleTopY,
                                                              regionTop,
                                                              regionBottom,
                                                              visibleViewportHeight,
                                                              margin,
                                                              margin)
        flickable.contentY = clampContentY(desiredVisibleTopY - cutTop)
    }

    function scrollToBlockIndex(idx) {
        if (idx < 0 || idx >= blockRepeater.count) return
        const item = blockRepeater.itemAt(idx)
        if (!item) return
        const y = item.mapToItem(flickable.contentItem, 0, 0).y
        const desired = y - (flickable.height - item.height) * 0.5
        flickable.contentY = clampContentY(desired)
    }

    function revealSearchBlockIndex(idx) {
        if (idx < 0) return
        scrollToBlockIndex(idx)
        root.searchHighlightBlockIndex = idx
        searchHighlightClearTimer.restart()
    }
    
    Flickable {
        id: flickable
        objectName: "blockEditorFlickable"
        
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.height + 200
        clip: true
        interactive: !(root.selectionDragging || root.reorderDragging)
        
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        WheelHandler {
            enabled: root.selectionDragging || root.blockRangeSelecting || root.reorderDragging
            target: null
            acceptedDevices: PointerDevice.Mouse

            function wheelPixels(wheel) {
                if (!wheel) return 0
                if (wheel.pixelDelta && wheel.pixelDelta.y !== 0) return wheel.pixelDelta.y
                if (wheel.angleDelta && wheel.angleDelta.y !== 0) return (wheel.angleDelta.y / 120) * 80
                return 0
            }

            onWheel: function(wheel) {
                const dy = wheelPixels(wheel)
                if (dy === 0) return
                flickable.contentY = clampContentY(flickable.contentY - dy)
                wheel.accepted = true

                if (root.selectionDragging) {
                    root.updateCrossBlockSelection(root.lastSelectionPoint, { autoscroll: false })
                } else if (root.blockRangeSelecting) {
                    root.updateBlockRangeSelectionByEditorY(root.lastSelectionPoint.y, { autoscroll: false })
                } else if (root.reorderDragging) {
                    root.updateReorderBlockByEditorY(root.lastReorderPoint.y)
                }
            }
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
            objectName: "blockDelegate_" + index
                    
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
                            const blockItem = blockRepeater.itemAt(index)
                            if (blockItem) {
                                const p = blockItem.mapToItem(null, ThemeManager.spacingLarge, blockItem.height)
                                slashMenu.desiredX = p.x
                                slashMenu.desiredY = p.y
                            } else {
                                const p = root.mapToItem(null, contentColumn.x + ThemeManager.spacingLarge, contentColumn.y)
                                slashMenu.desiredX = p.x
                                slashMenu.desiredY = p.y
                            }
                            slashMenu.open()
                        } else {
                            slashMenu.close()
                        }
                        root.scheduleEnsureFocusedCursorVisible()
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
                            root.deleteBlockAt(index)
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
                        if (!root.selectionDragging && !root.blockRangeSelecting && root.selectionAnchorBlockIndex >= 0) {
                            root.clearCrossBlockSelection()
                        }
                        currentBlockIndex = index
                        root.blockFocused(index)
                        root.scheduleEnsureFocusedCursorVisible()
                    }

                    onCursorMoved: function(pos) {
                        root.cursorMoved(index, pos)
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

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.keyboardInset > 0 ? (root.keyboardInset + ThemeManager.spacingXLarge) : 0
            }
        }
    }

    Shortcut {
        enabled: root.hasCrossBlockSelection
        sequences: [StandardKey.Copy]
        context: Qt.ApplicationShortcut
        onActivated: root.copyCrossBlockSelectionToClipboard()
    }

    Timer {
        id: autoscrollTimer
        interval: 16
        repeat: true
        running: root.selectionDragging || root.blockRangeSelecting || root.reorderDragging
        onTriggered: {
            if (root.selectionDragging) {
                root.updateCrossBlockSelection(root.lastSelectionPoint)
            } else if (root.blockRangeSelecting) {
                root.updateBlockRangeSelectionByEditorY(root.lastSelectionPoint.y)
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
                if (command.type === "date") {
                    pendingDateInsertBlockIndex = idx
                    datePicker.selectedDate = new Date()
                    datePicker.includeTime = false
                    datePicker.open()
                } else if (command.type === "datetime") {
                    pendingDateInsertBlockIndex = idx
                    datePicker.selectedDate = new Date()
                    datePicker.includeTime = true
                    datePicker.open()
                } else if (command.type === "now") {
                    blockModel.setProperty(idx, "blockType", "paragraph")
                    blockModel.setProperty(idx, "content", formatLocalDateTime(new Date()))
                    scheduleAutosave()
                    Qt.callLater(() => root.focusBlock(idx))
                } else if (command.type === "link") {
                    // Show page picker for link blocks
                    blockModel.setProperty(idx, "blockType", "link")
                    blockModel.setProperty(idx, "content", "")
                    pendingLinkBlockIndex = idx
                    root.showPagePicker(idx)
                } else if (command.type === "image") {
                    startImageUpload(idx)
                } else if (command.type === "columns") {
                    const count = command.count || 2
                    let cols = []
                    for (let i = 0; i < count; i++) cols.push("")
                    blockModel.setProperty(idx, "blockType", "columns")
                    blockModel.setProperty(idx, "content", JSON.stringify({ cols: cols }))
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

    DatePickerPopup {
        id: datePicker
        onAccepted: function(date) {
            const idx = pendingDateInsertBlockIndex
            pendingDateInsertBlockIndex = -1
            if (idx < 0 || idx >= blockModel.count) return
            blockModel.setProperty(idx, "blockType", "paragraph")
            blockModel.setProperty(idx, "content", datePicker.includeTime ? formatLocalDateTime(date) : formatLocalDate(date))
            scheduleAutosave()
            Qt.callLater(() => root.focusBlock(idx))
        }
        onCanceled: pendingDateInsertBlockIndex = -1
    }

    function openImageFileDialog() {
        if (!imageFileDialog) {
            imageFileDialog = Qt.createQmlObject(
                "import QtQuick\\n" +
                "import QtQuick.Dialogs\\n" +
                "FileDialog {\\n" +
                "  title: \\\"Select an image\\\"\\n" +
                "  nameFilters: [\\\"Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp)\\\", \\\"All files (*)\\\"]\\n" +
                "}",
                root,
                "imageFileDialog")

            imageFileDialog.accepted.connect(function() {
                const dataUrl = Clipboard.importImageFile(imageFileDialog.selectedFile)
                if (!dataUrl || dataUrl.length === 0) {
                    console.log("BlockEditor: Failed to import image:", imageFileDialog.selectedFile)
                    pendingImageUploadBlockIndex = -1
                    return
                }
                const attachmentId = DataStore.saveAttachmentFromDataUrl(dataUrl)
                if (!attachmentId || attachmentId.length === 0) {
                    console.log("BlockEditor: Failed to store image attachment:", imageFileDialog.selectedFile)
                    pendingImageUploadBlockIndex = -1
                    return
                }

                const idx = pendingImageUploadBlockIndex
                pendingImageUploadBlockIndex = -1
                if (idx < 0 || idx >= blockModel.count) return

                blockModel.setProperty(idx, "blockType", "image")
                blockModel.setProperty(idx, "content", JSON.stringify({ src: "image://attachments/" + attachmentId, w: 0, h: 0 }))
                scheduleAutosave()
            })

            imageFileDialog.rejected.connect(function() {
                pendingImageUploadBlockIndex = -1
            })
        }

        imageFileDialog.open()
    }

    property var imageFileDialog: null
    
    property int pendingLinkBlockIndex: -1
    
    // Called when user selects a page from page picker
    function setLinkTarget(pageId, pageTitle) {
        if (pendingLinkBlockIndex >= 0 && pendingLinkBlockIndex < blockModel.count) {
            blockModel.setProperty(pendingLinkBlockIndex, "content", pageId + "|" + pageTitle)
            scheduleAutosave()
        }
        pendingLinkBlockIndex = -1
    }

    function setLinkAtIndex(blockIndex, pageId, pageTitle) {
        if (blockIndex < 0 || blockIndex >= blockModel.count) return
        blockModel.setProperty(blockIndex, "blockType", "link")
        blockModel.setProperty(blockIndex, "content", pageId + "|" + pageTitle)
        scheduleAutosave()
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
                root.focusBlock(targetIndex)
            }
        }
    }
    
    // Focus a specific block by index
    function focusBlockAt(idx, cursorPos) {
        if (idx < 0 || idx >= blockRepeater.count) return
        const item = blockRepeater.itemAt(idx)
        if (!item) return
        const target = item.textControl ? item.textControl : item
        target.forceActiveFocus()
        if ("cursorPosition" in target) {
            const text = target.text || ""
            const pos = (cursorPos === undefined || cursorPos < 0) ? text.length : Math.min(cursorPos, text.length)
            target.cursorPosition = pos
        }
    }

    function adjacentBlockNavigation(blockIndex, key, cursorPos, textLen) {
        const count = blockModel.count
        const pos = cursorPos === undefined ? -1 : cursorPos
        const len = textLen === undefined ? 0 : textLen
        if (key === Qt.Key_Up && blockIndex > 0) {
            return { handled: true, targetIndex: blockIndex - 1, targetPos: -1 }
        }
        if (key === Qt.Key_Down && blockIndex < (count - 1)) {
            return { handled: true, targetIndex: blockIndex + 1, targetPos: 0 }
        }
        return { handled: false, targetIndex: -1, targetPos: 0 }
    }

    function focusBlockAtStart(idx) {
        focusBlockAt(idx, 0)
    }

    function focusBlockAtEnd(idx) {
        focusBlockAt(idx, -1)
    }

    function focusBlock(idx) {
        focusBlockAtEnd(idx)
    }

    function focusContent() {
        if (blockModel.count <= 0) return
        focusTimer.targetIndex = 0
        focusTimer.start()
    }
}
