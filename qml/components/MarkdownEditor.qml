import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property string pageTitle: ""
    property string pageId: ""
    property var availablePages: []

    signal titleEdited(string newTitle)

    property var blockSpans: []
    property int draggingBlockIndex: -1
    property int dragTargetIndex: -1

    property double lastLocalEditMs: 0
    property var pendingDateInsertSpan: null

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

    function loadPage(id) {
        if (pageId && pageId !== "" && pageId !== id) {
            saveBlocks()
        }
        pageId = id
        loadFromStorage()
    }

    function stripHeaderIfPresent(markdown) {
        const header = "<!-- zinc-blocks v1 -->"
        let text = markdown || ""
        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim() === "") continue
            if (lines[i].trim() === header) {
                lines.splice(i, 1)
                if (i < lines.length && lines[i].trim() === "") lines.splice(i, 1)
                return lines.join("\n")
            }
            break
        }
        return text
    }

    function loadFromStorage() {
        try {
            const markdown = DataStore ? DataStore.getPageContentMarkdown(pageId) : ""
            editor.text = stripHeaderIfPresent(markdown || "")
            parseTimer.restart()
        } catch (e) {
            console.log("MarkdownEditor: Error loading blocks:", e)
            editor.text = ""
        }
    }

    function ensureEditorPadding() {
        editor.leftPadding = gutter.width + ThemeManager.spacingMedium
        editor.rightPadding = ThemeManager.spacingMedium
        editor.topPadding = ThemeManager.spacingMedium
        editor.bottomPadding = ThemeManager.spacingMedium
    }

    function saveBlocks() {
        if (!pageId || pageId === "") return
        try {
            if (DataStore) DataStore.savePageContentMarkdown(pageId, editor.text || "")
        } catch (e) {
            console.log("MarkdownEditor: Error saving blocks:", e)
        }
    }

    Timer {
        id: saveTimer
        interval: 750
        onTriggered: saveBlocks()
    }

    Timer {
        id: parseTimer
        interval: 120
        repeat: false
        onTriggered: {
            try {
                blockSpans = MarkdownBlocks.parseWithSpans(editor.text || "")
            } catch (e) {
                blockSpans = []
            }
        }
    }

    function scheduleAutosave() {
        lastLocalEditMs = Date.now()
        saveTimer.restart()
        parseTimer.restart()
    }

    function textItem() {
        return editor && editor.contentItem ? editor.contentItem : null
    }

    function blockTopY(blockIndex) {
        const t = textItem()
        if (!t) return 0
        if (blockIndex < 0 || blockIndex >= blockSpans.length) return 0
        const start = blockSpans[blockIndex].start || 0
        const r = t.positionToRectangle(start)
        const p = t.mapToItem(gutter, 0, r.y)
        return p.y
    }

    function blockIndexAtY(y) {
        if (!blockSpans || blockSpans.length === 0) return -1
        let best = 0
        let bestDist = 1e9
        for (let i = 0; i < blockSpans.length; i++) {
            const dy = Math.abs(blockTopY(i) - y)
            if (dy < bestDist) {
                bestDist = dy
                best = i
            }
        }
        return best
    }

    function replaceRange(start, end, replacement) {
        const s = Math.max(0, start)
        const e = Math.max(s, end)
        const before = editor.text.substring(0, s)
        const after = editor.text.substring(e)
        editor.text = before + replacement + after
        scheduleAutosave()
    }

    function toggleTodoAt(blockIndex) {
        const b = blockSpans[blockIndex]
        if (!b) return
        const raw = b.raw || ""
        let out = raw
        if (raw.indexOf("- [x]") >= 0 || raw.indexOf("- [X]") >= 0) {
            out = raw.replace("- [x]", "- [ ]").replace("- [X]", "- [ ]")
        } else if (raw.indexOf("- [ ]") >= 0) {
            out = raw.replace("- [ ]", "- [x]")
        }
        replaceRange(b.start, b.end, out)
    }

    function currentBlockIndex() {
        const t = textItem()
        if (!t) return -1
        const pos = t.cursorPosition
        for (let i = 0; i < blockSpans.length; i++) {
            const b = blockSpans[i]
            if (pos >= b.start && pos <= b.end) return i
        }
        return -1
    }

    function currentLinePrefix() {
        const t = textItem()
        if (!t) return ""
        const pos = t.cursorPosition
        const text = editor.text
        const lineStart = text.lastIndexOf("\n", pos - 1) + 1
        return text.substring(lineStart, pos)
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.height + 200
        clip: true

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: contentColumn
            width: Math.min(ThemeManager.editorMaxWidth, parent.width - ThemeManager.spacingXXLarge * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: ThemeManager.spacingMedium

            TextInput {
                id: titleInput

                Layout.fillWidth: true
                Layout.topMargin: ThemeManager.spacingXLarge
                Layout.bottomMargin: ThemeManager.spacingSmall

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

            Item {
                id: editorWrap
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(400, root.height - titleInput.height - ThemeManager.spacingXXLarge * 2)

                TextArea {
                    id: editor
                    objectName: "markdownEditorTextArea"
                    anchors.fill: parent

                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                    persistentSelection: true
                    textFormat: TextEdit.PlainText

                    color: ThemeManager.text
                    placeholderText: "Write in Markdown..."
                    font.family: ThemeManager.monoFontFamily
                    font.pixelSize: ThemeManager.fontSizeNormal

                    background: Rectangle {
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.surface
                        border.width: 1
                        border.color: ThemeManager.border
                    }

                    Component.onCompleted: ensureEditorPadding()
                    onWidthChanged: ensureEditorPadding()
                    onTextChanged: scheduleAutosave()

                    Timer {
                        id: slashTimer
                        interval: 1
                        repeat: false
                        onTriggered: {
                            const line = currentLinePrefix()
                            if (line.startsWith("/") && line.indexOf(" ") === -1) {
                                slashMenu.filterText = line.substring(1)
                                const t = textItem()
                                if (t) {
                                    const r = t.cursorRectangle
                                    const p = t.mapToItem(null, r.x, r.y + r.height)
                                    slashMenu.desiredX = p.x
                                    slashMenu.desiredY = p.y
                                }
                                slashMenu.open()
                            } else {
                                slashMenu.close()
                            }
                        }
                    }

                    function currentLineRange() {
                        const t = textItem()
                        if (!t) return { start: 0, end: 0, text: "" }
                        const pos = t.cursorPosition
                        const text = editor.text
                        const start = text.lastIndexOf("\n", pos - 1) + 1
                        const endIdx = text.indexOf("\n", pos)
                        const end = endIdx >= 0 ? endIdx : text.length
                        return { start: start, end: end, text: text.substring(start, end) }
                    }

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Tab) {
                            const line = currentLineRange()
                            const m = line.text.match(/^(\\s*)(-\\s+\\[[ xX]\\]\\s+|-\\s+)(.*)$/)
                            if (!m) return
                            event.accepted = true
                            const indent = m[1] || ""
                            const marker = m[2] || ""
                            const rest = m[3] || ""
                            const t = textItem()
                            if (event.modifiers & Qt.ShiftModifier) {
                                if (indent.length >= 2) {
                                    replaceRange(line.start, line.end, indent.substring(2) + marker + rest)
                                    t.cursorPosition = Math.max(line.start, t.cursorPosition - 2)
                                }
                            } else {
                                replaceRange(line.start, line.end, "  " + indent + marker + rest)
                                t.cursorPosition = t.cursorPosition + 2
                            }
                            return
                        }

                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const line = currentLineRange()
                            const m = line.text.match(/^(\\s*)(-\\s+\\[[ xX]\\]\\s+|-\\s+)(.*)$/)
                            if (!m) return
                            event.accepted = true
                            const indent = m[1] || ""
                            const marker = m[2] || ""
                            const rest = m[3] || ""
                            const t = textItem()
                            const cursor = t.cursorPosition
                            if (rest.trim().length === 0) {
                                replaceRange(line.start, line.end, "")
                                t.cursorPosition = line.start
                                editor.insert(t.cursorPosition, "\n")
                                t.cursorPosition = t.cursorPosition + 1
                                scheduleAutosave()
                                return
                            }
                            editor.insert(cursor, "\n" + indent + marker)
                            t.cursorPosition = cursor + 1 + indent.length + marker.length
                            scheduleAutosave()
                            return
                        }

                        if (event.text && event.text.length > 0) {
                            Qt.callLater(function() {
                                slashTimer.restart()
                            })
                        }
                    }
                }

                Item {
                    id: gutter
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 28

                    Repeater {
                        model: root.blockSpans

                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index

                            width: gutter.width
                            height: 24
                            y: root.blockTopY(index)

                            Rectangle {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                radius: ThemeManager.radiusSmall
                                color: dragArea.pressed || dragArea.containsMouse ? ThemeManager.surfaceHover : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "⋮⋮"
                                    color: ThemeManager.textMuted
                                    font.pixelSize: 10
                                }

                                MouseArea {
                                    id: dragArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.SizeAllCursor

                                    onPressed: function(mouse) {
                                        root.draggingBlockIndex = index
                                        root.dragTargetIndex = index
                                    }

                                    onPositionChanged: function(mouse) {
                                        if (!pressed) return
                                        const p = row.mapToItem(gutter, mouse.x, mouse.y)
                                        root.dragTargetIndex = root.blockIndexAtY(p.y)
                                        // Autoscroll internal TextArea while dragging
                                        const margin = 24
                                        const speed = 18
                                        if (p.y < margin) {
                                            editor.flickable.contentY = Math.max(0, editor.flickable.contentY - speed)
                                        } else if (p.y > (editorWrap.height - margin)) {
                                            editor.flickable.contentY = Math.min(editor.flickable.contentHeight - editorWrap.height,
                                                                                 editor.flickable.contentY + speed)
                                        }
                                    }

                                    onReleased: {
                                        if (root.draggingBlockIndex >= 0 && root.dragTargetIndex >= 0 &&
                                            root.draggingBlockIndex !== root.dragTargetIndex) {
                                            let blocks = []
                                            for (let i = 0; i < root.blockSpans.length; i++) {
                                                blocks.push(root.blockSpans[i].raw || "")
                                            }
                                            const moved = blocks.splice(root.draggingBlockIndex, 1)[0]
                                            blocks.splice(root.dragTargetIndex, 0, moved)
                                            editor.text = blocks.join("\n\n")
                                            scheduleAutosave()
                                        }
                                        root.draggingBlockIndex = -1
                                        root.dragTargetIndex = -1
                                    }
                                }
                            }

                            Rectangle {
                                width: 16
                                height: 16
                                radius: ThemeManager.radiusSmall
                                anchors.left: parent.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.blockType === "todo" && modelData.checked ? ThemeManager.accent : "transparent"
                                border.width: modelData.blockType === "todo" ? 2 : 0
                                border.color: ThemeManager.border
                                visible: modelData.blockType === "todo"

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "white"
                                    font.pixelSize: 10
                                    visible: modelData.checked
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleTodoAt(index)
                                }
                            }

                            Text {
                                anchors.left: parent.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "•"
                                color: ThemeManager.textMuted
                                font.pixelSize: 14
                                visible: modelData.blockType === "bulleted"
                            }
                        }
                    }
                }
            }
        }
    }

    SlashMenu {
        id: slashMenu
        z: 9999
        onCommandSelected: function(command) {
            const idx = root.currentBlockIndex()
            if (idx < 0 || idx >= root.blockSpans.length) return
            const b = root.blockSpans[idx]
            const raw = (b.raw || "").trim()

            let content = raw
            if (content.startsWith("/")) content = ""
            // Remove leading markdown markers when transforming between block types.
            if (content.startsWith("#")) content = content.replace(/^#{1,3}\\s+/, "")
            if (content.startsWith("- [ ] ")) content = content.substring(6)
            if (content.startsWith("- [x] ")) content = content.substring(6)
            if (content.startsWith("- ")) content = content.substring(2)
            if (content.startsWith("> ")) content = content.split("\\n").map(l => l.startsWith("> ") ? l.substring(2) : l).join("\\n")

            function replaceWith(text) {
                root.replaceRange(b.start, b.end, text + "\n")
            }

            if (command.type === "date") {
                pendingDateInsertSpan = b
                datePicker.selectedDate = new Date()
                datePicker.includeTime = false
                datePicker.open()
            } else if (command.type === "datetime") {
                pendingDateInsertSpan = b
                datePicker.selectedDate = new Date()
                datePicker.includeTime = true
                datePicker.open()
            } else if (command.type === "now") {
                replaceWith(formatLocalDateTime(new Date()))
            } else if (command.type === "heading") {
                const hashes = command.level === 1 ? "#" : command.level === 2 ? "##" : "###"
                replaceWith(hashes + " " + content)
            } else if (command.type === "bulleted") {
                // Convert current block into a bulleted list block (single item to start).
                replaceWith("- " + content)
            } else if (command.type === "todo") {
                replaceWith("- [ ] " + content)
            } else if (command.type === "image") {
                replaceWith("![]()")
            } else if (command.type === "columns") {
                const count = command.count || 2
                let cols = []
                for (let i = 0; i < count; i++) cols.push("")
                replaceWith("<!-- zinc-columns v1 " + JSON.stringify({ cols: cols }) + " -->")
            } else if (command.type === "quote") {
                const lines = content.split("\n")
                replaceWith(lines.map(l => "> " + l).join("\n"))
            } else if (command.type === "code") {
                replaceWith("```\n" + content + "\n```")
            } else if (command.type === "divider") {
                replaceWith("---")
            } else if (command.type === "toggle") {
                replaceWith("<details><summary>" + (content === "" ? "Toggle" : content) + "</summary></details>")
            } else if (command.type === "paragraph") {
                replaceWith(content)
            } else if (command.type === "link") {
                // Placeholder link; page picker integration TBD.
                replaceWith("[Link](zinc://page/)")
            }
        }
    }

    DatePickerPopup {
        id: datePicker
        z: 10000
        onAccepted: function(date) {
            const span = pendingDateInsertSpan
            pendingDateInsertSpan = null
            if (!span) return
            root.replaceRange(span.start, span.end, (datePicker.includeTime ? formatLocalDateTime(date) : formatLocalDate(date)) + "\n")
        }
        onCanceled: pendingDateInsertSpan = null
    }

    function generateUuid() {
        function s4() {
            return Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)
        }
        return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4()
    }
}
