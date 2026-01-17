import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property bool collapsed: false
    property bool showNewPageButton: true
    property bool showExpandArrowsAlways: false
    
    signal pageSelected(string pageId, string title)
    signal pagesChanged()
    
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
    
    function ensureInitialPage() {
        // Select first page (pages are already loaded by Component.onCompleted)
        if (pageModel.count > 0) {
            let first = pageModel.get(0)
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
            
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: pageModel
            clip: true
            spacing: 2
        
        delegate: Rectangle {
            id: delegateItem
            width: pageList.width
            height: rowVisible(index) ? (collapsed ? 32 : 28) : 0
            visible: rowVisible(index)
            radius: ThemeManager.radiusSmall
            color: delegateMouseArea.containsMouse ? ThemeManager.surfaceHover : "transparent"
            
            // Background MouseArea for hover and page selection (z = 0)
            MouseArea {
                id: delegateMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                z: 0
                
                onClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        root.pageSelected(model.pageId, model.title)
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
                    visible: delegateMouseArea.containsMouse && !collapsed
                    
                    Rectangle {
                        width: 20
                        height: 20
                        radius: ThemeManager.radiusSmall
                        color: addChildMouse.containsMouse ? ThemeManager.surfaceActive : "transparent"
                        
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
                            onClicked: function(mouse) {
                                root.createPage(model.pageId)
                                mouse.accepted = true
                            }
                        }
                    }
                    
                    Rectangle {
                        width: 20
                        height: 20
                        radius: ThemeManager.radiusSmall
                        color: menuMouse.containsMouse ? ThemeManager.surfaceActive : "transparent"
                        
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
                            onClicked: function(mouse) {
                                pageContextMenu.targetPageId = model.pageId
                                pageContextMenu.targetPageTitle = model.title
                                pageContextMenu.popup()
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Context menu for page actions
    Menu {
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
