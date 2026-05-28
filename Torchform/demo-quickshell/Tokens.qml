pragma Singleton
import QtQuick

QtObject {
    // Backgrounds — Minerva Dark palette
    readonly property color bgBase:       "#0d0f14"
    readonly property color bgSurface:    "#161a22"
    readonly property color bgElevated:   "#1e2330"
    readonly property color bgOverlay:    "#cc0d0f14"

    // Accent — electric teal
    readonly property color accent:       "#00d4ff"
    readonly property color accentDim:    "#0099bb"
    readonly property color accentGlow:   "#2200d4ff"

    // Semantic
    readonly property color primary:      "#5b9cf6"
    readonly property color success:      "#3dd68c"
    readonly property color warning:      "#f7b731"
    readonly property color error:        "#f74040"

    // Text
    readonly property color textPrimary:  "#e8eaf0"
    readonly property color textSecondary:"#8c92a4"
    readonly property color textDisabled: "#4a5068"
    readonly property color textOnAccent: "#000000"

    // Borders
    readonly property color border:       "#2a2f3d"
    readonly property color borderFocused:"#00d4ff"
    readonly property color borderSubtle: "#1d2230"

    // Lower display
    readonly property color lowerBg:      "#0a0c11"
    readonly property color lowerSurface: "#12151c"

    // Typography
    readonly property string fontSans:    "Inter, DejaVu Sans, sans-serif"
    readonly property string fontMono:    "JetBrains Mono, monospace"
    readonly property string fontDisplay: "Barlow Condensed, Inter, sans-serif"

    // Spacing (base 4px)
    readonly property real sp1:  4
    readonly property real sp2:  8
    readonly property real sp3:  12
    readonly property real sp4:  16
    readonly property real sp5:  20
    readonly property real sp6:  24
    readonly property real sp8:  32
    readonly property real sp10: 40

    // Radii
    readonly property real rSm:  4
    readonly property real rMd:  8
    readonly property real rLg:  14
    readonly property real rXl:  22

    // Radial menu geometry
    readonly property real radialRadius:   160
    readonly property real radialItemSize:  72

    // Animation durations (ms)
    readonly property int animFast:   80
    readonly property int animNormal: 160
    readonly property int animSlow:   320
}
