import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Popup {
    id: root

    property var availablePages: []
    property string queryText: ""

    signal pageSelected(string pageId, string pageTitle)
    signal createPageRequested(string title)

    property var matches: []
    property int currentIndex: 0

    function updateMatches() {
        const pages = availablePages || []
        const q = (queryText || "").trim().toLowerCase()
        if (q === "") {
            matches = pages.slice(0, 20)
        } else {
            matches = pages.filter(p => (p.title || "").toLowerCase().indexOf(q) >= 0).slice(0, 20)
        }
        currentIndex = 0
    }

    function openAt(x, y, initialQuery) {
        queryText = initialQuery || ""
        updateMatches()
        root.x = Math.max(0, Math.min((parent ? parent.width : 10000) - width, x))
        root.y = Math.max(0, Math.min((parent ? parent.height : 10000) - height, y))
        open()
        Qt.callLater(() => query.forceActiveFocus())
    }

    function acceptCurrent() {
        const q = (queryText || "").trim()
        if (matches.length > 0) {
            const m = matches[currentIndex]
            if (m && m.pageId) {
                pageSelected(m.pageId, m.title || "Untitled")
                close()
                return
            }
        }
        if (q !== "") {
            createPageRequested(q)
            close()
        }
    }

    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: ThemeManager.spacingSmall
    width: Math.min(420, parent ? parent.width : 420)
    height: Math.min(260, 60 + list.contentHeight)

    background: Rectangle {
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusMedium
    }

    contentItem: ColumnLayout {
        spacing: ThemeManager.spacingSmall

        TextField {
            id: query
            Layout.fillWidth: true
            placeholderText: "Page…"
            text: root.queryText
            color: ThemeManager.text
            placeholderTextColor: ThemeManager.textMuted

            background: Rectangle {
                radius: ThemeManager.radiusSmall
                color: ThemeManager.surfaceHover
                border.width: 1
                border.color: ThemeManager.border
            }

            onTextChanged: {
                if (text === root.queryText) return
                root.queryText = text
                root.updateMatches()
            }

            Keys.onUpPressed: root.currentIndex = Math.max(0, root.currentIndex - 1)
            Keys.onDownPressed: root.currentIndex = Math.min(list.count - 1, root.currentIndex + 1)
            Keys.onReturnPressed: root.acceptCurrent()
            Keys.onEscapePressed: root.close()
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.matches
            currentIndex: root.currentIndex

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
                    onEntered: root.currentIndex = index
                    onClicked: {
                        root.pageSelected(modelData.pageId, modelData.title || "Untitled")
                        root.close()
                    }
                }
            }

            Keys.onUpPressed: root.currentIndex = Math.max(0, root.currentIndex - 1)
            Keys.onDownPressed: root.currentIndex = Math.min(count - 1, root.currentIndex + 1)
            Keys.onReturnPressed: root.acceptCurrent()
            Keys.onEscapePressed: root.close()
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

            onClicked: root.acceptCurrent()
        }
    }
}
