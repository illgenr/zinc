import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc
import Zinc 1.0
import "ScrollMath.js" as ScrollMath
import "BlockEditorEnterLogic.js" as EnterLogic
import "CursorMotionIndicatorLogic.js" as CursorMotionLogic

FocusScope {
    id: root
    readonly property bool debugSearchUi: Qt.application.arguments.indexOf("--debug-search-ui") !== -1

    // Keep undo/redo centralized (avoid per-TextEdit undo stacks).
    Shortcut { sequences: ["Ctrl+Z", "Meta+Z"]; onActivated: root.performUndo() }
    Shortcut { sequences: ["Ctrl+Shift+Z", "Meta+Shift+Z", "Ctrl+Y", "Meta+Y"]; onActivated: root.performRedo() }

    // Inline formatting shortcuts (hybrid editor).
    Shortcut { sequence: ShortcutPreferences.boldShortcut; onActivated: formatBar.bold() }
    Shortcut { sequence: ShortcutPreferences.italicShortcut; onActivated: formatBar.italic() }
    Shortcut { sequence: ShortcutPreferences.underlineShortcut; onActivated: formatBar.underline() }
    Shortcut { sequence: ShortcutPreferences.linkShortcut; onActivated: formatBar.link() }
    Shortcut { sequence: ShortcutPreferences.toggleFormatBarShortcut; onActivated: formatBar.collapsed = !formatBar.collapsed }

    Shortcut { context: Qt.WidgetWithChildrenShortcut; sequences: ["Ctrl+Home", "Meta+Home"]; onActivated: root.focusDocumentStart() }
    Shortcut { context: Qt.WidgetWithChildrenShortcut; sequences: ["Ctrl+End", "Meta+End"]; onActivated: root.focusDocumentEnd() }

    // Cursor restore for undo/redo (best-effort, grouped typing).
    property bool typingMacroActive: false
    property int typingMacroBlockIndex: -1
    property int typingMacroStartPos: -1
    property int typingMacroEndPos: -1
    property var cursorUndoStack: []
    property var cursorRedoStack: []

    Timer {
        id: typingMacroTimer
        interval: 650
        repeat: false
        onTriggered: root.finalizeTypingMacro()
    }

    Timer {
        id: keyboardSelectionGuardTimer
        interval: 250
        repeat: false
        onTriggered: root.keyboardSelecting = false
    }

    property bool cursorMotionIndicatorActive: false

    Timer {
        id: cursorMotionIndicatorTimer
        interval: 250
        repeat: false
        onTriggered: root.cursorMotionIndicatorActive = false
    }

    function armCursorMotionIndicator() {
        cursorMotionIndicatorActive = true
        cursorMotionIndicatorTimer.restart()
    }
    
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
    signal titleEditingFinished(string pageId, string newTitle)
    signal externalLinkRequested(string url)
    signal navigateToPage(string targetPageId)
    signal showPagePicker(int blockIndex)
    signal createChildPageRequested(string title, int blockIndex)
    signal createChildPageInlineRequested(string title, int blockIndex, int replaceStart, int replaceEnd)

    property bool showRemoteCursor: false
    property string remoteCursorPageId: ""
    property int remoteCursorBlockIndex: -1
    property int remoteCursorPos: -1
    property var remoteCursors: []

    function remoteTitleCursorPos() {
        if (!remoteCursors || remoteCursors.length === 0 || !pageId || pageId === "") return -1
        for (let i = 0; i < remoteCursors.length; i++) {
            const c = remoteCursors[i] || {}
            if ((c.pageId || "") !== pageId) continue
            const block = c.blockIndex === undefined ? -1 : c.blockIndex
            const pos = c.cursorPos === undefined ? -1 : c.cursorPos
            if (block < 0 && pos >= 0) return pos
        }
        return -1
    }
    
    property var availablePages: []  // Set by parent to provide page list for linking
    property bool selectionDragging: false
    property bool blockRangeSelecting: false
    property bool keyboardSelecting: false
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
    property string titleEditingPageId: ""
    property string titleEditingOriginalTitle: ""
    property int pendingSlashBlockIndex: -1
    property int pendingSlashReplaceStart: -1
    property int pendingSlashReplaceEnd: -1
    property bool pendingSlashInline: false
    property var pendingInlineDateInsert: null

    function slashTokenAt(text, cursorPos) {
        const s = text || ""
        const pos = Math.max(0, Math.min(cursorPos === undefined ? s.length : cursorPos, s.length))
        const prefix = s.substring(0, pos)
        const lastSpace = Math.max(prefix.lastIndexOf(" "), prefix.lastIndexOf("\n"), prefix.lastIndexOf("\t"))
        const tokenStart = lastSpace + 1
        if (tokenStart < 0 || tokenStart >= prefix.length) return null
        if (prefix[tokenStart] !== "/") return null
        if (tokenStart > 0) {
            const prev = prefix[tokenStart - 1]
            if (prev !== " " && prev !== "\n" && prev !== "\t") return null
        }
        const filter = prefix.substring(tokenStart + 1)
        return { start: tokenStart, end: pos, filter: filter }
    }

    function replaceBlockContentRange(blockIndex, start, end, replacement, cursorAfter) {
        if (blockIndex < 0 || blockIndex >= blockModel.count) return
        const item = blockRepeater.itemAt(blockIndex)
        const tc = item && item.textControl ? item.textControl : null
        const row = blockModel.get(blockIndex)
        const modelText = row && ("content" in row) ? (row.content || "") : ""
        const current = tc && ("text" in tc) ? (tc.text || "") : modelText
        const a = Math.max(0, Math.min(start, end))
        const b = Math.max(0, Math.max(start, end))
        const next = current.substring(0, a) + (replacement || "") + current.substring(b)

        blockModel.beginUndoMacro("Insert")
        blockModel.setProperty(blockIndex, "content", next)
        blockModel.endUndoMacro()
        scheduleAutosave()

        if (tc && ("text" in tc) && tc.text !== next) tc.text = next
        if (tc) {
            Qt.callLater(() => {
                tc.forceActiveFocus()
                const c = cursorAfter === undefined ? (a + (replacement || "").length) : cursorAfter
                if ("cursorPosition" in tc) tc.cursorPosition = Math.max(0, Math.min(c, (tc.text || "").length))
            })
        }
    }

    function insertPageLinkAt(blockIndex, start, end, pageId, pageTitle) {
        const label = (pageTitle || "Untitled").replace(/]/g, "\\]")
        const href = "zinc://page/" + (pageId || "")
        const md = "[" + label + "](" + href + ")"
        replaceBlockContentRange(blockIndex, start, end, md)
    }

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

        root.finalizeTypingMacro()
        const before = currentFocusSnapshot()
        blockModel.beginUndoMacro("Paste")
        let ended = false
        try {
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
        let lastInsertedIndex = -1
        if (target >= 0 && target < blockModel.count) {
            const current = blockModel.get(target)
            if (current.blockType === "paragraph" && (current.content || "") === "") {
                blockModel.remove(target)
                blockModel.insert(target, blocks[0])
                insertAt = target + 1
                lastInsertedIndex = target
                blocks.shift()
            }
        }

        for (let i = 0; i < blocks.length; i++) {
            blockModel.insert(insertAt + i, blocks[i])
            lastInsertedIndex = insertAt + i
        }
        blockModel.endUndoMacro()
        ended = true
        const undoIndex = blockModel.undoIndex ? blockModel.undoIndex() : -1
        cursorUndoStack.push({
            kind: "Paste",
            undoIndexAfter: undoIndex,
            beforeIndex: before.index,
            beforePos: before.pos,
            afterIndex: lastInsertedIndex,
            afterPos: -1
        })
        cursorRedoStack = []
        scheduleAutosave()
        clearCrossBlockSelection()
        focusTimer.targetIndex = lastInsertedIndex >= 0 ? lastInsertedIndex : Math.max(0, target)
        focusTimer.targetCursorPos = -1
        focusTimer.attemptsRemaining = 10
        focusTimer.start()
        return true
        } finally {
            if (!ended) blockModel.endUndoMacro()
        }
    }

    function pasteImageFromClipboard(atIndex) {
        if (!Clipboard.saveClipboardImage) return false
        const dataUrl = Clipboard.saveClipboardImage()
        if (!dataUrl || dataUrl.length === 0) return false
        if (!DataStore || !DataStore.saveAttachmentFromDataUrl) return false
        const attachmentId = DataStore.saveAttachmentFromDataUrl(dataUrl)
        if (!attachmentId || attachmentId.length === 0) return false
        const imageContent = JSON.stringify({ src: "image://attachments/" + attachmentId, w: 0, h: 0 })

        root.finalizeTypingMacro()
        const before = currentFocusSnapshot()
        blockModel.beginUndoMacro("Paste image")
        let ended = false
        try {
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
        let insertedIndex = -1
        if (target >= 0 && target < blockModel.count) {
            const current = blockModel.get(target)
            if (current.blockType === "paragraph" && (current.content || "") === "") {
                blockModel.remove(target)
                blockModel.insert(target, imageBlock)
                insertAt = target + 1
                insertedIndex = target
            } else {
                blockModel.insert(insertAt, imageBlock)
                insertedIndex = insertAt
            }
        } else {
            blockModel.append(imageBlock)
            insertedIndex = blockModel.count - 1
        }

        blockModel.endUndoMacro()
        ended = true
        const undoIndex = blockModel.undoIndex ? blockModel.undoIndex() : -1
        cursorUndoStack.push({
            kind: "Paste image",
            undoIndexAfter: undoIndex,
            beforeIndex: before.index,
            beforePos: before.pos,
            afterIndex: insertedIndex,
            afterPos: -1
        })
        cursorRedoStack = []
        scheduleAutosave()
        clearCrossBlockSelection()
        focusTimer.targetIndex = insertedIndex >= 0 ? insertedIndex : Math.max(0, target)
        focusTimer.targetCursorPos = -1
        focusTimer.attemptsRemaining = 10
        focusTimer.start()
        return true
        } finally {
            if (!ended) blockModel.endUndoMacro()
        }
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

    function deleteBlockAt(blockIndex, focusAfter) {
        if (blockIndex < 0 || blockIndex >= blockModel.count) return
        const shouldFocus = (focusAfter === undefined) ? true : !!focusAfter
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
        if (shouldFocus) {
            const next = Math.max(0, Math.min(blockIndex - 1, blockModel.count - 1))
            focusTimer.targetIndex = next
            focusTimer.targetCursorPos = -1
            focusTimer.attemptsRemaining = 10
            focusTimer.start()
        }
    }

    function handleEnterPressedAt(blockIndex) {
        if (blockIndex < 0 || blockIndex >= blockModel.count) return

        const item = blockRepeater.itemAt(blockIndex)
        const tc = item && item.textControl ? item.textControl : null
        const cursorPos = (tc && ("cursorPosition" in tc)) ? tc.cursorPosition : -1

        const row = blockModel.get(blockIndex)
        if (!row) return

        const content = row.content || ""
        const rowType = row.blockType || "paragraph"
        const action = EnterLogic.enterAction({
            blockIndex: blockIndex,
            cursorPos: cursorPos,
            blockType: rowType,
            content: content,
        })

        if (!action || !("kind" in action) || action.kind === "noop") return

        if (action.kind === "convertTodoToParagraph") {
            blockModel.setProperty(blockIndex, "blockType", "paragraph")
            return
        }

        if (action.kind !== "insert") return

        const insertIndex = action.insertIndex
        const newBlockType = action.newBlockType || "paragraph"
        const focusCursorPos = ("focusCursorPos" in action) ? action.focusCursorPos : 0
        const newChecked = false
        const newBlock = {
            blockId: generateUuid(),
            blockType: newBlockType,
            content: "",
            depth: row.depth || 0,
            checked: newChecked,
            collapsed: false,
            language: "",
            headingLevel: 0
        }

        // Defer model mutation until after the key event finishes dispatching.
        // Inserting above the currently-focused delegate can otherwise cause
        // teardown/rebind while the TextEdit is still processing Enter.
        const capturedInsertIndex = insertIndex
        const capturedNewBlock = newBlock
        Qt.callLater(() => {
            blockModel.insert(capturedInsertIndex, capturedNewBlock)

            // Focus the new block after a brief delay
            focusTimer.targetIndex = capturedInsertIndex
            focusTimer.targetCursorPos = focusCursorPos
            focusTimer.attemptsRemaining = 10
            focusTimer.start()
        })
    }
    
    function loadPage(id) {
        if (root.debugSearchUi) {
            console.log("SEARCHUI: BlockEditor.loadPage id=", id, "current=", pageId)
        }
        // Save current page first if we have one
        if (pageId && pageId !== "" && pageId !== id) {
            saveBlocks()
        }
        
        pageId = id
        blockModel.clearUndoStack()
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

    function clearPage() {
        pendingRemoteRefresh = false
        dirty = false
        pageId = ""
        blockModel.clearUndoStack()
        blockModel.clear()
    }
    
    function saveBlocks() {
        if (!pageId || pageId === "") return
        
        try {
            const markdown = blockModel.serializeContentToMarkdown()
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
        return blockModel.loadFromMarkdown(markdown || "")
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

    function mergeBlocksFromStorage(options) {
        if (!pageId || pageId === "") return
        try {
            const markdown = DataStore ? DataStore.getPageContentMarkdown(pageId) : ""
            if (!markdown) return
            const preserveFocus = !(options && options.preserveFocus === false)
            const mobileImeVisible = (Qt.platform.os !== "android") || Qt.inputMethod.visible
            const restoreFocus = preserveFocus && currentBlockIndex >= 0 && mobileImeVisible
            const restoreIndex = currentBlockIndex
            let restorePos = -1
            if (restoreFocus) {
                const item = blockRepeater.itemAt(restoreIndex)
                if (item && item.textControl && item.textControl.activeFocus && ("cursorPosition" in item.textControl)) {
                    restorePos = item.textControl.cursorPosition
                } else {
                    // Only refocus when a text control was already focused; otherwise avoid opening the IME.
                    restorePos = -1
                }
            }
            loadFromMarkdown(markdown)
            if (restoreFocus && restorePos >= 0) {
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
            mergeBlocksFromStorage({ preserveFocus: false })
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
    
    BlockModel {
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

    function focusSearchResult(blockId, blockIndex) {
        let idx = blockIndex === undefined ? -1 : blockIndex
        if (idx < 0 && blockId && blockId !== "") {
            for (let i = 0; i < blockModel.count; i++) {
                if (blockModel.get(i).blockId === blockId) {
                    idx = i
                    break
                }
            }
        }
        if (idx < 0) {
            focusContent()
            scheduleEnsureFocusedCursorVisible()
            return
        }
        revealSearchBlockIndex(idx)
        focusBlockAtDeferred(idx, 0)
        scheduleEnsureFocusedCursorVisible()
    }

    function focusDocumentEnd() {
        if (blockRepeater.count <= 0) return
        const idx = blockRepeater.count - 1
        scrollToBlockIndex(idx)
        focusBlockAtDeferred(idx, -1)
        scheduleEnsureFocusedCursorVisible()
    }

    function focusDocumentStart() {
        if (blockRepeater.count <= 0) return
        flickable.contentY = 0
        focusBlockAtDeferred(0, 0)
        scheduleEnsureFocusedCursorVisible()
    }

    function currentFocusSnapshot() {
        const idx = root.currentBlockIndex
        if (idx < 0 || idx >= blockRepeater.count) return { index: -1, pos: -1 }
        const item = blockRepeater.itemAt(idx)
        if (!item || !item.textControl || !("cursorPosition" in item.textControl)) return { index: idx, pos: -1 }
        return { index: idx, pos: item.textControl.cursorPosition }
    }

    function beginTypingMacro(blockIndex, startPos) {
        if (typingMacroActive && typingMacroBlockIndex === blockIndex) return
        finalizeTypingMacro()
        typingMacroActive = true
        typingMacroBlockIndex = blockIndex
        typingMacroStartPos = startPos
        typingMacroEndPos = startPos
        blockModel.beginUndoMacro("Typing")
        typingMacroTimer.restart()
    }

    function recordTypingEdit(blockIndex, oldContent, newContent, cursorPos, selStart, selEnd) {
        const oldLen = (oldContent || "").length
        const newLen = (newContent || "").length

        const a = (selStart === undefined || selStart < 0) ? -1 : selStart
        const b = (selEnd === undefined || selEnd < 0) ? -1 : selEnd
        const hasSelection = (a >= 0 && b >= 0 && a !== b)
        const selectionStart = hasSelection ? Math.min(a, b) : -1

        let startPos = 0
        if (hasSelection) {
            startPos = selectionStart
        } else {
            const delta = Math.max(0, newLen - oldLen)
            startPos = Math.max(0, (cursorPos || 0) - delta)
        }

        beginTypingMacro(blockIndex, startPos)
        typingMacroEndPos = Math.max(0, cursorPos || 0)
        typingMacroTimer.restart()
    }

    function finalizeTypingMacro() {
        if (!typingMacroActive) return
        typingMacroActive = false
        typingMacroTimer.stop()
        blockModel.endUndoMacro()
        const undoIndex = blockModel.undoIndex ? blockModel.undoIndex() : -1
        cursorUndoStack.push({
            kind: "Typing",
            undoIndexAfter: undoIndex,
            beforeIndex: typingMacroBlockIndex,
            beforePos: typingMacroStartPos,
            afterIndex: typingMacroBlockIndex,
            afterPos: typingMacroEndPos
        })
        cursorRedoStack = []
        typingMacroBlockIndex = -1
        typingMacroStartPos = -1
        typingMacroEndPos = -1
    }

    function pageNavigate(direction) {
        const viewH = flickable.height - root.keyboardInset
        const step = Math.max(48, viewH * 0.85)

        // Move in content space first, then place caret near the same viewport Y.
        // This avoids getting "stuck" on repeated PageDown at the same cursor hit.
        const focused = (root.currentBlockIndex >= 0 && root.currentBlockIndex < blockRepeater.count)
            ? blockRepeater.itemAt(root.currentBlockIndex)
            : null
        const tc = focused && focused.textControl ? focused.textControl : null
        const prevContentY = flickable.contentY
        const nextContentY = clampContentY(prevContentY + (direction >= 0 ? step : -step))
        flickable.contentY = nextContentY

        if (!tc || !("cursorRectangle" in tc)) return

        const rect = tc.cursorRectangle
        const p = tc.mapToItem(root, rect.x, rect.y + rect.height * 0.5)
        const anchorY = Math.max(0, Math.min(flickable.height - root.keyboardInset - 1, p.y))
        const hit = blockTextControlAtEditorPoint(Qt.point(p.x, anchorY))
        if (!hit || hit.index < 0) return

        focusBlockAt(hit.index, hit.pos)
        // If scrolling had no effect, still keep cursor visible in-place.
        if (nextContentY === prevContentY) {
            scheduleEnsureFocusedCursorVisible()
            return
        }
        scheduleEnsureFocusedCursorVisible()
    }

    function handleEditorKeyEvent(event) {
        const mod = event.modifiers
        const ctrl = (mod & Qt.ControlModifier) || (mod & Qt.MetaModifier)

        if (CursorMotionLogic.shouldArm(mod, event.key)) {
            root.armCursorMotionIndicator()
        }

        if ((mod & Qt.ShiftModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            event.accepted = true
            keyboardExtendSelection(event.key === Qt.Key_Up ? -1 : 1)
            return true
        }

        if (ctrl && event.key === Qt.Key_Z) {
            event.accepted = true
            if (mod & Qt.ShiftModifier) root.performRedo()
            else root.performUndo()
            return true
        }
        if (ctrl && event.key === Qt.Key_Y) {
            event.accepted = true
            root.performRedo()
            return true
        }
        if (ctrl && event.key === Qt.Key_End) {
            event.accepted = true
            focusDocumentEnd()
            return true
        }
        if (ctrl && event.key === Qt.Key_Home) {
            event.accepted = true
            focusDocumentStart()
            return true
        }
        if (event.key === Qt.Key_PageDown) {
            event.accepted = true
            pageNavigate(1)
            return true
        }
        if (event.key === Qt.Key_PageUp) {
            event.accepted = true
            pageNavigate(-1)
            return true
        }
        return false
    }

    function keyboardExtendSelection(direction) {
        finalizeTypingMacro()

        const count = blockRepeater.count
        if (count <= 0) return

        const caretIndex = selectionFocusBlockIndex >= 0 ? selectionFocusBlockIndex : currentBlockIndex
        if (caretIndex < 0 || caretIndex >= count) return

        const caretItem = blockRepeater.itemAt(caretIndex)
        const tc = caretItem && caretItem.textControl ? caretItem.textControl : null
        if (!tc || !("cursorPosition" in tc) || !("positionToRectangle" in tc) || !("positionAt" in tc)) return

        const caretPos = selectionFocusPos >= 0 ? selectionFocusPos : tc.cursorPosition

        const selectionEmpty = selectionAnchorBlockIndex < 0 || selectionFocusBlockIndex < 0
        if (selectionEmpty) {
            selectionAnchorBlockIndex = caretIndex
            selectionFocusBlockIndex = caretIndex
            selectionAnchorPos = caretPos
            selectionFocusPos = caretPos
        }

        let nextIndex = caretIndex
        let nextPos = caretPos

        if (direction < 0) {
            if (selectionEmpty) {
                nextPos = 0
            } else if (caretIndex > 0) {
                nextIndex = caretIndex - 1
                nextPos = 0
            } else {
                nextPos = 0
            }
        } else {
            const len = (tc.text || "").length
            if (selectionEmpty) {
                nextPos = len
            } else if (caretIndex < (count - 1)) {
                nextIndex = caretIndex + 1
                nextPos = 1e9
            } else {
                nextPos = len
            }
        }

        keyboardSelecting = true
        keyboardSelectionGuardTimer.restart()
        selectionFocusBlockIndex = nextIndex
        selectionFocusPos = nextPos
        applyCrossBlockSelection()
        currentBlockIndex = nextIndex
        focusBlockAtDeferred(nextIndex, nextPos >= 1e9 ? -1 : nextPos)
        scheduleEnsureFocusedCursorVisible()
    }

    function performUndo() {
        finalizeTypingMacro()

        if (focusTimer && focusTimer.running) focusTimer.stop()
        const snap = currentFocusSnapshot()
        const text = blockModel.undoText ? blockModel.undoText() : ""
        const undoIndex = blockModel.undoIndex ? blockModel.undoIndex() : -1

        let cursorOp = null
        if (undoIndex >= 0 && cursorUndoStack.length > 0) {
            for (let i = cursorUndoStack.length - 1; i >= 0; i--) {
                const entry = cursorUndoStack[i]
                if (entry && entry.undoIndexAfter === undoIndex) {
                    cursorOp = entry
                    cursorUndoStack.splice(i, 1)
                    cursorRedoStack.push(entry)
                    break
                }
            }
        }
        if (!cursorOp && text && cursorUndoStack.length > 0 && cursorUndoStack[cursorUndoStack.length - 1].kind === text) {
            cursorOp = cursorUndoStack.pop()
            cursorRedoStack.push(cursorOp)
        }

        blockModel.undo()

        const targetIndex = cursorOp ? cursorOp.beforeIndex : snap.index
        const targetPos = cursorOp ? cursorOp.beforePos : snap.pos
        if (targetIndex >= 0) {
            Qt.callLater(() => root.focusBlockAtDeferred(targetIndex, targetPos))
        }
    }

    function performRedo() {
        finalizeTypingMacro()

        if (focusTimer && focusTimer.running) focusTimer.stop()
        const snap = currentFocusSnapshot()
        const text = blockModel.redoText ? blockModel.redoText() : ""
        const undoIndex = blockModel.undoIndex ? blockModel.undoIndex() : -1
        const redoTarget = undoIndex >= 0 ? undoIndex + 1 : -1

        let cursorOp = null
        if (redoTarget >= 0 && cursorRedoStack.length > 0) {
            for (let i = cursorRedoStack.length - 1; i >= 0; i--) {
                const entry = cursorRedoStack[i]
                if (entry && entry.undoIndexAfter === redoTarget) {
                    cursorOp = entry
                    cursorRedoStack.splice(i, 1)
                    cursorUndoStack.push(entry)
                    break
                }
            }
        }
        if (!cursorOp && text && cursorRedoStack.length > 0 && cursorRedoStack[cursorRedoStack.length - 1].kind === text) {
            cursorOp = cursorRedoStack.pop()
            cursorUndoStack.push(cursorOp)
        }

        blockModel.redo()

        const targetIndex = cursorOp ? cursorOp.afterIndex : snap.index
        const targetPos = cursorOp ? cursorOp.afterPos : snap.pos
        if (targetIndex >= 0) {
            Qt.callLater(() => root.focusBlockAtDeferred(targetIndex, targetPos))
        }
    }

        Item {
            id: formatBarWrap
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            z: 100
            height: formatBarContainer.height + ((AndroidUtils.isAndroid() || Qt.platform.os === "ios") ? Math.round(ThemeManager.spacingSmall / 2) : ThemeManager.spacingSmall)

	        Item {
	            id: formatBarContainer
	            width: (AndroidUtils.isAndroid() || Qt.platform.os === "ios")
	                ? (parent.width - ThemeManager.spacingSmall * 2)
	                : Math.min(ThemeManager.editorMaxWidth, parent.width - ThemeManager.spacingXXLarge * 2)
	            anchors.horizontalCenter: parent.horizontalCenter
	            anchors.top: parent.top
	            anchors.topMargin: (AndroidUtils.isAndroid() || Qt.platform.os === "ios") ? ThemeManager.spacingSmall : ThemeManager.spacingMedium
	            height: formatBar.implicitHeight

            InlineFormatBar {
                id: formatBar
                objectName: "blockEditorInlineFormatBar"
                anchors.left: parent.left
                anchors.right: parent.right

	                getState: function() {
	                    const idx = root.currentBlockIndex
	                    if (idx < 0 || idx >= blockRepeater.count) return null
	                    const item = blockRepeater.itemAt(idx)
	                    const tc = item && item.textControl ? item.textControl : null
	                    const bc = item && item.blockControl ? item.blockControl : null
	                    if (!tc) return null
	                    return {
	                        text: tc.text || "",
	                        selectionStart: ("selectionStart" in tc) ? tc.selectionStart : -1,
	                        selectionEnd: ("selectionEnd" in tc) ? tc.selectionEnd : -1,
	                        cursorPosition: ("cursorPosition" in tc) ? tc.cursorPosition : 0,
	                        runs: (bc && ("inlineRuns" in bc)) ? (bc.inlineRuns || []) : [],
	                        typingAttrs: (bc && ("typingAttrs" in bc)) ? (bc.typingAttrs || ({})) : ({})
	                    }
	                }

	                applyState: function(result) {
	                    const idx = root.currentBlockIndex
	                    if (idx < 0 || idx >= blockModel.count) return
	                    const itemNow = blockRepeater.itemAt(idx)
	                    const bcNow = itemNow && itemNow.blockControl ? itemNow.blockControl : null
	                    const tcNow = itemNow && itemNow.textControl ? itemNow.textControl : null

	                    const beforeText = tcNow ? (tcNow.text || "") : ""
	                    const beforeRuns = (bcNow && ("inlineRuns" in bcNow)) ? (bcNow.inlineRuns || []) : []
	                    const beforeTyping = (bcNow && ("typingAttrs" in bcNow)) ? (bcNow.typingAttrs || ({})) : ({})

	                    const nextText = (result && ("text" in result)) ? (result.text || "") : beforeText
	                    const focusTarget = (result && ("focusTarget" in result)) ? (result.focusTarget || "") : ""
	                    const nextTyping = (result && ("typingAttrs" in result)) ? (result.typingAttrs || ({})) : beforeTyping
	                    let nextRuns = (result && ("runs" in result)) ? (result.runs || []) : null

	                    if (!nextRuns) {
	                        const cursorForReconcile = (result && ("cursorPosition" in result)) ? result.cursorPosition : (tcNow && ("cursorPosition" in tcNow) ? tcNow.cursorPosition : 0)
	                        const reconciled = InlineRichText.reconcileTextChange(beforeText,
	                                                                             nextText,
	                                                                             beforeRuns,
	                                                                             beforeTyping,
	                                                                             cursorForReconcile)
	                        nextRuns = reconciled && ("runs" in reconciled) ? (reconciled.runs || []) : beforeRuns
	                    }

	                    const markup = InlineRichText.serialize(nextText, nextRuns)
	
	                    blockModel.beginUndoMacro("Format")
	                    blockModel.setProperty(idx, "content", markup)
	                    blockModel.endUndoMacro()
	                    root.scheduleAutosave()

	                    if (bcNow && ("inlineRuns" in bcNow)) bcNow.inlineRuns = nextRuns
	                    if (bcNow && ("typingAttrs" in bcNow)) bcNow.typingAttrs = nextTyping
	
	                    Qt.callLater(() => {
	                        const item = blockRepeater.itemAt(idx)
	                        const tc = item && item.textControl ? item.textControl : null
	                        if (!tc) return
	                        if (focusTarget !== "toolbar") {
	                            tc.forceActiveFocus()
	                        }
	
	                        const cursor = (result && ("cursorPosition" in result)) ? result.cursorPosition : -1
	                        if (cursor >= 0 && ("cursorPosition" in tc)) tc.cursorPosition = cursor
	
	                        const a = (result && ("selectionStart" in result)) ? result.selectionStart : -1
	                        const b = (result && ("selectionEnd" in result)) ? result.selectionEnd : -1
	                        if (a >= 0 && b >= 0 && ("select" in tc)) tc.select(a, b)
	                    })
	                }
	            }
        }
    }
    
    Flickable {
        id: flickable
        objectName: "blockEditorFlickable"
        
        anchors.fill: parent
        anchors.topMargin: formatBarWrap.height
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
            TextEdit {
                id: titleInput
                
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(ThemeManager.fontSizeH1 + ThemeManager.spacingSmall, contentHeight)
                Layout.topMargin: ThemeManager.spacingXLarge
                Layout.bottomMargin: ThemeManager.spacingLarge
                Layout.leftMargin: ThemeManager.spacingSmall
                Layout.rightMargin: ThemeManager.spacingSmall
                
                text: pageTitle
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
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

                Rectangle {
                    readonly property int remotePos: root.remoteTitleCursorPos()
                    visible: root.showRemoteCursor && remotePos >= 0 && !titleInput.activeFocus
                    color: ThemeManager.remoteCursor
                    width: 2
                    height: Math.max(20, titleInput.cursorRectangle.height)
                    x: titleInput.positionToRectangle(remotePos).x
                    y: titleInput.positionToRectangle(remotePos).y
                }
                
                onTextChanged: {
                    if (root.debugSyncUi) {
                        console.log("SYNCUI: BlockEditor titleInput textChanged pageId=", root.pageId,
                                    "text=", text,
                                    "pageTitle=", pageTitle,
                                    "willEmit=", (text !== pageTitle))
                    }
                    if (text !== pageTitle) {
                        root.titleEdited(text)
                    }
                    if (activeFocus) {
                        root.cursorMoved(-1, cursorPosition)
                    }
                }

                onCursorPositionChanged: {
                    if (activeFocus) {
                        root.cursorMoved(-1, cursorPosition)
                    }
                }

                onActiveFocusChanged: {
                    if (root.debugSyncUi) {
                        console.log("SYNCUI: BlockEditor titleInput focusChanged pageId=", root.pageId,
                                    "activeFocus=", activeFocus,
                                    "text=", text)
                    }
                    if (activeFocus) {
                        root.titleEditingPageId = root.pageId
                        root.titleEditingOriginalTitle = text
                        root.cursorMoved(-1, cursorPosition)
                        return
                    }
                    root.cursorMoved(-1, -1)
                    const editedId = root.titleEditingPageId
                    const changed = editedId && editedId !== "" && text !== root.titleEditingOriginalTitle
                    root.titleEditingPageId = ""
                    root.titleEditingOriginalTitle = ""
                    if (changed) {
                        root.titleEditingFinished(editedId, text)
                    }
                }

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        event.accepted = true
                        Qt.callLater(() => root.focusContent())
                        return
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
                        const item = blockRepeater.itemAt(index)
                        const tc = item && item.textControl ? item.textControl : null
                        const curPos = (tc && ("cursorPosition" in tc)) ? tc.cursorPosition : 0
                        const selStart = (tc && ("selectionStart" in tc)) ? tc.selectionStart : -1
                        const selEnd = (tc && ("selectionEnd" in tc)) ? tc.selectionEnd : -1
                        root.recordTypingEdit(index, model.content || "", newContent || "", curPos, selStart, selEnd)

                        model.content = newContent
                        currentBlockIndex = index
                        scheduleAutosave()
                        
                        // Slash command: allow invocation mid-block (at a whitespace boundary).
                        const token = root.slashTokenAt(newContent, curPos)
                        const wantsSlash = token !== null && token.end >= token.start + 1
                        if (wantsSlash) {
                            slashMenu.currentBlockIndex = index
                            slashMenu.filterText = token.filter || ""
                            root.pendingSlashBlockIndex = index
                            root.pendingSlashReplaceStart = token.start
                            root.pendingSlashReplaceEnd = token.end
                            const before = (newContent || "").substring(0, token.start)
                            const after = (newContent || "").substring(token.end)
                            root.pendingSlashInline = before.trim().length > 0 || after.trim().length > 0
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
                            if (root.pendingSlashBlockIndex === index) {
                                root.pendingSlashBlockIndex = -1
                                root.pendingSlashReplaceStart = -1
                                root.pendingSlashReplaceEnd = -1
                                root.pendingSlashInline = false
                            }
                            slashMenu.close()
                        }
                        root.scheduleEnsureFocusedCursorVisible()
                    }

                    onLanguageEdited: function(newLanguage) {
                        if (model.language === newLanguage) {
                            return
                        }
                        model.language = newLanguage
                        currentBlockIndex = index
                        scheduleAutosave()
                    }
                    
                    onBlockEnterPressed: {
                        root.handleEnterPressedAt(index)
                    }
                    
                    onBlockBackspaceOnEmpty: {
                        if (index > 0) {
                            // Defer model mutation until after the key event finishes dispatching.
                            // Removing the currently-focused delegate can otherwise cause teardown
                            // while the TextEdit is still processing Backspace.
                            root.focusBlockAt(index - 1, -1)
                            const capturedIndex = index
                            Qt.callLater(() => root.deleteBlockAt(capturedIndex, false))
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
                        root.finalizeTypingMacro()
                        if (!root.keyboardSelecting && !root.selectionDragging && !root.blockRangeSelecting && root.selectionAnchorBlockIndex >= 0) {
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
                            focusTimer.targetCursorPos = -1
                            focusTimer.attemptsRemaining = 10
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
        objectName: "slashMenu"
        
        onCommandSelected: function(command) {
            let idx = slashMenu.currentBlockIndex
            if (idx >= 0 && idx < blockModel.count) {
                const inline = root.pendingSlashInline && root.pendingSlashBlockIndex === idx &&
                               root.pendingSlashReplaceStart >= 0 && root.pendingSlashReplaceEnd >= 0
                const needsImmediateMutation = command.type !== "date" &&
                                              command.type !== "datetime" &&
                                              command.type !== "image"
                const needsBlockMutation = !inline
                if (needsImmediateMutation) {
                    if (needsBlockMutation) blockModel.beginUndoMacro("Slash command")
                }

                if (inline && (command.type === "date" || command.type === "datetime")) {
                    root.pendingInlineDateInsert = {
                        blockIndex: idx,
                        start: root.pendingSlashReplaceStart,
                        end: root.pendingSlashReplaceEnd,
                        includeTime: command.type === "datetime"
                    }
                    datePicker.selectedDate = new Date()
                    datePicker.includeTime = command.type === "datetime"
                    datePicker.open()
                } else if (inline && command.type === "now") {
                    root.replaceBlockContentRange(idx, root.pendingSlashReplaceStart, root.pendingSlashReplaceEnd, formatLocalDateTime(new Date()))
                } else if (command.type === "page") {
                    const query = ""
                    const item = blockRepeater.itemAt(idx)
                    const tc = item && item.textControl ? item.textControl : null
                    inlinePagePicker._blockIndex = idx
                    inlinePagePicker._replaceStart = root.pendingSlashReplaceStart
                    inlinePagePicker._replaceEnd = root.pendingSlashReplaceEnd
                    if (tc && ("cursorRectangle" in tc)) {
                        const rect = tc.cursorRectangle
                        const p = tc.mapToItem(root, rect.x, rect.y + rect.height)
                        inlinePagePicker.openAt(p.x, p.y + ThemeManager.spacingSmall, query)
                    } else {
                        inlinePagePicker.openAt(ThemeManager.spacingLarge, ThemeManager.spacingLarge, query)
                    }
                } else if (!inline && command.type === "date") {
                    pendingDateInsertBlockIndex = idx
                    datePicker.selectedDate = new Date()
                    datePicker.includeTime = false
                    datePicker.open()
                } else if (!inline && command.type === "datetime") {
                    pendingDateInsertBlockIndex = idx
                    datePicker.selectedDate = new Date()
                    datePicker.includeTime = true
                    datePicker.open()
                } else if (!inline && command.type === "now") {
                    blockModel.setProperty(idx, "blockType", "paragraph")
                    blockModel.setProperty(idx, "content", formatLocalDateTime(new Date()))
                    scheduleAutosave()
                    Qt.callLater(() => root.focusBlock(idx))
                } else if (command.type === "image") {
                    if (!inline) startImageUpload(idx)
                } else if (command.type === "columns") {
                    const count = command.count || 2
                    let cols = []
                    for (let i = 0; i < count; i++) cols.push("")
                    if (!inline) {
                        blockModel.setProperty(idx, "blockType", "columns")
                        blockModel.setProperty(idx, "content", JSON.stringify({ cols: cols }))
                    }
                } else {
                    // Transform current block
                    if (!inline) {
                        blockModel.setProperty(idx, "blockType", command.type)
                        blockModel.setProperty(idx, "content", "")
                        if (command.type === "heading") {
                            blockModel.setProperty(idx, "headingLevel", command.level || 1)
                        }
                    }
                }
                if (needsImmediateMutation) {
                    if (needsBlockMutation) blockModel.endUndoMacro()
                }
                if (!inline) scheduleAutosave()
                const shouldRefocus = command.type !== "date" &&
                                      command.type !== "datetime" &&
                                      command.type !== "image" &&
                                      command.type !== "page"
                if (shouldRefocus && !inline) {
                    Qt.callLater(() => root.focusBlock(idx))
                }
            }
        }
    }

    InlinePagePickerPopup {
        id: inlinePagePicker
        parent: root
        z: 20000
        availablePages: root.availablePages || []

        property int _blockIndex: -1
        property int _replaceStart: -1
        property int _replaceEnd: -1

        onPageSelected: function(pageId, pageTitle) {
            if (_blockIndex < 0) return
            root.insertPageLinkAt(_blockIndex, _replaceStart, _replaceEnd, pageId, pageTitle)
            _blockIndex = -1
            _replaceStart = -1
            _replaceEnd = -1
        }

        onCreatePageRequested: function(title) {
            if (_blockIndex < 0) return
            root.createChildPageInlineRequested(title, _blockIndex, _replaceStart, _replaceEnd)
            _blockIndex = -1
            _replaceStart = -1
            _replaceEnd = -1
        }
    }

    DatePickerPopup {
        id: datePicker
        onAccepted: function(date) {
            if (root.pendingInlineDateInsert) {
                const payload = root.pendingInlineDateInsert
                root.pendingInlineDateInsert = null
                root.replaceBlockContentRange(
                    payload.blockIndex,
                    payload.start,
                    payload.end,
                    (payload.includeTime ? formatLocalDateTime(date) : formatLocalDate(date)))
                return
            }

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
            root.setLinkAtIndex(pendingLinkBlockIndex, pageId, pageTitle)
        }
        pendingLinkBlockIndex = -1
    }

    function setLinkAtIndex(blockIndex, pageId, pageTitle) {
        if (blockIndex < 0 || blockIndex >= blockModel.count) return
        blockModel.setProperty(blockIndex, "blockType", "paragraph")
        const label = (pageTitle || "Untitled").replace(/]/g, "\\]")
        const href = "zinc://page/" + (pageId || "")
        blockModel.setProperty(blockIndex, "content", "[" + label + "](" + href + ")")
        scheduleAutosave()
    }
    
    property int currentBlockIndex: -1
    
    // Timer to focus blocks after they're created
    Timer {
        id: focusTimer
        property int targetIndex: -1
        property int targetCursorPos: -1
        property int attemptsRemaining: 0
        interval: 50
        onTriggered: {
            if (targetIndex >= 0 && targetIndex < blockRepeater.count) {
                const item = blockRepeater.itemAt(targetIndex)
                if (item) {
                    root.focusBlockAt(targetIndex, targetCursorPos)
                    attemptsRemaining = 0
                } else if (attemptsRemaining > 0) {
                    attemptsRemaining = attemptsRemaining - 1
                    focusTimer.start()
                }
            } else if (attemptsRemaining > 0) {
                attemptsRemaining = attemptsRemaining - 1
                focusTimer.start()
            }
            targetCursorPos = -1
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

    function blockItemAt(idx) {
        if (idx < 0 || idx >= blockRepeater.count) return null
        return blockRepeater.itemAt(idx)
    }

    function adjacentBlockNavigation(blockIndex, key, cursorPos, textLen) {
        const count = blockModel.count
        const idx = blockIndex
        const pos = cursorPos === undefined ? -1 : cursorPos
        if (idx < 0 || idx >= count) return { handled: false, targetIndex: -1, targetPos: 0 }

        const item = blockRepeater.itemAt(idx)
        const tc = item && item.textControl ? item.textControl : null
        if (!tc || !("positionToRectangle" in tc) || !("mapToItem" in tc)) {
            return { handled: false, targetIndex: -1, targetPos: 0 }
        }

        const rect = tc.positionToRectangle(Math.max(0, pos))
        const center = tc.mapToItem(root, rect.x, rect.y + rect.height * 0.5)
        const editorX = center.x

        const contentH = ("contentHeight" in tc) ? tc.contentHeight : tc.height
        const atTopLine = rect.y <= 0.5
        const atBottomLine = (rect.y + rect.height) >= (contentH - 0.5)

        if (key === Qt.Key_Up && idx > 0 && atTopLine) {
            const targetIndex = idx - 1
            const targetItem = blockRepeater.itemAt(targetIndex)
            const ttc = targetItem && targetItem.textControl ? targetItem.textControl : null
            if (!ttc || !("positionAt" in ttc) || !("mapFromItem" in ttc)) {
                return { handled: true, targetIndex: targetIndex, targetPos: -1 }
            }
            const ty = ("contentHeight" in ttc) ? Math.max(0, ttc.contentHeight - 1) : Math.max(0, ttc.height - 1)
            const local = ttc.mapFromItem(root, editorX, targetItem.mapToItem(root, 0, 0).y + ty)
            const targetPos = ttc.positionAt(local.x, local.y)
            return { handled: true, targetIndex: targetIndex, targetPos: targetPos }
        }
        if (key === Qt.Key_Down && idx < (count - 1) && atBottomLine) {
            const targetIndex = idx + 1
            const targetItem = blockRepeater.itemAt(targetIndex)
            const ttc = targetItem && targetItem.textControl ? targetItem.textControl : null
            if (!ttc || !("positionAt" in ttc) || !("mapFromItem" in ttc)) {
                return { handled: true, targetIndex: targetIndex, targetPos: 0 }
            }
            const firstRect = ttc.positionToRectangle(0)
            const firstCenterY = firstRect.y + firstRect.height * 0.5
            const rootY = ttc.mapToItem(root, 0, firstCenterY).y
            const local = ttc.mapFromItem(root, editorX, rootY)
            const targetPos = ttc.positionAt(local.x, firstCenterY)
            return { handled: true, targetIndex: targetIndex, targetPos: targetPos }
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

    function focusBlockAtDeferred(idx, cursorPos) {
        focusTimer.targetIndex = idx
        focusTimer.targetCursorPos = cursorPos === undefined ? -1 : cursorPos
        focusTimer.attemptsRemaining = 20
        focusTimer.start()
    }

    function focusContent() {
        if (blockModel.count <= 0) return
        focusBlockAtDeferred(0, -1)
    }
}
