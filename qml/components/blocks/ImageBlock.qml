import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Item {
    id: root

    property string content: ""
    property var editor: null
    property int blockIndex: -1
    property string imageSource: ""
    property real desiredWidth: 0
    property real desiredHeight: 0
    property bool updatingFromModel: false
    property bool selected: false
    property bool resizing: false
    property bool pendingResizeEmit: false

    signal contentEdited(string newContent)
    signal enterPressed()
    signal backspaceOnEmpty()
    signal blockFocused()

    function loadFromContent() {
        updatingFromModel = true
        desiredWidth = 0
        desiredHeight = 0
        imageSource = ""
        const raw = root.content || ""
        if (raw.trim().startsWith("{")) {
            try {
                const obj = JSON.parse(raw)
                imageSource = obj && obj.src ? String(obj.src) : ""
                desiredWidth = obj && obj.w ? Number(obj.w) : 0
                desiredHeight = obj && obj.h ? Number(obj.h) : 0
            } catch (e) {
                imageSource = raw
                desiredWidth = 0
                desiredHeight = 0
            }
        } else {
            imageSource = raw
            desiredWidth = 0
            desiredHeight = 0
        }
        if (!isFinite(desiredWidth) || desiredWidth < 0) desiredWidth = 0
        if (!isFinite(desiredHeight) || desiredHeight < 0) desiredHeight = 0
        updatingFromModel = false
    }

    function emitContent() {
        if (updatingFromModel) return
        const json = JSON.stringify({ src: imageSource, w: Math.round(desiredWidth), h: Math.round(desiredHeight) })
        if (json !== root.content) root.contentEdited(json)
    }

    function scheduleEmitContent() {
        if (updatingFromModel) return
        pendingResizeEmit = true
        resizeEmitTimer.restart()
    }

    Component.onCompleted: loadFromContent()
    onContentChanged: loadFromContent()

    implicitHeight: Math.max(imageWrap.implicitHeight + ThemeManager.spacingSmall * 2, 80)

    Timer {
        id: resizeEmitTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (!root.pendingResizeEmit) return
            root.pendingResizeEmit = false
            root.emitContent()
        }
    }

    ColumnLayout {
        id: imageWrap
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingSmall
        spacing: ThemeManager.spacingSmall

        Item {
            id: imageOuter
            Layout.fillWidth: true
            visible: root.imageSource && root.imageSource.length > 0
            Layout.preferredHeight: root.desiredHeight > 0
                                    ? Math.max(80, Math.min(1200, root.desiredHeight))
                                    : (image.sourceSize.height > 0
                                        ? Math.min(360, Math.max(120, image.sourceSize.height))
                                        : 160)

            Item {
                id: imageFrame
                objectName: "imageFrame"
                anchors.centerIn: parent
                width: root.desiredWidth > 0 ? Math.max(80, Math.min(parent.width, root.desiredWidth)) : parent.width
                height: parent.height

                Image {
                    id: image
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: root.imageSource
                    sourceSize.width: Math.max(1, Math.round(width))
                    sourceSize.height: Math.max(1, Math.round(height))
                    cache: true
                    asynchronous: true

                    onStatusChanged: {
                        if (status === Image.Error) {
                            console.log("ImageBlock: load error source=", source, "error=", image.errorString)
                        }
                    }
                }

                Item {
                    id: paintedBox
                    objectName: "paintedBox"
                    anchors.centerIn: parent
                    width: image.paintedWidth > 0 ? image.paintedWidth : parent.width
                    height: image.paintedHeight > 0 ? image.paintedHeight : parent.height
                    visible: root.selected

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 1
                        border.color: "black"
                    }
                }

                component Handle: Item {
                    required property string key
                    required property string label
                    required property int cursorShape
                    required property int dirX
                    required property int dirY

                    width: 18
                    height: 18
                    visible: root.selected
                    objectName: "resizeHandle_" + key

                    Text {
                        anchors.centerIn: parent
                        text: parent.label
                        color: "black"
                        font.pixelSize: 12
                    }

                    HoverHandler {
                        cursorShape: parent.cursorShape
                    }

                    DragHandler {
                        id: resizeDrag
                        target: null
                        acceptedButtons: Qt.LeftButton
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                        dragThreshold: 0

                        property real startW: 0
                        property real startH: 0
                        property real startSceneX: 0
                        property real startSceneY: 0

                        function clampWidth(w) {
                            return Math.max(80, Math.min(imageOuter.width, w))
                        }

                        function clampHeight(h) {
                            return Math.max(80, Math.min(1200, h))
                        }

                        onActiveChanged: {
                            if (active) {
                                root.resizing = true
                                startW = root.desiredWidth > 0 ? root.desiredWidth : imageFrame.width
                                startH = root.desiredHeight > 0 ? root.desiredHeight : imageOuter.height
                                startSceneX = centroid.scenePressPosition.x
                                startSceneY = centroid.scenePressPosition.y
                            } else {
                                root.resizing = false
                                root.pendingResizeEmit = false
                                root.emitContent()
                            }
                        }

                        onTranslationChanged: {
                            if (!active) return
                            const dx = centroid.scenePosition.x - startSceneX
                            const dy = centroid.scenePosition.y - startSceneY
                            if (parent.dirX !== 0) {
                                root.desiredWidth = clampWidth(startW + (parent.dirX * dx))
                            }
                            if (parent.dirY !== 0) {
                                root.desiredHeight = clampHeight(startH + (parent.dirY * dy))
                            }
                            root.scheduleEmitContent()
                        }
                    }
                }

                // 8 handles: corners + sides
                Handle { key: "nw"; label: "↖↘"; cursorShape: Qt.SizeFDiagCursor; dirX: -1; dirY: -1; anchors.left: paintedBox.left; anchors.top: paintedBox.top; anchors.leftMargin: -9; anchors.topMargin: -9 }
                Handle { key: "n"; label: "↕"; cursorShape: Qt.SizeVerCursor; dirX: 0; dirY: -1; anchors.horizontalCenter: paintedBox.horizontalCenter; anchors.top: paintedBox.top; anchors.topMargin: -9 }
                Handle { key: "ne"; label: "↗↙"; cursorShape: Qt.SizeBDiagCursor; dirX: 1; dirY: -1; anchors.right: paintedBox.right; anchors.top: paintedBox.top; anchors.rightMargin: -9; anchors.topMargin: -9 }
                Handle { key: "w"; label: "↔"; cursorShape: Qt.SizeHorCursor; dirX: -1; dirY: 0; anchors.left: paintedBox.left; anchors.verticalCenter: paintedBox.verticalCenter; anchors.leftMargin: -9 }
                Handle { key: "e"; label: "↔"; cursorShape: Qt.SizeHorCursor; dirX: 1; dirY: 0; anchors.right: paintedBox.right; anchors.verticalCenter: paintedBox.verticalCenter; anchors.rightMargin: -9 }
                Handle { key: "sw"; label: "↗↙"; cursorShape: Qt.SizeBDiagCursor; dirX: -1; dirY: 1; anchors.left: paintedBox.left; anchors.bottom: paintedBox.bottom; anchors.leftMargin: -9; anchors.bottomMargin: -9 }
                Handle { key: "s"; label: "↕"; cursorShape: Qt.SizeVerCursor; dirX: 0; dirY: 1; anchors.horizontalCenter: paintedBox.horizontalCenter; anchors.bottom: paintedBox.bottom; anchors.bottomMargin: -9 }
                Handle { key: "se"; label: "↖↘"; cursorShape: Qt.SizeFDiagCursor; dirX: 1; dirY: 1; anchors.right: paintedBox.right; anchors.bottom: paintedBox.bottom; anchors.rightMargin: -9; anchors.bottomMargin: -9 }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: {
                        root.selected = true
                        keyCatcher.forceActiveFocus()
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: contextMenu.popup()
                }

                DragHandler {
                    target: null
                    acceptedButtons: Qt.LeftButton
                    enabled: !root.resizing && root.editor
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                    dragThreshold: 2

                    onActiveChanged: {
                        if (!root.editor) return
                        if (active) {
                            root.selected = true
                            root.editor.startReorderBlock(root.blockIndex)
                            const p = imageFrame.mapToItem(root.editor, centroid.position.x, centroid.position.y)
                            root.editor.updateReorderBlockByEditorY(p.y)
                        } else {
                            root.editor.endReorderBlock()
                        }
                    }

                    onTranslationChanged: {
                        if (!active || !root.editor) return
                        const p = imageFrame.mapToItem(root.editor, centroid.position.x, centroid.position.y)
                        root.editor.updateReorderBlockByEditorY(p.y)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Paste an image (Ctrl+V) or use /image to upload"
            color: ThemeManager.textMuted
            font.pixelSize: ThemeManager.fontSizeSmall
            wrapMode: Text.WordWrap
            visible: !imageOuter.visible
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
            } else {
                root.selected = false
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
        enabled: !imageOuter.visible
        cursorShape: Qt.IBeamCursor
        onClicked: keyCatcher.forceActiveFocus()
    }

    Menu {
        id: contextMenu
        MenuItem {
            text: "Delete"
            onTriggered: {
                if (root.editor && root.editor.deleteBlockAt) {
                    root.editor.deleteBlockAt(root.blockIndex)
                }
            }
        }
        MenuItem {
            text: "Reset size"
            enabled: root.desiredHeight > 0 || root.desiredWidth > 0
            onTriggered: {
                root.desiredWidth = 0
                root.desiredHeight = 0
                root.emitContent()
            }
        }
    }

    property alias textControl: keyCatcher
}
