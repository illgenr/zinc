import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property string content: ""
    property var editor: null
    property int blockIndex: -1

    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()

    implicitHeight: Math.max(imageWrap.implicitHeight + ThemeManager.spacingSmall * 2, 80)

    Rectangle {
        anchors.fill: parent
        radius: ThemeManager.radiusSmall
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
    }

    ColumnLayout {
        id: imageWrap
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingSmall

        Image {
            id: image
            Layout.fillWidth: true
            Layout.preferredHeight: sourceSize.height > 0
                                    ? Math.min(360, Math.max(120, sourceSize.height))
                                    : 160
            fillMode: Image.PreserveAspectFit
            source: root.content
            cache: true
            asynchronous: true
            visible: root.content && root.content.length > 0
        }

        Text {
            Layout.fillWidth: true
            text: "Paste an image (Ctrl+V) or use /image to upload"
            color: ThemeManager.textMuted
            font.pixelSize: ThemeManager.fontSizeSmall
            wrapMode: Text.WordWrap
            visible: !image.visible
        }
    }

    TextEdit {
        id: keyCatcher
        visible: false
        text: ""
        focus: false

        onActiveFocusChanged: {
            if (activeFocus) {
                root.blockFocused()
            }
        }

        Keys.onReturnPressed: function(event) {
            event.accepted = true
            root.enterPressed()
        }

        Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && root.editor) {
                if (root.editor.pasteFromClipboard(root.blockIndex)) {
                    event.accepted = true
                }
            } else if (event.key === Qt.Key_Backspace) {
                event.accepted = true
                root.backspaceOnEmpty()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: keyCatcher.forceActiveFocus()
    }

    DragHandler {
        target: null
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        onActiveChanged: {
            if (!root.editor) return
            if (active) {
                const p = root.mapToItem(root.editor, centroid.pressPosition.x, centroid.pressPosition.y)
                root.editor.startCrossBlockSelection(p)
            } else {
                root.editor.endCrossBlockSelection()
            }
        }

        onTranslationChanged: {
            if (!active || !root.editor) return
            const p = root.mapToItem(root.editor, centroid.position.x, centroid.position.y)
            root.editor.updateCrossBlockSelection(p)
        }
    }

    property alias textControl: keyCatcher
}

