import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import zinc

SettingsPage {
    id: page
    property bool isMobile: false
    signal resetAllDataRequested()
    property ListModel notebooksModel: ListModel {}
    property bool exportAllNotebooks: true
    property bool exportIncludeAttachments: true
    property url exportDestinationFolder: ""
    property int exportFormatIndex: 0 // 0=markdown, 1=html
    property string exportStatus: ""
    property bool exportSucceeded: false
    property string exportFolderPickerStatus: ""
    property url folderPickerCurrentFolder: ""
    property url folderPickerSelectedFolder: ""
    property string exportFolderPickerPathText: ""
    property url importSourceFolder: ""
    property int importFormatIndex: 0 // 0=auto, 1=markdown, 2=html
    property bool importReplaceExisting: false
    property string importStatus: ""
    property bool importSucceeded: false
    property string importFolderPickerStatus: ""
    property url importFolderPickerCurrentFolder: ""
    property url importFolderPickerSelectedFolder: ""
    property string importFolderPickerPathText: ""
    property string newFolderName: ""
    property string newFolderTarget: "export" // export | import | db
    property string databaseStatus: ""
    property bool databaseSucceeded: false
    property string databaseFolderPickerStatus: ""
    property string databaseFolderPickerMode: "move" // move | select
    property url databaseFolderPickerCurrentFolder: ""
    property url databaseFolderPickerSelectedFolder: ""
    property string databaseFolderPickerPathText: ""
    property url databaseCreateFolder: ""
    property string newDbFileName: "zinc.db"
    property string databaseFilePickerStatus: ""
    property url databaseFilePickerCurrentFolder: ""
    property url databaseFilePickerSelectedFile: ""
    property string databaseFilePickerPathText: ""

    function focusFirstControl() {
        if (!moveDatabaseButton || !moveDatabaseButton.visible || !moveDatabaseButton.enabled) {
            console.log("DataSettingsPage focus: moveDatabaseButton unavailable visible=",
                        moveDatabaseButton ? moveDatabaseButton.visible : "n/a",
                        "enabled=", moveDatabaseButton ? moveDatabaseButton.enabled : "n/a")
            return false
        }
        console.log("DataSettingsPage focus: focusing moveDatabaseButton")
        moveDatabaseButton.forceActiveFocus()
        return true
    }

    function _normalizePathText(text) {
        return text ? text.trim() : ""
    }

    function _localPathFromUrl(url) {
        if (!url || url === "") return ""
        const s = url.toString ? url.toString() : ("" + url)
        return s.replace("file://", "")
    }

    function _urlFromUserPathText(text) {
        const t = _normalizePathText(text)
        if (t === "") return ""
        if (t.indexOf("file:") === 0) return t
        return "file://" + t
    }

    function _looksLikeFilePath(pathText) {
        const t = _normalizePathText(pathText)
        if (t === "" || t.endsWith("/")) return false
        const lastSlash = Math.max(t.lastIndexOf("/"), t.lastIndexOf("\\"))
        const lastDot = t.lastIndexOf(".")
        return lastDot > lastSlash
    }

    function refreshNotebooks() {
        notebooksModel.clear()
        const notebooks = DataStore ? DataStore.getAllNotebooks() : []
        for (let i = 0; i < notebooks.length; i++) {
            const nb = notebooks[i] || {}
            if (!nb.notebookId) continue
            notebooksModel.append({
                notebookId: nb.notebookId,
                name: nb.name || "Untitled Notebook",
                selected: true
            })
        }
    }

    function selectedNotebookIds() {
        const ids = []
        for (let i = 0; i < notebooksModel.count; i++) {
            const nb = notebooksModel.get(i)
            if (nb.selected) ids.push(nb.notebookId)
        }
        return ids
    }

    function canExport() {
        if (!exportDestinationFolder || exportDestinationFolder === "") return false
        if (exportAllNotebooks) return true
        return selectedNotebookIds().length > 0
    }

    function ensureExportDestinationFolder() {
        const hasFolder = exportDestinationFolder && exportDestinationFolder !== "" &&
            exportDestinationFolder.toString().indexOf("file:") === 0
        if (hasFolder) return
        exportDestinationFolder = DataStore ? DataStore.exportLastFolder() : ""
    }

    function openFolderPicker() {
        ensureExportDestinationFolder()
        exportFolderPickerStatus = ""
        folderPickerCurrentFolder = exportDestinationFolder
        folderPickerSelectedFolder = ""
        exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
        exportFolderPickerDialog.open()
    }

    function ensureImportSourceFolder() {
        const hasFolder = importSourceFolder && importSourceFolder !== "" &&
            importSourceFolder.toString().indexOf("file:") === 0
        if (hasFolder) return
        importSourceFolder = DataStore ? DataStore.exportLastFolder() : ""
    }

    function openImportFolderPicker() {
        ensureImportSourceFolder()
        importFolderPickerStatus = ""
        importFolderPickerCurrentFolder = importSourceFolder
        importFolderPickerSelectedFolder = ""
        importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
        importFolderPickerDialog.open()
    }

    function ensureDatabaseFolderPicker() {
        const folder = DataStore ? DataStore.databaseFolder() : ""
        const hasFolder = folder && folder !== "" && folder.toString().indexOf("file:") === 0
        databaseFolderPickerCurrentFolder = hasFolder ? folder : (DataStore ? DataStore.exportLastFolder() : "")
        databaseFolderPickerSelectedFolder = ""
        databaseFolderPickerStatus = ""
    }

    function openDatabaseFolderPicker() {
        databaseFolderPickerMode = "move"
        ensureDatabaseFolderPicker()
        databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
        databaseFolderPickerDialog.open()
    }

    function openDatabaseCreateFolderPicker() {
        databaseFolderPickerMode = "select"
        ensureDatabaseFolderPicker()
        databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
        databaseFolderPickerDialog.open()
    }

    function openDatabaseFilePicker() {
        const folder = DataStore ? DataStore.databaseFolder() : ""
        const hasFolder = folder && folder !== "" && folder.toString().indexOf("file:") === 0
        databaseFilePickerCurrentFolder = hasFolder ? folder : (DataStore ? DataStore.exportLastFolder() : "")
        databaseFilePickerSelectedFile = ""
        databaseFilePickerStatus = ""
        databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
        databaseFilePickerDialog.open()
    }

    Component.onCompleted: {
        refreshNotebooks()
        ensureExportDestinationFolder()
        ensureImportSourceFolder()
    }

    property Connections _dataStoreConnections: Connections {
        target: DataStore
        function onNotebooksChanged() { refreshNotebooks() }
        function onError(message) {
            if (newFolderDialog && newFolderDialog.visible) {
                if (newFolderTarget === "import") {
                    importFolderPickerStatus = message
                } else if (newFolderTarget === "db") {
                    if (databaseFilePickerDialog && databaseFilePickerDialog.visible) {
                        databaseFilePickerStatus = message
                    } else {
                        databaseFolderPickerStatus = message
                    }
                } else {
                    exportFolderPickerStatus = message
                }
                return
            }
            if (databaseFolderPickerDialog && databaseFolderPickerDialog.visible) {
                databaseFolderPickerStatus = message
                return
            }
            if (databaseFilePickerDialog && databaseFilePickerDialog.visible) {
                databaseFilePickerStatus = message
                return
            }
            if (createDatabaseDialog && createDatabaseDialog.visible) {
                databaseStatus = message
                databaseSucceeded = false
                return
            }
            if (importFolderPickerDialog && importFolderPickerDialog.visible) {
                importFolderPickerStatus = message
                return
            }
            if (exportFolderPickerDialog && exportFolderPickerDialog.visible) {
                exportFolderPickerStatus = message
                return
            }
            if (importDialog && importDialog.visible) {
                importStatus = message
                importSucceeded = false
            } else {
                exportStatus = message
                exportSucceeded = false
            }
        }
    }

    SettingsSection {
        title: "Database"
        
        Text {
            Layout.fillWidth: true
            text: "Path: " + (DataStore ? DataStore.databasePath : "N/A")
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeSmall
            wrapMode: Text.WrapAnywhere
        }
        
        Text {
            text: "Schema: " + (DataStore && DataStore.schemaVersion >= 0 ? ("v" + DataStore.schemaVersion) : "N/A")
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeSmall
        }

        Text {
            Layout.fillWidth: true
            visible: databaseStatus && databaseStatus.length > 0
            text: databaseStatus
            color: databaseSucceeded ? ThemeManager.success : ThemeManager.danger
            font.pixelSize: ThemeManager.fontSizeSmall
            wrapMode: Text.Wrap
        }

        SettingsButton {
            id: moveDatabaseButton
            Layout.fillWidth: true
            text: "Move Database…"

            background: Rectangle {
                implicitHeight: 40
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }

            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                databaseStatus = ""
                databaseSucceeded = false
                openDatabaseFolderPicker()
            }
        }

        SettingsButton {
            Layout.fillWidth: true
            text: "Create New Database…"

            background: Rectangle {
                implicitHeight: 40
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }

            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                databaseStatus = ""
                databaseSucceeded = false
                ensureDatabaseFolderPicker()
                newDbFileName = "zinc.db"
                databaseCreateFolder = DataStore ? DataStore.databaseFolder() : ""
                createDatabaseDialog.open()
            }
        }

        SettingsButton {
            Layout.fillWidth: true
            text: "Open Database…"

            background: Rectangle {
                implicitHeight: 40
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }

            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                databaseStatus = ""
                databaseSucceeded = false
                openDatabaseFilePicker()
            }
        }

        SettingsButton {
            Layout.fillWidth: true
            text: "Close Database"
            enabled: DataStore && DataStore.schemaVersion >= 0

            background: Rectangle {
                implicitHeight: 40
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }

            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                if (!DataStore) return
                DataStore.closeDatabase()
                databaseSucceeded = true
                databaseStatus = "Database closed."
            }
        }
        
        SettingsButton {
            Layout.fillWidth: true
            text: "Run Migrations"
            
            background: Rectangle {
                implicitHeight: 40
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }
            
            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            
            onClicked: {
                if (DataStore && DataStore.runMigrations()) {
                    console.log("Migrations complete")
                }
            }
        }
    }

    SettingsSection {
        title: "Export"

        SettingsButton {
            Layout.fillWidth: true
            text: "Export Notebooks…"

            background: Rectangle {
                implicitHeight: 40
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }

            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                exportStatus = ""
                exportSucceeded = false
                refreshNotebooks()
                ensureExportDestinationFolder()
                exportDialog.open()
            }
        }
    }

    SettingsSection {
        title: "Import"

        SettingsButton {
            Layout.fillWidth: true
            text: "Import Notebooks…"

            background: Rectangle {
                implicitHeight: 40
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }

            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                importStatus = ""
                importSucceeded = false
                ensureImportSourceFolder()
                importDialog.open()
            }
        }
    }
    
    SettingsSection {
        title: "⚠️ Danger Zone"
        
        SettingsButton {
            Layout.fillWidth: true
            text: "Reset All Data"
            
            background: Rectangle {
                implicitHeight: 44
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? "#7a2020" : "transparent"
                border.width: 2
                border.color: ThemeManager.danger
            }
            
            contentItem: Text {
                text: parent.text
                color: ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            
            onClicked: page.resetAllDataRequested()
        }
    }

    property Dialog _exportDialog: Dialog {
        id: exportDialog
        title: "Export Notebooks"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(520, parent.width * 0.9)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingMedium

            SettingsRow {
                label: "Format"
                SettingsComboBox {
                    width: parent.width
                    model: ["Markdown (.md)", "HTML (.html)"]
                    currentIndex: exportFormatIndex
                    onCurrentIndexChanged: exportFormatIndex = currentIndex
                }
            }

            SettingsRow {
                label: "Notebooks"
                CheckBox {
                    text: "All notebooks"
                    checked: exportAllNotebooks
                    onToggled: exportAllNotebooks = checked
                }
            }

            SettingsRow {
                label: "Attachments"
                CheckBox {
                    text: "Include attachments"
                    checked: exportIncludeAttachments
                    onToggled: exportIncludeAttachments = checked
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                visible: !exportAllNotebooks
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: notebooksModel
                        delegate: CheckBox {
                            text: model.name
                            checked: model.selected
                            onToggled: notebooksModel.setProperty(index, "selected", checked)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                SettingsButton {
                    text: "Choose Folder…"
                    onClicked: {
                        exportStatus = ""
                        exportSucceeded = false
                        openFolderPicker()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: exportDestinationFolder && exportDestinationFolder !== ""
                        ? exportDestinationFolder.toString().replace("file://", "")
                        : "No folder selected"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideMiddle
                }
            }

            Text {
                Layout.fillWidth: true
                visible: exportStatus && exportStatus.length > 0
                text: exportStatus
                color: exportSucceeded ? ThemeManager.success : ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: exportDialog.close()
                }

                SettingsButton {
                    text: "Export"
                    enabled: canExport()
                    onClicked: {
                        if (!DataStore) return
                        exportStatus = ""
                        exportSucceeded = false
                        const ids = exportAllNotebooks ? [] : selectedNotebookIds()
                        const fmt = exportFormatIndex === 0 ? "markdown" : "html"
                        DataStore.setExportLastFolder(exportDestinationFolder)
                        const ok = DataStore.exportNotebooks(ids, exportDestinationFolder, fmt, exportIncludeAttachments)
                        if (ok) {
                            exportSucceeded = true
                            exportStatus = "Export complete."
                        }
                    }
                }
            }
        }
    }

    property Dialog _importDialog: Dialog {
        id: importDialog
        title: "Import Notebooks"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(520, parent.width * 0.9)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingMedium

            SettingsRow {
                label: "Format"
                SettingsComboBox {
                    width: parent.width
                    model: ["Auto", "Markdown (.md)", "HTML (.html)"]
                    currentIndex: importFormatIndex
                    onCurrentIndexChanged: importFormatIndex = currentIndex
                }
            }

            SettingsRow {
                label: "Behavior"
                CheckBox {
                    text: "Replace existing data"
                    checked: importReplaceExisting
                    onToggled: importReplaceExisting = checked
                }
            }

            Text {
                Layout.fillWidth: true
                visible: importReplaceExisting
                text: "Replacing existing data will erase your current notebooks and attachments before importing."
                color: ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                SettingsButton {
                    text: "Choose Folder…"
                    onClicked: {
                        importStatus = ""
                        importSucceeded = false
                        openImportFolderPicker()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: importSourceFolder && importSourceFolder !== ""
                        ? importSourceFolder.toString().replace("file://", "")
                        : "No folder selected"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideMiddle
                }
            }

            Text {
                Layout.fillWidth: true
                visible: importStatus && importStatus.length > 0
                text: importStatus
                color: importSucceeded ? ThemeManager.success : ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: importDialog.close()
                }

                SettingsButton {
                    text: "Import"
                    enabled: importSourceFolder && importSourceFolder !== ""
                    onClicked: {
                        if (!DataStore) return
                        importStatus = ""
                        importSucceeded = false
                        const fmt = importFormatIndex === 0 ? "auto" : (importFormatIndex === 1 ? "markdown" : "html")
                        const ok = DataStore.importNotebooks(importSourceFolder, fmt, importReplaceExisting)
                        if (ok) {
                            importSucceeded = true
                            importStatus = "Import complete."
                        }
                    }
                }
            }
        }
    }

    property Dialog _exportFolderPickerDialog: Dialog {
        id: exportFolderPickerDialog
        title: "Choose Export Folder"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(560, parent.width * 0.9)
        height: isMobile ? parent.height * 0.85 : Math.min(520, parent.height * 0.85)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingSmall

	                RowLayout {
	                    Layout.fillWidth: true
	                    spacing: ThemeManager.spacingSmall

	                    SettingsButton {
	                        text: "Up"
                    enabled: DataStore && folderPickerCurrentFolder !== "" &&
                        DataStore.parentFolder(folderPickerCurrentFolder).toString() !== folderPickerCurrentFolder.toString()
                    onClicked: {
                        if (!DataStore) return
                        folderPickerCurrentFolder = DataStore.parentFolder(folderPickerCurrentFolder)
                        folderPickerSelectedFolder = ""
                        exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
                    }
	                    }

	                    SettingsButton {
	                        text: "New Folder…"
	                        enabled: folderPickerCurrentFolder && folderPickerCurrentFolder !== ""
	                        onClicked: {
	                            newFolderName = ""
	                            newFolderTarget = "export"
	                            exportFolderPickerStatus = ""
	                            newFolderDialog.open()
	                        }
	                    }

                    TextField {
                        objectName: "exportFolderPickerPathField"
	                        Layout.fillWidth: true
                        placeholderText: "Path"
                        text: exportFolderPickerPathText
                        selectByMouse: true
                        onTextChanged: exportFolderPickerPathText = text
                        onAccepted: {
                            const url = _urlFromUserPathText(exportFolderPickerPathText)
                            if (!url || url === "") return
                            exportFolderPickerStatus = ""
                            folderPickerCurrentFolder = url
                            folderPickerSelectedFolder = ""
                        }
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: ThemeManager.background
                radius: ThemeManager.radiusSmall
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border

                ListView {
                    id: folderListView
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    clip: true
                    model: FolderListModel {
                        objectName: "exportFolderListModel"
                        folder: folderPickerCurrentFolder
                        showDirs: true
                        showFiles: false
                        showHidden: true
                        showDotAndDotDot: false
                        sortField: FolderListModel.Name
                    }

	                        delegate: Rectangle {
	                            readonly property string dirUrl: "file://" + filePath
	                            width: ListView.view.width
	                            height: 36
	                            radius: ThemeManager.radiusSmall
	                            color: (folderPickerSelectedFolder && folderPickerSelectedFolder.toString() === dirUrl)
	                                ? ThemeManager.surfaceHover
	                                : (rowMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ThemeManager.spacingSmall
                            anchors.rightMargin: ThemeManager.spacingSmall
                            spacing: ThemeManager.spacingSmall

                            Text {
                                text: "📁"
                                font.pixelSize: ThemeManager.fontSizeSmall
                            }

                            Text {
                                Layout.fillWidth: true
                                text: fileName
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeSmall
                                elide: Text.ElideRight
                            }
                        }

	                            MouseArea {
	                                id: rowMouse
	                                anchors.fill: parent
	                                hoverEnabled: true
	                                cursorShape: Qt.PointingHandCursor
	                                onClicked: folderPickerSelectedFolder = dirUrl
	                                onDoubleClicked: {
	                                    folderPickerCurrentFolder = dirUrl
	                                    folderPickerSelectedFolder = ""
                                    exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
	                                }
	                            }
	                        }
                }
            }

	                RowLayout {
	                    Layout.fillWidth: true
	                    spacing: ThemeManager.spacingSmall

	                    Text {
                    Layout.fillWidth: true
                    text: folderPickerSelectedFolder && folderPickerSelectedFolder !== ""
                        ? ("Selected: " + folderPickerSelectedFolder.toString().replace("file://", ""))
                        : "Selected: (current folder)"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideMiddle
	                    }
	                }

	                Text {
	                    Layout.fillWidth: true
	                    visible: exportFolderPickerStatus && exportFolderPickerStatus.length > 0
	                    text: exportFolderPickerStatus
	                    color: ThemeManager.danger
	                    font.pixelSize: ThemeManager.fontSizeSmall
	                    wrapMode: Text.Wrap
	                }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: exportFolderPickerDialog.close()
                }

                SettingsButton {
                    text: "Export"
                    enabled: folderPickerCurrentFolder && folderPickerCurrentFolder !== ""
                    onClicked: {
                        const chosen = (folderPickerSelectedFolder && folderPickerSelectedFolder !== "")
                            ? folderPickerSelectedFolder
                            : folderPickerCurrentFolder
                        exportDestinationFolder = chosen
                        if (DataStore) DataStore.setExportLastFolder(chosen)
                        exportFolderPickerDialog.close()
                    }
                }
            }
        }
    }

    property Dialog _databaseFolderPickerDialog: Dialog {
        id: databaseFolderPickerDialog
        title: "Choose Database Folder"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(560, parent.width * 0.9)
        height: isMobile ? parent.height * 0.85 : Math.min(520, parent.height * 0.85)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                SettingsButton {
                    text: "Up"
                    enabled: DataStore && databaseFolderPickerCurrentFolder !== "" &&
                        DataStore.parentFolder(databaseFolderPickerCurrentFolder).toString() !== databaseFolderPickerCurrentFolder.toString()
                    onClicked: {
                        if (!DataStore) return
                        databaseFolderPickerCurrentFolder = DataStore.parentFolder(databaseFolderPickerCurrentFolder)
                        databaseFolderPickerSelectedFolder = ""
                        databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
                    }
                }

                SettingsButton {
                    text: "New Folder…"
                    enabled: databaseFolderPickerCurrentFolder && databaseFolderPickerCurrentFolder !== ""
                    onClicked: {
                        newFolderName = ""
                        newFolderTarget = "db"
                        databaseFolderPickerStatus = ""
                        newFolderDialog.open()
                    }
                }

                TextField {
                    objectName: "databaseFolderPickerPathField"
                    Layout.fillWidth: true
                    placeholderText: "Path"
                    text: databaseFolderPickerPathText
                    selectByMouse: true
                    onTextChanged: databaseFolderPickerPathText = text
                    onAccepted: {
                        const url = _urlFromUserPathText(databaseFolderPickerPathText)
                        if (!url || url === "") return
                        databaseFolderPickerStatus = ""
                        databaseFolderPickerCurrentFolder = url
                        databaseFolderPickerSelectedFolder = ""
                    }
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: ThemeManager.background
                radius: ThemeManager.radiusSmall
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border

                ListView {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    clip: true
                    model: FolderListModel {
                        objectName: "databaseFolderListModel"
                        folder: databaseFolderPickerCurrentFolder
                        showDirs: true
                        showFiles: false
                        showHidden: true
                        showDotAndDotDot: false
                        sortField: FolderListModel.Name
                    }

                    delegate: Rectangle {
                        readonly property string dirUrl: "file://" + filePath
                        width: ListView.view.width
                        height: 36
                        radius: ThemeManager.radiusSmall
                        color: (databaseFolderPickerSelectedFolder && databaseFolderPickerSelectedFolder.toString() === dirUrl)
                            ? ThemeManager.surfaceHover
                            : (rowMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ThemeManager.spacingSmall
                            anchors.rightMargin: ThemeManager.spacingSmall
                            spacing: ThemeManager.spacingSmall

                            Text {
                                text: "📁"
                                font.pixelSize: ThemeManager.fontSizeSmall
                            }

                            Text {
                                Layout.fillWidth: true
                                text: fileName
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeSmall
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: databaseFolderPickerSelectedFolder = dirUrl
                            onDoubleClicked: {
                                databaseFolderPickerCurrentFolder = dirUrl
                                databaseFolderPickerSelectedFolder = ""
                                databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Text {
                    Layout.fillWidth: true
                    text: databaseFolderPickerSelectedFolder && databaseFolderPickerSelectedFolder !== ""
                        ? ("Selected: " + databaseFolderPickerSelectedFolder.toString().replace("file://", ""))
                        : "Selected: (current folder)"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideMiddle
                }
            }

            Text {
                Layout.fillWidth: true
                visible: databaseFolderPickerStatus && databaseFolderPickerStatus.length > 0
                text: databaseFolderPickerStatus
                color: ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: databaseFolderPickerDialog.close()
                }

                SettingsButton {
                    text: databaseFolderPickerMode === "move" ? "Move Here" : "Choose"
                    enabled: databaseFolderPickerCurrentFolder && databaseFolderPickerCurrentFolder !== ""
                    onClicked: {
                        if (!DataStore) return
                        const chosen = (databaseFolderPickerSelectedFolder && databaseFolderPickerSelectedFolder !== "")
                            ? databaseFolderPickerSelectedFolder
                            : databaseFolderPickerCurrentFolder
                        databaseFolderPickerStatus = ""
                        if (databaseFolderPickerMode === "move") {
                            const ok = DataStore.moveDatabaseToFolder(chosen)
                            if (ok) {
                                databaseSucceeded = true
                                databaseStatus = "Database moved."
                                refreshNotebooks()
                                databaseFolderPickerDialog.close()
                            }
                        } else {
                            databaseCreateFolder = chosen
                            databaseFolderPickerDialog.close()
                        }
                    }
                }
            }
        }
    }

    property Dialog _newFolderDialog: Dialog {
        id: newFolderDialog
        title: "New Folder"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(420, parent.width * 0.9)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingMedium

            TextField {
                Layout.fillWidth: true
                placeholderText: "Folder name"
                text: newFolderName
                onTextChanged: newFolderName = text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: newFolderDialog.close()
                }

	                    SettingsButton {
	                        text: "Create"
	                        enabled: newFolderName && newFolderName.trim().length > 0
	                        onClicked: {
	                            if (!DataStore) return
	                            const parentUrl = newFolderTarget === "import"
	                                ? importFolderPickerCurrentFolder
	                                : (newFolderTarget === "db" ? databaseFolderPickerCurrentFolder : folderPickerCurrentFolder)
	                            const created = DataStore.createFolder(parentUrl, newFolderName)
	                            if (created && created.toString && created.toString() !== "") {
	                                if (newFolderTarget === "import") {
	                                    importFolderPickerCurrentFolder = created
	                                    importFolderPickerSelectedFolder = ""
	                                    importFolderPickerStatus = ""
                                    importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
	                                } else if (newFolderTarget === "db") {
	                                    if (databaseFilePickerDialog && databaseFilePickerDialog.visible) {
	                                        databaseFilePickerCurrentFolder = created
	                                        databaseFilePickerSelectedFile = ""
	                                        databaseFilePickerStatus = ""
                                        databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
	                                    } else {
	                                        databaseFolderPickerCurrentFolder = created
	                                        databaseFolderPickerSelectedFolder = ""
	                                        databaseFolderPickerStatus = ""
                                        databaseFolderPickerPathText = _localPathFromUrl(databaseFolderPickerCurrentFolder)
	                                    }
	                                } else {
	                                    folderPickerCurrentFolder = created
	                                    folderPickerSelectedFolder = ""
	                                    exportFolderPickerStatus = ""
                                    exportFolderPickerPathText = _localPathFromUrl(folderPickerCurrentFolder)
	                                }
	                            } else {
	                                const msg = "Could not create folder."
	                                if (newFolderTarget === "import") importFolderPickerStatus = msg
	                                else if (newFolderTarget === "db") {
	                                    if (databaseFilePickerDialog && databaseFilePickerDialog.visible) databaseFilePickerStatus = msg
	                                    else databaseFolderPickerStatus = msg
	                                }
	                                else exportFolderPickerStatus = msg
	                            }
	                            newFolderDialog.close()
	                        }
	                    }
            }
        }
    }

    property Dialog _createDatabaseDialog: Dialog {
        id: createDatabaseDialog
        title: "Create New Database"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(520, parent.width * 0.9)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingMedium

            SettingsRow {
                label: "Folder"
                SettingsButton {
                    text: "Choose Folder…"
                    onClicked: {
                        databaseFolderPickerStatus = ""
                        openDatabaseCreateFolderPicker()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: databaseCreateFolder && databaseCreateFolder !== ""
                    ? databaseCreateFolder.toString().replace("file://", "")
                    : "(not selected)"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
                elide: Text.ElideMiddle
            }

            SettingsRow {
                label: "File name"
                TextField {
                    Layout.fillWidth: true
                    placeholderText: "zinc.db"
                    text: newDbFileName
                    onTextChanged: newDbFileName = text
                }
            }

            Text {
                Layout.fillWidth: true
                visible: databaseFolderPickerStatus && databaseFolderPickerStatus.length > 0
                text: databaseFolderPickerStatus
                color: ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: databaseStatus && databaseStatus.length > 0
                text: databaseStatus
                color: databaseSucceeded ? ThemeManager.success : ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: createDatabaseDialog.close()
                }

                SettingsButton {
                    text: "Create"
                    enabled: databaseCreateFolder && databaseCreateFolder !== "" && newDbFileName && newDbFileName.trim().length > 0
                    onClicked: {
                        if (!DataStore) return
                        databaseStatus = ""
                        databaseSucceeded = false
                        const ok = DataStore.createNewDatabase(databaseCreateFolder, newDbFileName)
                        if (ok) {
                            databaseSucceeded = true
                            databaseStatus = "Database created."
                            refreshNotebooks()
                            createDatabaseDialog.close()
                        }
                    }
                }
            }
        }
    }

    property Dialog _databaseFilePickerDialog: Dialog {
        id: databaseFilePickerDialog
        title: "Open Database"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(560, parent.width * 0.9)
        height: isMobile ? parent.height * 0.85 : Math.min(520, parent.height * 0.85)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                SettingsButton {
                    text: "Up"
                    enabled: DataStore && databaseFilePickerCurrentFolder !== "" &&
                        DataStore.parentFolder(databaseFilePickerCurrentFolder).toString() !== databaseFilePickerCurrentFolder.toString()
                    onClicked: {
                        if (!DataStore) return
                        databaseFilePickerCurrentFolder = DataStore.parentFolder(databaseFilePickerCurrentFolder)
                        databaseFilePickerSelectedFile = ""
                        databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
                    }
                }

                SettingsButton {
                    text: "New Folder…"
                    enabled: databaseFilePickerCurrentFolder && databaseFilePickerCurrentFolder !== ""
                    onClicked: {
                        newFolderName = ""
                        newFolderTarget = "db"
                        databaseFilePickerStatus = ""
                        // Reuse new-folder dialog against current folder.
                        databaseFolderPickerCurrentFolder = databaseFilePickerCurrentFolder
                        databaseFolderPickerSelectedFolder = ""
                        newFolderDialog.open()
                    }
                }

                TextField {
                    objectName: "databaseFilePickerPathField"
                    Layout.fillWidth: true
                    placeholderText: "Path (folder or database file)"
                    text: databaseFilePickerPathText
                    selectByMouse: true
                    onTextChanged: databaseFilePickerPathText = text
                    onAccepted: {
                        if (!DataStore) return
                        const url = _urlFromUserPathText(databaseFilePickerPathText)
                        if (!url || url === "") return
                        databaseFilePickerStatus = ""
                        if (_looksLikeFilePath(databaseFilePickerPathText)) {
                            databaseFilePickerSelectedFile = url
                            databaseFilePickerCurrentFolder = DataStore.parentFolder(url)
                            return
                        }
                        databaseFilePickerCurrentFolder = url
                        databaseFilePickerSelectedFile = ""
                    }
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: ThemeManager.background
                radius: ThemeManager.radiusSmall
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border

                ListView {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    clip: true
                    model: FolderListModel {
                        objectName: "databaseFileListModel"
                        folder: databaseFilePickerCurrentFolder
                        showDirs: true
                        showFiles: true
                        showHidden: true
                        showDotAndDotDot: false
                        nameFilters: ["*.db", "*.sqlite", "*.sqlite3"]
                        sortField: FolderListModel.Name
                    }

                    delegate: Rectangle {
                        readonly property string itemUrl: "file://" + filePath
                        width: ListView.view.width
                        height: 36
                        radius: ThemeManager.radiusSmall
                        color: (databaseFilePickerSelectedFile && databaseFilePickerSelectedFile.toString() === itemUrl)
                            ? ThemeManager.surfaceHover
                            : (rowMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ThemeManager.spacingSmall
                            anchors.rightMargin: ThemeManager.spacingSmall
                            spacing: ThemeManager.spacingSmall

                            Text {
                                text: fileIsDir ? "📁" : "📄"
                                font.pixelSize: ThemeManager.fontSizeSmall
                            }

                            Text {
                                Layout.fillWidth: true
                                text: fileName
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeSmall
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                databaseFilePickerSelectedFile = itemUrl
                                databaseFilePickerPathText = _localPathFromUrl(itemUrl)
                            }
                            onDoubleClicked: {
                                if (fileIsDir) {
                                    databaseFilePickerCurrentFolder = itemUrl
                                    databaseFilePickerSelectedFile = ""
                                    databaseFilePickerPathText = _localPathFromUrl(databaseFilePickerCurrentFolder)
                                    return
                                }
                                databaseFilePickerSelectedFile = itemUrl
                                databaseFilePickerPathText = _localPathFromUrl(itemUrl)
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: databaseFilePickerSelectedFile && databaseFilePickerSelectedFile !== ""
                    ? ("Selected: " + databaseFilePickerSelectedFile.toString().replace("file://", ""))
                    : "Selected: (none)"
                color: ThemeManager.textSecondary
                font.pixelSize: ThemeManager.fontSizeSmall
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                visible: databaseFilePickerStatus && databaseFilePickerStatus.length > 0
                text: databaseFilePickerStatus
                color: ThemeManager.danger
                font.pixelSize: ThemeManager.fontSizeSmall
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: databaseFilePickerDialog.close()
                }

                SettingsButton {
                    text: "Open"
                    enabled: databaseFilePickerSelectedFile && databaseFilePickerSelectedFile !== "" && !databaseFilePickerSelectedFile.toString().endsWith("/")
                    onClicked: {
                        if (!DataStore) return
                        databaseFilePickerStatus = ""
                        const ok = DataStore.openDatabaseFile(databaseFilePickerSelectedFile)
                        if (ok) {
                            databaseSucceeded = true
                            databaseStatus = "Database opened."
                            refreshNotebooks()
                            databaseFilePickerDialog.close()
                        }
                    }
                }
            }
        }
    }

    property Dialog _importFolderPickerDialog: Dialog {
        id: importFolderPickerDialog
        title: "Choose Import Folder"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.NoButton

        width: isMobile ? parent.width * 0.95 : Math.min(520, parent.width * 0.9)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: isMobile ? 0 : 1
            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            radius: ThemeManager.radiusLarge
        }

        contentItem: ColumnLayout {
            anchors.margins: ThemeManager.spacingMedium
            spacing: ThemeManager.spacingSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacingSmall

                SettingsButton {
                    text: "Up"
                    enabled: DataStore && importFolderPickerCurrentFolder && importFolderPickerCurrentFolder !== "" &&
                             DataStore.parentFolder(importFolderPickerCurrentFolder).toString() !== importFolderPickerCurrentFolder.toString()
                    onClicked: {
                        if (!DataStore) return
                        importFolderPickerCurrentFolder = DataStore.parentFolder(importFolderPickerCurrentFolder)
                        importFolderPickerSelectedFolder = ""
                        importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
                    }
	                    }

	                    SettingsButton {
	                        text: "New Folder…"
	                        enabled: importFolderPickerCurrentFolder && importFolderPickerCurrentFolder !== ""
	                        onClicked: {
	                            newFolderName = ""
	                            newFolderTarget = "import"
	                            importFolderPickerStatus = ""
	                            newFolderDialog.open()
	                        }
	                    }

	                    TextField {
                        objectName: "importFolderPickerPathField"
	                        Layout.fillWidth: true
                        placeholderText: "Path"
                        text: importFolderPickerPathText
                        selectByMouse: true
                        onTextChanged: importFolderPickerPathText = text
                        onAccepted: {
                            const url = _urlFromUserPathText(importFolderPickerPathText)
                            if (!url || url === "") return
                            importFolderPickerStatus = ""
                            importFolderPickerCurrentFolder = url
                            importFolderPickerSelectedFolder = ""
                        }
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                }
            }

            FolderListModel {
                id: importFolderListModel
                objectName: "importFolderListModel"
                folder: importFolderPickerCurrentFolder
                showDirs: true
                showFiles: false
                showHidden: true
                showDotAndDotDot: false
                sortField: FolderListModel.Name
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                clip: true

                ListView {
                    width: parent.width
                    model: importFolderListModel
                    spacing: 2

	                        delegate: Rectangle {
	                            readonly property string dirUrl: "file://" + filePath
	                            width: ListView.view.width
	                            height: 36
	                            radius: ThemeManager.radiusSmall
	                            color: (importFolderPickerSelectedFolder && importFolderPickerSelectedFolder.toString() === dirUrl)
	                                ? ThemeManager.surfaceHover
	                                : (rowMouse.containsMouse ? ThemeManager.surfaceHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ThemeManager.spacingSmall
                            anchors.rightMargin: ThemeManager.spacingSmall
                            spacing: ThemeManager.spacingSmall

                            Text {
                                text: "📁"
                                font.pixelSize: ThemeManager.fontSizeSmall
                            }

                            Text {
                                Layout.fillWidth: true
                                text: fileName
                                color: ThemeManager.text
                                font.pixelSize: ThemeManager.fontSizeSmall
                                elide: Text.ElideRight
                            }
                        }

	                            MouseArea {
	                                id: rowMouse
	                                anchors.fill: parent
	                                hoverEnabled: true
	                                cursorShape: Qt.PointingHandCursor
	                                onClicked: importFolderPickerSelectedFolder = dirUrl
	                                onDoubleClicked: {
	                                    importFolderPickerCurrentFolder = dirUrl
	                                    importFolderPickerSelectedFolder = ""
                                    importFolderPickerPathText = _localPathFromUrl(importFolderPickerCurrentFolder)
	                                }
	                            }
	                        }
                }
            }

	                RowLayout {
	                    Layout.fillWidth: true
	                    spacing: ThemeManager.spacingSmall

	                    Text {
                    Layout.fillWidth: true
                    text: importFolderPickerSelectedFolder && importFolderPickerSelectedFolder !== ""
                        ? ("Selected: " + importFolderPickerSelectedFolder.toString().replace("file://", ""))
                        : "Selected: (current folder)"
                    color: ThemeManager.textSecondary
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideMiddle
	                    }
	                }

	                Text {
	                    Layout.fillWidth: true
	                    visible: importFolderPickerStatus && importFolderPickerStatus.length > 0
	                    text: importFolderPickerStatus
	                    color: ThemeManager.danger
	                    font.pixelSize: ThemeManager.fontSizeSmall
	                    wrapMode: Text.Wrap
	                }

	                RowLayout {
	                    Layout.fillWidth: true
	                    spacing: ThemeManager.spacingSmall

                Item { Layout.fillWidth: true }

                SettingsButton {
                    text: "Cancel"
                    onClicked: importFolderPickerDialog.close()
                }

                SettingsButton {
                    text: "Choose"
                    enabled: importFolderPickerCurrentFolder && importFolderPickerCurrentFolder !== ""
                    onClicked: {
                        const chosen = (importFolderPickerSelectedFolder && importFolderPickerSelectedFolder !== "")
                            ? importFolderPickerSelectedFolder
                            : importFolderPickerCurrentFolder
                        importSourceFolder = chosen
                        if (DataStore) DataStore.setExportLastFolder(chosen)
                        importFolderPickerDialog.close()
                    }
                }
            }
        }
    }
}
