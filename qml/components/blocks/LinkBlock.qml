import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root
    
    property string content: ""  // Format: "pageId|pageTitle"
    property string linkedPageId: content.split("|")[0] || ""
    property string linkedPageTitle: content.split("|")[1] || ""
    property var editor: null
    property int blockIndex: -1
    property bool multiBlockSelectionActive: false
    property bool editing: false
    property string queryText: ""
    
    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()
    signal linkClicked(string pageId)
    
    implicitHeight: 40
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        radius: ThemeManager.radiusSmall
        color: linkMouse.containsMouse ? ThemeManager.surfaceHover : ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: ThemeManager.spacingSmall
            spacing: ThemeManager.spacingSmall
            
            Text {
                text: "📄"
                font.pixelSize: 16
            }
            
            Text {
                Layout.fillWidth: true
                text: linkedPageId ? (linkedPageTitle || "Untitled") : "Type a page name…"
                color: linkedPageId ? ThemeManager.accent : ThemeManager.textPlaceholder
                font.pixelSize: ThemeManager.fontSizeNormal
                font.underline: linkedPageId !== ""
                elide: Text.ElideRight
                visible: !root.editing
            }

            TextField {
                id: input

                Layout.fillWidth: true
                visible: root.editing

                text: root.queryText
                placeholderText: "Link to page…"
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal

                background: Item {}

                onTextChanged: {
                    root.queryText = text
                    suggestions.update()
                }

                Keys.onEscapePressed: {
                    root.editing = false
                    suggestions.close()
                }

                Keys.onReturnPressed: {
                    suggestions.acceptCurrent()
                }
            }
            
            Text {
                text: "↗"
                color: ThemeManager.textSecondary
                font.pixelSize: 14
                visible: linkedPageId !== ""
            }
        }
        
        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            
            onClicked: function(mouse) {
                if (linkedPageId && (mouse.modifiers & Qt.ControlModifier)) {
                    root.linkClicked(linkedPageId)
                    return
                }
                root.editing = true
                root.queryText = linkedPageTitle || ""
                Qt.callLater(function() {
                    input.forceActiveFocus()
                    input.selectAll()
                    suggestions.update()
                    suggestions.openBelow()
                })
            }
        }
    }

    Popup {
        id: suggestions
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0
        width: Math.min(420, root.width)
        height: Math.min(260, list.contentHeight + 16)

        background: Rectangle {
            color: ThemeManager.surface
            border.width: 1
            border.color: ThemeManager.border
            radius: ThemeManager.radiusMedium
        }

        property var matches: []
        property int currentIndex: 0

        function openBelow() {
            x = Math.max(0, (root.width - width) / 2)
            y = root.height
            open()
        }

        function update() {
            if (!root.editor || !root.editor.availablePages) {
                matches = []
                currentIndex = 0
                return
            }
            const q = (root.queryText || "").trim().toLowerCase()
            const pages = root.editor.availablePages
            if (q === "") {
                matches = pages.slice(0, 20)
            } else {
                matches = pages.filter(p => (p.title || "").toLowerCase().indexOf(q) >= 0).slice(0, 20)
            }
            currentIndex = 0
        }

        function acceptCurrent() {
            const q = (root.queryText || "").trim()
            if (q === "") return
            if (matches.length > 0) {
                const m = matches[currentIndex]
                if (m && m.pageId) {
                    root.setLink(m.pageId, m.title || "Untitled")
                    root.editing = false
                    close()
                    return
                }
            }
            // Create new child page under the current page.
            if (root.editor) {
                root.editor.createChildPageRequested(q, root.blockIndex)
            }
            root.editing = false
            close()
        }

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: ThemeManager.spacingSmall
            spacing: 4

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: suggestions.matches
                currentIndex: suggestions.currentIndex

                delegate: Rectangle {
                    width: list.width
                    height: 34
                    radius: ThemeManager.radiusSmall
                    color: ListView.isCurrentItem ? ThemeManager.surfaceHover : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: ThemeManager.spacingSmall
                        text: modelData.title || "Untitled"
                        color: ThemeManager.text
                        elide: Text.ElideRight
                        width: parent.width - ThemeManager.spacingSmall * 2
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: suggestions.currentIndex = index
                        onClicked: {
                            root.setLink(modelData.pageId, modelData.title || "Untitled")
                            root.editing = false
                            suggestions.close()
                        }
                    }
                }

                Keys.onUpPressed: suggestions.currentIndex = Math.max(0, suggestions.currentIndex - 1)
                Keys.onDownPressed: suggestions.currentIndex = Math.min(count - 1, suggestions.currentIndex + 1)
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: ThemeManager.border
                visible: (root.queryText || "").trim().length > 0
            }

            Button {
                Layout.fillWidth: true
                visible: (root.queryText || "").trim().length > 0
                text: "Create \"" + ((root.queryText || "").trim()) + "\" as child page"

                background: Rectangle {
                    radius: ThemeManager.radiusSmall
                    color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surfaceHover
                    border.width: 1
                    border.color: ThemeManager.border
                }

                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeSmall
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: suggestions.acceptCurrent()
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
    
    // Set link data
    function setLink(pageId, pageTitle) {
        root.contentEdited(pageId + "|" + pageTitle)
    }
    
    // Handle key events
    Keys.onPressed: function(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) || (event.modifiers & Qt.MetaModifier)
        if (ctrl && root.editor && root.editor.blocksModel) {
            if (event.key === Qt.Key_Z) {
                event.accepted = true
                if (event.modifiers & Qt.ShiftModifier) {
                    root.editor.blocksModel.redo()
                } else {
                    root.editor.blocksModel.undo()
                }
                return
            } else if (event.key === Qt.Key_Y) {
                event.accepted = true
                root.editor.blocksModel.redo()
                return
            }
        }

        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && root.multiBlockSelectionActive && root.editor) {
            event.accepted = true
            root.editor.copyCrossBlockSelectionToClipboard()
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
            if (root.editor.pasteFromClipboard(root.blockIndex)) {
                event.accepted = true
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            root.enterPressed()
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            event.accepted = true
            root.backspaceOnEmpty()
        }
    }
    
    // Make focusable
    focus: true
}
