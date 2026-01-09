import QtQuick

QtObject {
    id: root
    
    // Theme mode: "dark" or "light"
    property string mode: "dark"
    
    // Dynamic colors based on mode
    readonly property color background: mode === "dark" ? "#191919" : "#ffffff"
    readonly property color surface: mode === "dark" ? "#202020" : "#f7f7f7"
    readonly property color surfaceHover: mode === "dark" ? "#2d2d2d" : "#ebebeb"
    readonly property color surfaceActive: mode === "dark" ? "#373737" : "#e0e0e0"
    readonly property color border: mode === "dark" ? "#373737" : "#e0e0e0"
    readonly property color borderLight: mode === "dark" ? "#2d2d2d" : "#ebebeb"
    
    readonly property color text: mode === "dark" ? "#e6e6e6" : "#1a1a1a"
    readonly property color textSecondary: mode === "dark" ? "#9b9b9b" : "#6b6b6b"
    readonly property color textMuted: mode === "dark" ? "#6b6b6b" : "#9b9b9b"
    readonly property color textPlaceholder: mode === "dark" ? "#505050" : "#b0b0b0"
    
    readonly property color accent: "#2383e2"
    readonly property color accentHover: "#0077db"
    readonly property color accentLight: mode === "dark" ? "#2383e220" : "#2383e215"
    
    readonly property color success: "#2ea043"
    readonly property color warning: "#e69c00"
    readonly property color danger: "#da3633"
    
    readonly property color codeBackground: mode === "dark" ? "#161616" : "#f5f5f5"
    readonly property color codeBorder: mode === "dark" ? "#303030" : "#e0e0e0"
    
    // Typography
    readonly property string fontFamily: "Inter, SF Pro Text, -apple-system, sans-serif"
    readonly property string monoFontFamily: "JetBrains Mono, SF Mono, Menlo, monospace"
    
    readonly property int fontSizeSmall: 12
    readonly property int fontSizeNormal: 14
    readonly property int fontSizeLarge: 16
    readonly property int fontSizeXLarge: 20
    readonly property int fontSizeH1: 30
    readonly property int fontSizeH2: 24
    readonly property int fontSizeH3: 20
    
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
    
    // Layout
    readonly property int sidebarWidth: 240
    readonly property int sidebarCollapsedWidth: 48
    readonly property int editorMaxWidth: 720
    readonly property int blockIndent: 24
    
    // Animation
    readonly property int animationFast: 100
    readonly property int animationNormal: 200
    readonly property int animationSlow: 300
    
    // Toggle theme
    function toggleTheme() {
        mode = mode === "dark" ? "light" : "dark"
    }
    
    function setDarkMode() {
        mode = "dark"
    }
    
    function setLightMode() {
        mode = "light"
    }
}
