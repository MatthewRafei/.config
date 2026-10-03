pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Colours come from ~/.cache/theme/palette.json, written by
// ~/.config/theme/wallpaper-theme whenever the wallpaper changes. The file
// is watched, so the whole shell recolours live. Fallbacks are the original
// monochrome look, used until a palette exists.
Singleton {
    id: theme

    FileView {
        path: Quickshell.env("HOME") + "/.cache/theme/palette.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: pal
            property string accent: "#ffffff"
            property string accent2: "#ffffff"
            property string accentFg: "#050505"
            property string bgPanel: "#050505"
            property string bgCard: "#0d0d0d"
            property string border: "#1e1e1e"
            property string borderAccent: "#2a2a2a"
            property string text: "#ffffff"
            property string textDim: "#888888"
            property string textFaint: "#4a4a4a"
            property string trackBg: "#161616"
            property string danger: "#ff003c"
            property string ok: "#00ff9c"
            property string wallpaper: ""
        }
    }

    readonly property color bg: alpha(bgPanel, 0.8)
    readonly property color bgPanel: pal.bgPanel
    readonly property color bgCard: pal.bgCard
    readonly property color border: pal.border
    readonly property color borderAccent: pal.borderAccent

    readonly property color text: pal.text
    readonly property color textDim: pal.textDim
    readonly property color textFaint: pal.textFaint

    readonly property color accent: pal.accent
    readonly property color accent2: pal.accent2
    readonly property color accentFg: pal.accentFg
    readonly property color danger: pal.danger
    readonly property color ok: pal.ok

    readonly property color trackBg: pal.trackBg

    // path of the wallpaper the palette was made from (lock screen backdrop)
    readonly property string wallpaper: pal.wallpaper

    // -------------------------
    // Type
    // -------------------------
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property string iconFont: "JetBrainsMono Nerd Font"

    // -------------------------
    // Metrics / motion
    // -------------------------
    readonly property int radius: 3
    readonly property int animFast: 120
    readonly property int animMed: 220
    readonly property int animSlow: 380

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // "rgba(r,g,b,a)" string for Canvas 2D contexts
    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
            + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a) + ")"
    }
}
