pragma Singleton
import QtQuick
import QtCore

Item {
    id: root

    readonly property bool settingsEnabled: Qt.application.name !== "zinc_qml_tests"
    property var settings: settingsLoader.item

    property string newPageShortcut: "Ctrl+N"
    property string findShortcut: "Ctrl+F"
    property string toggleSidebarShortcut: "Ctrl+\\"
    property string focusPageTreeShortcut: "Ctrl+E"
    property string openSettingsShortcut: "Ctrl+Alt+S"
    property string showShortcutHelpShortcut: "Ctrl+Shift+?"
    property string focusDocumentEndShortcut: "Ctrl+End"

    property string boldShortcut: "Ctrl+B"
    property string italicShortcut: "Ctrl+I"
    property string underlineShortcut: "Ctrl+U"
    property string linkShortcut: "Ctrl+L"
    property string toggleFormatBarShortcut: "Ctrl+Shift+M"

    Loader {
        id: settingsLoader
        active: settingsEnabled
        sourceComponent: Settings {
            category: "Shortcuts"

            property string newPageShortcut: "Ctrl+N"
            property string findShortcut: "Ctrl+F"
            property string toggleSidebarShortcut: "Ctrl+\\"
            property string focusPageTreeShortcut: "Ctrl+E"
            property string openSettingsShortcut: "Ctrl+Alt+S"
            property string showShortcutHelpShortcut: "Ctrl+Shift+?"
            property string focusDocumentEndShortcut: "Ctrl+End"

            property string boldShortcut: "Ctrl+B"
            property string italicShortcut: "Ctrl+I"
            property string underlineShortcut: "Ctrl+U"
            property string linkShortcut: "Ctrl+L"
            property string toggleFormatBarShortcut: "Ctrl+Shift+M"
        }

        onLoaded: {
            if (!item) return
            root.newPageShortcut = item.newPageShortcut
            root.findShortcut = item.findShortcut
            root.toggleSidebarShortcut = item.toggleSidebarShortcut
            root.focusPageTreeShortcut = item.focusPageTreeShortcut
            root.openSettingsShortcut = item.openSettingsShortcut
            root.showShortcutHelpShortcut = item.showShortcutHelpShortcut
            root.focusDocumentEndShortcut = item.focusDocumentEndShortcut
            root.boldShortcut = item.boldShortcut
            root.italicShortcut = item.italicShortcut
            root.underlineShortcut = item.underlineShortcut
            root.linkShortcut = item.linkShortcut
            root.toggleFormatBarShortcut = item.toggleFormatBarShortcut
        }
    }

    function syncRootFromSettings() {
        if (!settingsLoader.item) return
        if (root.newPageShortcut !== settingsLoader.item.newPageShortcut) root.newPageShortcut = settingsLoader.item.newPageShortcut
        if (root.findShortcut !== settingsLoader.item.findShortcut) root.findShortcut = settingsLoader.item.findShortcut
        if (root.toggleSidebarShortcut !== settingsLoader.item.toggleSidebarShortcut) root.toggleSidebarShortcut = settingsLoader.item.toggleSidebarShortcut
        if (root.focusPageTreeShortcut !== settingsLoader.item.focusPageTreeShortcut) root.focusPageTreeShortcut = settingsLoader.item.focusPageTreeShortcut
        if (root.openSettingsShortcut !== settingsLoader.item.openSettingsShortcut) root.openSettingsShortcut = settingsLoader.item.openSettingsShortcut
        if (root.showShortcutHelpShortcut !== settingsLoader.item.showShortcutHelpShortcut) root.showShortcutHelpShortcut = settingsLoader.item.showShortcutHelpShortcut
        if (root.focusDocumentEndShortcut !== settingsLoader.item.focusDocumentEndShortcut) root.focusDocumentEndShortcut = settingsLoader.item.focusDocumentEndShortcut
        if (root.boldShortcut !== settingsLoader.item.boldShortcut) root.boldShortcut = settingsLoader.item.boldShortcut
        if (root.italicShortcut !== settingsLoader.item.italicShortcut) root.italicShortcut = settingsLoader.item.italicShortcut
        if (root.underlineShortcut !== settingsLoader.item.underlineShortcut) root.underlineShortcut = settingsLoader.item.underlineShortcut
        if (root.linkShortcut !== settingsLoader.item.linkShortcut) root.linkShortcut = settingsLoader.item.linkShortcut
        if (root.toggleFormatBarShortcut !== settingsLoader.item.toggleFormatBarShortcut) root.toggleFormatBarShortcut = settingsLoader.item.toggleFormatBarShortcut
    }

    function syncSettingsFromRoot() {
        if (!settingsLoader.item) return
        if (settingsLoader.item.newPageShortcut !== root.newPageShortcut) settingsLoader.item.newPageShortcut = root.newPageShortcut
        if (settingsLoader.item.findShortcut !== root.findShortcut) settingsLoader.item.findShortcut = root.findShortcut
        if (settingsLoader.item.toggleSidebarShortcut !== root.toggleSidebarShortcut) settingsLoader.item.toggleSidebarShortcut = root.toggleSidebarShortcut
        if (settingsLoader.item.focusPageTreeShortcut !== root.focusPageTreeShortcut) settingsLoader.item.focusPageTreeShortcut = root.focusPageTreeShortcut
        if (settingsLoader.item.openSettingsShortcut !== root.openSettingsShortcut) settingsLoader.item.openSettingsShortcut = root.openSettingsShortcut
        if (settingsLoader.item.showShortcutHelpShortcut !== root.showShortcutHelpShortcut) settingsLoader.item.showShortcutHelpShortcut = root.showShortcutHelpShortcut
        if (settingsLoader.item.focusDocumentEndShortcut !== root.focusDocumentEndShortcut) settingsLoader.item.focusDocumentEndShortcut = root.focusDocumentEndShortcut
        if (settingsLoader.item.boldShortcut !== root.boldShortcut) settingsLoader.item.boldShortcut = root.boldShortcut
        if (settingsLoader.item.italicShortcut !== root.italicShortcut) settingsLoader.item.italicShortcut = root.italicShortcut
        if (settingsLoader.item.underlineShortcut !== root.underlineShortcut) settingsLoader.item.underlineShortcut = root.underlineShortcut
        if (settingsLoader.item.linkShortcut !== root.linkShortcut) settingsLoader.item.linkShortcut = root.linkShortcut
        if (settingsLoader.item.toggleFormatBarShortcut !== root.toggleFormatBarShortcut) settingsLoader.item.toggleFormatBarShortcut = root.toggleFormatBarShortcut
    }

    Connections {
        target: settingsLoader.item
        enabled: settingsLoader.item
        function onNewPageShortcutChanged() { root.syncRootFromSettings() }
        function onFindShortcutChanged() { root.syncRootFromSettings() }
        function onToggleSidebarShortcutChanged() { root.syncRootFromSettings() }
        function onFocusPageTreeShortcutChanged() { root.syncRootFromSettings() }
        function onOpenSettingsShortcutChanged() { root.syncRootFromSettings() }
        function onShowShortcutHelpShortcutChanged() { root.syncRootFromSettings() }
        function onFocusDocumentEndShortcutChanged() { root.syncRootFromSettings() }
        function onBoldShortcutChanged() { root.syncRootFromSettings() }
        function onItalicShortcutChanged() { root.syncRootFromSettings() }
        function onUnderlineShortcutChanged() { root.syncRootFromSettings() }
        function onLinkShortcutChanged() { root.syncRootFromSettings() }
        function onToggleFormatBarShortcutChanged() { root.syncRootFromSettings() }
    }

    Connections {
        target: root
        enabled: settingsLoader.item
        function onNewPageShortcutChanged() { root.syncSettingsFromRoot() }
        function onFindShortcutChanged() { root.syncSettingsFromRoot() }
        function onToggleSidebarShortcutChanged() { root.syncSettingsFromRoot() }
        function onFocusPageTreeShortcutChanged() { root.syncSettingsFromRoot() }
        function onOpenSettingsShortcutChanged() { root.syncSettingsFromRoot() }
        function onShowShortcutHelpShortcutChanged() { root.syncSettingsFromRoot() }
        function onFocusDocumentEndShortcutChanged() { root.syncSettingsFromRoot() }
        function onBoldShortcutChanged() { root.syncSettingsFromRoot() }
        function onItalicShortcutChanged() { root.syncSettingsFromRoot() }
        function onUnderlineShortcutChanged() { root.syncSettingsFromRoot() }
        function onLinkShortcutChanged() { root.syncSettingsFromRoot() }
        function onToggleFormatBarShortcutChanged() { root.syncSettingsFromRoot() }
    }
}
