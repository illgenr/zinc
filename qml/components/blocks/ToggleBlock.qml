import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property string content: ""
    property bool isCollapsed: true
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal collapseToggled()
    signal blockFocused()

    property var inlineRuns: []
    property var typingAttrs: ({})

    property string _lastAppliedMarkup: ""
    property string _lastPlainText: ""
    property bool _syncingFromModel: false

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
    
    implicitHeight: Math.max(rowLayout.height + ThemeManager.spacingSmall * 2, 32)
    
    RowLayout {
        id: rowLayout
        
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingSmall
        
        // Toggle arrow
        Text {
            text: isCollapsed ? "▶" : "▼"
            color: ThemeManager.textSecondary
            font.pixelSize: 10
            
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.collapseToggled()
            }
        }
        
        // Summary text
	        TextEdit {
	            id: textEdit
            
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            
	            text: root._lastPlainText
	            color: ThemeManager.text
	            font.family: ThemeManager.fontFamily
	            font.pixelSize: ThemeManager.fontSizeNormal
	            wrapMode: TextEdit.Wrap
	            selectByMouse: true
	            persistentSelection: true

                InlineRichTextHighlighter {
                    document: textEdit.textDocument
                    runs: root.inlineRuns
                }
            
            // Placeholder
            Text {
                anchors.fill: parent
                text: "Toggle"
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
                event.accepted = true
                root.enterPressed()
            }

            Keys.onPressed: function(event) {
                if ((event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                    // Handled via Keys.onShortcutOverride to avoid duplicate handling.
                    return
                }
                if (root.editor && root.editor.handleEditorKeyEvent && root.editor.handleEditorKeyEvent(event)) {
                    return
                }
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && root.multiBlockSelectionActive && root.editor) {
                    event.accepted = true
                    root.editor.copyCrossBlockSelectionToClipboard()
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
                    if (root.editor.pasteFromClipboard(root.blockIndex)) {
                        event.accepted = true
                    }
                }
            }
        }
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
