import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import zinc

SettingsPage {
    id: page
    property ListModel startupPagesModel: ListModel {}

    function focusFirstControl() {
        if (!themeCombo || !themeCombo.visible || !themeCombo.enabled) {
            console.log("GeneralSettingsPage focus: themeCombo unavailable visible=",
                        themeCombo ? themeCombo.visible : "n/a",
                        "enabled=", themeCombo ? themeCombo.enabled : "n/a")
            return false
        }
        console.log("GeneralSettingsPage focus: focusing themeCombo")
        themeCombo.forceActiveFocus()
        return true
    }

    function refreshStartupPages() {
        startupPagesModel.clear()
        const pages = DataStore ? DataStore.getAllPages() : []
        for (let i = 0; i < pages.length; i++) {
            const p = pages[i] || {}
            const depth = p.depth || 0
            let prefix = ""
            for (let d = 0; d < depth; d++) prefix += "  "
            if (p.pageId) {
                startupPagesModel.append({
                    pageId: p.pageId,
                    title: prefix + (p.title || "Untitled")
                })
            }
        }

        const fixedId = DataStore ? DataStore.startupFixedPageId() : ""
        if (!fixedId || fixedId === "") return
        if (!startupPageCombo) return
        for (let i = 0; i < startupPagesModel.count; i++) {
            if (startupPagesModel.get(i).pageId === fixedId) {
                startupPageCombo.currentIndex = i
                break
            }
        }
    }

    Component.onCompleted: refreshStartupPages()

    property Connections dataStoreConnections: Connections {
        target: DataStore
        function onPagesChanged() {
            page.refreshStartupPages()
        }
    }

    SettingsSection {
        title: "Appearance"

        SettingsRow {
            label: "Theme"
            SettingsComboBox {
                id: themeCombo
                width: parent.width
                model: ["Dark", "Light", "System"]
                currentIndex: ThemeManager.currentMode

                onCurrentIndexChanged: ThemeManager.setMode(currentIndex)
            }
        }

        SettingsRow {
            label: "Font size"
            SettingsComboBox {
                id: fontCombo
                width: parent.width
                model: ["Small", "Medium", "Large"]
                currentIndex: ThemeManager.fontSizeScale

                onCurrentIndexChanged: ThemeManager.setFontScale(currentIndex)
            }
        }
    }

    SettingsSection {
        title: "Navigation"

        SettingsRow {
            label: "Jump to new page on creation"

            SettingsSwitch {
                id: jumpToNewPageSwitch
                checked: GeneralPreferences.jumpToNewPageOnCreate
                onToggled: GeneralPreferences.jumpToNewPageOnCreate = checked
            }
        }
    }

    SettingsSection {
        title: "Startup"

        SettingsRow {
            label: "Open on launch"
            SettingsComboBox {
                id: startupModeCombo
                width: parent.width
                model: ["Last viewed page", "Always open a page"]
                Component.onCompleted: {
                    startupModeCombo.currentIndex = DataStore ? DataStore.startupPageMode() : 0
                }

                onActivated: {
                    if (DataStore) DataStore.setStartupPageMode(currentIndex)
                }
            }
        }

        SettingsRow {
            visible: startupModeCombo.currentIndex === 1
            label: "Page"
            SettingsComboBox {
                id: startupPageCombo
                width: parent.width
                model: startupPagesModel
                textRole: "title"
                valueRole: "pageId"

                Component.onCompleted: {
                    const fixedId = DataStore ? DataStore.startupFixedPageId() : ""
                    for (let i = 0; i < startupPagesModel.count; i++) {
                        if (startupPagesModel.get(i).pageId === fixedId) {
                            startupPageCombo.currentIndex = i
                            break
                        }
                    }
                }

                onActivated: {
                    if (DataStore) DataStore.setStartupFixedPageId(currentValue)
                }
            }
        }
    }
}
