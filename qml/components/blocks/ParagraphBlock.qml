import QtQuick
import QtQuick.Controls
import zinc

Item {
    id: root
    
    property string content: ""
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal indentRequested()
    signal outdentRequested()
    signal moveUpRequested()
    signal moveDownRequested()
    signal blockFocused()
    
    readonly property bool showRendered: root.editor && root.editor.renderBlocksWhenNotFocused && !textEdit.activeFocus
    property var inlineRuns: []
    property var typingAttrs: ({})

    property string _lastAppliedMarkup: ""
    property string _lastPlainText: ""
    property bool _syncingFromModel: false

    function markdownForRender() {
        const raw = root.content || ""
        return raw.replace(/\\[(\\s|x|X)\\]/g, (m, v) => (v === "x" || v === "X") ? "☑" : "☐")
    }

    implicitHeight: Math.max((showRendered ? rendered.implicitHeight : textEdit.contentHeight) + ThemeManager.spacingSmall * 2, 32)

    function _syncFromMarkup() {
        if (root._syncingFromModel) return
        const markup = root.content || ""
        if (markup === root._lastAppliedMarkup) return
        root._syncingFromModel = true
        const parsed = InlineRichText.parse(markup)
        const plain = parsed && ("text" in parsed) ? (parsed.text || "") : ""
        root.inlineRuns = parsed && ("runs" in parsed) ? (parsed.runs || []) : []
        root._lastAppliedMarkup = markup
        root._lastPlainText = plain
        if (textEdit.text !== plain) textEdit.text = plain
        root._syncingFromModel = false
    }

    onContentChanged: _syncFromMarkup()
    Component.onCompleted: _syncFromMarkup()
    
    TextEdit {
        id: rendered

        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall

        textFormat: Text.RichText
        text: Cmark.toHtml(root.markdownForRender())
        color: ThemeManager.text
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeNormal
        wrapMode: TextEdit.Wrap
        readOnly: true
        selectByMouse: false
        visible: root.showRendered

        MouseArea {
            id: renderedMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor

            property string hoveredLink: ""
            property point hoveredPoint: Qt.point(0, 0)

            Timer {
                id: linkTooltipTimer
                interval: 1500
                repeat: false
                onTriggered: {
                    if (!renderedMouse.containsMouse) return
                    if (!renderedMouse.hoveredLink || renderedMouse.hoveredLink === "") return
                    linkToolTip.visible = true
                }
            }

            ToolTip {
                id: linkToolTip
                parent: root
                visible: false
                text: renderedMouse.hoveredLink
                x: Math.max(0, Math.min(root.width - implicitWidth, renderedMouse.hoveredPoint.x + 8))
                y: Math.max(0, Math.min(root.height - implicitHeight, renderedMouse.hoveredPoint.y + 18))
            }

            function isExternalHttpLink(link) {
                return link && (link.indexOf("http://") === 0 || link.indexOf("https://") === 0)
            }

            function updateHover(mouse) {
                const link = rendered.linkAt(mouse.x, mouse.y) || ""
                const localPoint = rendered.mapToItem(root, mouse.x, mouse.y)
                renderedMouse.hoveredPoint = Qt.point(localPoint.x, localPoint.y)
                if (link === renderedMouse.hoveredLink) return
                renderedMouse.hoveredLink = link
                linkToolTip.visible = false
                linkTooltipTimer.stop()
                if (link && link !== "") {
                    linkTooltipTimer.restart()
                }
            }

            onClicked: function(mouse) {
                if (!root.editor) return
                const link = rendered.linkAt(mouse.x, mouse.y)
                linkToolTip.visible = false
                linkTooltipTimer.stop()
                if (link && link.indexOf("zinc://date/") === 0 && "openDateEditor" in root.editor) {
                    root.editor.openDateEditor(root.blockIndex, link.substring("zinc://date/".length))
                    return
                }
                if (mouse.modifiers & Qt.ControlModifier) {
                    if (link && link.indexOf("zinc://page/") === 0) {
                        root.editor.navigateToPage(link.substring("zinc://page/".length))
                        return
                    }
                    if (isExternalHttpLink(link) && "externalLinkRequested" in root.editor) {
                        root.editor.externalLinkRequested(link)
                        return
                    }
                }
                textEdit.forceActiveFocus()
            }

            onPositionChanged: function(mouse) {
                updateHover(mouse)
            }

            onExited: {
                renderedMouse.hoveredLink = ""
                linkToolTip.visible = false
                linkTooltipTimer.stop()
            }
        }
    }

    TextEdit {
        id: textEdit
        
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        
        text: root._lastPlainText
        color: ThemeManager.text
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeNormal
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        persistentSelection: true
        visible: !root.showRendered

        InlineRichTextHighlighter {
            document: textEdit.textDocument
            runs: root.inlineRuns
        }
        
        // Placeholder
        Text {
            anchors.fill: parent
            text: "Type '/' for commands..."
            color: ThemeManager.textPlaceholder
            font: parent.font
            visible: parent.text.length === 0 && !parent.activeFocus
        }
        
        onTextChanged: {
            if (root._syncingFromModel) return
            const before = root._lastPlainText
            const after = text
            if (before !== after) {
                const reconciled = InlineRichText.reconcileTextChange(before,
                                                                     after,
                                                                     root.inlineRuns || [],
                                                                     root.typingAttrs || ({}),
                                                                     cursorPosition)
                root.inlineRuns = reconciled && ("runs" in reconciled) ? (reconciled.runs || []) : (root.inlineRuns || [])
                root.typingAttrs = reconciled && ("typingAttrs" in reconciled) ? (reconciled.typingAttrs || ({})) : (root.typingAttrs || ({}))
                root._lastPlainText = after
                const markup = InlineRichText.serialize(after, root.inlineRuns || [])
                root._lastAppliedMarkup = markup
                root.contentEdited(markup)
            }
            root.maybeConvertTaskMarker()
        }
        
        onActiveFocusChanged: {
            if (activeFocus) {
                root.blockFocused()
            }
        }

        onCursorPositionChanged: {
            if (root._syncingFromModel) return
            root.typingAttrs = InlineRichText.attrsAt(root.inlineRuns || [], cursorPosition)
        }

        Keys.onShortcutOverride: function(event) {
            if ((event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                if (root.editor && root.editor.handleEditorKeyEvent && root.editor.handleEditorKeyEvent(event)) {
                    event.accepted = true
                }
            }
        }
        
        Keys.onReturnPressed: function(event) {
            if (event.modifiers & Qt.ShiftModifier) {
                // Shift+Enter: insert newline
                event.accepted = false
            } else {
                event.accepted = true
                root.enterPressed()
            }
        }
        
        Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                // Handled via Keys.onShortcutOverride to avoid duplicate handling.
                return
            }
            if (root.editor && root.editor.handleEditorKeyEvent && root.editor.handleEditorKeyEvent(event)) {
                return
            }
            if (event.text === "[") {
                root.taskMarkerStartPos = cursorPosition
                root.taskMarkerKeystrokes = 0
            }
            if (root.taskMarkerStartPos >= 0 && event.text && event.text.length > 0) {
                root.taskMarkerKeystrokes += 1
            }
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && root.multiBlockSelectionActive && root.editor) {
                event.accepted = true
                root.editor.copyCrossBlockSelectionToClipboard()
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
                if (root.editor.pasteFromClipboard(root.blockIndex)) {
                    event.accepted = true
                }
            } else if (event.modifiers === 0 && root.editor && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                const nav = root.editor.adjacentBlockNavigation(root.blockIndex, event.key, cursorPosition, text.length)
                if (nav && nav.handled) {
                    event.accepted = true
                    root.editor.focusBlockAt(nav.targetIndex, nav.targetPos)
                }
            } else if (event.key === Qt.Key_Backspace && text.length === 0) {
                event.accepted = true
                root.backspaceOnEmpty()
            } else if (event.key === Qt.Key_Tab) {
                event.accepted = true
                if (event.modifiers & Qt.ShiftModifier) {
                    root.outdentRequested()
                } else {
                    root.indentRequested()
                }
            } else if (event.modifiers & Qt.AltModifier) {
                if (event.key === Qt.Key_Up) {
                    event.accepted = true
                    root.moveUpRequested()
                } else if (event.key === Qt.Key_Down) {
                    event.accepted = true
                    root.moveDownRequested()
                }
            }
        }
    }

    property int taskMarkerStartPos: -1
    property int taskMarkerKeystrokes: 0
    property bool taskMarkerConverting: false

    function maybeConvertTaskMarker() {
        if (taskMarkerConverting) return
        if (taskMarkerStartPos < 0) return
        if (taskMarkerKeystrokes > 10) {
            taskMarkerStartPos = -1
            taskMarkerKeystrokes = 0
            return
        }
        const pos = textEdit.cursorPosition
        if (pos - taskMarkerStartPos !== 3) return
        const snippet = textEdit.text.substring(taskMarkerStartPos, taskMarkerStartPos + 3)
        const m = snippet.match(/^\\[(\\s|x|X)\\]$/)
        if (!m) return
        const glyph = (m[1] === "x" || m[1] === "X") ? "☑" : "☐"
        taskMarkerConverting = true
        textEdit.remove(taskMarkerStartPos, 3)
        textEdit.insert(taskMarkerStartPos, glyph)
        textEdit.cursorPosition = taskMarkerStartPos + 1
        taskMarkerConverting = false
        taskMarkerStartPos = -1
        taskMarkerKeystrokes = 0
    }

    Timer {
        id: selectionDelayTimer
        interval: (AndroidUtils.isAndroid() && root.editor) ? root.editor.blockSelectDelayMs : 0
        repeat: false
        onTriggered: {
            if (!selectionDrag.active || !root.editor) return
            selectionDrag.selectionArmed = true
            const p = root.mapToItem(root.editor, selectionDrag.centroid.pressPosition.x, selectionDrag.centroid.pressPosition.y)
            root.editor.startCrossBlockSelection(p)
        }
    }

    DragHandler {
        id: selectionDrag
        target: null
        acceptedButtons: Qt.LeftButton
        grabPermissions: (AndroidUtils.isAndroid() && root.editor && root.editor.blockSelectDelayMs > 0)
            ? PointerHandler.ApprovesTakeOverByAnything
            : PointerHandler.CanTakeOverFromAnything

        property bool selectionArmed: false

        onActiveChanged: {
            if (!root.editor) return
            if (active) {
                selectionArmed = !(AndroidUtils.isAndroid() && root.editor.blockSelectDelayMs > 0)
                if (selectionArmed) {
                    const p = root.mapToItem(root.editor, centroid.pressPosition.x, centroid.pressPosition.y)
                    root.editor.startCrossBlockSelection(p)
                } else {
                    selectionDelayTimer.restart()
                }
            } else {
                selectionDelayTimer.stop()
                if (selectionArmed) {
                    root.editor.endCrossBlockSelection()
                }
                selectionArmed = false
            }
        }

        onTranslationChanged: {
            if (!active || !root.editor || !selectionArmed) return
            const p = root.mapToItem(root.editor, centroid.position.x, centroid.position.y)
            root.editor.updateCrossBlockSelection(p)
        }
    }

    property alias textControl: textEdit
}
