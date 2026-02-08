import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

SettingsPage {
    id: page

    signal pairDevice()

    property var syncController: null
    property var pairedDevicesModel: null
    property var availableDevicesModel: null
    property var refreshPairedDevices: null
    property var refreshAvailableDevices: null
    property var openEndpointEditor: null
    property var openRenameDeviceDialog: null
    property var connectToPeer: null

    function focusFirstControl() {
        if (!pairNewDeviceButton || !pairNewDeviceButton.visible || !pairNewDeviceButton.enabled) {
            console.log("DevicesSettingsPage focus: pairNewDeviceButton unavailable visible=",
                        pairNewDeviceButton ? pairNewDeviceButton.visible : "n/a",
                        "enabled=", pairNewDeviceButton ? pairNewDeviceButton.enabled : "n/a")
            return false
        }
        console.log("DevicesSettingsPage focus: focusing pairNewDeviceButton")
        pairNewDeviceButton.forceActiveFocus()
        return true
    }

    function isOnline(lastSeen) {
        if (!lastSeen || lastSeen === "") return false
        const iso = lastSeen.indexOf("T") >= 0 ? lastSeen : lastSeen.replace(" ", "T") + "Z"
        const t = Date.parse(iso)
        if (isNaN(t)) return false
        return (Date.now() - t) < 15000
    }

    function resolvedDeviceName(deviceId, discoveredName, pairedName) {
        if (pairedName && pairedName !== "") return pairedName
        if (discoveredName && discoveredName !== "") return discoveredName
        return deviceId
    }

    Component.onCompleted: {
        if (page.refreshPairedDevices) page.refreshPairedDevices()
        if (page.refreshAvailableDevices) page.refreshAvailableDevices()
    }

    onVisibleChanged: {
        if (!visible) return
        if (page.refreshPairedDevices) page.refreshPairedDevices()
        if (page.refreshAvailableDevices) page.refreshAvailableDevices()
    }

    SettingsSection {
        title: "Available Devices"

        Text {
            text: "No devices discovered"
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeNormal
            visible: page.availableDevicesModel && page.availableDevicesModel.count === 0
        }

        Repeater {
            model: page.availableDevicesModel

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                implicitHeight: deviceRow.implicitHeight + ThemeManager.spacingSmall * 2
                radius: ThemeManager.radiusSmall
                color: ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border

                RowLayout {
                    id: deviceRow
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: ThemeManager.spacingSmall

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2
                        clip: true

                        Text {
                            text: page.resolvedDeviceName(deviceId, deviceName, pairedDeviceName)
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeNormal
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            Layout.fillWidth: true
                        }

                        Text {
                            Layout.fillWidth: true
                            color: ThemeManager.textSecondary
                            font.pixelSize: ThemeManager.fontSizeSmall
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            text: (host && host !== "" && port && port > 0) ? (host + ":" + port) : "unknown"
                        }
                    }

                    SettingsButton {
                        text: "Endpoint…"
                        enabled: DataStore && deviceId && deviceId !== ""
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: 92
                        Layout.minimumWidth: 92

                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
                            border.width: 1
                            border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
                        }

                        contentItem: Text {
                            text: parent.text
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            if (page.openEndpointEditor) {
                                page.openEndpointEditor(deviceId, page.resolvedDeviceName(deviceId, deviceName, pairedDeviceName),
                                                        host && host !== "" ? host : "",
                                                        port && port > 0 ? ("" + port) : "")
                            }
                        }
                    }

                    SettingsButton {
                        text: "Connect"
                        enabled: page.syncController && page.syncController.syncing &&
                                 deviceId && deviceId !== "" &&
                                 host && host !== "" && port && port > 0
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: 80
                        Layout.minimumWidth: 80

                        background: Rectangle {
                            radius: ThemeManager.radiusSmall
                            color: parent.pressed ? ThemeManager.accentHover : ThemeManager.accent
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            font.pixelSize: ThemeManager.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            console.log("SettingsDialog: connect to discovered peer", deviceId, host, port)
                            if (page.connectToPeer) page.connectToPeer(
                                        deviceId,
                                        page.resolvedDeviceName(deviceId, deviceName, pairedDeviceName),
                                        host,
                                        port)
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        title: "Paired Devices"

        Text {
            text: "No devices paired"
            color: ThemeManager.textSecondary
            font.pixelSize: ThemeManager.fontSizeNormal
            visible: page.pairedDevicesModel && page.pairedDevicesModel.count === 0
        }

        Repeater {
            model: page.pairedDevicesModel

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                implicitHeight: deviceRow.implicitHeight + ThemeManager.spacingSmall * 2
                radius: ThemeManager.radiusSmall
                color: ThemeManager.surfaceHover
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border

                RowLayout {
                    id: deviceRow
                    anchors.fill: parent
                    anchors.margins: ThemeManager.spacingSmall
                    spacing: ThemeManager.spacingSmall

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2
                        clip: true

                        Text {
                            text: deviceName
                            color: ThemeManager.text
                            font.pixelSize: ThemeManager.fontSizeNormal
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            Layout.fillWidth: true
                        }

                        Text {
                            text: workspaceId
                            color: ThemeManager.textMuted
                            font.pixelSize: ThemeManager.fontSizeSmall
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            Layout.fillWidth: true
                        }

                        Text {
                            Layout.fillWidth: true
                            color: ThemeManager.textSecondary
                            font.pixelSize: ThemeManager.fontSizeSmall
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            text: {
                                const online = page.isOnline(lastSeen)
                                const endpoint = (host && host !== "" && port && port > 0) ? (host + ":" + port) : "unknown"
                                return online ? ("Available (" + endpoint + ")") : ("Offline (" + endpoint + ")")
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 172
                        Layout.minimumWidth: 172
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: actionFlow.implicitHeight

                        Flow {
                            id: actionFlow
                            width: parent.width
                            spacing: ThemeManager.spacingSmall
                            layoutDirection: Qt.LeftToRight
                            flow: Flow.LeftToRight

                            SettingsButton {
                                text: "Rename…"
                                width: 84
                                height: 28

                                background: Rectangle {
                                    radius: ThemeManager.radiusSmall
                                    color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
                                    border.width: 1
                                    border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
                                }

                                contentItem: Text {
                                    text: parent.text
                                    color: ThemeManager.text
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (page.openRenameDeviceDialog) {
                                        page.openRenameDeviceDialog(deviceId, deviceName)
                                    }
                                }
                            }

                            SettingsButton {
                                text: "Remove"
                                width: 80
                                height: 28

                                background: Rectangle {
                                    radius: ThemeManager.radiusSmall
                                    color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
                                    border.width: 1
                                    border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
                                }

                                contentItem: Text {
                                    text: parent.text
                                    color: ThemeManager.text
                                    font.pixelSize: ThemeManager.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: DataStore.removePairedDevice(deviceId)
                            }
                        }
                    }
                }
            }
        }

        SettingsButton {
            Layout.fillWidth: true
            text: "Remove All Devices"
            visible: page.pairedDevicesModel && page.pairedDevicesModel.count > 0

            background: Rectangle {
                implicitHeight: 44
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.surfaceActive : ThemeManager.surface
                border.width: 1
                border.color: (parent && parent.visualFocus) ? ThemeManager.accent : ThemeManager.border
            }

            contentItem: Text {
                text: parent.text
                color: ThemeManager.text
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: DataStore.clearPairedDevices()
        }

        SettingsButton {
            id: pairNewDeviceButton
            Layout.fillWidth: true
            text: "+ Pair New Device"

            background: Rectangle {
                implicitHeight: 44
                radius: ThemeManager.radiusSmall
                color: parent.pressed ? ThemeManager.accentHover : ThemeManager.accent
            }

            contentItem: Text {
                text: parent.text
                color: "white"
                font.pixelSize: ThemeManager.fontSizeNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: page.pairDevice()
        }
    }
}
