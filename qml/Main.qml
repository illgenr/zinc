import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc
import Zinc 1.0
import "components"
import "dialogs"

ApplicationWindow {
    id: root
    
    width: 1200
    height: 800
    minimumWidth: 400
    minimumHeight: 600
    visible: true
    title: currentPage ? currentPage.title + " - Zinc" : "Zinc"
    color: ThemeManager.background
    
    property var currentPage: null
    property bool sidebarCollapsed: false
    property var mobilePagesList: []  // Reactive list for mobile

    property string pagesCursorAt: ""
    property string pagesCursorId: ""
    property string deletedPagesCursorAt: ""
    property string deletedPagesCursorId: ""
    property string attachmentsCursorAt: ""
    property string attachmentsCursorId: ""

    SyncController {
        id: appSyncController

        onError: function(message) {
            console.log("SYNC: error", message)
        }

        onSyncingChanged: console.log("SYNC: syncing=", appSyncController.syncing, "peerCount=", appSyncController.peerCount)
    }
    
    // Detect mobile (Android) vs desktop
    readonly property bool isMobile: Qt.platform.os === "android" || Qt.platform.os === "ios" || width < 600
    
    // Keyboard shortcuts (desktop)
    Shortcut {
        sequence: "Ctrl+N"
        enabled: !isMobile
        onActivated: pageTree.createPage("")
    }
    
    Shortcut {
        sequence: "Ctrl+P"
        enabled: !isMobile
        onActivated: searchDialog.open()
    }
    
    Shortcut {
        sequence: "Ctrl+\\"
        enabled: !isMobile
        onActivated: sidebarCollapsed = !sidebarCollapsed
    }

    ShortcutsDialog {
        id: shortcutsDialog
    }

    Shortcut {
        enabled: !isMobile
        context: Qt.ApplicationShortcut
        sequences: ["Ctrl+Shift+?", "Ctrl+Shift+/"]
        onActivated: shortcutsDialog.open()
    }
    
    // Mobile layout using StackView
    StackView {
        id: mobileStack
        anchors.fill: parent
        visible: isMobile
        initialItem: mobileNotesListComponent
        
        // Handle Android back button
        Keys.onBackPressed: function(event) {
            if (mobileStack.depth > 1) {
                mobileStack.pop()
                event.accepted = true
            }
        }
    }
    
    // Mobile notes list page
    Component {
        id: mobileNotesListComponent
        
        Page {
            background: Rectangle { color: ThemeManager.background }
            
            header: ToolBar {
                background: Rectangle { 
                    color: ThemeManager.surface 
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: ThemeManager.border
                    }
                }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    
                    Rectangle {
                        width: 32
                        height: 32
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.accent
                        
                        Text {
                            anchors.centerIn: parent
                            text: "Z"
                            color: "white"
                            font.pixelSize: ThemeManager.fontSizeLarge
                            font.bold: true
                        }
                    }
                    
                    Text {
                        Layout.fillWidth: true
                        text: "My Notes"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeXLarge
                        font.weight: Font.Medium
                    }
                    
                    ToolButton {
                        icon.name: "settings"
                        contentItem: Text {
                            text: "⚙"
                            color: ThemeManager.text
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.surfaceActive : "transparent"
                        }
                        onClicked: settingsDialog.open()
                    }
                }
            }
            
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                
                // Search bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    Layout.margins: ThemeManager.spacingMedium
                    radius: ThemeManager.radiusMedium
                    color: ThemeManager.surfaceHover
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: ThemeManager.spacingSmall
                        
                        Text {
                            text: "🔍"
                            font.pixelSize: ThemeManager.fontSizeNormal
                        }
                        
                        Text {
                            Layout.fillWidth: true
                            text: "Search notes..."
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeNormal
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: searchDialog.open()
                    }
                }

                Button {
                    Layout.fillWidth: true
                    Layout.margins: ThemeManager.spacingMedium
                    text: "+ New Page"

                    background: Rectangle {
                        implicitHeight: 44
                        radius: ThemeManager.radiusSmall
                        color: parent.pressed ? ThemeManager.accentHover : ThemeManager.accent
                    }

                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        font.pixelSize: ThemeManager.fontSizeNormal
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        mobilePageTree.createPage("")
                    }
                }
                
                // Notes list
                PageTree {
                    id: mobilePageTree
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    showNewPageButton: false
                    showExpandArrowsAlways: true

                    onPageSelected: function(pageId, title) {
                        root.currentPage = { id: pageId, title: title }
                        mobileStack.push(mobileEditorComponent)
                    }
                }
            }
            
            // Floating action button
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: ThemeManager.spacingLarge
                width: 56
                height: 56
                radius: 28
                color: fabMouse.pressed ? ThemeManager.accentHover : ThemeManager.accent
                
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "white"
                    font.pixelSize: 28
                    font.weight: Font.Light
                }
                
                MouseArea {
                    id: fabMouse
                    anchors.fill: parent
                    onClicked: {
                        // Create new page using pageTree and navigate to it
                        mobilePageTree.createPage("")
                        // pageTree will emit pageSelected which we handle
                    }
                }
                
                layer.enabled: true
                layer.effect: Item {} // Simple shadow placeholder
            }
        }
    }
    
    // Mobile editor page
    Component {
        id: mobileEditorComponent
        
        Page {
            background: Rectangle { color: ThemeManager.background }
            
            header: ToolBar {
                background: Rectangle { 
                    color: ThemeManager.surface
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: ThemeManager.border
                    }
                }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    
                    ToolButton {
                        contentItem: Text {
                            text: "←"
                            color: ThemeManager.text
                            font.pixelSize: 24
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.surfaceActive : "transparent"
                        }
                        onClicked: mobileStack.pop()
                    }
                    
                    Text {
                        Layout.fillWidth: true
                        text: root.currentPage ? root.currentPage.title : "Note"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeLarge
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    
                    ToolButton {
                        contentItem: Text {
                            text: "⋯"
                            color: ThemeManager.text
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.surfaceActive : "transparent"
                        }
                    }
                }
            }
            
            BlockEditor {
                id: mobileBlockEditor
                anchors.fill: parent
                pageTitle: root.currentPage ? root.currentPage.title : ""
                availablePages: pageTree.getAllPages()
                
                Component.onCompleted: {
                    if (root.currentPage) {
                        loadPage(root.currentPage.id)
                    }
                }
                
                onTitleEdited: function(newTitle) {
                    if (root.currentPage) {
                        root.currentPage.title = newTitle
                        pageTree.updatePageTitle(root.currentPage.id, newTitle)
                    }
                }

                onShowPagePicker: function(blockIndex) {
                    mobilePagePickerDialog.pages = pageTree.getAllPages()
                    mobilePagePickerDialog.open()
                    mobilePagePickerDialog._targetEditor = mobileBlockEditor
                }

                onNavigateToPage: function(targetPageId) {
                    if (!targetPageId || targetPageId === "") return
                    var page = DataStore ? DataStore.getPage(targetPageId) : null
                    var title = page && page.title ? page.title : "Untitled"
                    root.currentPage = { id: targetPageId, title: title }
                    mobileBlockEditor.loadPage(targetPageId)
                }

                onCreateChildPageRequested: function(title, blockIndex) {
                    if (!title || title === "") return
                    var newId = pageTree.createPage(mobileBlockEditor.pageId)
                    if (!newId || newId === "") return
                    pageTree.updatePageTitle(newId, title)
                    mobileBlockEditor.setLinkAtIndex(blockIndex, newId, title)
                }
            }
            
            PagePickerDialog {
                id: mobilePagePickerDialog
                parent: Overlay.overlay
                visible: false

                property var _targetEditor: null

                onPageSelected: function(pageId, pageTitle) {
                    if (_targetEditor) {
                        _targetEditor.setLinkTarget(pageId, pageTitle)
                    }
                }
            }
        }
    }
    
    // Desktop layout using SplitView
    SplitView {
        anchors.fill: parent
        orientation: Qt.Horizontal
        visible: !isMobile
        
        handle: Rectangle {
            implicitWidth: 1
            color: ThemeManager.border
        }
        
        // Sidebar
        Rectangle {
            id: sidebar
            
            SplitView.preferredWidth: sidebarCollapsed ? ThemeManager.sidebarCollapsedWidth : ThemeManager.sidebarWidth
            SplitView.minimumWidth: ThemeManager.sidebarCollapsedWidth
            SplitView.maximumWidth: 400
            
            color: ThemeManager.surface
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingSmall
                spacing: ThemeManager.spacingSmall
                
                // Workspace header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall
                    
                    Rectangle {
                        width: 28
                        height: 28
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.accent
                        
                        Text {
                            anchors.centerIn: parent
                            text: "Z"
                            color: "white"
                            font.pixelSize: ThemeManager.fontSizeLarge
                            font.bold: true
                        }
                    }
                    
                    Text {
                        Layout.fillWidth: true
                        text: "My Notes"
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        visible: !sidebarCollapsed
                    }
                    
                    ToolButton {
                        width: 24
                        height: 24
                        visible: !sidebarCollapsed
                        
                        contentItem: Text {
                            text: "⚙"
                            color: ThemeManager.textSecondary
                            font.pixelSize: ThemeManager.fontSizeNormal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.hovered ? ThemeManager.surfaceHover : "transparent"
                        }
                        
                        onClicked: settingsDialog.open()
                    }
                }
                
                // Search button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: ThemeManager.radiusMedium
                    color: ThemeManager.surfaceHover
                    visible: !sidebarCollapsed
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: ThemeManager.spacingSmall
                        anchors.rightMargin: ThemeManager.spacingSmall
                        
                        Text {
                            text: "🔍"
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                        
                        Text {
                            Layout.fillWidth: true
                            text: "Search"
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                        
                        Text {
                            text: "Ctrl+P"
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchDialog.open()
                    }
                }
                
                // Page tree
                PageTree {
                    id: pageTree
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !sidebarCollapsed
                    
                    onPageSelected: function(pageId, title) {
                        root.currentPage = { id: pageId, title: title }
                        if (isMobile) {
                            mobileStack.push(mobileEditorComponent)
                        } else {
                            blockEditor.loadPage(pageId)
                        }
                    }
                    
                    onPagesChanged: {
                        root.mobilePagesList = pageTree.getAllPages()
                    }
                }
                
                // Collapsed sidebar icon
                Item {
                    Layout.fillHeight: true
                    visible: sidebarCollapsed
                }
            }
        }
        
        // Main content
        Rectangle {
            SplitView.fillWidth: true
            color: ThemeManager.background
            
            BlockEditor {
                id: blockEditor
                anchors.fill: parent
                pageTitle: currentPage ? currentPage.title : ""
                availablePages: pageTree.getAllPages()

                onTitleEdited: function(newTitle) {
                    if (currentPage) {
                        currentPage.title = newTitle
                        pageTree.updatePageTitle(currentPage.id, newTitle)
                    }
                }

                onShowPagePicker: function(blockIndex) {
                    pagePickerDialog.pages = pageTree.getAllPages()
                    pagePickerDialog.open()
                    pagePickerDialog._targetEditor = blockEditor
                }

                onNavigateToPage: function(targetPageId) {
                    if (!targetPageId || targetPageId === "") return
                    var page = DataStore ? DataStore.getPage(targetPageId) : null
                    var title = page && page.title ? page.title : "Untitled"
                    root.currentPage = { id: targetPageId, title: title }
                    blockEditor.loadPage(targetPageId)
                }

                onCreateChildPageRequested: function(title, blockIndex) {
                    if (!title || title === "") return
                    var newId = pageTree.createPage(blockEditor.pageId)
                    if (!newId || newId === "") return
                    pageTree.updatePageTitle(newId, title)
                    blockEditor.setLinkAtIndex(blockIndex, newId, title)
                }
            }
        }
    }
    
    // Dialogs
    SearchDialog {
        id: searchDialog
        
        onResultSelected: function(pageId, blockId) {
            if (isMobile) {
                root.currentPage = { id: pageId, title: "Note" }
                mobileStack.push(mobileEditorComponent)
            } else {
                blockEditor.loadPage(pageId)
                if (blockId) {
                    blockEditor.scrollToBlock(blockId)
                }
            }
        }
    }
    
    PairingDialog {
        id: pairingDialog
        externalSyncController: appSyncController
    }
    
    PagePickerDialog {
        id: pagePickerDialog
        parent: Overlay.overlay
        visible: false

        property var _targetEditor: null

        onPageSelected: function(pageId, pageTitle) {
            if (_targetEditor) {
                _targetEditor.setLinkTarget(pageId, pageTitle)
            }
        }
    }
    
    SettingsDialog {
        id: settingsDialog
        syncController: appSyncController
        
        onPairDeviceRequested: {
            pairingDialog.open()
        }
    }
    
    // UUID generator
    function generateUuid() {
        function s4() {
            return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        }
        return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4()
    }
    
    // Initial page (desktop only)
    Component.onCompleted: {
        if (DataStore) {
            DataStore.initialize()
        }
        tryStartSync()
        if (isMobile && DataStore) {
            root.mobilePagesList = DataStore.getAllPages()
        }
        // Pages are loaded by PageTree's Component.onCompleted
        // Just need to select the first page for desktop
        if (!isMobile) {
            pageTree.ensureInitialPage()
        }
        // Mobile list is updated via pagesChanged signal
    }

    Connections {
        target: DataStore

        function onPagesChanged() {
            if (isMobile) {
                Qt.callLater(function() {
                    root.mobilePagesList = DataStore.getAllPages()
                })
            }
            root.scheduleOutgoingSnapshot()
        }
    }

    Connections {
        target: DataStore

        function onAttachmentsChanged() {
            root.scheduleOutgoingSnapshot()
        }
    }

    Connections {
        target: appSyncController

        function onPeerDiscovered(deviceId, deviceName, workspaceId, host, port) {
            if (!DataStore) return
            if (!deviceId || !workspaceId) return
            if (host && host !== "" && port && port > 0) {
                DataStore.updatePairedDeviceEndpoint(deviceId, host, port)
            }
        }

        function onPeerConnected(deviceId) {
            pagesCursorAt = ""
            pagesCursorId = ""
            deletedPagesCursorAt = ""
            deletedPagesCursorId = ""
            attachmentsCursorAt = ""
            attachmentsCursorId = ""
            root.sendLocalSnapshot(true)
        }

        function onAttachmentSnapshotReceivedAttachments(attachments) {
            if (!DataStore || !attachments) return
            console.log("SYNC: received attachments", attachments.length)
            DataStore.applyAttachmentUpdates(attachments)
        }

        function onPageSnapshotReceivedPages(pages) {
            if (!DataStore || !pages) return
            console.log("SYNC: received pages", pages.length)
            DataStore.applyPageUpdates(pages)
        }

        function onDeletedPageSnapshotReceivedPages(deletedPages) {
            if (!DataStore || !deletedPages) return
            console.log("SYNC: received deleted pages", deletedPages.length)
            DataStore.applyDeletedPageUpdates(deletedPages)
        }

        function onBlockSnapshotReceivedBlocks(blocks) {
            if (!DataStore || !blocks) return
            console.log("SYNC: received blocks", blocks.length)
            DataStore.applyBlockUpdates(blocks)
        }
    }

    Timer {
        id: outgoingSnapshotTimer
        interval: 200
        repeat: false
        onTriggered: root.sendLocalSnapshot(false)
    }

    function scheduleOutgoingSnapshot() {
        outgoingSnapshotTimer.restart()
    }

    function advanceCursorFrom(items, cursorAtKey, cursorIdKey, cursorAtField, idField) {
        var cursorAt = root[cursorAtKey]
        var cursorId = root[cursorIdKey]
        for (var i = 0; i < items.length; i++) {
            var entry = items[i]
            var updatedAt = entry[cursorAtField] || ""
            var entryId = entry[idField] || ""
            if (cursorAt === "" || updatedAt > cursorAt || (updatedAt === cursorAt && entryId > cursorId)) {
                cursorAt = updatedAt
                cursorId = entryId
            }
        }
        root[cursorAtKey] = cursorAt
        root[cursorIdKey] = cursorId
    }

    function collectAttachmentIdsFromPages(pages) {
        var unique = {}
        var out = []
        if (!pages) return out
        var re = new RegExp("image://attachments/([0-9a-fA-F-]{36})", "g")
        for (var i = 0; i < pages.length; i++) {
            var p = pages[i] || {}
            var md = p.contentMarkdown || ""
            var m
            while ((m = re.exec(md)) !== null) {
                var id = m[1] || ""
                if (id !== "" && !unique[id]) {
                    unique[id] = true
                    out.push(id)
                }
            }
        }
        return out
    }

    function mergeAttachments(primaryList, extraList) {
        var seen = {}
        var out = []
        function add(list) {
            if (!list) return
            for (var i = 0; i < list.length; i++) {
                var entry = list[i] || {}
                var id = entry.attachmentId || entry.id || ""
                if (id === "" || seen[id]) continue
                seen[id] = true
                out.push(entry)
            }
        }
        add(primaryList)
        add(extraList)
        return out
    }

    function sendLocalSnapshot(full) {
        if (!DataStore || !appSyncController) return
        if (!appSyncController.syncing) return
        if (appSyncController.peerCount <= 0) return

        var pages = full ? DataStore.getPagesForSync()
                         : DataStore.getPagesForSyncSince(pagesCursorAt, pagesCursorId)
        var deletedPages = full ? DataStore.getDeletedPagesForSync()
                                : DataStore.getDeletedPagesForSyncSince(deletedPagesCursorAt, deletedPagesCursorId)
        var attachments = full ? DataStore.getAttachmentsForSync()
                               : DataStore.getAttachmentsForSyncSince(attachmentsCursorAt, attachmentsCursorId)
        if (!full && DataStore.getAttachmentsByIds) {
            var neededIds = collectAttachmentIdsFromPages(pages)
            if (neededIds.length > 0) {
                attachments = mergeAttachments(attachments, DataStore.getAttachmentsByIds(neededIds))
            }
        }
        if (!full && (!pages || pages.length === 0) &&
            (!deletedPages || deletedPages.length === 0) &&
            (!attachments || attachments.length === 0)) {
            return
        }

        var payload = JSON.stringify({
            v: 2,
            workspaceId: appSyncController.workspaceId,
            full: full === true,
            pages: pages,
            deletedPages: deletedPages,
            attachments: attachments
        })
        console.log("SYNC: sending snapshot full=", full === true, "pages", pages.length, "deleted", deletedPages.length, "attachments", attachments.length)
        appSyncController.sendPageSnapshot(payload)

        advanceCursorFrom(pages, "pagesCursorAt", "pagesCursorId", "updatedAt", "pageId")
        advanceCursorFrom(deletedPages, "deletedPagesCursorAt", "deletedPagesCursorId", "deletedAt", "pageId")
        advanceCursorFrom(attachments, "attachmentsCursorAt", "attachmentsCursorId", "updatedAt", "attachmentId")
    }

    function tryStartSync() {
        if (!appSyncController) return
        if (appSyncController.syncing) return

        // Prefer persisted workspace id.
        if (appSyncController.tryAutoStart("Zinc Device")) {
            console.log("SYNC: auto-started from settings")
            return
        }

        // Fallback: infer workspace id from previously paired devices.
        if (DataStore) {
            var devices = DataStore.getPairedDevices()
            if (devices && devices.length > 0) {
                var wsId = devices[0].workspaceId
                if (wsId && wsId !== "") {
                    if (appSyncController.configure(wsId, "Zinc Device")) {
                        appSyncController.startSync()
                        console.log("SYNC: started from paired devices workspaceId", wsId)
                    }
                }
            }
        }
    }

    // Opportunistic direct reconnect to paired endpoints (useful when discovery is slow/unavailable).
    Timer {
        id: syncReconnectTimer
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            tryStartSync()
            if (!DataStore || !appSyncController) return
            if (!appSyncController.syncing) return
            if (appSyncController.peerCount > 0) return

            var devices = DataStore.getPairedDevices()
            for (var i = 0; i < devices.length; i++) {
                var d = devices[i]
                if (!d) continue
                if (!d.deviceId || !d.host || !d.port) continue
                if (d.port <= 0) continue
                if (d.workspaceId && d.workspaceId !== "" && d.workspaceId !== appSyncController.workspaceId) continue
                appSyncController.connectToPeer(d.deviceId, d.host, d.port)
            }
        }
    }
    
    // Handle Android back button
    onClosing: function(close) {
        if (isMobile && mobileStack.depth > 1) {
            close.accepted = false
            mobileStack.pop()
        }
    }
}
