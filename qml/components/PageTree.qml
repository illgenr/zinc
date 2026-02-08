import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    readonly property bool databaseActive: DataStore && DataStore.schemaVersion >= 0
    enabled: databaseActive
    
    property bool collapsed: false
    property bool showNewPageButton: true
    property bool showNewNotebookButton: true
    property bool showSortButton: true
    property bool showExpandArrowsAlways: false
    property bool actionsAlwaysVisible: false
    property bool activateOnSingleTap: true
    property int actionButtonSize: 20
    property string selectedPageId: ""
    property string sortMode: "alphabetical" // "alphabetical" | "updatedAt" | "createdAt"
    property bool enableContextMenu: true
    property bool typeaheadCaseSensitive: GeneralPreferences.pageTreeTypeaheadCaseSensitive
    property int typeaheadTimeoutMs: 700
    
    signal pageSelected(string pageId, string title)
    signal pagesChanged()
    signal pageActivatedByKeyboard(string pageId, string title)
    signal newNotebookRequested()

    property bool _dragActive: false
    property real _dragY: 0
    property bool _componentReady: false
    readonly property bool _isMobile: Qt.platform.os === "android" || Qt.platform.os === "ios"
    readonly property int _inlineRowHeight: root._isMobile ? 44 : 36

    property string _inlineMode: "" // "" | "newNotebook" | "rename"
    property string _inlineKind: "" // "page" | "notebook"
    property string _inlinePageId: ""
    property string _inlineNotebookId: ""
    property string _inlineText: ""
    property var _activeRenameField: null

    property string _pendingDeleteNotebookId: ""
    property string _pendingDeleteNotebookTitle: ""
    property string _typeaheadBuffer: ""
    property string _typeaheadLastSingleChar: ""

    onSortModeChanged: {
        if (!root._componentReady) return
        loadPagesFromStorage()
        pagesChanged()
    }

    function beginNewNotebook() {
        if (!root.databaseActive) return
        root._inlineMode = "newNotebook"
        root._inlineKind = "notebook"
        root._inlinePageId = ""
        root._inlineNotebookId = ""
        root._inlineText = ""
        Qt.callLater(() => {
            if (newNotebookField) newNotebookField.forceActiveFocus()
        })
    }

    function beginRenamePage(pageId, title) {
        if (!pageId || pageId === "") return
        root._inlineMode = "rename"
        root._inlineKind = "page"
        root._inlinePageId = pageId
        root._inlineNotebookId = ""
        root._inlineText = title || ""
        Qt.callLater(() => {
            if (root._activeRenameField) {
                root._activeRenameField.forceActiveFocus()
                root._activeRenameField.selectAll()
            }
        })
    }

    function beginRenameNotebook(notebookId, title) {
        if (!notebookId || notebookId === "") return
        root._inlineMode = "rename"
        root._inlineKind = "notebook"
        root._inlinePageId = ""
        root._inlineNotebookId = notebookId
        root._inlineText = title || ""
        Qt.callLater(() => {
            if (root._activeRenameField) {
                root._activeRenameField.forceActiveFocus()
                root._activeRenameField.selectAll()
            }
        })
    }

    function cancelInlineEdit() {
        root._inlineMode = ""
        root._inlineKind = ""
        root._inlinePageId = ""
        root._inlineNotebookId = ""
        root._inlineText = ""
        root._activeRenameField = null
    }

    function commitInlineEdit() {
        if (!root.databaseActive) {
            cancelInlineEdit()
            return
        }
        const text = (root._inlineText || "").trim()
        if (root._inlineMode === "newNotebook") {
            if (!text) {
                cancelInlineEdit()
                return
            }
            if (DataStore && DataStore.createNotebook) {
                DataStore.createNotebook(text)
            }
            cancelInlineEdit()
            loadPagesFromStorage()
            pagesChanged()
            return
        }
        if (root._inlineMode === "rename" && root._inlineKind === "page") {
            if (!root._inlinePageId || root._inlinePageId === "") {
                cancelInlineEdit()
                return
            }
            if (text) {
                updatePageTitle(root._inlinePageId, text)
            }
            cancelInlineEdit()
            return
        }
        if (root._inlineMode === "rename" && root._inlineKind === "notebook") {
            if (!root._inlineNotebookId || root._inlineNotebookId === "") {
                cancelInlineEdit()
                return
            }
            if (DataStore && DataStore.renameNotebook && text) {
                DataStore.renameNotebook(root._inlineNotebookId, text)
            }
            cancelInlineEdit()
            loadPagesFromStorage()
            pagesChanged()
            return
        }
        cancelInlineEdit()
    }

    Timer {
        id: dragAutoScrollTimer
        interval: 16
        repeat: true
        running: root._dragActive
        onTriggered: {
            if (!pageList) return
            const localY = root._dragY - pageList.contentY
            const threshold = 56
            const step = 18
            if (localY < threshold) {
                pageList.contentY = Math.max(0, pageList.contentY - step)
            } else if (localY > pageList.height - threshold) {
                const maxY = Math.max(0, pageList.contentHeight - pageList.height)
                pageList.contentY = Math.min(maxY, pageList.contentY + step)
            }
        }
    }

    Timer {
        id: typeaheadTimer
        interval: root.typeaheadTimeoutMs
        repeat: false
        onTriggered: root._typeaheadBuffer = ""
    }

    function movePageTo(parentKind, targetPageId, targetNotebookId, draggedPageId) {
        if (!DataStore) return
        if (!draggedPageId || draggedPageId === "") return

        const pages = getAllPages()
        const byId = {}
        const children = {}
        for (let i = 0; i < pages.length; i++) {
            const p = pages[i]
            byId[p.pageId] = p
            const parent = p.parentId || ""
            if (!children[parent]) children[parent] = []
            children[parent].push(p.pageId)
        }

        function descendantsOf(rootId) {
            const out = {}
            const stack = [rootId]
            out[rootId] = true
            while (stack.length > 0) {
                const cur = stack.pop()
                const kids = children[cur] || []
                for (let i = 0; i < kids.length; i++) {
                    const kid = kids[i]
                    if (out[kid]) continue
                    out[kid] = true
                    stack.push(kid)
                }
            }
            return out
        }

        function isDescendant(targetId, rootId) {
            let cur = byId[targetId]
            while (cur && cur.parentId && cur.parentId !== "") {
                if (cur.parentId === rootId) return true
                cur = byId[cur.parentId]
            }
            return false
        }

        const dragged = byId[draggedPageId]
        if (!dragged) return

        let newParentId = ""
        let newNotebookId = ""

        if (parentKind === "page") {
            if (!targetPageId || targetPageId === "") return
            if (targetPageId === draggedPageId) return
            if (isDescendant(targetPageId, draggedPageId)) return
            const target = byId[targetPageId]
            if (!target) return
            newParentId = targetPageId
            newNotebookId = target.notebookId || ""
        } else if (parentKind === "notebook") {
            newParentId = ""
            newNotebookId = targetNotebookId || ""
        } else {
            // Root drop => loose note
            newParentId = ""
            newNotebookId = ""
        }

        let maxOrder = 0
        for (const id in byId) {
            if (id === draggedPageId) continue
            const p = byId[id]
            if (!p) continue
            if ((p.notebookId || "") !== newNotebookId) continue
            if ((p.parentId || "") !== newParentId) continue
            maxOrder = Math.max(maxOrder, p.sortOrder || 0)
        }

        const movedSet = descendantsOf(draggedPageId)
        for (const id in movedSet) {
            if (!byId[id]) continue
            byId[id].notebookId = newNotebookId
        }
        byId[draggedPageId].parentId = newParentId
        byId[draggedPageId].notebookId = newNotebookId
        byId[draggedPageId].sortOrder = maxOrder + 1

        const depthMemo = {}
        function depthOf(id) {
            if (depthMemo[id] !== undefined) return depthMemo[id]
            const p = byId[id]
            if (!p) return 0
            if (!p.parentId || p.parentId === "") {
                depthMemo[id] = (p.notebookId && p.notebookId !== "") ? 1 : 0
                return depthMemo[id]
            }
            depthMemo[id] = depthOf(p.parentId) + 1
            return depthMemo[id]
        }

        const updated = []
        for (const id in byId) {
            const p = byId[id]
            updated.push({
                pageId: p.pageId,
                notebookId: p.notebookId || "",
                title: p.title,
                parentId: p.parentId || "",
                depth: depthOf(p.pageId),
                sortOrder: p.sortOrder || 0
            })
        }

        DataStore.saveAllPages(updated)
    }

    function importDroppedFiles(fileUrls, targetKind, targetPageId, targetNotebookId) {
        if (!DataStore || !DataStore.importPagesFromFiles) return
        if (!fileUrls || fileUrls.length === 0) return

        let parentId = ""
        let notebookId = ""
        if (targetKind === "page") {
            parentId = targetPageId || ""
            notebookId = targetNotebookId || ""
        } else if (targetKind === "notebook") {
            notebookId = targetNotebookId || ""
        }

        const imported = DataStore.importPagesFromFiles(fileUrls, parentId, notebookId)
        if (!imported || imported.length === 0) return

        loadPagesFromStorage()
        pagesChanged()

        const firstImported = imported[0] || ""
        if (firstImported && firstImported !== "") {
            root.selectedPageId = firstImported
            const row = DataStore.getPage(firstImported)
            const title = row && row.title ? row.title : "Untitled"
            root.pageSelected(firstImported, title)
        }
    }

    function indexOfPageId(pageId) {
        if (!pageId || pageId === "") return -1
        for (let i = 0; i < pageModel.count; i++) {
            const row = pageModel.get(i)
            if (row && row.kind === "page" && row.pageId === pageId) return i
        }
        return -1
    }

    function indexOfNotebookId(notebookId) {
        if (!notebookId || notebookId === "") return -1
        for (let i = 0; i < pageModel.count; i++) {
            const row = pageModel.get(i)
            if (row && row.kind === "notebook" && row.notebookId === notebookId) return i
        }
        return -1
    }

    function indexOfFirstNotebookRow() {
        for (let i = 0; i < pageModel.count; i++) {
            const row = pageModel.get(i)
            if (row && row.kind === "notebook") return i
        }
        return -1
    }

    function nextVisibleIndex(fromIndex) {
        for (let i = fromIndex + 1; i < pageModel.count; i++) {
            if (rowVisible(i)) return i
        }
        return -1
    }

    function previousVisibleIndex(fromIndex) {
        for (let i = fromIndex - 1; i >= 0; i--) {
            if (rowVisible(i)) return i
        }
        return -1
    }

    function nextVisiblePageIndex(fromIndex) {
        for (let i = fromIndex + 1; i < pageModel.count; i++) {
            if (!rowVisible(i)) continue
            const row = pageModel.get(i)
            if (row && row.kind === "page") return i
        }
        return -1
    }

    function previousVisiblePageIndex(fromIndex) {
        for (let i = fromIndex - 1; i >= 0; i--) {
            if (!rowVisible(i)) continue
            const row = pageModel.get(i)
            if (row && row.kind === "page") return i
        }
        return -1
    }

    function currentKeyboardIndex() {
        if (pageList.currentIndex >= 0) return pageList.currentIndex
        return indexOfPageId(root.selectedPageId)
    }

    function normalizeTypeaheadText(text) {
        const value = (text || "") + ""
        return root.typeaheadCaseSensitive ? value : value.toLowerCase()
    }

    function rowMatchesPrefix(rowIndex, query) {
        if (rowIndex < 0 || rowIndex >= pageModel.count) return false
        if (!rowVisible(rowIndex)) return false
        const row = pageModel.get(rowIndex)
        if (!row || row.kind !== "page") return false
        const title = normalizeTypeaheadText(row.title || "")
        return query !== "" && title.indexOf(query) === 0
    }

    function findTypeaheadMatch(query, startExclusiveIndex) {
        if (!query || query === "" || pageModel.count <= 0) return -1
        const total = pageModel.count
        const start = (startExclusiveIndex >= -1 && startExclusiveIndex < total) ? startExclusiveIndex : -1
        for (let offset = 1; offset <= total; offset++) {
            const idx = (start + offset) % total
            if (rowMatchesPrefix(idx, query)) return idx
        }
        return -1
    }

    function handleTypeahead(event) {
        if (root._inlineMode !== "") return false
        const mod = event.modifiers
        if (mod & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        const text = (event.text || "")
        if (text.length !== 1 || text.trim() === "") return false

        const normalizedChar = normalizeTypeaheadText(text)
        const hasActiveSequence = typeaheadTimer.running && root._typeaheadBuffer !== ""
        const query = hasActiveSequence ? (root._typeaheadBuffer + normalizedChar) : normalizedChar
        const cycleSingleChar = !hasActiveSequence
            && root._typeaheadLastSingleChar !== ""
            && root._typeaheadLastSingleChar === normalizedChar
        const current = currentKeyboardIndex()
        const start = cycleSingleChar ? current : (current - 1)
        const matchIndex = findTypeaheadMatch(query, start)

        if (matchIndex >= 0) {
            selectIndex(matchIndex)
        }

        root._typeaheadBuffer = query
        if (!hasActiveSequence && query.length === 1) {
            root._typeaheadLastSingleChar = query
        }
        typeaheadTimer.restart()
        return true
    }

    function estimatedVisibleRowStepCount() {
        const rowHeight = collapsed
            ? 32
            : (root._isMobile ? Math.max(44, root.actionButtonSize) : 28)
        const approxGap = 2
        const perRow = Math.max(1, rowHeight + approxGap)
        const viewHeight = Math.max(1, pageList.height)
        return Math.max(1, Math.floor(viewHeight / perRow))
    }

    function pageStepIndex(fromIndex, direction) {
        const stepCount = estimatedVisibleRowStepCount()
        let idx = fromIndex
        for (let i = 0; i < stepCount; i++) {
            const next = direction >= 0 ? nextVisiblePageIndex(idx) : previousVisiblePageIndex(idx)
            if (next < 0) break
            idx = next
        }
        return idx
    }

    function navigatePageByScreen(direction) {
        const from = currentKeyboardIndex()
        if (from < 0) {
            return selectIndex(direction >= 0 ? nextVisiblePageIndex(-1) : previousVisiblePageIndex(pageModel.count))
        }
        const target = pageStepIndex(from, direction)
        if (target < 0 || target === from) return false
        const selected = selectIndex(target)
        if (selected) {
            pageList.positionViewAtIndex(target, ListView.Visible)
        }
        return selected
    }

    function navigateToBoundary(direction) {
        const target = direction < 0 ? nextVisiblePageIndex(-1) : previousVisiblePageIndex(pageModel.count)
        if (target < 0) return false
        const selected = selectIndex(target)
        if (selected) {
            pageList.positionViewAtIndex(target, ListView.Visible)
        }
        return selected
    }

    function focusTree() {
        syncCurrentIndexToSelection()
        pageList.focus = true
        pageList.forceActiveFocus()
    }

    function syncCurrentIndexToSelection() {
        const idx = indexOfPageId(root.selectedPageId)
        if (idx >= 0) {
            pageList.currentIndex = idx
            return
        }
        const first = nextVisibleIndex(-1)
        if (first >= 0) pageList.currentIndex = first
    }

    function selectIndex(idx) {
        if (idx < 0 || idx >= pageModel.count) return false
        if (!rowVisible(idx)) return false
        pageList.currentIndex = idx
        const row = pageModel.get(idx)
        if (!row) return false
        if (row.kind === "notebook") return true
        root.handleRowTap(row.kind || "page", row.pageId || "", row.notebookId || "", row.title || "")
        return true
    }

    function firstChildIndex(parentIndex) {
        if (parentIndex < 0 || parentIndex >= pageModel.count) return -1
        const parent = pageModel.get(parentIndex)
        if (!parent) return -1
        const wantDepth = parent.depth + 1
        for (let i = parentIndex + 1; i < pageModel.count; i++) {
            const row = pageModel.get(i)
            if (!row) continue
            if (row.depth <= parent.depth) break
            if (row.depth === wantDepth) return i
        }
        return -1
    }

    function parentIndex(childIndex) {
        if (childIndex < 0 || childIndex >= pageModel.count) return -1
        const row = pageModel.get(childIndex)
        if (!row || !row.parentId || row.parentId === "") return -1
        return indexOfPageId(row.parentId)
    }

    function parentIndexForRow(childIndex) {
        if (childIndex < 0 || childIndex >= pageModel.count) return -1
        const row = pageModel.get(childIndex)
        if (!row) return -1
        if (row.depth <= 0) return -1
        if (row.kind === "page") {
            if (row.parentId && row.parentId !== "") return indexOfPageId(row.parentId)
            if (row.depth === 1 && row.notebookId && row.notebookId !== "") return indexOfNotebookId(row.notebookId)
        }
        return -1
    }
    
    // Auto-load pages on component creation
    Component.onCompleted: {
        // Initialize database
        if (DataStore) {
            DataStore.initialize()
        }
        
        if (!loadPagesFromStorage()) {
            createDefaultPages()
        }
        pagesChanged()
        root._componentReady = true
    }

    Connections {
        target: DataStore

        function onPagesChanged() {
            loadPagesFromStorage()
            pagesChanged()
        }

        function onNotebooksChanged() {
            loadPagesFromStorage()
            pagesChanged()
        }
    }
    
    // UUID generator
    function generateUuid() {
        function s4() {
            return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        }
        return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4()
    }
    
    function createPage(parentId, options) {
        return createPageWithNotebook(parentId, "", options)
    }

    function createPageWithNotebook(parentId, notebookId, options) {
        if (!root.databaseActive) return ""
        let id = generateUuid()
        let depth = 0
        let insertIndex = pageModel.count
        let resolvedNotebookId = notebookId || ""
        const selectAfterCreate = options && ("selectAfterCreate" in options)
            ? !!options.selectAfterCreate
            : GeneralPreferences.jumpToNewPageOnCreate

        // Calculate depth and notebook based on parent page (if any).
        if (parentId && parentId !== "") {
            for (let i = 0; i < pageModel.count; i++) {
                let row = pageModel.get(i)
                if (row && row.kind === "page" && row.pageId === parentId) {
                    resolvedNotebookId = row.notebookId || ""
                    depth = row.depth + 1
                    // Find insert position (after parent and its children)
                    insertIndex = i + 1
                    while (insertIndex < pageModel.count &&
                           pageModel.get(insertIndex).depth > row.depth) {
                        insertIndex++
                    }
                    break
                }
            }
        } else if (resolvedNotebookId !== "") {
            // Root page inside a notebook.
            depth = 1
            const nbIndex = indexOfNotebookId(resolvedNotebookId)
            if (nbIndex >= 0) {
                insertIndex = nbIndex + 1
                while (insertIndex < pageModel.count &&
                       pageModel.get(insertIndex).depth > 0) {
                    insertIndex++
                }
            }
        } else {
            // Root page not in a notebook: insert before first notebook folder.
            const firstNotebook = indexOfFirstNotebookRow()
            if (firstNotebook >= 0) {
                insertIndex = firstNotebook
            }
        }

        pageModel.insert(insertIndex, {
            kind: "page",
            pageId: id,
            notebookId: resolvedNotebookId,
            title: "Untitled",
            parentId: parentId || "",
            expanded: true,
            depth: depth,
            sortOrder: insertIndex
        })

        // Save to storage
        savePagesToStorage()
        pagesChanged()

        if (selectAfterCreate) {
            root.selectedPageId = id
            pageSelected(id, "Untitled")
        }
        return id
    }
    
    // Get all pages as a list (for mobile and linking)
    function getAllPages() {
        let pages = []
        for (let i = 0; i < pageModel.count; i++) {
            let p = pageModel.get(i)
            if (!p || p.kind !== "page") continue
            pages.push({
                pageId: p.pageId,
                notebookId: p.notebookId || "",
                title: p.title,
                depth: p.depth,
                parentId: p.parentId,
                sortOrder: p.sortOrder || 0
            })
        }
        return pages
    }
    
    // Update page title
    function updatePageTitle(pageId, newTitle) {
        for (let i = 0; i < pageModel.count; i++) {
            const row = pageModel.get(i)
            if (row && row.kind === "page" && row.pageId === pageId) {
                pageModel.setProperty(i, "title", newTitle)
                savePagesToStorage()
                pagesChanged()
                break
            }
        }
    }
    
    // Delete a page and its children
    function deletePage(pageId) {
        // Find all pages to delete (the page and its descendants)
        let toDelete = []
        let pageDepth = -1
        let foundPage = false
        
        for (let i = 0; i < pageModel.count; i++) {
            let page = pageModel.get(i)
            if (page && page.kind === "page" && page.pageId === pageId) {
                foundPage = true
                pageDepth = page.depth
                toDelete.push(i)
            } else if (foundPage && page.depth > pageDepth) {
                // This is a child of the deleted page
                toDelete.push(i)
            } else if (foundPage && page.depth <= pageDepth) {
                // We've passed all children
                break
            }
        }
        
        // Delete from end to start to maintain indices
        for (let i = toDelete.length - 1; i >= 0; i--) {
            pageModel.remove(toDelete[i])
        }
        
        savePagesToStorage()
        pagesChanged()
    }
    
    // Storage functions - using SQLite via DataStore
    function savePagesToStorage() {
        if (!DataStore || DataStore.schemaVersion < 0) return
        let pages = getAllPages()
        DataStore.saveAllPages(pages)
    }
    
    function loadPagesFromStorage() {
        if (!DataStore || DataStore.schemaVersion < 0) {
            cancelInlineEdit()
            root.selectedPageId = ""
            pageModel.clear()
            return false
        }
        try {
            let pages = DataStore ? DataStore.getAllPages() : []
            let notebooks = (DataStore && DataStore.getAllNotebooks) ? DataStore.getAllNotebooks() : []
            rebuildModel(pages || [], notebooks || [])
            const hasAny = (pages && pages.length > 0) || (notebooks && notebooks.length > 0)
            if (!hasAny) {
                cancelInlineEdit()
                root.selectedPageId = ""
            }
            return hasAny
        } catch (e) {
            console.log("Error loading pages:", e)
            cancelInlineEdit()
            root.selectedPageId = ""
            pageModel.clear()
        }
        return false
    }

    function rebuildModel(pages, notebooks) {
        const byNotebook = {}
        for (let i = 0; i < pages.length; i++) {
            const p = pages[i] || {}
            const nb = p.notebookId || ""
            if (!byNotebook[nb]) byNotebook[nb] = []
            byNotebook[nb].push(p)
        }

        function normalizedSortMode() {
            if (root.sortMode === "updatedAt") return "updatedAt"
            if (root.sortMode === "createdAt") return "createdAt"
            return "alphabetical"
        }

        function compareAlpha(a, b) {
            const aTitle = ((a.title || "") + "").toLowerCase()
            const bTitle = ((b.title || "") + "").toLowerCase()
            const byTitle = aTitle.localeCompare(bTitle)
            if (byTitle !== 0) return byTitle
            const aId = (a.pageId || a.notebookId || "") + ""
            const bId = (b.pageId || b.notebookId || "") + ""
            return aId.localeCompare(bId)
        }

        function compareTimestampDesc(field, a, b) {
            const aTs = (a && a[field]) ? (a[field] + "") : ""
            const bTs = (b && b[field]) ? (b[field] + "") : ""
            const byTs = bTs.localeCompare(aTs)
            if (byTs !== 0) return byTs
            const byTitle = compareAlpha(a, b)
            if (byTitle !== 0) return byTitle
            const aOrder = a.sortOrder || 0
            const bOrder = b.sortOrder || 0
            return aOrder - bOrder
        }

        function pageComparator() {
            const mode = normalizedSortMode()
            if (mode === "updatedAt") return (a, b) => compareTimestampDesc("updatedAt", a, b)
            if (mode === "createdAt") return (a, b) => compareTimestampDesc("createdAt", a, b)
            return compareAlpha
        }

        function notebookComparator() {
            const mode = normalizedSortMode()
            if (mode === "updatedAt") return (a, b) => compareTimestampDesc("updatedAt", a, b)
            if (mode === "createdAt") return (a, b) => compareTimestampDesc("createdAt", a, b)
            return (a, b) => {
                const aName = ((a.name || "") + "").toLowerCase()
                const bName = ((b.name || "") + "").toLowerCase()
                const byName = aName.localeCompare(bName)
                if (byName !== 0) return byName
                const aId = (a.notebookId || "") + ""
                const bId = (b.notebookId || "") + ""
                return aId.localeCompare(bId)
            }
        }

        function toChildrenMap(list) {
            const m = {}
            for (let i = 0; i < list.length; i++) {
                const p = list[i] || {}
                const parent = p.parentId || ""
                if (!m[parent]) m[parent] = []
                m[parent].push(p)
            }
            for (const key in m) {
                m[key].sort(pageComparator())
            }
            return m
        }

        function appendTree(childrenMap, parentId, depthBase, notebookId) {
            const kids = childrenMap[parentId] || []
            for (let i = 0; i < kids.length; i++) {
                const p = kids[i] || {}
                pageModel.append({
                    kind: "page",
                    pageId: p.pageId,
                    notebookId: notebookId || "",
                    title: p.title,
                    parentId: p.parentId || "",
                    expanded: true,
                    depth: depthBase,
                    sortOrder: p.sortOrder || 0,
                    createdAt: p.createdAt || "",
                    updatedAt: p.updatedAt || ""
                })
                appendTree(childrenMap, p.pageId, depthBase + 1, notebookId)
            }
        }

        pageModel.clear()

        // 1) Loose notes (no notebook) at root.
        const loosePages = byNotebook[""] || []
        appendTree(toChildrenMap(loosePages), "", 0, "")

        // 2) Notebook folders + their notes.
        if (notebooks && notebooks.length > 0) {
            const notebookList = []
            for (let i = 0; i < notebooks.length; i++) {
                notebookList.push(notebooks[i] || {})
            }
            notebookList.sort(notebookComparator())

            for (let i = 0; i < notebookList.length; i++) {
                const nb = notebookList[i] || {}
                const notebookId = nb.notebookId || ""
                if (notebookId === "") continue
                pageModel.append({
                    kind: "notebook",
                    pageId: "",
                    notebookId: notebookId,
                    title: nb.name || "Untitled Notebook",
                    parentId: "",
                    expanded: true,
                    depth: 0,
                    createdAt: nb.createdAt || "",
                    updatedAt: nb.updatedAt || ""
                })
                const notebookPages = byNotebook[notebookId] || []
                appendTree(toChildrenMap(notebookPages), "", 1, notebookId)
            }
        }
    }
    
    function hasChildrenAtIndex(rowIndex) {
        if (rowIndex < 0 || rowIndex >= pageModel.count) return false
        const row = pageModel.get(rowIndex)
        if (!row) return false
        const baseDepth = row.depth
        for (let i = rowIndex + 1; i < pageModel.count; i++) {
            const next = pageModel.get(i)
            if (!next) continue
            if (next.depth <= baseDepth) break
            if (next.depth === baseDepth + 1) return true
        }
        return false
    }

    // Determine if a row should be visible based on ancestor expanded state.
    function rowVisible(rowIndex) {
        if (rowIndex < 0 || rowIndex >= pageModel.count) return false
        const row = pageModel.get(rowIndex)
        if (!row) return false
        if (row.depth <= 0) return true

        let neededDepth = row.depth - 1
        for (let i = rowIndex - 1; i >= 0 && neededDepth >= 0; i--) {
            const candidate = pageModel.get(i)
            if (!candidate) continue
            if (candidate.depth === neededDepth) {
                if (!candidate.expanded) return false
                neededDepth--
            }
        }
        return neededDepth < 0
    }

    function toggleExpandedAtIndex(rowIndex) {
        if (rowIndex < 0 || rowIndex >= pageModel.count) return
        const row = pageModel.get(rowIndex)
        if (!row) return
        if (!hasChildrenAtIndex(rowIndex)) return
        pageModel.setProperty(rowIndex, "expanded", !row.expanded)
    }

    function handleRowTap(kind, pageId, notebookId, title) {
        if (kind === "notebook") {
            handleNotebookTap(notebookId)
            return
        }

        if (root.activateOnSingleTap || root.selectedPageId === pageId) {
            root.selectedPageId = pageId
            root.pageSelected(pageId, title)
            return
        }
        root.selectedPageId = pageId
    }

    function handleNotebookTap(notebookId) {
        const idx = indexOfNotebookId(notebookId)
        if (idx < 0) return
        toggleExpandedAtIndex(idx)
    }

    function activateRow(kind, pageId, notebookId, title) {
        if (kind === "notebook") {
            handleNotebookTap(notebookId)
            return
        }
        root.selectedPageId = pageId
        root.pageSelected(pageId, title)
    }

    function openContextMenu(kind, pageId, notebookId, title) {
        if (!root.enableContextMenu) return
        const menu = pageContextMenuLoader.item
        if (!menu) return
        menu.targetKind = kind
        menu.targetPageId = pageId
        menu.targetNotebookId = notebookId
        menu.targetTitle = title
        menu.popup()
    }

    function requestDeleteNotebook(notebookId, title) {
        if (!notebookId || notebookId === "") return
        root._pendingDeleteNotebookId = notebookId
        root._pendingDeleteNotebookTitle = title || ""
        deleteNotebookDeletePages.checked = false
        deleteNotebookDialog.open()
    }

    function selectPage(pageId) {
        if (!pageId || pageId === "") return false
        for (let i = 0; i < pageModel.count; i++) {
            const page = pageModel.get(i)
            if (page && page.kind === "page" && page.pageId === pageId) {
                root.selectedPageId = pageId
                pageSelected(pageId, page.title)
                return true
            }
        }
        return false
    }
    
    function ensureInitialPage(preferredPageId) {
        // Select preferred page when present, else first page.
        if (preferredPageId && preferredPageId !== "" && selectPage(preferredPageId)) {
            return
        }
        for (let i = 0; i < pageModel.count; i++) {
            const row = pageModel.get(i)
            if (row && row.kind === "page") {
                root.selectedPageId = row.pageId
                pageSelected(row.pageId, row.title)
                return
            }
        }
    }
    
    function createDefaultPages() {
        if (DataStore) {
            DataStore.seedDefaultPages()
            loadPagesFromStorage()
            return
        }
        pageModel.clear()
        pageModel.append({ kind: "page", pageId: "1", notebookId: "", title: "Getting Started", parentId: "", expanded: true, depth: 0 })
        pageModel.append({ kind: "page", pageId: "2", notebookId: "", title: "Projects", parentId: "", expanded: true, depth: 0 })
        pageModel.append({ kind: "page", pageId: "3", notebookId: "", title: "Work Project", parentId: "2", expanded: true, depth: 1 })
        pageModel.append({ kind: "page", pageId: "4", notebookId: "", title: "Personal", parentId: "", expanded: true, depth: 0 })
        savePagesToStorage()
    }
    
    ListModel {
        id: pageModel
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: ThemeManager.spacingSmall
        
        // Top controls (New Page / New Notebook / Sort)
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: ThemeManager.spacingSmall
            visible: root.showNewPageButton || root.showNewNotebookButton || root.showSortButton
            
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                visible: root.showNewPageButton
                radius: ThemeManager.radiusSmall
                color: newPageMouse.containsMouse || newPageMouse.pressed ? ThemeManager.surfaceHover : ThemeManager.surface
                border.width: 1
                border.color: ThemeManager.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: ThemeManager.spacingSmall

                    Text {
                        text: "🗎"
                        color: ThemeManager.accent
                        font.pixelSize: ThemeManager.fontSizeLarge
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "New Page"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                    }
                }

                MouseArea {
                    id: newPageMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.createPage("")
                }
            }

            Rectangle {
                Layout.preferredWidth: 144
                Layout.preferredHeight: 36
                visible: root.showNewNotebookButton
                radius: ThemeManager.radiusSmall
                color: newNotebookMouse.containsMouse || newNotebookMouse.pressed ? ThemeManager.surfaceHover : ThemeManager.surface
                border.width: 1
                border.color: ThemeManager.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: ThemeManager.spacingSmall

                    Text {
                        text: "📁"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "New Notebook"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: newNotebookMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.beginNewNotebook()
                }
            }

            Item {
                Layout.fillWidth: true
                visible: !root.showNewPageButton
            }

            Rectangle {                
                Layout.preferredHeight: 36
                visible: root.showSortButton
                implicitWidth: sortButtonRow.implicitWidth + ThemeManager.spacingSmall + 20
                radius: ThemeManager.radiusSmall
                color: sortMouse.containsMouse || sortMouse.pressed ? ThemeManager.surfaceHover : ThemeManager.surface
                border.width: 1
                border.color: ThemeManager.border

                RowLayout {
                    id: sortButtonRow
                    anchors.fill: parent
                    implicitWidth: sortIcon.implicitWidth + sortText.implicitWidth 
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: ThemeManager.spacingSmall

                    Text {
                        id: sortIcon
                        text: "⇅"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                    }

                    Text {
                        id: sortText
                        Layout.fillWidth: true
                        text: "Sort"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: sortMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sortMenu.popup()
                }

                Menu {
                    id: sortMenu
                    modal: true

                    MenuItem {
                        text: "Alphabetical"
                        checkable: true
                        checked: root.sortMode === "alphabetical"
                        onTriggered: root.sortMode = "alphabetical"
                    }
                    MenuItem {
                        text: "Updated at"
                        checkable: true
                        checked: root.sortMode === "updatedAt"
                        onTriggered: root.sortMode = "updatedAt"
                    }
                    MenuItem {
                        text: "Created at"
                        checkable: true
                        checked: root.sortMode === "createdAt"
                        onTriggered: root.sortMode = "createdAt"
                    }
                }
            }
        }

        // Inline notebook creation row (replaces dialog).
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root._inlineMode === "newNotebook" ? root._inlineRowHeight : 0
            Layout.maximumHeight: Layout.preferredHeight
            clip: true

            Rectangle {
                anchors.fill: parent
                visible: root._inlineMode === "newNotebook"
                radius: ThemeManager.radiusSmall
                color: ThemeManager.surface
                border.width: 1
                border.color: ThemeManager.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: ThemeManager.spacingSmall

                    Text {
                        text: "📁"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                    }

                    TextField {
                        id: newNotebookField
                        objectName: root.objectName + "_newNotebookField"
                        Layout.fillWidth: true
                        height: root._inlineRowHeight - ThemeManager.spacingSmall * 2
                        placeholderText: "Notebook name"
                        color: ThemeManager.text
                        placeholderTextColor: ThemeManager.textMuted
                        selectionColor: ThemeManager.accent
                        selectedTextColor: "white"
                        text: root._inlineText
                        leftPadding: ThemeManager.spacingSmall
                        rightPadding: ThemeManager.spacingSmall
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: ThemeManager.surfaceHover
                            border.width: 1
                            border.color: ThemeManager.border
                        }
                        onTextChanged: root._inlineText = text
                        onAccepted: root.commitInlineEdit()
                        Keys.onEscapePressed: root.cancelInlineEdit()
                    }

                    ToolButton {
                        visible: !root._isMobile
                        text: "Create"
                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: root.commitInlineEdit()
                    }

                    ToolButton {
                        visible: !root._isMobile
                        text: "Cancel"
                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: root.cancelInlineEdit()
                    }
                }
            }
        }
        
        ListView {
            id: pageList
            objectName: root.objectName + "_list"

            Layout.fillWidth: true
            Layout.fillHeight: true
            model: pageModel
            clip: true
            spacing: 0

            DropArea {
                anchors.fill: parent
                onDropped: function(drop) {
                    if (!drop) return
                    if (drop.hasUrls && drop.urls && drop.urls.length > 0) {
                        root.importDroppedFiles(drop.urls, "root", "", "")
                        drop.accepted = true
                        return
                    }
                    if (!drop.mimeData) return
                    const idx = pageList.indexAt(drop.x, drop.y)
                    if (idx >= 0) return
                    const draggedId = drop.mimeData.getDataAsString("application/x-zinc-page")
                    if (!draggedId || draggedId === "") return
                    root.movePageTo("root", "", "", draggedId)
                }
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                    event.accepted = true
                    const from = pageList.currentIndex >= 0 ? pageList.currentIndex : indexOfPageId(root.selectedPageId)
                    if (from < 0) {
                        selectIndex(nextVisibleIndex(-1))
                        return
                    }
                    selectIndex(nextVisibleIndex(from))
                    return
                }
                if (event.key === Qt.Key_Up) {
                    event.accepted = true
                    const from = pageList.currentIndex >= 0 ? pageList.currentIndex : indexOfPageId(root.selectedPageId)
                    if (from < 0) {
                        selectIndex(previousVisibleIndex(pageModel.count))
                        return
                    }
                    selectIndex(previousVisibleIndex(from))
                    return
                }
                if (event.key === Qt.Key_Right) {
                    event.accepted = true
                    const idx = pageList.currentIndex >= 0 ? pageList.currentIndex : indexOfPageId(root.selectedPageId)
                    if (idx < 0) return
                    const row = pageModel.get(idx)
                    if (!row) return
                    const hasKids = root.hasChildrenAtIndex(idx)
                    if (!hasKids) return
                    if (!row.expanded) {
                        pageModel.setProperty(idx, "expanded", true)
                        return
                    }
                    selectIndex(firstChildIndex(idx))
                    return
                }
                if (event.key === Qt.Key_Left) {
                    event.accepted = true
                    const idx = pageList.currentIndex >= 0 ? pageList.currentIndex : indexOfPageId(root.selectedPageId)
                    if (idx < 0) return
                    const row = pageModel.get(idx)
                    if (!row) return
                    const hasKids = root.hasChildrenAtIndex(idx)
                    if (hasKids && row.expanded) {
                        pageModel.setProperty(idx, "expanded", false)
                        return
                    }
                    selectIndex(parentIndexForRow(idx))
                    return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true
                    const idx = pageList.currentIndex >= 0 ? pageList.currentIndex : indexOfPageId(root.selectedPageId)
                    if (idx < 0 || idx >= pageModel.count) return
                    if (!rowVisible(idx)) return
                    const page = pageModel.get(idx)
                    if (!page) return
                    root.activateRow(page.kind || "page", page.pageId || "", page.notebookId || "", page.title || "")
                    if (page.kind === "page") {
                        root.pageActivatedByKeyboard(page.pageId, page.title)
                    }
                    return
                }
                if (event.key === Qt.Key_PageDown) {
                    event.accepted = true
                    navigatePageByScreen(1)
                    return
                }
                if (event.key === Qt.Key_PageUp) {
                    event.accepted = true
                    navigatePageByScreen(-1)
                    return
                }
                if (event.key === Qt.Key_Home) {
                    event.accepted = true
                    navigateToBoundary(-1)
                    return
                }
                if (event.key === Qt.Key_End) {
                    event.accepted = true
                    navigateToBoundary(1)
                    return
                }
                if (root.handleTypeahead(event)) {
                    event.accepted = true
                    return
                }
            }

            delegate: Item {
                id: delegateItem
                objectName: "pageTreeRow_" + index
                width: pageList.width

                readonly property bool rowIsVisible: rowVisible(index)
                readonly property bool rowHasKids: root.hasChildrenAtIndex(index)
                readonly property bool rowIsCollapsedFolder: rowHasKids && !model.expanded
                readonly property bool rowHovered: delegateMouseArea.containsMouse
                    || arrowMouse.containsMouse
                    || addChildMouse.containsMouse
                    || menuMouse.containsMouse
                readonly property int rowHeight: collapsed
                    ? 32
                    : (root._isMobile ? Math.max(44, root.actionButtonSize) : 28)
                readonly property bool hasNextVisible: rowIsVisible && root.nextVisibleIndex(index) !== -1
                readonly property int rowGap: hasNextVisible ? 2 : 0

                height: rowIsVisible ? (rowHeight + rowGap) : 0
                visible: rowIsVisible

                Rectangle {
                    id: rowBackground
                    width: parent.width
                    height: delegateItem.rowHeight
                    visible: delegateItem.visible
                    radius: ThemeManager.radiusSmall
                    readonly property bool selected: root.selectedPageId === model.pageId
                    readonly property bool keyboardCurrent: pageList.activeFocus && pageList.currentIndex === index
                    readonly property string pageId: model.pageId || ""
                    color: selected
                        ? ThemeManager.surfaceActive
                        : (keyboardCurrent
                            ? ThemeManager.surfaceHover
                            : (delegateItem.rowHovered || delegateMouseArea.pressed ? ThemeManager.surfaceHover : "transparent"))

                    Drag.active: root._isMobile ? mobileDragHandler.active : desktopDragHandler.active
                    Drag.supportedActions: Qt.MoveAction
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    Drag.mimeData: (model.kind === "page" && model.pageId)
                        ? ({ "application/x-zinc-page": model.pageId })
                        : ({})

                    DragHandler {
                        id: desktopDragHandler
                        enabled: !root._isMobile && model.kind === "page"
                        target: null

                        onActiveChanged: {
                            root._dragActive = desktopDragHandler.active
                            if (!desktopDragHandler.active) {
                                root._dragY = 0
                            }
                        }

                        onCentroidChanged: {
                            if (!desktopDragHandler.active) return
                            root._dragY = delegateItem.y + desktopDragHandler.centroid.position.y
                        }
                    }

                    DropArea {
                        anchors.fill: parent
                        onDropped: function(drop) {
                            if (!drop) return
                            if (drop.hasUrls && drop.urls && drop.urls.length > 0) {
                                root.importDroppedFiles(drop.urls, model.kind || "page", model.pageId || "", model.notebookId || "")
                                drop.accepted = true
                                return
                            }
                            if (!drop.mimeData) return
                            const draggedId = drop.mimeData.getDataAsString("application/x-zinc-page")
                            if (!draggedId || draggedId === "") return
                            root.movePageTo(model.kind || "page", model.pageId || "", model.notebookId || "", draggedId)
                            drop.accepted = true
                        }
                    }
                    
                    // Background MouseArea for hover and page selection (z = 0)
                    MouseArea {
                        id: delegateMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        z: 0
                        enabled: !(root._inlineMode === "rename" &&
                                   ((root._inlineKind === "page" && (model.pageId || "") === root._inlinePageId) ||
                                    (root._inlineKind === "notebook" && (model.notebookId || "") === root._inlineNotebookId)))
                        
                        onPressed: function(mouse) {
                            if (mouse.button === Qt.RightButton) {
                                root.openContextMenu(model.kind || "page", model.pageId || "", model.notebookId || "", model.title || "")
                                mouse.accepted = true
                            }
                        }

                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                root.handleRowTap(model.kind || "page", model.pageId || "", model.notebookId || "", model.title || "")
                            }
                        }
                    }
                    
		            RowLayout {
		                anchors.fill: parent
		                anchors.leftMargin: collapsed ? ThemeManager.spacingSmall : (ThemeManager.spacingSmall + model.depth * 20)
		                anchors.rightMargin: ThemeManager.spacingSmall
		                spacing: ThemeManager.spacingSmall
		                z: 1
	                
	                // Left affordance: small icon, becomes expand/collapse arrow on hover.
	                Item {
	                    Layout.fillHeight: true
	                    Layout.alignment: Qt.AlignVCenter
	                    Layout.preferredWidth: 18
	                    width: 18

	                    readonly property bool showArrow: !collapsed && delegateItem.rowHasKids &&
	                                                     (root.showExpandArrowsAlways || delegateItem.rowHovered)

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        color: ThemeManager.textMuted
                        font.pixelSize: 9
                        rotation: model.expanded ? 90 : 0
                        visible: parent.showArrow

                        Behavior on rotation {
                            NumberAnimation { duration: ThemeManager.animationFast }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: model.kind === "notebook" ? "📁" : "📄"
                        font.pixelSize: collapsed ? 14 : 12
                        visible: !parent.showArrow
                    }

                    MouseArea {
                        id: arrowMouse
                        anchors.fill: parent
                        enabled: parent.showArrow
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: function(mouse) {
                            model.expanded = !model.expanded
                            mouse.accepted = true
                        }
                    }
                }
                
	                // Page title
	                Item {
	                    Layout.fillWidth: true
	                    Layout.fillHeight: true
	                    Layout.alignment: Qt.AlignVCenter
	                    visible: !collapsed

                    readonly property bool editingThisRow: root._inlineMode === "rename" &&
                        ((root._inlineKind === "page" && (model.pageId || "") === root._inlinePageId) ||
                         (root._inlineKind === "notebook" && (model.notebookId || "") === root._inlineNotebookId))

                    Text {
                        anchors.fill: parent
                        text: model.title || ""
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        visible: !parent.editingThisRow
                    }

                    Loader {
                        anchors.fill: parent
                        active: parent.editingThisRow
                        visible: parent.editingThisRow

                        sourceComponent: TextField {
                            objectName: root.objectName + "_renameField"
                            color: ThemeManager.text
                            placeholderTextColor: ThemeManager.textMuted
                            selectionColor: ThemeManager.accent
                            selectedTextColor: "white"
                            text: root._inlineText
                            leftPadding: ThemeManager.spacingSmall
                            rightPadding: ThemeManager.spacingSmall
                            background: Rectangle {
                                radius: ThemeManager.radiusSmall
                                color: ThemeManager.surfaceHover
                                border.width: 1
                                border.color: ThemeManager.border
                            }
                            onTextChanged: root._inlineText = text
                            onAccepted: root.commitInlineEdit()
                            Keys.onEscapePressed: root.cancelInlineEdit()
                            Component.onCompleted: {
                                root._activeRenameField = this
                                forceActiveFocus()
                                selectAll()
                            }
                        }
                    }
                }

	                // Mobile drag handle (prevents interfering with scroll flick).
	                Item {
	                    Layout.fillHeight: true
	                    Layout.alignment: Qt.AlignVCenter
	                    Layout.preferredWidth: 18
	                    width: 18
	                    visible: root._isMobile && (model.kind === "page") && !collapsed

                    Text {
                        anchors.centerIn: parent
                        text: "≡"
                        color: ThemeManager.textMuted
                        font.pixelSize: 12
                    }

                    DragHandler {
                        id: mobileDragHandler
                        enabled: root._isMobile && model.kind === "page"
                        target: null

                        onActiveChanged: {
                            root._dragActive = mobileDragHandler.active
                            if (!mobileDragHandler.active) {
                                root._dragY = 0
                            }
                        }

                        onCentroidChanged: {
                            if (!mobileDragHandler.active) return
                            root._dragY = delegateItem.y + mobileDragHandler.centroid.position.y
                        }
                    }
                }
                
	                // Actions (appear on hover)
	                RowLayout {
	                    Layout.alignment: Qt.AlignVCenter
	                    Layout.fillHeight: true
	                    spacing: 2
	                    visible: (root.actionsAlwaysVisible || delegateItem.rowHovered) && !collapsed
	                    
	                    Rectangle {
	                        id: addChildButton
	                        objectName: "pageTreeAddChildButton_" + index
	                        Layout.alignment: Qt.AlignVCenter
                            visible: !delegateItem.rowIsCollapsedFolder
	                        width: root.actionButtonSize
	                        height: root.actionButtonSize
	                        radius: ThemeManager.radiusSmall
	                        color: addChildMouse.containsMouse || addChildMouse.pressed ? ThemeManager.surfaceActive : "transparent"
                        
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: ThemeManager.textSecondary
                            font.pixelSize: 14
                        }
                        
                        MouseArea {
                            id: addChildMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            onPressed: function(mouse) { mouse.accepted = true }
                            onClicked: function(mouse) {
                                if (model.kind === "notebook") {
                                    root.createPageWithNotebook("", model.notebookId || "")
                                } else {
                                    root.createPage(model.pageId)
                                }
                                mouse.accepted = true
                            }
                        }
                    }
                    
	                    Rectangle {
	                        id: menuButton
	                        objectName: "pageTreeMenuButton_" + index
	                        Layout.alignment: Qt.AlignVCenter
	                        width: root.actionButtonSize
	                        height: root.actionButtonSize
	                        radius: ThemeManager.radiusSmall
	                        color: menuMouse.containsMouse || menuMouse.pressed ? ThemeManager.surfaceActive : "transparent"
                        
                        Text {
                            anchors.centerIn: parent
                            text: "⋯"
                            color: ThemeManager.textSecondary
                            font.pixelSize: 14
                        }
                        
                        MouseArea {
                            id: menuMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            onPressed: function(mouse) { mouse.accepted = true }
                            onClicked: function(mouse) {
                                root.openContextMenu(model.kind || "page", model.pageId || "", model.notebookId || "", model.title || "")
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }
	        }
	    }
        }
	    
	    // Context menu for page actions
	    Loader {
	        id: pageContextMenuLoader
        active: root.enableContextMenu

        sourceComponent: Menu {
            id: pageContextMenu
            property string targetKind: "page"
            property string targetPageId: ""
            property string targetNotebookId: ""
            property string targetTitle: ""

            MenuItem {
                text: "New notebook"
                onTriggered: root.beginNewNotebook()
            }

            MenuSeparator {}

            MenuItem {
                text: pageContextMenu.targetKind === "notebook" ? "New page in notebook" : "Add sub-page"
                onTriggered: {
                    if (pageContextMenu.targetKind === "notebook") {
                        root.createPageWithNotebook("", pageContextMenu.targetNotebookId)
                    } else {
                        root.createPage(pageContextMenu.targetPageId)
                    }
                }
            }

            MenuSeparator {}

            MenuItem {
                text: "Rename"
                onTriggered: {
                    if (pageContextMenu.targetKind === "notebook") {
                        root.beginRenameNotebook(pageContextMenu.targetNotebookId, pageContextMenu.targetTitle)
                    } else {
                        root.beginRenamePage(pageContextMenu.targetPageId, pageContextMenu.targetTitle)
                    }
                }
            }

            MenuSeparator {}

            MenuItem {
                text: pageContextMenu.targetKind === "notebook" ? "Delete notebook" : "Delete"
                onTriggered: {
                    if (pageContextMenu.targetKind === "notebook") {
                        root.requestDeleteNotebook(pageContextMenu.targetNotebookId, pageContextMenu.targetTitle)
                        return
                    }

                    if (pageModel.count > 1) {
                        root.deletePage(pageContextMenu.targetPageId)
                    }
                }
            }
        }
    }
    } // End ColumnLayout

    Dialog {
        id: deleteNotebookDialog
        objectName: "deleteNotebookDialog"
        title: "Delete notebook?"
        anchors.centerIn: parent
        modal: true
        width: Math.min(360, root.width - 40)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusMedium
        }

        contentItem: ColumnLayout {
            spacing: ThemeManager.spacingLarge

            Text {
                Layout.fillWidth: true
                text: root._pendingDeleteNotebookTitle && root._pendingDeleteNotebookTitle !== ""
                    ? ("Delete \"" + root._pendingDeleteNotebookTitle + "\"?")
                    : "Delete this notebook?"
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                wrapMode: Text.Wrap
            }

            CheckBox {
                id: deleteNotebookDeletePages
                objectName: "deleteNotebookDeletePages"
                text: "Also delete pages in this notebook"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Button {
                    objectName: "deleteNotebookCancelButton"
                    Layout.fillWidth: true
                    text: "Cancel"
                    onClicked: deleteNotebookDialog.close()
                }

                Button {
                    objectName: "deleteNotebookConfirmButton"
                    Layout.fillWidth: true
                    text: "Delete"

                    background: Rectangle {
                        implicitHeight: 40
                        radius: ThemeManager.radiusSmall
                        color: parent.pressed ? "#7a2020" : ThemeManager.danger
                    }

                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        font.pixelSize: ThemeManager.fontSizeNormal
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (DataStore && DataStore.deleteNotebook) {
                            DataStore.deleteNotebook(root._pendingDeleteNotebookId, deleteNotebookDeletePages.checked)
                            loadPagesFromStorage()
                            pagesChanged()
                        }
                        deleteNotebookDialog.close()
                    }
                }
            }
        }
    }
    
    // Public function to reset pages
    function resetToDefaults() {
        createDefaultPages()
        if (pageModel.count > 0) {
            ensureInitialPage("")
        }
    }
}
