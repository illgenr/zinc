import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

Popup {
    id: root
    
    property var targetBlock: null
    property int currentBlockIndex: -1
    property real desiredX: 0
    property real desiredY: 0
    
    signal commandSelected(var command)
    
    function show(block, filter) {
        targetBlock = block
        filterText = filter || ""
        updateFilteredCommands()
        open()
    }
    
    function hide() {
        close()
    }
    
    property string filterText: ""
    signal linkPageRequested()
    
    property var commands: [
        { type: "paragraph", label: "Text", description: "Plain text paragraph", icon: "📝" },
        { type: "heading", level: 1, label: "Heading 1", description: "Large heading", icon: "H1" },
        { type: "heading", level: 2, label: "Heading 2", description: "Medium heading", icon: "H2" },
        { type: "heading", level: 3, label: "Heading 3", description: "Small heading", icon: "H3" },
        { type: "bulleted", label: "Bulleted list", description: "Multi-line list block", icon: "•" },
        { type: "todo", label: "To-do", description: "Checkbox item", icon: "☑️" },
        { type: "date", label: "Date", description: "Insert a date", icon: "📅" },
        { type: "datetime", label: "Date/Time", description: "Insert a date with optional time", icon: "🕒" },
        { type: "now", label: "Now", description: "Insert current date and time", icon: "⏱" },
        { type: "image", label: "Image", description: "Upload an image", icon: "🖼" },
        { type: "columns", count: 2, label: "2 columns", description: "Side-by-side columns", icon: "▦" },
        { type: "columns", count: 3, label: "3 columns", description: "Three columns", icon: "▦" },
        { type: "code", label: "Code", description: "Code block", icon: "💻" },
        { type: "quote", label: "Quote", description: "Block quote", icon: "❝" },
        { type: "divider", label: "Divider", description: "Horizontal line", icon: "—" },
        { type: "toggle", label: "Toggle", description: "Collapsible content", icon: "▶" },
        { type: "link", label: "Link to page", description: "Link to another page", icon: "🔗" }
    ]
    
    property var filteredCommands: commands

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(value, maxValue))
    }

    function keyboardTopY() {
        const kb = Qt.inputMethod.keyboardRectangle
        if (!Qt.inputMethod.visible || !kb || kb.height <= 0) {
            return parent ? parent.height : 0
        }
        if (kb.y > 0) {
            return kb.y
        }
        return parent ? (parent.height - kb.height) : 0
    }

    function updatePosition() {
        if (!parent) return

        const margin = ThemeManager.spacingSmall
        const maxX = parent.width - root.width - margin
        const maxY = keyboardTopY() - root.height - margin

        root.x = clamp(root.desiredX, margin, Math.max(margin, maxX))
        root.y = clamp(root.desiredY, margin, Math.max(margin, maxY))
    }
    
    function updateFilteredCommands() {
        if (filterText.length === 0) {
            filteredCommands = commands
        } else {
            let lower = filterText.toLowerCase()
            filteredCommands = commands.filter(cmd => 
                cmd.label.toLowerCase().includes(lower) ||
                cmd.type.toLowerCase().includes(lower)
            )
        }
        commandList.currentIndex = 0
    }
    
    width: 280
    height: Math.min(filteredCommands.length * 44 + 54, 340)
    padding: ThemeManager.spacingSmall
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onDesiredXChanged: updatePosition()
    onDesiredYChanged: updatePosition()
    onWidthChanged: updatePosition()
    onHeightChanged: updatePosition()

    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() { root.updatePosition() }
        function onKeyboardRectangleChanged() { root.updatePosition() }
    }
    
    background: Rectangle {
        color: ThemeManager.surface
        border.width: 1
        border.color: ThemeManager.border
        radius: ThemeManager.radiusMedium
    }
    
    contentItem: ColumnLayout {
        spacing: ThemeManager.spacingSmall

        TextField {
            id: filterInput
            Layout.fillWidth: true
            placeholderText: "Type to filter..."
            selectByMouse: true

            onTextChanged: {
                if (text !== root.filterText) {
                    root.filterText = text
                }
            }

            Keys.onUpPressed: commandList.currentIndex = Math.max(0, commandList.currentIndex - 1)
            Keys.onDownPressed: commandList.currentIndex = Math.min(commandList.count - 1, commandList.currentIndex + 1)

            Keys.onReturnPressed: {
                if (commandList.currentIndex >= 0 && commandList.currentIndex < filteredCommands.length) {
                    root.commandSelected(filteredCommands[commandList.currentIndex])
                    root.close()
                }
            }

            Keys.onEscapePressed: root.close()
        }

        ListView {
            id: commandList

            Layout.fillWidth: true
            Layout.fillHeight: true
            model: filteredCommands
            clip: true
            currentIndex: 0
            spacing: 2

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                id: delegateItem
                width: commandList.width
                height: 44
                anchors.margins: ThemeManager.spacingSmall
                radius: ThemeManager.radiusSmall
                color: commandList.currentIndex === index || delegateMouseArea.containsMouse
                       ? ThemeManager.surfaceHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall                    
                    spacing: ThemeManager.spacingSmall

                    // Icon
                    Rectangle {
                        width: 28
                        height: 28
                        Layout.alignment: Qt.AlignVCenter
                        radius: ThemeManager.radiusSmall
                        color: ThemeManager.background

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            font.pixelSize: 14
                        }
                    }

                    // Label and description
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            text: modelData.label
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeNormal
                        }

                        Text {
                            text: modelData.description
                            color: ThemeManager.textSecondary
                            font.pixelSize: ThemeManager.fontSizeSmall
                        }
                    }
                }

                MouseArea {
                    id: delegateMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: commandList.currentIndex = index

                    onClicked: {
                        root.commandSelected(modelData)
                        root.close()
                    }
                }
            }

            Keys.onUpPressed: {
                if (currentIndex > 0) currentIndex--
            }

            Keys.onDownPressed: {
                if (currentIndex < count - 1) currentIndex++
            }

            Keys.onReturnPressed: {
                if (currentIndex >= 0 && currentIndex < filteredCommands.length) {
                    root.commandSelected(filteredCommands[currentIndex])
                    root.close()
                }
            }

            Keys.onEscapePressed: root.close()
        }
    }
    
    onFilterTextChanged: {
        updateFilteredCommands()
        if (filterInput.text !== filterText) {
            filterInput.text = filterText
        }
    }
    
    onOpened: {
        updatePosition()
        filterInput.text = filterText
        filterInput.forceActiveFocus()
    }
}
