import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property bool collapsed: false
    property bool showNewPageButton: true
    property bool showExpandArrowsAlways: false
    property bool actionsAlwaysVisible: false
    property bool activateOnSingleTap: true
    property int actionButtonSize: 20
    property string selectedPageId: ""
    property bool enableContextMenu: true
    
    signal pageSelected(string pageId, string title)
    signal pagesChanged()
    signal pageActivatedByKeyboard(string pageId, string title)

    function indexOfPageId(pageId) {
        if (!pageId || pageId === "") return -1
        for (let i = 0; i < pageModel.count; i++) {
            if (pageModel.get(i).pageId === pageId) return i
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
        const page = pageModel.get(idx)
        if (!page) return false
        root.handleRowTap(page.pageId, page.title)
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
    }

    Connections {
        target: DataStore

        function onPagesChanged() {
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
    
    function createPage(parentId) {
        let id = generateUuid()
        let depth = 0
        let insertIndex = pageModel.count
        
        // Calculate depth based on parent
        if (parentId && parentId !== "") {
            for (let i = 0; i < pageModel.count; i++) {
                let page = pageModel.get(i)
                if (page.pageId === parentId) {
                    depth = page.depth + 1
                    // Find insert position (after parent and its children)
                    insertIndex = i + 1
                    while (insertIndex < pageModel.count && 
                           pageModel.get(insertIndex).depth > page.depth) {
                        insertIndex++
                    }
                    break
                }
            }
        }
        
        pageModel.insert(insertIndex, {
            pageId: id,
            title: "Untitled",
            parentId: parentId || "",
            expanded: true,
            depth: depth
        })
        
        // Save to storage
        savePagesToStorage()
        pagesChanged()
        
        root.selectedPageId = id
        pageSelected(id, "Untitled")
        return id
    }
    
    // Get all pages as a list (for mobile and linking)
    function getAllPages() {
        let pages = []
        for (let i = 0; i < pageModel.count; i++) {
            let p = pageModel.get(i)
            pages.push({ pageId: p.pageId, title: p.title, depth: p.depth, parentId: p.parentId })
        }
        return pages
    }
    
    // Update page title
    function updatePageTitle(pageId, newTitle) {
        for (let i = 0; i < pageModel.count; i++) {
            if (pageModel.get(i).pageId === pageId) {
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
            if (page.pageId === pageId) {
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
        let pages = getAllPages()
        if (DataStore) DataStore.saveAllPages(pages)
    }
    
    function loadPagesFromStorage() {
        try {
            let pages = DataStore ? DataStore.getAllPages() : []
            if (pages && pages.length > 0) {
                pageModel.clear()
                for (let p of pages) {
                    pageModel.append({
                        pageId: p.pageId,
                        title: p.title,
                        parentId: p.parentId || "",
                        expanded: true,
                        depth: p.depth || 0
                    })
                }
                // Recalculate depths based on parentId to fix any corruption
                recalculateDepths()
                return true
            }
        } catch (e) {
            console.log("Error loading pages:", e)
        }
        return false
    }
    
    // Recalculate depths based on parentId relationships
    function recalculateDepths() {
        function getDepth(pageId) {
            if (!pageId || pageId === "") return 0
            for (let i = 0; i < pageModel.count; i++) {
                let p = pageModel.get(i)
                if (p.pageId === pageId) {
                    return getDepth(p.parentId) + 1
                }
            }
            return 0
        }
        
        for (let i = 0; i < pageModel.count; i++) {
            let page = pageModel.get(i)
            let correctDepth = getDepth(page.parentId)
            if (page.depth !== correctDepth) {
                pageModel.setProperty(i, "depth", correctDepth)
            }
        }
    }
    
    // Check if a page has children
    function hasChildren(pageId) {
        for (let i = 0; i < pageModel.count; i++) {
            if (pageModel.get(i).parentId === pageId) {
                return true
            }
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

    function handleRowTap(pageId, title) {
        if (root.activateOnSingleTap || root.selectedPageId === pageId) {
            root.selectedPageId = pageId
            root.pageSelected(pageId, title)
            return
        }
        root.selectedPageId = pageId
    }

    function openContextMenu(pageId, title) {
        if (!root.enableContextMenu) return
        const menu = pageContextMenuLoader.item
        if (!menu) return
        menu.targetPageId = pageId
        menu.targetPageTitle = title
        menu.popup()
    }

    function selectPage(pageId) {
        if (!pageId || pageId === "") return false
        for (let i = 0; i < pageModel.count; i++) {
            const page = pageModel.get(i)
            if (page.pageId === pageId) {
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
        if (pageModel.count > 0) {
            const first = pageModel.get(0)
            root.selectedPageId = first.pageId
            pageSelected(first.pageId, first.title)
        }
    }
    
    function createDefaultPages() {
        if (DataStore) {
            DataStore.seedDefaultPages()
            loadPagesFromStorage()
            return
        }
        pageModel.clear()
        pageModel.append({ pageId: "1", title: "Getting Started", parentId: "", expanded: true, depth: 0 })
        pageModel.append({ pageId: "2", title: "Projects", parentId: "", expanded: true, depth: 0 })
        pageModel.append({ pageId: "3", title: "Work Project", parentId: "2", expanded: true, depth: 1 })
        pageModel.append({ pageId: "4", title: "Personal", parentId: "", expanded: true, depth: 0 })
        savePagesToStorage()
    }
    
    ListModel {
        id: pageModel
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: ThemeManager.spacingSmall
        
        // New Page button at top
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
                    text: "+"
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
        
        ListView {
            id: pageList
            objectName: root.objectName + "_list"

            Layout.fillWidth: true
            Layout.fillHeight: true
            model: pageModel
            clip: true
            spacing: 2

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
                    const hasKids = root.hasChildren(row.pageId)
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
                    const hasKids = root.hasChildren(row.pageId)
                    if (hasKids && row.expanded) {
                        pageModel.setProperty(idx, "expanded", false)
                        return
                    }
                    selectIndex(parentIndex(idx))
                    return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true
                    const idx = pageList.currentIndex >= 0 ? pageList.currentIndex : indexOfPageId(root.selectedPageId)
                    if (idx < 0 || idx >= pageModel.count) return
                    if (!rowVisible(idx)) return
                    const page = pageModel.get(idx)
                    if (!page) return
                    root.handleRowTap(page.pageId, page.title)
                    root.pageActivatedByKeyboard(page.pageId, page.title)
                    return
                }
            }

            delegate: Rectangle {
            id: delegateItem
            objectName: "pageTreeRow_" + index
            width: pageList.width
            height: rowVisible(index) ? (collapsed ? 32 : 28) : 0
            visible: rowVisible(index)
            radius: ThemeManager.radiusSmall
            readonly property bool selected: root.selectedPageId === model.pageId
            readonly property string pageId: model.pageId
            color: selected
                ? ThemeManager.surfaceActive
                : (delegateMouseArea.containsMouse || delegateMouseArea.pressed ? ThemeManager.surfaceHover : "transparent")
            
            // Background MouseArea for hover and page selection (z = 0)
            MouseArea {
                id: delegateMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                z: 0
                
                onClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        root.handleRowTap(model.pageId, model.title)
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
                    width: 18
                    height: 18

                    readonly property bool hasKids: root.hasChildren(model.pageId)
                    readonly property bool showArrow: !collapsed && hasKids &&
                                                     (root.showExpandArrowsAlways || delegateMouseArea.containsMouse)

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
                        text: "📄"
                        font.pixelSize: collapsed ? 14 : 12
                        visible: !parent.showArrow
                    }

                    MouseArea {
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
                Text {
                    Layout.fillWidth: true
                    text: model.title
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideRight
                    visible: !collapsed
                }
                
                // Actions (appear on hover)
                RowLayout {
                    spacing: 2
                    visible: (root.actionsAlwaysVisible || delegateMouseArea.containsMouse) && !collapsed
                    
                    Rectangle {
                        id: addChildButton
                        objectName: "pageTreeAddChildButton_" + index
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
                                root.createPage(model.pageId)
                                mouse.accepted = true
                            }
                        }
                    }
                    
                    Rectangle {
                        id: menuButton
                        objectName: "pageTreeMenuButton_" + index
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
                                root.openContextMenu(model.pageId, model.title)
                                mouse.accepted = true
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
            property string targetPageId: ""
            property string targetPageTitle: ""

            MenuItem {
                text: "Add sub-page"
                onTriggered: root.createPage(pageContextMenu.targetPageId)
            }

            MenuSeparator {}

            MenuItem {
                text: "Delete"
                onTriggered: {
                    if (pageModel.count > 1) {
                        root.deletePage(pageContextMenu.targetPageId)
                    }
                }
            }

            MenuSeparator {}

            MenuItem {
                text: "Reset all pages to defaults"
                onTriggered: {
                    root.createDefaultPages()
                    if (pageModel.count > 0) {
                        let first = pageModel.get(0)
                        root.pageSelected(first.pageId, first.title)
                    }
                }
            }
        }
    }
    } // End ColumnLayout
    
    // Public function to reset pages
    function resetToDefaults() {
        createDefaultPages()
        if (pageModel.count > 0) {
            let first = pageModel.get(0)
            pageSelected(first.pageId, first.title)
        }
    }
}
