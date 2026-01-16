import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Rectangle {
    id: root
    
    property string content: ""
    property string codeLanguage: ""
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    
    signal contentEdited(string newContent)
    signal blockFocused()
    
    implicitHeight: Math.max(codeEdit.contentHeight + 60, 80)
    
    color: ThemeManager.codeBackground
    border.width: 1
    border.color: ThemeManager.codeBorder
    radius: ThemeManager.radiusSmall
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingSmall
        
        // Language selector
        RowLayout {
            Layout.fillWidth: true
            
            TextField {
                id: langField
                
                Layout.preferredWidth: 120
                
                text: root.codeLanguage
                placeholderText: "language"
                color: ThemeManager.textSecondary
                font.family: ThemeManager.monoFontFamily
                font.pixelSize: ThemeManager.fontSizeSmall
                
                background: Rectangle {
                    color: "transparent"
                }
            }
            
            Item { Layout.fillWidth: true }
            
            // Copy button
            ToolButton {
                width: 24
                height: 24
                
                contentItem: Text {
                    text: "📋"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                background: Rectangle {
                    radius: ThemeManager.radiusSmall
                    color: parent.hovered ? ThemeManager.surfaceHover : "transparent"
                }
            }
        }
        
        // Code content
        TextEdit {
            id: codeEdit

            Layout.fillWidth: true
            Layout.fillHeight: true

            text: root.content
            color: ThemeManager.text
            font.family: ThemeManager.monoFontFamily
            font.pixelSize: ThemeManager.fontSizeNormal
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            tabStopDistance: 40

            // Placeholder
            Text {
                text: "// Enter code here"
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

            function insertAtCursor(s) {
                const pos = codeEdit.cursorPosition
                codeEdit.insert(pos, s)
                codeEdit.cursorPosition = pos + s.length
            }

            Keys.onReturnPressed: function(event) {
                event.accepted = true
                insertAtCursor("\n")
            }

            Keys.onEnterPressed: function(event) {
                event.accepted = true
                insertAtCursor("\n")
            }

            Keys.onTabPressed: function(event) {
                event.accepted = true
                insertAtCursor("\t")
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Tab) {
                    event.accepted = true
                    insertAtCursor("\t")
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

    property alias textControl: codeEdit
}
