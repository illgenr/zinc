import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

SettingsPage {
    id: page
    property var syncController: null

    function focusFirstControl() {
        if (!syncEnabledSwitch || !syncEnabledSwitch.visible || !syncEnabledSwitch.enabled) {
            console.log("SyncSettingsPage focus: syncEnabledSwitch unavailable visible=",
                        syncEnabledSwitch ? syncEnabledSwitch.visible : "n/a",
                        "enabled=", syncEnabledSwitch ? syncEnabledSwitch.enabled : "n/a")
            return false
        }
        console.log("SyncSettingsPage focus: focusing syncEnabledSwitch")
        syncEnabledSwitch.forceActiveFocus()
        return true
    }

    SettingsSection {
        title: "Sync Settings"

        SettingsRow {
            label: "Enable sync"
            SettingsSwitch {
                id: syncEnabledSwitch
                checked: true
            }
        }

        SettingsRow {
            label: "Workspace ID"

            TextField {
                Layout.fillWidth: true
                readOnly: true
                text: (page.syncController && page.syncController.workspaceId && page.syncController.workspaceId !== "")
                    ? page.syncController.workspaceId
                    : "Not configured"
                selectByMouse: true
            }
        }

        SettingsRow {
            label: "Auto sync"

            SettingsSwitch {
                id: autoSyncSwitch
                checked: SyncPreferences.autoSyncEnabled
                onToggled: SyncPreferences.autoSyncEnabled = checked
            }
        }

        SettingsRow {
            label: "Deleted pages history"

            SpinBox {
                id: deletedPagesRetentionSpin
                from: 0
                to: 10000
                value: DataStore ? DataStore.deletedPagesRetentionLimit() : 100
                editable: true

                onValueModified: {
                    if (DataStore) {
                        DataStore.setDeletedPagesRetentionLimit(value)
                    }
                }
            }
        }
    }
}
