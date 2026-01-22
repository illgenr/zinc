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

    Connections {
        target: DataStore
    }
    
    // Keyboard shortcuts (desktop)
    Shortcut {
        sequence: "Ctrl+N"
        enabled: !isMobile
        onActivated: pageTree.createPage("")
    }
    
    Shortcut {
        sequence: "Ctrl+F"
        enabled: !isMobile
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

                    ToolButton {
                        Layout.alignment: Qt.AlignVCenter
                        contentItem: Text {
                            text: "+"
                            color: ThemeManager.text
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.surfaceActive : "transparent"
                        }
                        onClicked: newNotebookDialog.open()
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

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: ThemeManager.spacingSmall
                    Layout.preferredHeight: 48
                    // Search bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        Layout.preferredWidth: 96
                        Layout.alignment: Qt.AlignVCenter
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
                                text: "Find"
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
                        Layout.margins: ThemeManager.spacingSmall
                        Layout.alignment: Qt.AlignVCenter
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

                    Button {
                        Layout.margins: ThemeManager.spacingSmall
                        Layout.alignment: Qt.AlignVCenter
                        text: "New Notebook"

                        background: Rectangle {
                            implicitHeight: 44
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                            border.width: 1
                            border.color: ThemeManager.border
                        }

                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeNormal
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: newNotebookDialog.open()
                    }
                }

                // Notes list
                PageTree {
                    id: mobilePageTree
                    objectName: "mobilePageTree"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    showNewPageButton: false
                    showExpandArrowsAlways: true
                    actionsAlwaysVisible: true
                    actionButtonSize: 44
                    activateOnSingleTap: false

                    onNewNotebookRequested: newNotebookDialog.open()

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
                            text: "Find"
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                        
                        Text {
                            text: "Ctrl+F"
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
                    objectName: "pageTree"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !sidebarCollapsed

                    onNewNotebookRequested: newNotebookDialog.open()

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
                            if (DataStore) DataStore.setLastViewedPageId(targetPageId)
                            root.currentPage = { id: targetPageId, title: title }
                            root.loadCurrentPageInActiveEditor(targetPageId)
                        }

                        onCreateChildPageRequested: function(title, blockIndex) {
                            if (!title || title === "") return
                            var newId = pageTree.createPage(blockEditor.pageId)
                            if (!newId || newId === "") return
                            pageTree.updatePageTitle(newId, title)
                            blockEditor.setLinkAtIndex(blockIndex, newId, title)
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
                        pageTitle: currentPage ? currentPage.title : ""
                        availablePages: pageTree.getAllPages()

                        onTitleEdited: function(newTitle) {
                            if (currentPage) {
                                currentPage.title = newTitle
                                pageTree.updatePageTitle(currentPage.id, newTitle)
                            }
                        }
                    }
                }

                ToolButton {
                    id: editorModeToggleButton
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: ThemeManager.spacingSmall
                    text: root.editorModeToggleLabel()
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
    }

    property var pendingSyncConflicts: []

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
    }

    Dialog {
        id: newNotebookDialog
        title: "New Notebook"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        parent: Overlay.overlay

        property string _name: ""

        contentItem: Item {
            implicitWidth: 360
            implicitHeight: 120

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall

                TextField {
                    id: newNotebookNameField
                    Layout.fillWidth: true
                    placeholderText: "Notebook name"
                    text: ""
                    onTextChanged: newNotebookDialog._name = text
                }
            }
        }

        onOpened: {
            newNotebookDialog._name = ""
            newNotebookNameField.text = ""
            newNotebookNameField.forceActiveFocus()
        }

        onAccepted: {
            if (!DataStore || !DataStore.createNotebook) return
            DataStore.createNotebook(newNotebookDialog._name)
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
