import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Dialog {
    id: root

    property var conflict: ({})
    readonly property string pageId: (conflict && conflict.pageId) ? conflict.pageId : ""
    readonly property string localTitle: (conflict && conflict.localTitle) ? conflict.localTitle : "This device"
    readonly property string remoteTitle: (conflict && conflict.remoteTitle) ? conflict.remoteTitle : "Other device"

    property var mergePreview: ({})

    function cssColor(c) {
        return "rgba(" +
            Math.round(c.r * 255) + ", " +
            Math.round(c.g * 255) + ", " +
            Math.round(c.b * 255) + ", " +
            c.a.toFixed(3) + ")"
    }

    function escapeHtml(text) {
        return text
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#39;")
    }

    function splitLines(text) {
        if (!text || text.length === 0) return []
        return text.split("\n")
    }

    function lineDiffOps(aText, bText) {
        const a = splitLines(aText)
        const b = splitLines(bText)
        const n = a.length
        const m = b.length
        const cellLimit = 200000

        if ((n + 1) * (m + 1) > cellLimit) {
            const fallback = []
            for (let i = 0; i < n; ++i) fallback.push({ kind: "del", text: a[i] })
            for (let j = 0; j < m; ++j) fallback.push({ kind: "add", text: b[j] })
            return fallback
        }

        const width = m + 1
        const dp = new Array((n + 1) * (m + 1)).fill(0)
        function at(i, j) { return i * width + j }

        for (let i = 0; i < n; ++i) {
            for (let j = 0; j < m; ++j) {
                if (a[i] === b[j]) {
                    dp[at(i + 1, j + 1)] = dp[at(i, j)] + 1
                } else {
                    dp[at(i + 1, j + 1)] = Math.max(dp[at(i, j + 1)], dp[at(i + 1, j)])
                }
            }
        }

        const out = []
        let i = n
        let j = m
        while (i > 0 || j > 0) {
            if (i > 0 && j > 0 && a[i - 1] === b[j - 1]) {
                out.push({ kind: "same", text: a[i - 1] })
                --i
                --j
            } else if (j > 0 && (i === 0 || dp[at(i, j - 1)] >= dp[at(i - 1, j)])) {
                out.push({ kind: "add", text: b[j - 1] })
                --j
            } else {
                out.push({ kind: "del", text: a[i - 1] })
                --i
            }
        }
        out.reverse()
        return out
    }

    function mergePreviewDiffHtml(localContent, remoteContent) {
        const ops = lineDiffOps(localContent, remoteContent)
        if (!ops || ops.length === 0) {
            return ""
        }

        const success = cssColor(ThemeManager.success)
        const danger = cssColor(ThemeManager.danger)
        const neutral = cssColor(ThemeManager.text)
        const formatted = ops.map(function(op) {
            const line = escapeHtml(op.text)
            if (op.kind === "add") {
                return "<span style=\"color: " + success + ";\">+ " + line + "</span>"
            }
            if (op.kind === "del") {
                return "<span style=\"color: " + danger + ";\">- " + line + "</span>"
            }
            return "<span style=\"color: " + neutral + ";\">  " + line + "</span>"
        })

        return "<pre style=\"margin: 0; white-space: pre-wrap; font-family: monospace; color: " + neutral + ";\">" +
            formatted.join("<br/>") +
            "</pre>"
    }

    title: "Sync conflict"
    anchors.centerIn: parent
    modal: true
    standardButtons: Dialog.NoButton

    property bool isMobile: Qt.platform.os === "android" || parent.width < 600
    width: isMobile ? parent.width * 0.95 : Math.min(720, parent.width * 0.95)
    height: isMobile ? Math.min(parent.height * 0.84, parent.height - 88) : Math.min(640, parent.height * 0.92)
    leftPadding: ThemeManager.spacingMedium
    rightPadding: ThemeManager.spacingMedium
    topPadding: ThemeManager.spacingMedium
    bottomPadding: ThemeManager.spacingMedium

    onOpened: {
        if (DataStore && DataStore.previewMergeForPageConflict && pageId !== "") {
            mergePreview = DataStore.previewMergeForPageConflict(pageId)
        } else {
            mergePreview = ({})
        }
    }

    background: Rectangle {
        color: ThemeManager.surface
        border.width: isMobile ? 0 : 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusLarge
    }

    header: Rectangle {
        height: 52
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.margins: ThemeManager.spacingMedium

            Text {
                Layout.fillWidth: true
                text: root.title
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeLarge
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
            }

            ToolButton {
                contentItem: Text {
                    text: "✕"
                    color: ThemeManager.text
                    font.pixelSize: 16
                }
                background: Rectangle {
                    color: parent.pressed ? ThemeManager.surfaceActive : "transparent"
                    radius: ThemeManager.radiusSmall
                }
                onClicked: root.close()
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: ThemeManager.border
        }
    }

    contentItem: ColumnLayout {
        spacing: ThemeManager.spacingMedium

        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: ThemeManager.textSecondary
            text: "This note was edited on both devices since the last sync. Choose which version to keep, or try an automatic merge."
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true

            TabButton { text: "This device" }
            TabButton { text: "Other device" }
            TabButton { text: "Merge" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // Local
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextArea.Wrap
                    color: ThemeManager.text
                    selectedTextColor: ThemeManager.text
                    selectionColor: ThemeManager.accentLight
                    background: Rectangle {
                        color: ThemeManager.surfaceHover
                        border.width: 1
                        border.color: ThemeManager.border
                        radius: ThemeManager.radiusSmall
                    }
                    text: (conflict && conflict.localContentMarkdown) ? conflict.localContentMarkdown : ""
                }
            }

            // Remote
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextArea.Wrap
                    color: ThemeManager.text
                    selectedTextColor: ThemeManager.text
                    selectionColor: ThemeManager.accentLight
                    background: Rectangle {
                        color: ThemeManager.surfaceHover
                        border.width: 1
                        border.color: ThemeManager.border
                        radius: ThemeManager.radiusSmall
                    }
                    text: (conflict && conflict.remoteContentMarkdown) ? conflict.remoteContentMarkdown : ""
                }
            }

            // Merge preview
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ThemeManager.spacingSmall

                Text {
                    Layout.fillWidth: true
                    color: ThemeManager.textSecondary
                    text: {
                        if (!mergePreview || mergePreview.kind === undefined) return "Merge preview unavailable."
                        if (mergePreview.kind === "clean") return "Diff between local and remote changes. Automatic merge looks clean."
                        if (mergePreview.kind === "conflict") return "Diff between local and remote changes. Automatic merge has conflicts."
                        return "Diff between local and remote changes. Automatic merge used fallback mode."
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextEdit {
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.RichText
                        color: ThemeManager.text
                        selectedTextColor: ThemeManager.text
                        selectionColor: ThemeManager.accentLight
                        text: mergePreviewDiffHtml(
                            (conflict && conflict.localContentMarkdown) ? conflict.localContentMarkdown : "",
                            (conflict && conflict.remoteContentMarkdown) ? conflict.remoteContentMarkdown : ""
                        )
                    }
                }
            }
        }
    }

    footer: Rectangle {
        color: "transparent"
        implicitHeight: isMobile ? 88 : 72

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: ThemeManager.border
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: ThemeManager.spacingSmall
            spacing: ThemeManager.spacingSmall

            Button {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: "Keep this device"
                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    if (DataStore && pageId !== "") DataStore.resolvePageConflict(pageId, "local")
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: "Keep other device"
                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    if (DataStore && pageId !== "") DataStore.resolvePageConflict(pageId, "remote")
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: "Try merge"
                contentItem: Text {
                    text: parent.text
                    color: ThemeManager.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    if (DataStore && pageId !== "") DataStore.resolvePageConflict(pageId, "merge")
                    root.close()
                }
            }
        }
    }
}
