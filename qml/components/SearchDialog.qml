import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Popup {
    id: root
    
    signal resultSelected(string pageId, string blockId, int blockIndex)
    
    anchors.centerIn: parent

    readonly property int _maxWidth: 560
    readonly property int _maxHeight: 400
    readonly property real _outerMargin: ThemeManager.spacingMedium

    width: Math.min(_maxWidth, Math.max(0, (parent ? parent.width : _maxWidth) - (_outerMargin * 2)))
    height: Math.min(_maxHeight, Math.max(0, (parent ? parent.height : _maxHeight) - (_outerMargin * 2)))
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    padding: 0
    
    background: Rectangle {
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusLarge
    }
    
    contentItem: ColumnLayout {
        spacing: 0
        
        // Search input
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: "transparent"
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: ThemeManager.spacingMedium
                spacing: ThemeManager.spacingSmall
                
                Text {
                    text: "🔍"
                    font.pixelSize: ThemeManager.fontSizeLarge
                    color: ThemeManager.textSecondary
                }
                
                TextField {
                    id: searchField
                    objectName: "searchField"
                    
                    Layout.fillWidth: true
                    
                    placeholderText: "Find..."
                    color: ThemeManager.text
                    font.pixelSize: ThemeManager.fontSizeNormal
                    
                    background: Item {}
                    
                    onTextChanged: {
                        searchTimer.restart()
                    }
                    
                    Keys.onDownPressed: {
                        resultsList.forceActiveFocus()
                        resultsList.currentIndex = 0
                    }
                    
                    Keys.onReturnPressed: {
                        if (resultsList.count > 0) {
                            let item = resultsModel.get(0)
                            root.resultSelected(item.pageId, item.blockId || "", item.blockIndex !== undefined ? item.blockIndex : -1)
                            root.close()
                        }
                    }
                }
                
                Text {
                    text: "ESC"
                    color: ThemeManager.textMuted
                    font.pixelSize: ThemeManager.fontSizeSmall
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: ThemeManager.border
        }
        
        // Results
        ListView {
            id: resultsList
            objectName: "resultsList"
            
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            model: resultsModel
            clip: true
            currentIndex: -1
            
            delegate: Rectangle {
                width: resultsList.width
                height: 64
                color: resultsList.currentIndex === index ? ThemeManager.surfaceHover : "transparent"
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingMedium
                    spacing: ThemeManager.spacingTiny
                    
                    Text {
                        text: model.pageTitle
                        color: ThemeManager.text
                        font.pixelSize: ThemeManager.fontSizeNormal
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    
                    Text {
                        text: model.snippet
                        color: ThemeManager.textSecondary
                        font.pixelSize: ThemeManager.fontSizeSmall
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    
                    onEntered: resultsList.currentIndex = index
                    onClicked: {
                        root.resultSelected(model.pageId, model.blockId || "", model.blockIndex !== undefined ? model.blockIndex : -1)
                        root.close()
                    }
                }
            }
            
            // Empty state
            Text {
                anchors.centerIn: parent
                text: searchField.text.length > 0 ? "No results found" : "Type to search..."
                color: ThemeManager.textMuted
                font.pixelSize: ThemeManager.fontSizeNormal
                visible: resultsModel.count === 0
            }
            
            Keys.onUpPressed: {
                if (currentIndex > 0) currentIndex--
            }
            
            Keys.onDownPressed: {
                if (currentIndex < count - 1) currentIndex++
            }
            
            Keys.onReturnPressed: {
                if (currentIndex >= 0) {
                    let item = resultsModel.get(currentIndex)
                    root.resultSelected(item.pageId, item.blockId || "", item.blockIndex !== undefined ? item.blockIndex : -1)
                    root.close()
                }
            }
        }
    }
    
    ListModel {
        id: resultsModel
    }
    
    Timer {
        id: searchTimer
        interval: 200
        onTriggered: performSearch()
    }
    
    function performSearch() {
        resultsModel.clear()
        
        const query = (searchField.text || "").trim()
        if (query.length === 0) return

        const results = DataStore ? DataStore.searchPages(query, 50) : []
        for (let i = 0; i < results.length; i++) {
            resultsModel.append(results[i])
        }
    }
    
    onOpened: {
        searchField.forceActiveFocus()
        searchField.selectAll()
        searchTimer.restart()
    }

    Connections {
        target: DataStore

        function onPagesChanged() {
            if (!root.opened) return
            if ((searchField.text || "").trim().length === 0) return
            searchTimer.restart()
        }

        function onPageContentChanged(changedPageId) {
            if (!root.opened) return
            if ((searchField.text || "").trim().length === 0) return
            searchTimer.restart()
        }
    }
}
