pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Mouse, keyboard and cursor settings for Settings > Mouse / Keyboard
// (Hyprland). The work is done by input/inputctl.py (options -> live +
// ~/.config/hypr/settings.lua, binds -> keybinds.lua) and
// ~/.config/theme/cursor/cursor-accent (the cursor, coloured from the
// wallpaper). Commands run one at a time, in order.
Singleton {
    id: root

    readonly property string ctl: Quickshell.shellPath("input/inputctl.py")
    readonly property string cursorTool: Quickshell.env("HOME") + "/.config/theme/cursor/cursor-accent"

    property var options: ({})     // "input:sensitivity" -> value (live)
    property bool touchpad: false
    property var cursor: null      // cursor-accent status
    property var binds: []         // [{ combo, orig, moved, disabled, description, mouse, locked }]
    property bool loaded: false
    property string error: ""
    property bool cursorBusy: false
    property bool capturing: false // Hyprland is in the "capture" submap

    function opt(key, fallback) {
        const v = options[key]
        return v === undefined || v === null ? fallback : v
    }

    // ---------------------------------------------------------------- queue
    property var queue: []
    function run(cmd, after) {
        queue = queue.concat([{ cmd: cmd, after: after || "" }])
        pump()
    }
    function pump() {
        if (proc.running || queue.length === 0) return
        const job = queue[0]
        queue = queue.slice(1)
        proc.after = job.after
        proc.command = job.cmd
        proc.running = true
    }

    Process {
        id: proc
        property string after: ""
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (after === "state" && code === 0) {
                try {
                    const d = JSON.parse(out.text)
                    root.options = d.options || {}
                    root.touchpad = d.touchpad === true
                    root.cursor = d.cursor
                    root.binds = d.binds || []
                    root.loaded = true
                } catch (e) {
                    root.error = "Couldn't read input settings"
                }
            } else if (code !== 0) {
                root.error = (err.text || "").trim().split("\n").pop() || "Something went wrong"
            }
            if (after === "cursor") {
                root.cursorBusy = false
                root.refresh()
            }
            if (after === "binds") root.refresh()
            Qt.callLater(root.pump)
        }
    }

    function refresh() {
        // one pending refresh is enough
        if (queue.some(j => j.after === "state")) return
        run(["python3", "-I", ctl, "state"], "state")
    }

    // ------------------------------------------------------------- actions
    // change one option: shown at once, applied live and saved by inputctl
    function set(key, value) {
        error = ""
        const o = Object.assign({}, options)
        o[key] = value
        options = o
        run(["python3", "-I", ctl, "set", key, String(value)])
    }
    // cursor-accent set KEY VALUE ... (rebuilds the cursor, ~8 s)
    function setCursor(pairs) {
        error = ""
        const c = Object.assign({}, cursor || {})
        for (let i = 0; i + 1 < pairs.length; i += 2) c[pairs[i]] = pairs[i] === "size" ? Number(pairs[i + 1]) : pairs[i + 1]
        cursor = c
        cursorBusy = true
        run([cursorTool, "set"].concat(pairs.map(String)), "cursor")
    }
    function remap(orig, to, description) {
        error = ""
        run(["python3", "-I", ctl, "remap", orig, to, description || ""], "binds")
    }
    function disable(orig, description) {
        error = ""
        run(["python3", "-I", ctl, "disable", orig, description || ""], "binds")
    }
    function reset(orig) { run(["python3", "-I", ctl, "reset", orig], "binds") }
    function resetAll() { run(["python3", "-I", ctl, "reset-all"], "binds") }

    // while recording a shortcut, Hyprland's own binds must not fire
    function capture(on) {
        capturing = on
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("' + (on ? "capture" : "reset") + '")'])
    }

    // ------------------------------------------------- keys -> Hyprland names
    // Qt reports the shifted character; Hyprland binds the unshifted key
    readonly property var keyNames: ({
        [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "KP_Enter", [Qt.Key_Escape]: "Escape", [Qt.Key_Tab]: "Tab",
        [Qt.Key_Backtab]: "Tab", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert",
        [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down",
        [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down",
        [Qt.Key_Space]: "space", [Qt.Key_Print]: "Print", [Qt.Key_Pause]: "Pause", [Qt.Key_Menu]: "Menu",
        [Qt.Key_Minus]: "minus", [Qt.Key_Underscore]: "minus", [Qt.Key_Equal]: "equal", [Qt.Key_Plus]: "equal",
        [Qt.Key_BracketLeft]: "bracketleft", [Qt.Key_BraceLeft]: "bracketleft",
        [Qt.Key_BracketRight]: "bracketright", [Qt.Key_BraceRight]: "bracketright",
        [Qt.Key_Semicolon]: "semicolon", [Qt.Key_Colon]: "semicolon",
        [Qt.Key_Apostrophe]: "apostrophe", [Qt.Key_QuoteDbl]: "apostrophe",
        [Qt.Key_Comma]: "comma", [Qt.Key_Less]: "comma", [Qt.Key_Period]: "period", [Qt.Key_Greater]: "period",
        [Qt.Key_Slash]: "slash", [Qt.Key_Question]: "slash", [Qt.Key_Backslash]: "backslash", [Qt.Key_Bar]: "backslash",
        [Qt.Key_QuoteLeft]: "grave", [Qt.Key_AsciiTilde]: "grave",
        [Qt.Key_Exclam]: "1", [Qt.Key_At]: "2", [Qt.Key_NumberSign]: "3", [Qt.Key_Dollar]: "4", [Qt.Key_Percent]: "5",
        [Qt.Key_AsciiCircum]: "6", [Qt.Key_Ampersand]: "7", [Qt.Key_Asterisk]: "8", [Qt.Key_ParenLeft]: "9", [Qt.Key_ParenRight]: "0",
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute", [Qt.Key_MediaPlay]: "XF86AudioPlay", [Qt.Key_MediaTogglePlayPause]: "XF86AudioPlay",
        [Qt.Key_MediaStop]: "XF86AudioStop", [Qt.Key_MediaPrevious]: "XF86AudioPrev", [Qt.Key_MediaNext]: "XF86AudioNext",
        [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp", [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown",
        [Qt.Key_Calculator]: "XF86Calculator", [Qt.Key_Mail]: "XF86Mail", [Qt.Key_HomePage]: "XF86HomePage"
    })
    readonly property var modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L,
                                         Qt.Key_Super_R, Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Hyper_L, Qt.Key_Hyper_R]

    // a key event -> "SUPER + SHIFT + D", "" for a lone modifier
    function comboOf(event) {
        if (modifierKeys.indexOf(event.key) >= 0) return ""
        let key = keyNames[event.key]
        if (!key) {
            if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) key = String.fromCharCode(event.key)
            else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) key = String.fromCharCode(event.key)
            else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24) key = "F" + (event.key - Qt.Key_F1 + 1)
            else return ""
        }
        const mods = []
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
        if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
        if (event.modifiers & Qt.AltModifier) mods.push("ALT")
        if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
        return mods.concat([key]).join(" + ")
    }
    function sameCombo(a, b) { return String(a).toLowerCase() === String(b).toLowerCase() }
    // "SUPER + SHIFT + D" -> ["SUPER", "SHIFT", "D"] for drawing keycaps
    function caps(combo) {
        return String(combo).split(" + ").map(k => ({ left: "←", right: "→", up: "↑", down: "↓", Return: "ENTER",
            "mouse:272": "LEFT CLICK", "mouse:273": "RIGHT CLICK", mouse_up: "SCROLL ↑", mouse_down: "SCROLL ↓",
            Page_Up: "PG UP", Page_Down: "PG DN", BRACKETLEFT: "[", BRACKETRIGHT: "]", bracketleft: "[", bracketright: "]",
            equal: "=", minus: "-", space: "SPACE" }[k] || k.replace(/^XF86/, "").toUpperCase()))
    }

    // never leave Hyprland stuck in the capture submap
    Component.onDestruction: if (capturing) capture(false)
}
