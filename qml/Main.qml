import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc
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
                        pageTree.createPage("")
                    }
                }
                
                // Notes list
                ListView {
                    id: mobileNotesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: mobilePagesList
                    
                    delegate: Rectangle {
                        id: mobilePageDelegate
                        width: mobileNotesList.width
                        height: 64
                        color: noteMouse.pressed ? ThemeManager.surfaceHover : "transparent"
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ThemeManager.spacingMedium + (modelData.depth * 24)
                            anchors.rightMargin: ThemeManager.spacingSmall
                            anchors.topMargin: ThemeManager.spacingSmall
                            anchors.bottomMargin: ThemeManager.spacingSmall
                            spacing: ThemeManager.spacingSmall
                            
                            // Indent indicator for child pages
                            Rectangle {
                                visible: modelData.depth > 0
                                width: 2
                                Layout.fillHeight: true
                                color: ThemeManager.border
                            }
                            
                            Rectangle {
                                width: 40
                                height: 40
                                radius: ThemeManager.radiusSmall
                                color: ThemeManager.surfaceHover
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.depth > 0 ? "📑" : "📄"
                                    font.pixelSize: 18
                                }
                            }
                            
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    color: ThemeManager.text
                                    font.pixelSize: ThemeManager.fontSizeNormal
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.depth > 0 ? "Sub-page" : "Page"
                                    color: ThemeManager.textSecondary
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                }
                            }
                            
                            // Add sub-page button
                            Rectangle {
                                width: 36
                                height: 36
                                radius: ThemeManager.radiusMedium
                                color: addSubMouse.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: ThemeManager.accent
                                    font.pixelSize: 20
                                    font.bold: true
                                }
                                
                                MouseArea {
                                    id: addSubMouse
                                    anchors.fill: parent
                                    onClicked: {
                                        pageTree.createPage(modelData.pageId)
                                    }
                                }
                            }
                            
                            // More options button
                            Rectangle {
                                width: 36
                                height: 36
                                radius: ThemeManager.radiusMedium
                                color: moreMouse.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "⋯"
                                    color: ThemeManager.textSecondary
                                    font.pixelSize: 18
                                }
                                
                                MouseArea {
                                    id: moreMouse
                                    anchors.fill: parent
                                    onClicked: {
                                        mobilePageMenu.targetPageId = modelData.pageId
                                        mobilePageMenu.targetPageTitle = modelData.title
                                        mobilePageMenu.popup()
                                    }
                                }
                            }
                            
                            // Navigate arrow
                            Text {
                                text: "›"
                                color: ThemeManager.textMuted
                                font.pixelSize: 20
                            }
                        }
                        
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: ThemeManager.spacingMedium + (modelData.depth * 24) + 56
                            height: 1
                            color: ThemeManager.borderLight
                        }
                        
                        MouseArea {
                            id: noteMouse
                            anchors.fill: parent
                            z: -1  // Behind the buttons
                            onClicked: {
                                root.currentPage = { id: modelData.pageId, title: modelData.title }
                                mobileStack.push(mobileEditorComponent)
                            }
                        }
                    }
                }
                
                // Mobile page context menu
                Menu {
                    id: mobilePageMenu
                    property string targetPageId: ""
                    property string targetPageTitle: ""
                    
                    MenuItem {
                        text: "Add sub-page"
                        onTriggered: pageTree.createPage(mobilePageMenu.targetPageId)
                    }
                    
                    MenuSeparator {}
                    
                    MenuItem {
                        text: "Delete"
                        onTriggered: {
                            if (mobilePagesList.length > 1) {
                                pageTree.deletePage(mobilePageMenu.targetPageId)
                            }
                        }
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
                        pageTree.createPage("")
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
                }
                
                onNavigateToPage: function(targetPageId) {
                    // Find the page title
                    let pages = pageTree.getAllPages()
                    let title = "Note"
                    for (let p of pages) {
                        if (p.pageId === targetPageId) {
                            title = p.title
                            break
                        }
                    }
                    root.currentPage = { id: targetPageId, title: title }
                    // Push a new editor or reload
                    mobileBlockEditor.loadPage(targetPageId)
                }
            }
            
            PagePickerDialog {
                id: mobilePagePickerDialog
                parent: Overlay.overlay
                
                onPageSelected: function(pageId, pageTitle) {
                    mobileBlockEditor.setLinkTarget(pageId, pageTitle)
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
                }
                
                onNavigateToPage: function(targetPageId) {
                    // Find the page title
                    let pages = pageTree.getAllPages()
                    let title = "Note"
                    for (let p of pages) {
                        if (p.pageId === targetPageId) {
                            title = p.title
                            break
                        }
                    }
                    currentPage = { id: targetPageId, title: title }
                    blockEditor.loadPage(targetPageId)
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
    }
    
    PagePickerDialog {
        id: pagePickerDialog
        parent: Overlay.overlay
        
        onPageSelected: function(pageId, pageTitle) {
            blockEditor.setLinkTarget(pageId, pageTitle)
        }
    }
    
    SettingsDialog {
        id: settingsDialog
        
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
