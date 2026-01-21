pragma Singleton
import QtQuick
import QtCore

Item {
    id: root
    
    // Persistent settings (disabled in headless tests)
    readonly property bool settingsEnabled: Qt.application.name !== "zinc_qml_tests"
    property var settings: settingsLoader.item

    Loader {
        id: settingsLoader
        active: settingsEnabled
        sourceComponent: Settings {
            id: settings
            category: "Appearance"
            property int themeMode: ThemeManager.Mode.Dark
            property int fontScale: ThemeManager.FontScale.Medium
        }

        onLoaded: {
            if (item) {
                root.currentMode = item.themeMode
                root.fontSizeScale = item.fontScale
            }
        }
    }

    Connections {
        target: settingsLoader.item
        enabled: settingsLoader.item

        function onThemeModeChanged() {
            if (root.currentMode !== settingsLoader.item.themeMode) {
                root.currentMode = settingsLoader.item.themeMode
            }
        }

        function onFontScaleChanged() {
            if (root.fontSizeScale !== settingsLoader.item.fontScale) {
                root.fontSizeScale = settingsLoader.item.fontScale
            }
        }
    }

    Connections {
        target: root
        enabled: settingsLoader.item

        function onCurrentModeChanged() {
            if (settingsLoader.item && settingsLoader.item.themeMode !== root.currentMode) {
                settingsLoader.item.themeMode = root.currentMode
            }
        }

        function onFontSizeScaleChanged() {
            if (settingsLoader.item && settingsLoader.item.fontScale !== root.fontSizeScale) {
                settingsLoader.item.fontScale = root.fontSizeScale
            }
        }
    }
    
    // Theme modes
    enum Mode {
        Dark,
        Light,
        System
    }
    
    // Font size scales
    enum FontScale {
        Small,
        Medium,
        Large
    }
    
    property int currentMode: ThemeManager.Mode.Dark
    property int fontSizeScale: ThemeManager.FontScale.Medium
    
    property bool isDark: {
        if (currentMode === ThemeManager.Mode.Light) return false
        if (currentMode === ThemeManager.Mode.Dark) return true
        // System mode - for now default to dark
        return true
    }
    
    function setMode(mode) {
        currentMode = mode
    }
    
    function setFontScale(scale) {
        fontSizeScale = scale
    }
    
    // Font scale multiplier
    readonly property real fontMultiplier: {
        switch (fontSizeScale) {
            case ThemeManager.FontScale.Small: return 0.9
            case ThemeManager.FontScale.Large: return 1.15
            default: return 1.0
        }
    }
    
    // Color palette - switches based on isDark
    readonly property color background: isDark ? "#191919" : "#ffffff"
    readonly property color surface: isDark ? "#202020" : "#f7f7f7"
    readonly property color surfaceHover: isDark ? "#2d2d2d" : "#ebebeb"
    readonly property color surfaceActive: isDark ? "#373737" : "#e0e0e0"
    readonly property color border: isDark ? "#373737" : "#e0e0e0"
    readonly property color borderLight: isDark ? "#2d2d2d" : "#ebebeb"
    
    readonly property color text: isDark ? "#e6e6e6" : "#1a1a1a"
    readonly property color textSecondary: isDark ? "#9b9b9b" : "#666666"
    readonly property color textMuted: isDark ? "#6b6b6b" : "#999999"
    readonly property color textPlaceholder: isDark ? "#505050" : "#b0b0b0"
    
    readonly property color accent: "#2383e2"
    readonly property color accentHover: "#0077db"
    readonly property color accentLight: "#2383e220"
    readonly property color remoteCursor: isDark ? "#ff5ca8" : "#b0005c"
    
    readonly property color success: "#2ea043"
    readonly property color warning: "#e69c00"
    readonly property color danger: "#da3633"
    
    readonly property color codeBackground: isDark ? "#161616" : "#f5f5f5"
    readonly property color codeBorder: isDark ? "#303030" : "#ddd"
    
    // Typography
    readonly property string fontFamily: "Inter, SF Pro Text, -apple-system, BlinkMacSystemFont, sans-serif"
    readonly property string monoFontFamily: "JetBrains Mono, SF Mono, Menlo, Consolas, monospace"
    
    readonly property int fontSizeSmall: Math.round(12 * fontMultiplier)
    readonly property int fontSizeNormal: Math.round(14 * fontMultiplier)
    readonly property int fontSizeLarge: Math.round(16 * fontMultiplier)
    readonly property int fontSizeXLarge: Math.round(20 * fontMultiplier)
    readonly property int fontSizeH1: Math.round(30 * fontMultiplier)
    readonly property int fontSizeH2: Math.round(24 * fontMultiplier)
    readonly property int fontSizeH3: Math.round(20 * fontMultiplier)
    
    // Spacing
    readonly property int spacingTiny: 4
    readonly property int spacingSmall: 8
    readonly property int spacingMedium: 12
    readonly property int spacingLarge: 16
    readonly property int spacingXLarge: 24
    readonly property int spacingXXLarge: 32
    
    // Border radius
    readonly property int radiusSmall: 4
    readonly property int radiusMedium: 6
    readonly property int radiusLarge: 8
    
    // Shadows
    readonly property string shadowSmall: isDark ? "0 1px 2px rgba(0,0,0,0.3)" : "0 1px 2px rgba(0,0,0,0.1)"
    readonly property string shadowMedium: isDark ? "0 4px 12px rgba(0,0,0,0.4)" : "0 4px 12px rgba(0,0,0,0.15)"
    readonly property string shadowLarge: isDark ? "0 8px 24px rgba(0,0,0,0.5)" : "0 8px 24px rgba(0,0,0,0.2)"
    
    // Layout
    readonly property int sidebarWidth: 240
    readonly property int sidebarCollapsedWidth: 48
    readonly property int editorMaxWidth: 720
    readonly property int blockIndent: 24
    
    // Animation
    readonly property int animationFast: 100
    readonly property int animationNormal: 200
    readonly property int animationSlow: 300
}
