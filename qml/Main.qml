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
    property bool startupPageAppliedDesktop: false
    property bool startupPageAppliedMobile: false
    property var pendingStartupCursorHint: null
    property int pendingSearchBlockIndex: -1
    readonly property bool debugSyncUi: Qt.application.arguments.indexOf("--debug-sync-ui") !== -1
    property int suppressOutgoingSnapshots: 0
    property var pendingCursorPersist: null
    property int editorMode: 0 // 0=hybrid, 1=plaintext markdown

    property string pagesCursorAt: ""
    property string pagesCursorId: ""
    property string deletedPagesCursorAt: ""
    property string deletedPagesCursorId: ""
    property string notebooksCursorAt: ""
    property string notebooksCursorId: ""
    property string deletedNotebooksCursorAt: ""
    property string deletedNotebooksCursorId: ""
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
    readonly property bool syncDisabled: Qt.application.arguments.indexOf("--no-sync") !== -1
    readonly property bool databaseActive: DataStore && DataStore.schemaVersion >= 0

    Connections {
        target: DataStore

        function onSchemaVersionChanged() {
            if (!DataStore || DataStore.schemaVersion >= 0) return
            root.currentPage = null
            root.pendingStartupCursorHint = null
            root.pendingSearchBlockIndex = -1
            if (pageTree) pageTree.selectedPageId = ""
            if (mobilePageTree) mobilePageTree.selectedPageId = ""
            if (blockEditor && blockEditor.clearPage) blockEditor.clearPage()
            if (markdownEditor && markdownEditor.clearPage) markdownEditor.clearPage()
            if (mobileStack && mobileStack.depth > 1) {
                while (mobileStack.depth > 1) mobileStack.pop()
            }
        }
    }
    
    // Keyboard shortcuts (desktop)
    Shortcut {
        sequence: "Ctrl+N"
        enabled: !isMobile && root.databaseActive
        context: Qt.ApplicationShortcut
        onActivated: pageTree.createPage("")
    }
    
    Shortcut {
        sequence: "Ctrl+F"
        enabled: !isMobile
        context: Qt.ApplicationShortcut
        onActivated: searchDialog.open()
    }
    
    Shortcut {
        sequence: "Ctrl+\\"
        enabled: !isMobile
        onActivated: sidebarCollapsed = !sidebarCollapsed
    }

    Shortcut {
        enabled: !isMobile
        context: Qt.ApplicationShortcut
        sequence: "Ctrl+E"
        onActivated: {
            sidebarCollapsed = false
            pageTree.focusTree()
        }
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

    Shortcut {
        enabled: !isMobile
        context: Qt.ApplicationShortcut
        sequence: "Ctrl+End"
        onActivated: {
            if (blockEditor && blockEditor.focusDocumentEnd) {
                blockEditor.focusDocumentEnd()
            }
        }
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
                    height: 48
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
                        Layout.alignment: Qt.AlignVCenter
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
                        Layout.alignment: Qt.AlignVCenter
                    }

                    SyncButtons {
                        Layout.alignment: Qt.AlignVCenter
                        autoSyncEnabled: SyncPreferences.autoSyncEnabled
                        compact: false
                        onManualSyncRequested: root.requestManualSync()
                        onSettingsRequested: settingsDialog.open()
                    }
                }
            }
            
            ColumnLayout {
                anchors.fill: parent                                
                spacing: ThemeManager.spacingSmall

                MobileSidebarActions {
                    Layout.fillWidth: true
                    Layout.margins: ThemeManager.spacingSmall
                    sortMode: mobilePageTree.sortMode
                    canCreate: root.databaseActive

                    onNewPageRequested: mobilePageTree.createPage("")
                    onFindRequested: searchDialog.open()
                    onNewNotebookRequested: mobilePageTree.beginNewNotebook()
                    onSortModeRequested: function(mode) { mobilePageTree.sortMode = mode }
                }

                // Notes list
                PageTree {
                    id: mobilePageTree
                    objectName: "mobilePageTree"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    showNewPageButton: false
                    showNewNotebookButton: false
                    showSortButton: false
                    showExpandArrowsAlways: true
                    actionsAlwaysVisible: true
                    actionButtonSize: 44
                    activateOnSingleTap: false

                    onNewNotebookRequested: mobilePageTree.beginNewNotebook()

                    onPageSelected: function(pageId, title) {
                        if (DataStore) DataStore.setLastViewedPageId(pageId)
                        root.currentPage = { id: pageId, title: title }
                        mobileStack.push(mobileEditorComponent)
                    }
                }

                Connections {
                    target: mobilePageTree
                    function onPagesChanged() {
                        root.applyStartupPageMobile()
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
                enabled: root.databaseActive
                pageTitle: root.currentPage ? root.currentPage.title : ""
                availablePages: pageTree.getAllPages()
                realtimeSyncEnabled: root.bothAutoSyncEnabled
                debugSyncUi: root.debugSyncUi
                showRemoteCursor: root.bothAutoSyncEnabled
                remoteCursorPageId: appSyncController ? appSyncController.remoteCursorPageId : ""
                remoteCursorBlockIndex: appSyncController ? appSyncController.remoteCursorBlockIndex : -1
                remoteCursorPos: appSyncController ? appSyncController.remoteCursorPos : -1
                
                Component.onCompleted: {
                    if (root.currentPage) {
                        loadPage(root.currentPage.id)
                        Qt.callLater(function() {
                            if (root.pendingSearchBlockIndex >= 0) {
                                mobileBlockEditor.revealSearchBlockIndex(root.pendingSearchBlockIndex)
                                root.pendingSearchBlockIndex = -1
                            }
                            root.applyPendingStartupFocusIfAny(mobileBlockEditor, root.currentPage.id)
                        })
                    }
                }
                
                onTitleEdited: function(newTitle) {
                    if (root.currentPage) {
                        root.currentPage.title = newTitle
                    }
                }

                onTitleEditingFinished: function(pageId, newTitle) {
                    if (!pageId || pageId === "") return
                    pageTree.updatePageTitle(pageId, newTitle)
                }

                onExternalLinkRequested: function(url) {
                    if (!url || url === "") return
                    Qt.openUrlExternally(url)
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
                    var newId = pageTree.createPage(mobileBlockEditor.pageId, { selectAfterCreate: false })
                    if (!newId || newId === "") return
                    pageTree.updatePageTitle(newId, title)
                    mobileBlockEditor.setLinkAtIndex(blockIndex, newId, title)
                    if (GeneralPreferences.jumpToNewPageOnCreate) {
                        pageTree.selectPage(newId)
                    }
                }

                onCreateChildPageInlineRequested: function(title, blockIndex, replaceStart, replaceEnd) {
                    if (!title || title === "") return
                    var newId = pageTree.createPage(mobileBlockEditor.pageId, { selectAfterCreate: false })
                    if (!newId || newId === "") return
                    pageTree.updatePageTitle(newId, title)
                    if (mobileBlockEditor && mobileBlockEditor.insertPageLinkAt) {
                        mobileBlockEditor.insertPageLinkAt(blockIndex, replaceStart, replaceEnd, newId, title)
                    }
                    if (GeneralPreferences.jumpToNewPageOnCreate) {
                        pageTree.selectPage(newId)
                    }
                }

                onCursorMoved: function(blockIndex, cursorPos) {
                    const pageId = mobileBlockEditor.pageId
                    if (root.localCursorPageId === pageId &&
                        root.localCursorBlockIndex === blockIndex &&
                        root.localCursorPos === cursorPos) {
                        return
                    }
                    root.localCursorPageId = pageId
                    root.localCursorBlockIndex = blockIndex
                    root.localCursorPos = cursorPos
                    root.scheduleCursorPersist(pageId, blockIndex, cursorPos)
                    presenceTimer.restart()
                }

                onContentSaved: function(pageId) {
                    if (root.debugSyncUi) console.log("SYNCUI: mobileBlockEditor contentSaved -> scheduleOutgoingSnapshot pageId=", pageId)
                    root.scheduleOutgoingSnapshot()
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
        
        handle: Item {
            implicitWidth: 8
            Rectangle {
                width: 1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: ThemeManager.border
            }
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
                    
                    SyncButtons {
                        visible: !sidebarCollapsed
                        autoSyncEnabled: SyncPreferences.autoSyncEnabled
                        compact: true
                        onManualSyncRequested: root.requestManualSync()
                        onSettingsRequested: settingsDialog.open()
                    }

	                    ToolButton {
	                        objectName: "sidebarToggleButton"
	                        width: 24
	                        height: 24

	                        contentItem: Text {
	                            text: sidebarCollapsed ? "⟩" : "⟨"
	                            color: ThemeManager.textSecondary
	                            font.pixelSize: ThemeManager.fontSizeNormal
	                            horizontalAlignment: Text.AlignHCenter
	                            verticalAlignment: Text.AlignVCenter
	                        }

	                        background: Rectangle {
	                            radius: ThemeManager.radiusSmall
	                            color: parent.hovered ? ThemeManager.surfaceHover : "transparent"
	                        }

	                        ToolTip.visible: hovered
	                        ToolTip.text: sidebarCollapsed
	                            ? "Expand sidebar (Ctrl+\\)"
	                            : "Collapse sidebar (Ctrl+\\)"

	                        Accessible.name: sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"

	                        onClicked: sidebarCollapsed = !sidebarCollapsed
	                    }
                }
                
                DesktopSidebarActions {
                    Layout.fillWidth: true
                    collapsed: sidebarCollapsed
                    sortMode: pageTree.sortMode
                    canCreate: root.databaseActive

                    onNewPageRequested: pageTree.createPage("")
                    onFindRequested: searchDialog.open()
                    onNewNotebookRequested: pageTree.beginNewNotebook()
                    onSortModeRequested: function(mode) { pageTree.sortMode = mode }
                }

                // Page tree
                PageTree {
                    id: pageTree
                    objectName: "pageTree"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !sidebarCollapsed
                    showNewPageButton: false
                    showNewNotebookButton: false
                    showSortButton: false

                    onNewNotebookRequested: mobilePageTree.beginNewNotebook()

                    onPageActivatedByKeyboard: function(pageId, title) {
                        Qt.callLater(() => blockEditor.focusContent())
                    }
                    
                    onPageSelected: function(pageId, title) {
                        if (DataStore) DataStore.setLastViewedPageId(pageId)
                        root.currentPage = { id: pageId, title: title }
                        if (isMobile) {
                            mobileStack.push(mobileEditorComponent)
                        } else {
                            root.loadCurrentPageInActiveEditor(pageId)
                        }
                    }
                    
                    onPagesChanged: {
                        root.mobilePagesList = pageTree.getAllPages()
                    }
                }

                Connections {
                    target: pageTree
                    function onPagesChanged() {
                        root.applyStartupPageDesktop()
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

            Item {
                anchors.fill: parent

                StackLayout {
                    id: editorStack
                    anchors.fill: parent
                    currentIndex: root.editorMode === 1 ? 1 : 0

                    BlockEditor {
                        id: blockEditor
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: root.databaseActive
                        pageTitle: currentPage ? currentPage.title : ""
                        availablePages: pageTree.getAllPages()
                        realtimeSyncEnabled: root.bothAutoSyncEnabled
                        debugSyncUi: root.debugSyncUi
                        showRemoteCursor: root.bothAutoSyncEnabled
                        remoteCursorPageId: appSyncController ? appSyncController.remoteCursorPageId : ""
                        remoteCursorBlockIndex: appSyncController ? appSyncController.remoteCursorBlockIndex : -1
                        remoteCursorPos: appSyncController ? appSyncController.remoteCursorPos : -1

                        onTitleEdited: function(newTitle) {
                            if (currentPage) {
                                currentPage.title = newTitle
                            }
                        }

                        onTitleEditingFinished: function(pageId, newTitle) {
                            if (!pageId || pageId === "") return
                            pageTree.updatePageTitle(pageId, newTitle)
                        }

                        onExternalLinkRequested: function(url) {
                            if (!url || url === "") return
                            Qt.openUrlExternally(url)
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
                            if (DataStore) DataStore.setLastViewedPageId(targetPageId)
                            root.currentPage = { id: targetPageId, title: title }
                            root.loadCurrentPageInActiveEditor(targetPageId)
                        }

                        onCreateChildPageRequested: function(title, blockIndex) {
                            if (!title || title === "") return
                            var newId = pageTree.createPage(blockEditor.pageId, { selectAfterCreate: false })
                            if (!newId || newId === "") return
                            pageTree.updatePageTitle(newId, title)
                            blockEditor.setLinkAtIndex(blockIndex, newId, title)
                            if (GeneralPreferences.jumpToNewPageOnCreate) {
                                pageTree.selectPage(newId)
                            }
                        }

                        onCreateChildPageInlineRequested: function(title, blockIndex, replaceStart, replaceEnd) {
                            if (!title || title === "") return
                            var newId = pageTree.createPage(blockEditor.pageId, { selectAfterCreate: false })
                            if (!newId || newId === "") return
                            pageTree.updatePageTitle(newId, title)
                            if (blockEditor && blockEditor.insertPageLinkAt) {
                                blockEditor.insertPageLinkAt(blockIndex, replaceStart, replaceEnd, newId, title)
                            }
                            if (GeneralPreferences.jumpToNewPageOnCreate) {
                                pageTree.selectPage(newId)
                            }
                        }

                        onCursorMoved: function(blockIndex, cursorPos) {
                            const pageId = blockEditor.pageId
                            if (root.localCursorPageId === pageId &&
                                root.localCursorBlockIndex === blockIndex &&
                                root.localCursorPos === cursorPos) {
                                return
                            }
                            root.localCursorPageId = pageId
                            root.localCursorBlockIndex = blockIndex
                            root.localCursorPos = cursorPos
                            root.scheduleCursorPersist(pageId, blockIndex, cursorPos)
                            presenceTimer.restart()
                        }

                        onContentSaved: function(pageId) {
                            if (root.debugSyncUi) console.log("SYNCUI: blockEditor contentSaved -> scheduleOutgoingSnapshot pageId=", pageId)
                            root.scheduleOutgoingSnapshot()
                        }
                    }

                    MarkdownEditor {
                        id: markdownEditor
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        enabled: root.databaseActive
                        pageTitle: currentPage ? currentPage.title : ""
                        availablePages: pageTree.getAllPages()

                        onTitleEdited: function(newTitle) {
                            if (currentPage) {
                                currentPage.title = newTitle
                            }
                        }

                        onTitleEditingFinished: function(pageId, newTitle) {
                            if (!pageId || pageId === "") return
                            pageTree.updatePageTitle(pageId, newTitle)
                        }
                    }
                }

                ToolButton {
                    id: editorModeToggleButton
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: ThemeManager.spacingSmall
                    text: root.editorModeToggleLabel()
                    enabled: root.databaseActive && root.currentPage !== null
                    onClicked: root.switchEditorMode()
                }
            }
        }
    }
    
    // Dialogs
    SearchDialog {
        id: searchDialog
        
        onResultSelected: function(pageId, blockId, blockIndex) {
            if (DataStore) DataStore.setLastViewedPageId(pageId)
            root.pendingSearchBlockIndex = blockIndex
            if (isMobile) {
                root.currentPage = { id: pageId, title: "Note" }
                mobileStack.push(mobileEditorComponent)
            } else {
                root.loadCurrentPageInActiveEditor(pageId)
                Qt.callLater(function() {
                    if (root.editorMode === 0 && blockEditor) {
                        if (blockIndex >= 0) {
                            blockEditor.revealSearchBlockIndex(blockIndex)
                        } else if (blockId) {
                            blockEditor.scrollToBlock(blockId)
                        }
                    }
                    root.pendingSearchBlockIndex = -1
                })
            }
        }
    }
    
    PairingDialog {
        id: pairingDialog
        externalSyncController: appSyncController
        onAddViaHostnameRequested: {
            settingsDialog.open()
            settingsDialog.openDevicesTab()
            Qt.callLater(function() { settingsDialog.openManualAddDialog() })
        }
    }

    property var pendingPairByHostname: null
    property var pendingSyncConflicts: []
    property var blockedReconnectUntilByDeviceId: ({})
    property var repairPromptedUntilByDeviceId: ({})

    function showSyncConflict(conflict) {
        if (!conflict || !conflict.pageId) return
        if (syncConflictDialog.visible) {
            pendingSyncConflicts.push(conflict)
            return
        }
        syncConflictDialog.conflict = conflict
        syncConflictDialog.open()
    }

    readonly property bool bothAutoSyncEnabled: SyncPreferences.autoSyncEnabled &&
                                               appSyncController &&
                                               appSyncController.remoteAutoSyncEnabled

    SyncConflictDialog {
        id: syncConflictDialog
        parent: Overlay.overlay

        onClosed: {
            if (pendingSyncConflicts.length <= 0) return
            var next = pendingSyncConflicts.shift()
            if (next) {
                syncConflictDialog.conflict = next
                syncConflictDialog.open()
            }
        }
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

        onManualDeviceAddRequested: function(host, port) {
            if (!appSyncController) return
            const h = host ? host.trim() : ""
            const p = port && port > 0 ? port : 47888
            if (h === "") return
            console.log("SYNCUI: manual add requested host=", h, "port=", p)
            pendingPairByHostname = { host: h, port: p, startedAt: Date.now() }
            if (appSyncController.pairToHostWithPort) {
                appSyncController.pairToHostWithPort(h, p)
            } else {
                appSyncController.connectToHostWithPort(h, p)
            }
        }
    }

    Dialog {
        id: repairRequiredDialog
        parent: Overlay.overlay
        modal: true
        title: "Re-pair Required"
        standardButtons: Dialog.NoButton

        property string pairedDeviceId: ""
        property string details: ""
        property bool canRemovePairing: false

        onClosed: {
            pairedDeviceId = ""
            details = ""
            canRemovePairing = false
        }

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: Item {
            implicitWidth: 420
            implicitHeight: contentLayout.implicitHeight + ThemeManager.spacingMedium * 2

            ColumnLayout {
                id: contentLayout
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium

                Text {
                    Layout.fillWidth: true
                    text: repairRequiredDialog.details !== "" ? repairRequiredDialog.details
                                                          : "This device and the peer are not in the same workspace or the peer was reset. Re-pairing is required."
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    wrapMode: Text.Wrap
                }

                Flow {
                    width: parent.width
                    spacing: ThemeManager.spacingSmall

                    Button {
                        text: "Open Devices"
                        onClicked: {
                            if (settingsDialog) {
                                settingsDialog.open()
                                if (settingsDialog.openDevicesTab) settingsDialog.openDevicesTab()
                            }
                            repairRequiredDialog.close()
                        }
                    }

                    Button {
                        text: "Remove Pairing"
                        visible: repairRequiredDialog.canRemovePairing && DataStore && repairRequiredDialog.pairedDeviceId !== ""
                        onClicked: {
                            if (DataStore && repairRequiredDialog.pairedDeviceId !== "") {
                                DataStore.removePairedDevice(repairRequiredDialog.pairedDeviceId)
                            }
                            repairRequiredDialog.close()
                        }
                    }

                    Button {
                        text: "Dismiss"
                        onClicked: repairRequiredDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: incomingPairDialog
        parent: Overlay.overlay
        modal: true
        title: "Allow Sync Connection?"
        standardButtons: Dialog.NoButton

        property string deviceId: ""
        property string deviceName: ""
        property string host: ""
        property int port: 0

        onClosed: {
            deviceId = ""
            deviceName = ""
            host = ""
            port = 0
        }

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: Item {
            implicitWidth: 360
            implicitHeight: contentLayout.implicitHeight + ThemeManager.spacingMedium * 2

            ColumnLayout {
                id: hostnameContentLayout
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium

                Text {
                    Layout.fillWidth: true
                    text: incomingPairDialog.deviceName
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeLarge
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: (incomingPairDialog.host && incomingPairDialog.host !== "" && incomingPairDialog.port > 0)
                        ? ("Endpoint: " + incomingPairDialog.host + ":" + incomingPairDialog.port)
                        : "Endpoint: unknown"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: "This device is requesting to sync with your workspace."
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Button {
                        Layout.fillWidth: true
                        text: "Reject"
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
                            border.width: 1
                            border.color: ThemeManager.border
                        }
                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeNormal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            if (appSyncController && incomingPairDialog.deviceId !== "") {
                                appSyncController.approvePeer(incomingPairDialog.deviceId, false)
                            }
                            incomingPairDialog.close()
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Allow"
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.accentHover : ThemeManager.accent
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.pixelSize: ThemeManager.fontSizeNormal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            const id = incomingPairDialog.deviceId
                            if (DataStore && id !== "") {
                                const name = incomingPairDialog.deviceName && incomingPairDialog.deviceName !== ""
                                    ? incomingPairDialog.deviceName
                                    : "Paired device"
                                const ws = appSyncController ? appSyncController.workspaceId : ""
                                if (ws && ws !== "") {
                                    DataStore.savePairedDevice(id, name, ws)
                                }
                                if (incomingPairDialog.host && incomingPairDialog.host !== "" && incomingPairDialog.port > 0) {
                                    DataStore.updatePairedDeviceEndpoint(id, incomingPairDialog.host, incomingPairDialog.port)
                                }
                            }
                            if (appSyncController && id !== "") {
                                appSyncController.approvePeer(id, true)
                            }
                            incomingPairDialog.close()
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: incomingHostnamePairDialog
        parent: Overlay.overlay
        modal: true
        title: "Allow Pairing?"
        standardButtons: Dialog.NoButton

        property string deviceId: ""
        property string deviceName: ""
        property string host: ""
        property int port: 0
        property string workspaceId: ""

        onClosed: {
            deviceId = ""
            deviceName = ""
            host = ""
            port = 0
            workspaceId = ""
        }

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: Item {
            implicitWidth: 380
            implicitHeight: contentLayout.implicitHeight + ThemeManager.spacingMedium * 2

            ColumnLayout {
                id: pairingContentLayout
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingMedium

                Text {
                    Layout.fillWidth: true
                    text: incomingHostnamePairDialog.deviceName
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeLarge
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: (incomingHostnamePairDialog.host && incomingHostnamePairDialog.host !== "" && incomingHostnamePairDialog.port > 0)
                        ? ("Endpoint: " + incomingHostnamePairDialog.host + ":" + incomingHostnamePairDialog.port)
                        : "Endpoint: unknown"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: incomingHostnamePairDialog.workspaceId && incomingHostnamePairDialog.workspaceId !== ""
                        ? ("Workspace: " + incomingHostnamePairDialog.workspaceId)
                        : "Workspace: unknown"
                    color: ThemeManager.textMuted
                    font.pixelSize: ThemeManager.fontSizeSmall
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: "This will pair this device into the requested workspace."
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeNormal
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ThemeManager.spacingSmall

                    Button {
                        Layout.fillWidth: true
                        text: "Reject"
                        onClicked: {
                            const id = incomingHostnamePairDialog.deviceId
                            const ws = incomingHostnamePairDialog.workspaceId
                            if (appSyncController && id !== "" && ws !== "" && appSyncController.sendPairingResponse) {
                                appSyncController.sendPairingResponse(id, false, "Rejected", ws)
                            }
                            incomingHostnamePairDialog.close()
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Allow"
                        onClicked: {
                            const id = incomingHostnamePairDialog.deviceId
                            const ws = incomingHostnamePairDialog.workspaceId
                            if (appSyncController && id !== "" && ws !== "" && appSyncController.sendPairingResponse) {
                                appSyncController.sendPairingResponse(id, true, "", ws)
                            }

                            // Persist pairing and switch to the new workspace.
                            if (DataStore && id !== "" && ws !== "") {
                                const name = incomingHostnamePairDialog.deviceName && incomingHostnamePairDialog.deviceName !== ""
                                    ? incomingHostnamePairDialog.deviceName
                                    : "Paired device"
                                DataStore.savePairedDevice(id, name, ws)
                                if (incomingHostnamePairDialog.host && incomingHostnamePairDialog.host !== "" && incomingHostnamePairDialog.port > 0) {
                                    DataStore.updatePairedDeviceEndpoint(id, incomingHostnamePairDialog.host, incomingHostnamePairDialog.port)
                                }
                            }

                            if (appSyncController && ws !== "") {
                                if (appSyncController.stopSync) appSyncController.stopSync()
                                if (appSyncController.configure) {
                                    appSyncController.configure(ws, "Zinc Device")
                                }
                                if (appSyncController.startSync) appSyncController.startSync()
                            }

                            incomingHostnamePairDialog.close()
                        }
                    }
                }
            }
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
        if (DataStore && DataStore.editorMode) {
            root.editorMode = DataStore.editorMode()
        }
        if (!syncDisabled) {
            tryStartSync()
        }
        if (isMobile && DataStore) {
            root.mobilePagesList = DataStore.getAllPages()
        }
        // Pages are loaded by PageTree's Component.onCompleted
        if (!isMobile) {
            Qt.callLater(root.applyStartupPageDesktop)
        }
        // Mobile list is updated via pagesChanged signal
        if (isMobile) {
            Qt.callLater(root.applyStartupPageMobile)
        }
    }

    Timer {
        id: cursorPersistTimer
        interval: 250
        repeat: false
        onTriggered: {
            const payload = root.pendingCursorPersist
            root.pendingCursorPersist = null
            if (!payload || !DataStore) return
            if (!DataStore.setLastViewedCursor) return
            if (!payload.pageId || payload.pageId === "") return
            DataStore.setLastViewedCursor(payload.pageId, payload.blockIndex, payload.cursorPos)
        }
    }

    function scheduleCursorPersist(pageId, blockIndex, cursorPos) {
        if (!DataStore || !DataStore.setLastViewedCursor) return
        if (!pageId || pageId === "") return
        root.pendingCursorPersist = { pageId: pageId, blockIndex: blockIndex, cursorPos: cursorPos }
        cursorPersistTimer.restart()
    }

    function applyPendingStartupFocusIfAny(editor, pageId) {
        const hint = root.pendingStartupCursorHint
        if (!hint) return
        if (!hint.pageId || hint.pageId !== pageId) return
        root.pendingStartupCursorHint = null
        if (!editor) return
        const idx = Math.max(0, hint.blockIndex === undefined ? 0 : hint.blockIndex)
        const pos = Math.max(0, hint.cursorPos === undefined ? 0 : hint.cursorPos)
        if (editor.focusBlockAtDeferred) {
            editor.focusBlockAtDeferred(idx, pos)
            return
        }
        if (editor.focusBlockAt) {
            editor.focusBlockAt(idx, pos)
        }
    }

    function persistEditorMode(mode) {
        root.editorMode = mode === 1 ? 1 : 0
        if (DataStore && DataStore.setEditorMode) {
            DataStore.setEditorMode(root.editorMode)
        }
    }

    function editorModeToggleLabel() {
        return root.editorMode === 1 ? "Hybrid" : "Markdown"
    }

    function switchEditorMode() {
        const pageId = root.currentPage ? root.currentPage.id : ""
        if (root.editorMode === 0) {
            if (blockEditor && blockEditor.flushIfDirty) blockEditor.flushIfDirty()
            persistEditorMode(1)
            if (pageId && markdownEditor && markdownEditor.loadPage) {
                markdownEditor.loadPage(pageId)
                Qt.callLater(() => markdownEditor.focusContent && markdownEditor.focusContent())
            }
            return
        }

        if (markdownEditor && markdownEditor.saveBlocks) markdownEditor.saveBlocks()
        persistEditorMode(0)
        if (pageId && blockEditor && blockEditor.loadPage) {
            blockEditor.loadPage(pageId)
            Qt.callLater(() => root.applyPendingStartupFocusIfAny(blockEditor, pageId))
        }
    }

    function loadCurrentPageInActiveEditor(pageId) {
        if (!pageId || pageId === "") return
        if (root.editorMode === 1) {
            if (markdownEditor && markdownEditor.loadPage) {
                markdownEditor.loadPage(pageId)
                Qt.callLater(() => markdownEditor.focusContent && markdownEditor.focusContent())
            }
            return
        }
        if (blockEditor && blockEditor.loadPage) {
            blockEditor.loadPage(pageId)
            Qt.callLater(() => root.applyPendingStartupFocusIfAny(blockEditor, pageId))
        }
    }

    function applyStartupPageDesktop() {
        if (startupPageAppliedDesktop || isMobile) return
        const pages = pageTree ? pageTree.getAllPages() : []
        if (!pages || pages.length === 0) return
        startupPageAppliedDesktop = true
        const startupId = DataStore ? DataStore.resolveStartupPageId(pages) : ""
        if (DataStore && DataStore.resolveStartupCursorHint) {
            root.pendingStartupCursorHint = DataStore.resolveStartupCursorHint(startupId)
        }
        if (pageTree) {
            pageTree.ensureInitialPage(startupId)
        }
    }

    function applyStartupPageMobile() {
        if (startupPageAppliedMobile || !isMobile) return
        if (!DataStore) return
        const pages = DataStore.getAllPages()
        if (!pages || pages.length === 0) return
        const startupId = DataStore.resolveStartupPageId(pages)
        if (!startupId || startupId === "") return
        if (DataStore.resolveStartupCursorHint) {
            root.pendingStartupCursorHint = DataStore.resolveStartupCursorHint(startupId)
        }
        const page = DataStore.getPage(startupId)
        const title = page && page.title ? page.title : "Note"
        startupPageAppliedMobile = true
        DataStore.setLastViewedPageId(startupId)
        root.currentPage = { id: startupId, title: title }
        if (mobileStack.depth === 1) {
            mobileStack.push(mobileEditorComponent)
        }
    }

    Connections {
        target: DataStore

        function onPagesChanged() {
            if (isMobile) {
                Qt.callLater(function() {
                    root.mobilePagesList = DataStore.getAllPages()
                })
            }
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (root.suppressOutgoingSnapshots > 0) {
                if (root.debugSyncUi) console.log("SYNCUI: onPagesChanged suppressed")
                return
            }
            root.scheduleOutgoingSnapshot()
        }

        function onPageConflictDetected(conflict) {
            root.showSyncConflict(conflict)
        }

        function onPageConflictsChanged() {
            if (!syncConflictDialog.visible) return
            if (!DataStore || !DataStore.hasPageConflict) return
            if (!syncConflictDialog.pageId || syncConflictDialog.pageId === "") return
            if (!DataStore.hasPageConflict(syncConflictDialog.pageId)) {
                syncConflictDialog.close()
            }
        }
    }

    Connections {
        target: DataStore

        function onAttachmentsChanged() {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (root.suppressOutgoingSnapshots > 0) {
                if (root.debugSyncUi) console.log("SYNCUI: onAttachmentsChanged suppressed")
                return
            }
            root.scheduleOutgoingSnapshot()
        }

        function onNotebooksChanged() {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (root.suppressOutgoingSnapshots > 0) {
                if (root.debugSyncUi) console.log("SYNCUI: onNotebooksChanged suppressed")
                return
            }
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

        function onPairingRequestReceived(deviceId, deviceName, host, port, workspaceId) {
            console.log("SYNCUI: pairingRequestReceived", deviceId, deviceName, host, port, workspaceId)
            incomingHostnamePairDialog.deviceId = deviceId || ""
            incomingHostnamePairDialog.deviceName = deviceName || "Unknown device"
            incomingHostnamePairDialog.host = host || ""
            incomingHostnamePairDialog.port = port || 0
            incomingHostnamePairDialog.workspaceId = workspaceId || ""
            incomingHostnamePairDialog.open()
        }

        function onPairingResponseReceived(deviceId, accepted, reason, workspaceId) {
            console.log("SYNCUI: pairingResponseReceived", deviceId, accepted, reason, workspaceId)
            const pending = pendingPairByHostname
            if (!pending) return
            if (!DataStore || !appSyncController) return
            if (!deviceId || deviceId === "") return
            if (!accepted) {
                pendingPairByHostname = null
                return
            }
            const ws = appSyncController.workspaceId
            if (!ws || ws === "") {
                pendingPairByHostname = null
                return
            }
            // Save paired device using our current workspace id.
            const name = pending.peerDeviceName && pending.peerDeviceName !== ""
                ? pending.peerDeviceName
                : "Paired device"
            DataStore.savePairedDevice(deviceId, name, ws)
            if (DataStore.setPairedDevicePreferredEndpoint) {
                DataStore.setPairedDevicePreferredEndpoint(deviceId, pending.host, pending.port)
            } else {
                DataStore.updatePairedDeviceEndpoint(deviceId, pending.host, pending.port)
            }
            pendingPairByHostname = null
        }

        function onPeerHelloReceived(deviceId, deviceName, host, port) {
            console.log("SYNCUI: peerHelloReceived", deviceId, deviceName, host, port)
            if (DataStore && deviceId && deviceId !== "" && host && host !== "" && port && port > 0) {
                DataStore.updatePairedDeviceEndpoint(deviceId, host, port)
            }
            const pending = pendingPairByHostname
            if (!pending) return
            if (!pending.peerDeviceId || pending.peerDeviceId === "") {
                pendingPairByHostname = {
                    host: pending.host,
                    port: pending.port,
                    startedAt: pending.startedAt,
                    peerDeviceId: deviceId || "",
                    peerDeviceName: deviceName || ""
                }
            }
        }

        function onPeerIdentityMismatch(expectedDeviceId, actualDeviceId, deviceName, host, port) {
            console.log("SYNCUI: peerIdentityMismatch expected=", expectedDeviceId,
                        "actual=", actualDeviceId, deviceName, host, port)
            if (!expectedDeviceId || expectedDeviceId === "") return
            // Avoid hot-looping reconnect attempts when a device was reinstalled/reset (device_id changed).
            blockedReconnectUntilByDeviceId[expectedDeviceId] = Date.now() + 60000

            const promptedUntil = repairPromptedUntilByDeviceId[expectedDeviceId]
            if (promptedUntil && Date.now() < promptedUntil) return
            repairPromptedUntilByDeviceId[expectedDeviceId] = Date.now() + 60000

            repairRequiredDialog.pairedDeviceId = expectedDeviceId
            repairRequiredDialog.canRemovePairing = true
            repairRequiredDialog.details =
                "This paired device was reset/reinstalled.\n\n" +
                "Expected deviceId: " + expectedDeviceId + "\n" +
                "Actual deviceId: " + (actualDeviceId || "unknown") + "\n" +
                "Endpoint: " + (host || "unknown") + ":" + (port || 0) + "\n\n" +
                "Remove the old pairing and pair again."
            repairRequiredDialog.open()
        }

        function onPeerWorkspaceMismatch(deviceId, remoteWorkspaceId, localWorkspaceId, deviceName, host, port) {
            console.log("SYNCUI: peerWorkspaceMismatch", deviceId, remoteWorkspaceId, localWorkspaceId, deviceName, host, port)
            if (!deviceId || deviceId === "") return
            blockedReconnectUntilByDeviceId[deviceId] = Date.now() + 60000

            const promptedUntil = repairPromptedUntilByDeviceId[deviceId]
            if (promptedUntil && Date.now() < promptedUntil) return
            repairPromptedUntilByDeviceId[deviceId] = Date.now() + 60000

            repairRequiredDialog.pairedDeviceId = deviceId
            repairRequiredDialog.canRemovePairing = true
            repairRequiredDialog.details =
                "This device is not in the same workspace as the peer.\n\n" +
                "Peer: " + deviceId + (deviceName ? (" (" + deviceName + ")") : "") + "\n" +
                "Peer workspace: " + (remoteWorkspaceId || "unknown") + "\n" +
                "This workspace: " + (localWorkspaceId || "unknown") + "\n" +
                "Endpoint: " + (host || "unknown") + ":" + (port || 0) + "\n\n" +
                "Re-pair the devices to get back into the same workspace."
            repairRequiredDialog.open()
        }

        function onPeerApprovalRequired(deviceId, deviceName, host, port) {
            console.log("SYNCUI: peerApprovalRequired", deviceId, deviceName, host, port)
            if (!appSyncController) return
            const id = deviceId || ""
            if (id === "") return

            function alreadyPaired() {
                if (!DataStore) return false
                const devices = DataStore.getPairedDevices() || []
                for (let i = 0; i < devices.length; i++) {
                    const d = devices[i] || {}
                    if (d.deviceId === id) return true
                }
                return false
            }

            if (alreadyPaired()) {
                if (DataStore && host && host !== "" && port && port > 0) {
                    DataStore.updatePairedDeviceEndpoint(id, host, port)
                }
                appSyncController.approvePeer(id, true)
                return
            }

            incomingPairDialog.deviceId = id
            incomingPairDialog.deviceName = deviceName || "Unknown device"
            incomingPairDialog.host = host || ""
            incomingPairDialog.port = port || 0
            incomingPairDialog.open()
        }

        function onPeerConnected(deviceId) {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            pagesCursorAt = ""
            pagesCursorId = ""
            deletedPagesCursorAt = ""
            deletedPagesCursorId = ""
            notebooksCursorAt = ""
            notebooksCursorId = ""
            deletedNotebooksCursorAt = ""
            deletedNotebooksCursorId = ""
            attachmentsCursorAt = ""
            attachmentsCursorId = ""
            root.sendLocalSnapshot(true)
        }

        function onAttachmentSnapshotReceivedAttachments(attachments) {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (!DataStore || !attachments) return
            console.log("SYNC: received attachments", attachments.length)
            root.suppressOutgoingSnapshots++
            DataStore.applyAttachmentUpdates(attachments)
            root.suppressOutgoingSnapshots--
        }

        function onPageSnapshotReceivedPages(pages) {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (!DataStore || !pages) return
            console.log("SYNC: received pages", pages.length)
            root.suppressOutgoingSnapshots++
            DataStore.applyPageUpdates(pages)
            root.suppressOutgoingSnapshots--
        }

        function onDeletedPageSnapshotReceivedPages(deletedPages) {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (!DataStore || !deletedPages) return
            console.log("SYNC: received deleted pages", deletedPages.length)
            root.suppressOutgoingSnapshots++
            DataStore.applyDeletedPageUpdates(deletedPages)
            root.suppressOutgoingSnapshots--
        }

        function onNotebookSnapshotReceivedNotebooks(notebooks) {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (!DataStore || !notebooks) return
            console.log("SYNC: received notebooks", notebooks.length)
            root.suppressOutgoingSnapshots++
            if (DataStore.applyNotebookUpdates) {
                DataStore.applyNotebookUpdates(notebooks)
            }
            root.suppressOutgoingSnapshots--
        }

        function onDeletedNotebookSnapshotReceivedNotebooks(deletedNotebooks) {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (!DataStore || !deletedNotebooks) return
            console.log("SYNC: received deleted notebooks", deletedNotebooks.length)
            root.suppressOutgoingSnapshots++
            if (DataStore.applyDeletedNotebookUpdates) {
                DataStore.applyDeletedNotebookUpdates(deletedNotebooks)
            }
            root.suppressOutgoingSnapshots--
        }

        function onBlockSnapshotReceivedBlocks(blocks) {
            if (pairingDialog && pairingDialog.visible) {
                return
            }
            if (!DataStore || !blocks) return
            console.log("SYNC: received blocks", blocks.length)
            DataStore.applyBlockUpdates(blocks)
        }
    }

    Timer {
        id: outgoingSnapshotTimer
        interval: root.bothAutoSyncEnabled ? 0 : 200
        repeat: false
        onTriggered: {
            if (root.debugSyncUi) {
                console.log("SYNCUI: outgoingSnapshotTimer fired bothAuto=", root.bothAutoSyncEnabled,
                            "syncing=", appSyncController ? appSyncController.syncing : null,
                            "peerCount=", appSyncController ? appSyncController.peerCount : null)
            }
            root.sendLocalSnapshot(false)
        }
    }

    property string localCursorPageId: ""
    property int localCursorBlockIndex: -1
    property int localCursorPos: -1

    Timer {
        id: presenceTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (!appSyncController) return
            if (!SyncPreferences.autoSyncEnabled) return
            if (!appSyncController.syncing) {
                if (root.debugSyncUi) console.log("SYNCUI: sendPresence skip syncing=false")
                return
            }
            if (appSyncController.peerCount <= 0) {
                if (root.debugSyncUi) console.log("SYNCUI: sendPresence skip peerCount=0")
                return
            }
            if (root.debugSyncUi) {
                console.log("SYNCUI: sendPresence pageId=", localCursorPageId,
                            "block=", localCursorBlockIndex, "pos=", localCursorPos,
                            "bothAuto=", root.bothAutoSyncEnabled)
            }
            appSyncController.sendPresence(localCursorPageId, localCursorBlockIndex, localCursorPos, SyncPreferences.autoSyncEnabled)
        }
    }

    function scheduleOutgoingSnapshot() {
        if (!SyncPreferences.autoSyncEnabled) return
        if (root.debugSyncUi) console.log("SYNCUI: scheduleOutgoingSnapshot()")
        outgoingSnapshotTimer.restart()
    }

    function requestManualSync() {
        tryStartSync()
        if (root.debugSyncUi) console.log("SYNCUI: requestManualSync()")
        outgoingSnapshotTimer.restart()
    }

    Connections {
        target: SyncPreferences

        function onAutoSyncEnabledChanged() {
            if (!SyncPreferences.autoSyncEnabled) {
                outgoingSnapshotTimer.stop()
                presenceTimer.stop()
                return
            }
            scheduleOutgoingSnapshot()
            presenceTimer.restart()
        }
    }

    Connections {
        target: appSyncController
        enabled: appSyncController !== null

        function onSyncingChanged() {
            if (root.debugSyncUi) console.log("SYNCUI: syncingChanged syncing=", appSyncController.syncing)
            if (appSyncController.syncing) presenceTimer.restart()
        }

        function onPeerCountChanged() {
            if (root.debugSyncUi) console.log("SYNCUI: peerCountChanged peerCount=", appSyncController.peerCount)
            if (appSyncController.peerCount > 0) presenceTimer.restart()
        }
    }

    Connections {
        target: appSyncController

        function onRemotePresenceChanged() {
            if (root.debugSyncUi && appSyncController) {
                console.log("SYNCUI: remotePresenceChanged remoteAuto=", appSyncController.remoteAutoSyncEnabled,
                            "pageId=", appSyncController.remoteCursorPageId,
                            "block=", appSyncController.remoteCursorBlockIndex,
                            "pos=", appSyncController.remoteCursorPos)
            }
        }
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
        if (!DataStore || !appSyncController) {
            if (root.debugSyncUi) console.log("SYNCUI: sendLocalSnapshot skip missing DataStore/appSyncController")
            return
        }
        if (!appSyncController.syncing) {
            if (root.debugSyncUi) console.log("SYNCUI: sendLocalSnapshot skip syncing=false")
            return
        }
        if (appSyncController.peerCount <= 0) {
            if (root.debugSyncUi) console.log("SYNCUI: sendLocalSnapshot skip peerCount=0")
            return
        }

        var pages = full ? DataStore.getPagesForSync()
                         : DataStore.getPagesForSyncSince(pagesCursorAt, pagesCursorId)
        var deletedPages = full ? DataStore.getDeletedPagesForSync()
                                : DataStore.getDeletedPagesForSyncSince(deletedPagesCursorAt, deletedPagesCursorId)
        var notebooks = full ? (DataStore.getNotebooksForSync ? DataStore.getNotebooksForSync() : [])
                             : (DataStore.getNotebooksForSyncSince ? DataStore.getNotebooksForSyncSince(notebooksCursorAt, notebooksCursorId) : [])
        var deletedNotebooks = full ? (DataStore.getDeletedNotebooksForSync ? DataStore.getDeletedNotebooksForSync() : [])
                                    : (DataStore.getDeletedNotebooksForSyncSince ? DataStore.getDeletedNotebooksForSyncSince(deletedNotebooksCursorAt, deletedNotebooksCursorId) : [])
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
            (!notebooks || notebooks.length === 0) &&
            (!deletedNotebooks || deletedNotebooks.length === 0) &&
            (!attachments || attachments.length === 0)) {
            if (root.debugSyncUi) console.log("SYNCUI: sendLocalSnapshot noop (no deltas)")
            return
        }

        var payload = JSON.stringify({
            v: 3,
            workspaceId: appSyncController.workspaceId,
            full: full === true,
            pages: pages,
            deletedPages: deletedPages,
            notebooks: notebooks,
            deletedNotebooks: deletedNotebooks,
            attachments: attachments
        })
        console.log("SYNC: sending snapshot full=", full === true, "pages", pages.length, "deleted", deletedPages.length,
                    "notebooks", notebooks.length, "deletedNotebooks", deletedNotebooks.length, "attachments", attachments.length)
        appSyncController.sendPageSnapshot(payload)

        advanceCursorFrom(pages, "pagesCursorAt", "pagesCursorId", "updatedAt", "pageId")
        advanceCursorFrom(deletedPages, "deletedPagesCursorAt", "deletedPagesCursorId", "deletedAt", "pageId")
        advanceCursorFrom(notebooks, "notebooksCursorAt", "notebooksCursorId", "updatedAt", "notebookId")
        advanceCursorFrom(deletedNotebooks, "deletedNotebooksCursorAt", "deletedNotebooksCursorId", "deletedAt", "notebookId")
        advanceCursorFrom(attachments, "attachmentsCursorAt", "attachmentsCursorId", "updatedAt", "attachmentId")
    }

    function tryStartSync() {
        if (root.syncDisabled) return
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

        // Not configured yet: start a passive listener so other devices can pair via hostname.
        if (appSyncController.startPairingListener) {
            if (appSyncController.startPairingListener("Zinc Device")) {
                console.log("SYNC: started pairing listener")
            }
        }
    }

    // Opportunistic direct reconnect to paired endpoints (useful when discovery is slow/unavailable).
    Timer {
        id: syncReconnectTimer
        interval: 5000
        repeat: true
        running: !root.syncDisabled
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
                var blockedUntil = blockedReconnectUntilByDeviceId[d.deviceId]
                if (blockedUntil && Date.now() < blockedUntil) continue
                if (blockedUntil && Date.now() >= blockedUntil) delete blockedReconnectUntilByDeviceId[d.deviceId]
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
