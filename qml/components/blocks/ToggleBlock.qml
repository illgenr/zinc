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
            
            text: root.content
            color: ThemeManager.text
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeNormal
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            
            // Placeholder
            Text {
                anchors.fill: parent
                text: "Toggle"
                color: ThemeManager.textPlaceholder
                font: parent.font
                visible: parent.text.length === 0 && !parent.activeFocus
            }
            
            onTextChanged: {
                if (text !== root.content) {
                    root.contentEdited(text)
                }
            }
            
            onActiveFocusChanged: {
                if (activeFocus) {
                    root.blockFocused()
                }
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
