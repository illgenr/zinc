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

    title: "Sync conflict"
    anchors.centerIn: parent
    modal: true
    standardButtons: Dialog.NoButton

    property bool isMobile: Qt.platform.os === "android" || parent.width < 600
    width: isMobile ? parent.width * 0.95 : Math.min(720, parent.width * 0.95)
    height: isMobile ? parent.height * 0.92 : Math.min(640, parent.height * 0.92)

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
        anchors.fill: parent
        anchors.margins: ThemeManager.spacingMedium
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
                    wrapMode: TextArea.Wrap
                    text: (conflict && conflict.localContentMarkdown) ? conflict.localContentMarkdown : ""
                }
            }

            // Remote
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextArea {
                    readOnly: true
                    wrapMode: TextArea.Wrap
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
                        if (mergePreview.kind === "clean") return "Automatic merge looks clean."
                        if (mergePreview.kind === "conflict") return "Automatic merge has conflicts (markers inserted)."
                        return "Automatic merge used fallback mode."
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea {
                        readOnly: true
                        wrapMode: TextArea.Wrap
                        text: (mergePreview && mergePreview.mergedMarkdown) ? mergePreview.mergedMarkdown : ""
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ThemeManager.spacingSmall

            Button {
                Layout.fillWidth: true
                text: "Keep this device"
                onClicked: {
                    if (DataStore && pageId !== "") DataStore.resolvePageConflict(pageId, "local")
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                text: "Keep other device"
                onClicked: {
                    if (DataStore && pageId !== "") DataStore.resolvePageConflict(pageId, "remote")
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                text: "Try merge"
                onClicked: {
                    if (DataStore && pageId !== "") DataStore.resolvePageConflict(pageId, "merge")
                    root.close()
                }
            }
        }
    }
}

