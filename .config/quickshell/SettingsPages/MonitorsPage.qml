import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    property var monitors: []
    property int rightMargin: 36

    // -------------------------
    // Brightness
    // -------------------------
    property real brightnessValue: 0.6
    // false on desktops (no backlight device) or without brightnessctl
    property bool hasBacklight: false

    Process {
        id: brightnessGet

        command: ["brightnessctl", "-m"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",")

                if (parts.length < 4 || parts[1] !== "backlight")
                    return

                page.hasBacklight = true

                const pct = parseInt(parts[3])

                if (!isNaN(pct))
                    page.brightnessValue = pct / 100
            }
        }
    }

    Process {
        id: brightnessSet

        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    function commitBrightness(value) {
        brightnessSet.command = [
            "brightnessctl",
            "set",
            Math.round(value * 100) + "%"
        ]

        brightnessSet.running = true
    }

    // Night light state and schedule live in ../NightLight.qml (always running).

    // -------------------------
    // Monitor helpers (niri or Hyprland, see ../Compositor.qml)
    // -------------------------
    // niri: monitors come from `niri msg --json outputs`; changes go through
    // `niri msg output <name> ...`. Hyprland: `hyprctl -j monitors all`, and
    // changes are `hl.monitor({...})` run with `hyprctl eval`. Both are
    // runtime only and reset to the compositor config on restart. niri can't
    // mirror outputs, so there is no DUPLICATE mode.
    function isInternalMonitor(mon) {
        return mon.name.indexOf("eDP") === 0
            || mon.name.indexOf("LVDS") === 0
    }

    function findMonitors() {
        let internal = null
        let external = null

        for (let i = 0; i < page.monitors.length; i++) {
            const mon = page.monitors[i]

            if (isInternalMonitor(mon)) {
                internal = mon
            } else if (!external) {
                external = mon
            }
        }

        return {
            internal: internal,
            external: external
        }
    }

    // -------------------------
    // Monitor list
    // -------------------------
    Process {
        id: pList

        command: Compositor.hyprland
            ? ["hyprctl", "-j", "monitors", "all"]
            : ["sh", "-c", "niri msg --json outputs; echo; niri msg --json focused-output"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                if (Compositor.hyprland) {
                    page.parseHyprland(text)
                    return
                }

                const parts = text.split("\n").filter(l => l.trim() !== "")

                try {
                    const outputs = JSON.parse(parts[0])
                    let focused = null
                    try { focused = JSON.parse(parts[1] || "null") } catch (e) {}

                    const list = []
                    for (const name in outputs) {
                        const o = outputs[name]
                        const mode = (o.current_mode !== null && o.current_mode !== undefined)
                            ? o.modes[o.current_mode]
                            : (o.modes[0] || { width: 0, height: 0, refresh_rate: 0 })
                        const l = o.logical

                        const modes = [...new Set(o.modes.map(md => md.width + "x" + md.height + "@" + (md.refresh_rate / 1000).toFixed(3)))]
                        const transforms = { "Normal": 0, "90": 1, "180": 2, "270": 3 }
                        list.push({
                            name: name,
                            description: ((o.make || "") + " " + (o.model || "")).trim(),
                            width: mode.width,
                            height: mode.height,
                            refreshRate: mode.refresh_rate / 1000,
                            enabled: l !== null,
                            x: l ? l.x : 0,
                            y: l ? l.y : 0,
                            scale: l ? l.scale : 1,
                            logicalWidth: l ? l.width : mode.width,
                            focused: focused !== null && focused.name === name,
                            modes: modes,
                            mode: mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000).toFixed(3),
                            transform: l ? (transforms[l.transform] || 0) : 0
                        })
                    }

                    list.sort((a, b) => a.x - b.x)
                    page.setMonitors(list)
                } catch (error) {
                    console.log("Failed to parse niri outputs:", error)
                    page.setMonitors([])
                }
            }
        }
    }

    function parseHyprland(text) {
        try {
            page.setMonitors(JSON.parse(text).map(m => {
                // "2560x1440@143.91Hz" -> "2560x1440@143.91", duplicates dropped
                const modes = [...new Set((m.availableModes || []).map(x => x.replace(/Hz$/, "")))]
                const res = m.width + "x" + m.height
                const same = modes.filter(x => x.indexOf(res + "@") === 0)
                const mode = same.length
                    ? same.reduce((a, b) => Math.abs(page.rateOf(a) - m.refreshRate) <= Math.abs(page.rateOf(b) - m.refreshRate) ? a : b)
                    : (modes[0] || res + "@" + m.refreshRate.toFixed(2))
                return {
                    name: m.name,
                    description: ((m.make || "") + " " + (m.model || "")).trim(),
                    width: m.width,
                    height: m.height,
                    refreshRate: m.refreshRate,
                    enabled: !m.disabled,
                    x: m.x,
                    y: m.y,
                    scale: m.scale,
                    logicalWidth: Math.round(m.width / m.scale),
                    focused: m.focused,
                    modes: modes,
                    mode: mode,
                    transform: m.transform % 4
                }
            }).sort((a, b) => a.x - b.x))
        } catch (error) {
            console.log("Failed to parse hyprctl monitors:", error)
            page.setMonitors([])
        }
    }

    function refresh() {
        pList.running = true
    }

    // -------------------------
    // Applying changes
    // -------------------------
    Process {
        id: pMode

        stderr: StdioCollector {
            onStreamFinished: {
                const output = text.trim()
                if (output !== "")
                    console.log("monitor change ERROR:", output)
            }
        }

        onExited: refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 250
        repeat: false
        onTriggered: page.refresh()
    }

    function shq(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    // run `niri msg output ...` commands in order, then refresh the list
    function runOutputs(cmds) {
        pMode.command = ["sh", "-c", cmds.map(c => "niri msg output " + c).join(" && ")]
        pMode.running = true
    }

    // Hyprland: one hl.monitor({...}) per change. A rule needs the full
    // mode/position/scale, so start from the monitor's current values.
    function hyprMonitor(mon, changes) {
        const f = Object.assign({
            mode: mon.width + "x" + mon.height + "@" + mon.refreshRate,
            position: mon.x + "x" + mon.y,
            scale: mon.scale
        }, changes)
        if (f.disabled)
            return 'hl.monitor({ output = "' + mon.name + '", disabled = true })'
        return 'hl.monitor({ output = "' + mon.name + '", mode = "' + f.mode
            + '", position = "' + f.position + '", scale = ' + f.scale + ' })'
    }

    function runHyprland(luas) {
        pMode.command = ["sh", "-c", luas.map(l => "hyprctl eval " + shq(l)).join(" && ")]
        pMode.running = true
    }

    function setScale(mon, scale) {
        if (Compositor.hyprland)
            runHyprland([hyprMonitor(mon, { scale: scale.toFixed(2) })])
        else
            runOutputs([shq(mon.name) + " scale " + scale.toFixed(2)])
    }

    // -------------------------
    // Layout editor
    // -------------------------
    // Arrange, resolution, refresh, scale, rotation and on/off, after
    // FlipZ3ro/screenhub. Edits go to `draft`; APPLY sets them live and starts
    // a countdown: KEEP within it, or the old layout comes back by itself (a
    // mode the screen can't show leaves nothing to click). On Hyprland, KEEP
    // also writes the rules into ~/.config/hypr/machine.lua (monitors/save.py,
    // previous file kept as machine.lua.bak). niri changes stay runtime only.
    property var draft: []              // [{ name, description, modes, mode, x, y, scale, transform, enabled }]
    property string selected: ""        // name of the monitor being edited
    property var trialPrev: null        // live layout before APPLY, while the countdown runs
    property int trialLeft: 0
    property bool resync: true          // next monitor list replaces the draft
    property string saveError: ""
    readonly property int trialSeconds: 15
    readonly property string configPath: Quickshell.env("HOME") + "/.config/hypr/machine.lua"

    function toDraft(list) {
        return list.map(m => ({
            name: m.name, description: m.description, modes: m.modes || [], mode: m.mode || "",
            x: m.x, y: m.y, scale: m.scale, transform: m.transform || 0, enabled: m.enabled
        }))
    }
    function key(list) {
        return JSON.stringify(list.map(m => [m.name, m.mode, m.x, m.y, Number(m.scale).toFixed(3), m.transform, m.enabled]))
    }
    readonly property bool dirty: draft.length > 0 && key(draft) !== key(toDraft(monitors))
    readonly property string problem: validate(draft)
    readonly property var sel: draft.find(m => m.name === selected) || null

    // the list arrived: keep the user's edits unless asked to start over
    function setMonitors(list) {
        const clean = !dirty
        monitors = list
        if (resync || clean) {
            draft = toDraft(list)
            resync = false
        }
        if (!draft.some(m => m.name === selected)) {
            const f = list.find(m => m.focused) || list[0]
            selected = f ? f.name : ""
        }
    }

    function rateOf(mode) { return parseFloat(String(mode).split("@")[1]) || 0 }
    function resOf(mode) { return String(mode).split("@")[0] }
    // logical size: what the layout uses, after scale and rotation
    function lsize(m) {
        const r = resOf(m.mode).split("x")
        let w = +r[0] || 1920, h = +r[1] || 1080
        if (m.transform % 2) { const t = w; w = h; h = t }
        return { w: Math.round(w / m.scale), h: Math.round(h / m.scale) }
    }
    function touching(a, b) {
        const A = lsize(a), B = lsize(b)
        const yo = Math.min(a.y + A.h, b.y + B.h) - Math.max(a.y, b.y)
        const xo = Math.min(a.x + A.w, b.x + B.w) - Math.max(a.x, b.x)
        return (yo > 0 && (a.x + A.w === b.x || b.x + B.w === a.x))
            || (xo > 0 && (a.y + A.h === b.y || b.y + B.h === a.y))
    }
    // "" when the layout is usable, else why not
    function validate(list) {
        const on = list.filter(m => m.enabled)
        if (list.length === 0) return ""
        if (on.length === 0) return "Keep at least one display on."
        for (let i = 0; i < on.length; i++)
            for (let j = i + 1; j < on.length; j++) {
                const a = on[i], b = on[j], A = lsize(a), B = lsize(b)
                if (Math.min(a.x + A.w, b.x + B.w) > Math.max(a.x, b.x)
                    && Math.min(a.y + A.h, b.y + B.h) > Math.max(a.y, b.y))
                    return "Displays overlap. Drag them apart."
            }
        // every display reachable from the first through shared edges
        let reached = [0], grew = true
        while (grew) {
            grew = false
            for (let j = 0; j < on.length; j++)
                if (reached.indexOf(j) < 0 && reached.some(i => touching(on[i], on[j]))) { reached.push(j); grew = true }
        }
        if (reached.length !== on.length) return "There's a gap between displays. Drag their edges together."
        return ""
    }
    // pull a dropped display onto the nearest edges of the others
    function snap(m, list, threshold) {
        const S = lsize(m), xs = [], ys = []
        for (const o of list) {
            if (o === m || !o.enabled) continue
            const O = lsize(o)
            xs.push(o.x - S.w, o.x + O.w, o.x, o.x + O.w - S.w)
            ys.push(o.y - S.h, o.y + O.h, o.y, o.y + O.h - S.h, Math.round(o.y + (O.h - S.h) / 2))
        }
        const best = (c, v) => c.reduce((b, n) => Math.abs(n - v) < Math.abs(b - v) ? n : b, c[0])
        if (xs.length) { const bx = best(xs, m.x); if (Math.abs(bx - m.x) <= threshold) m.x = bx }
        if (ys.length) { const by = best(ys, m.y); if (Math.abs(by - m.y) <= threshold) m.y = by }
    }
    // top-left of the desktop at 0,0
    function normalize(list) {
        const on = list.filter(m => m.enabled)
        if (!on.length) return
        const mx = Math.min(...on.map(m => m.x)), my = Math.min(...on.map(m => m.y))
        for (const m of list) { m.x -= mx; m.y -= my }
    }
    function edit(name, changes) {
        const list = toDraft(draft)
        const m = list.find(x => x.name === name)
        if (!m) return
        Object.assign(m, changes)
        // a size change can open a gap or an overlap: re-seat it against the rest
        if (changes.mode !== undefined || changes.scale !== undefined || changes.transform !== undefined || changes.enabled)
            snap(m, list, 400)
        normalize(list)
        draft = list
    }
    function moveTo(name, x, y) {
        const list = toDraft(draft)
        const m = list.find(o => o.name === name)
        m.x = Math.round(x); m.y = Math.round(y)
        snap(m, list, 90)
        normalize(list)
        draft = list
    }
    function resetDraft() { draft = toDraft(monitors) }

    // one shell command that sets the whole layout
    function layoutCommand(list) {
        if (Compositor.hyprland) {
            // turn displays on before others go off, so something always shows
            const order = list.filter(m => m.enabled).concat(list.filter(m => !m.enabled))
            return ["sh", "-c", order.map(m => "hyprctl eval " + shq(m.enabled
                ? 'hl.monitor({ output = "' + m.name + '", mode = "' + m.mode + '", position = "' + m.x + "x" + m.y
                  + '", scale = ' + Number(m.scale).toFixed(2) + ', transform = ' + m.transform + ' })'
                : 'hl.monitor({ output = "' + m.name + '", disabled = true })')).join(" && ")]
        }
        const names = ["normal", "90", "180", "270"]
        const cmds = []
        for (const m of list.filter(x => x.enabled)) {
            const N = shq(m.name)
            cmds.push(N + " on", N + " mode " + m.mode, N + " scale " + Number(m.scale).toFixed(2),
                      N + " transform " + names[m.transform], N + " position set " + m.x + " " + m.y)
        }
        for (const m of list.filter(x => !x.enabled)) cmds.push(shq(m.name) + " off")
        return ["sh", "-c", cmds.map(c => "niri msg output " + c).join(" && ")]
    }
    function applyLayout(list) {
        pMode.command = layoutCommand(list)
        pMode.running = true
    }
    function apply() {
        if (problem !== "" || !dirty || trialPrev !== null) return
        saveError = ""
        trialPrev = toDraft(monitors)
        trialLeft = trialSeconds
        resync = true
        applyLayout(draft)
        trialTimer.restart()
    }
    function keep() {
        if (trialPrev === null) return
        trialTimer.stop()
        trialPrev = null
        if (Compositor.hyprland) {
            pSave.command = ["python3", "-I", Quickshell.shellPath("monitors/save.py"), configPath,
                JSON.stringify(draft.map(m => ({ name: m.name, mode: m.mode, x: m.x, y: m.y,
                                                 scale: Number(Number(m.scale).toFixed(2)), transform: m.transform, enabled: m.enabled })))]
            pSave.running = true
        }
    }
    function revert() {
        if (trialPrev === null) return
        trialTimer.stop()
        const prev = trialPrev
        trialPrev = null
        resync = true
        applyLayout(prev)
    }

    Timer {
        id: trialTimer
        interval: 1000
        repeat: true
        onTriggered: {
            page.trialLeft--
            if (page.trialLeft <= 0) page.revert()
        }
    }
    // leaving the page or closing Settings mid-countdown counts as "no"
    Component.onDestruction: if (trialPrev !== null) Quickshell.execDetached(layoutCommand(trialPrev))

    Process {
        id: pSave
        stderr: StdioCollector {
            onStreamFinished: page.saveError = text.trim()
        }
    }

    // -------------------------
    // Monitor modes
    // -------------------------
    function applyMonitorMode(mode) {
        const displays = findMonitors()
        const internal = displays.internal
        const external = displays.external

        if (!internal || !external) {
            page.refresh()
            return
        }

        if (Compositor.hyprland) {
            // a disabled output reports 0x0, so fall back to its preferred mode
            const on = m => m.enabled ? {} : { mode: "preferred" }
            const extWidth = Math.round(external.width / (external.enabled ? external.scale : 1))
            if (mode === "first")
                runHyprland([hyprMonitor(internal, Object.assign(on(internal), { position: "0x0" })),
                             hyprMonitor(external, { disabled: true })])
            else if (mode === "second")
                runHyprland([hyprMonitor(external, Object.assign(on(external), { position: "0x0" })),
                             hyprMonitor(internal, { disabled: true })])
            else if (mode === "extend")
                runHyprland([hyprMonitor(external, Object.assign(on(external), { position: "0x0" })),
                             hyprMonitor(internal, Object.assign(on(internal), { position: extWidth + "x0" }))])
            return
        }

        const I = shq(internal.name)
        const E = shq(external.name)

        if (mode === "first") {
            runOutputs([I + " on", I + " position set 0 0", E + " off"])
        } else if (mode === "second") {
            runOutputs([E + " on", E + " position set 0 0", I + " off"])
        } else if (mode === "extend") {
            // external on the left, laptop panel to its right
            const extWidth = Math.round(external.width / (external.enabled ? external.scale : 1))
            runOutputs([
                E + " on",
                I + " on",
                E + " position set 0 0",
                I + " position set " + extWidth + " 0"
            ])
        }
    }

    // -------------------------
    // Page
    // -------------------------
    // small building blocks for the display editor
    component Chip: Rectangle {
        id: chip
        property string label
        property bool current: false
        signal clicked()
        width: Math.max(chipText.implicitWidth + 20, 54)
        height: 28
        radius: Theme.radius
        color: current ? Theme.alpha(Theme.accent, 0.14) : chipMouse.containsMouse ? Theme.bgCard : "transparent"
        border.width: 1
        border.color: current || chipMouse.containsMouse ? Theme.accent : Theme.border
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.current ? Theme.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: chip.current
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
    component Btn: Rectangle {
        id: btn
        property string label
        property bool primary: false
        property bool active: true
        signal clicked()
        width: btnText.implicitWidth + 28
        height: 30
        radius: Theme.radius
        opacity: active ? 1 : 0.4
        color: primary ? Theme.alpha(Theme.accent, btnMouse.containsMouse && active ? 0.28 : 0.16)
             : btnMouse.containsMouse && active ? Theme.bgCard : "transparent"
        border.width: 1
        border.color: primary ? Theme.accent : Theme.border
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? Theme.accent : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.active) btn.clicked()
        }
    }
    component FieldLabel: Text {
        width: 96
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageCol.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

    Column {
        id: pageCol
        width: parent.width - page.rightMargin
        spacing: 20

        // -------------------------
        // Header
        // -------------------------
        Row {
            width: parent.width

            Text {
                text: "MONITORS"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 3
            }

            Item {
                width: parent.width - 150
                height: 1
            }

            Text {
                text: "󰑐"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 22

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.refresh()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
        }

        // -------------------------
        // MONITOR MODE
        // -------------------------
        Column {
            // only for a laptop panel plus an external display
            visible: page.findMonitors().internal !== null && page.findMonitors().external !== null
            width: parent.width
            spacing: 10

            Text {
                text: "MONITOR MODE"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 2
            }

            Row {
                width: parent.width
                spacing: 10

                Repeater {
                    model: [
                        { name: "FIRST", mode: "first" },
                        { name: "SECOND", mode: "second" },
                        { name: "EXTEND", mode: "extend" }
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        width:
                            (
                                parent.width -
                                parent.spacing * 2
                            ) / 3

                        height: 42
                        radius: Theme.radius
                        color: "#00000000"
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: modelData.name
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true

                            onEntered: {
                                parent.color =
                                    Theme.alpha(
                                        Theme.accent,
                                        0.08
                                    )

                                parent.border.color =
                                    Theme.accent
                            }

                            onExited: {
                                parent.color = "#00000000"
                                parent.border.color = Theme.border
                            }

                            onClicked: {
                                console.log(
                                    "BUTTON CLICKED:",
                                    modelData.name,
                                    modelData.mode
                                )

                                page.applyMonitorMode(
                                    modelData.mode
                                )
                            }
                        }
                    }
                }
            }
        }

        // -------------------------
        // DISPLAYS: layout + the selected display's settings
        // -------------------------
        Column {
            width: parent.width
            spacing: 12
            visible: page.draft.length > 0

            Row {
                spacing: 14
                Text {
                    text: "DISPLAYS"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: "DRAG TO ARRANGE  ·  EDGES SNAP"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }

            // the desktop, to scale
            Rectangle {
                id: layoutBox
                width: parent.width
                height: 210
                radius: Theme.radius
                color: Theme.alpha(Theme.bgCard, 0.6)
                border.width: 1
                border.color: page.problem !== "" ? Theme.danger : Theme.border
                clip: true

                readonly property var on: page.draft.filter(m => m.enabled)
                readonly property real x0: on.length ? Math.min(...on.map(m => m.x)) : 0
                readonly property real y0: on.length ? Math.min(...on.map(m => m.y)) : 0
                readonly property real bw: on.length ? Math.max(...on.map(m => m.x + page.lsize(m).w)) - x0 : 1
                readonly property real bh: on.length ? Math.max(...on.map(m => m.y + page.lsize(m).h)) - y0 : 1
                // leave room around the desktop to drag a display past the edge
                readonly property real f: Math.min((width - 120) / bw, (height - 60) / bh)
                readonly property real ox: (width - bw * f) / 2 - x0 * f
                readonly property real oy: (height - bh * f) / 2 - y0 * f

                Repeater {
                    model: layoutBox.on
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        readonly property var sz: page.lsize(modelData)
                        readonly property bool isSel: modelData.name === page.selected

                        x: layoutBox.ox + modelData.x * layoutBox.f
                        y: layoutBox.oy + modelData.y * layoutBox.f
                        z: dragArea.pressed ? 2 : 1
                        width: sz.w * layoutBox.f
                        height: sz.h * layoutBox.f
                        radius: Theme.radius
                        color: isSel ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.text, 0.05)
                        border.width: isSel ? 2 : 1
                        border.color: isSel ? Theme.accent : Theme.borderAccent

                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.name
                                color: tile.isSel ? Theme.accent : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: page.resOf(tile.modelData.mode) + " @" + Math.round(page.rateOf(tile.modelData.mode))
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                            }
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            cursorShape: Qt.SizeAllCursor
                            preventStealing: true
                            enabled: page.trialPrev === null
                            drag.target: tile
                            drag.threshold: 4
                            onPressed: page.selected = tile.modelData.name
                            onReleased: if (drag.active || tile.x !== layoutBox.ox + tile.modelData.x * layoutBox.f)
                                page.moveTo(tile.modelData.name, (tile.x - layoutBox.ox) / layoutBox.f,
                                            (tile.y - layoutBox.oy) / layoutBox.f)
                        }
                    }
                }
            }

            // every display, including ones that are off
            Row {
                spacing: 6
                Repeater {
                    model: page.draft
                    Chip {
                        required property var modelData
                        label: modelData.name + (modelData.enabled ? "" : "  ·  OFF")
                        current: modelData.name === page.selected
                        onClicked: page.selected = modelData.name
                    }
                }
            }

            // the selected display
            Column {
                visible: page.sel !== null
                width: parent.width
                spacing: 10

                Item {
                    width: parent.width
                    height: 26
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80
                        elide: Text.ElideRight
                        text: page.sel ? page.sel.name + (page.sel.description ? "   " + page.sel.description : "") : ""
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }
                    // on / off; the last display that's on can't go off
                    Rectangle {
                        readonly property bool on: page.sel !== null && page.sel.enabled
                        readonly property bool locked: on && page.draft.filter(m => m.enabled).length < 2
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 60
                        height: 24
                        radius: Theme.radius
                        opacity: locked ? 0.45 : 1
                        color: on ? Theme.alpha(Theme.accent, 0.15) : "transparent"
                        border.color: on ? Theme.accent : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: parent.on ? "ON" : "OFF"
                            color: parent.on ? Theme.accent : Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: parent.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (!parent.locked && page.trialPrev === null) {
                                const m = page.sel
                                // a display coming back on starts at its best mode, beside the others
                                const changes = { enabled: !m.enabled }
                                if (!m.enabled && m.modes.indexOf(m.mode) < 0 && m.modes.length) changes.mode = m.modes[0]
                                if (!m.enabled) {
                                    const others = page.draft.filter(o => o.enabled)
                                    changes.x = Math.max(...others.map(o => o.x + page.lsize(o).w))
                                    changes.y = 0
                                }
                                page.edit(m.name, changes)
                            }
                        }
                    }
                }

                // resolution: the current one, click for the full list
                Row {
                    visible: page.sel !== null && page.sel.enabled
                    width: parent.width
                    FieldLabel { anchors.verticalCenter: parent.verticalCenter; text: "RESOLUTION" }
                    Chip {
                        id: resChip
                        property bool open: false
                        label: page.sel ? page.resOf(page.sel.mode) + (open ? "  ▴" : "  ▾") : ""
                        current: open
                        onClicked: open = !open
                    }
                }
                Flow {
                    visible: resChip.open && page.sel !== null && page.sel.enabled
                    x: 96
                    width: parent.width - 96
                    spacing: 6
                    Repeater {
                        // unique resolutions, biggest first
                        model: page.sel ? [...new Set(page.sel.modes.map(md => page.resOf(md)))]
                            .sort((a, b) => b.split("x")[0] * b.split("x")[1] - a.split("x")[0] * a.split("x")[1]) : []
                        Chip {
                            required property string modelData
                            label: modelData
                            current: page.sel && page.resOf(page.sel.mode) === modelData
                            onClicked: {
                                // the fastest refresh at that size
                                const best = page.sel.modes.filter(md => page.resOf(md) === modelData)
                                    .sort((a, b) => page.rateOf(b) - page.rateOf(a))[0]
                                resChip.open = false
                                page.edit(page.sel.name, { mode: best })
                            }
                        }
                    }
                }

                Row {
                    visible: page.sel !== null && page.sel.enabled
                    width: parent.width
                    spacing: 6
                    FieldLabel { anchors.verticalCenter: parent.verticalCenter; text: "REFRESH"; width: 90 }
                    Repeater {
                        model: page.sel ? page.sel.modes.filter(md => page.resOf(md) === page.resOf(page.sel.mode))
                            .sort((a, b) => page.rateOf(b) - page.rateOf(a)) : []
                        Chip {
                            required property string modelData
                            label: (+page.rateOf(modelData).toFixed(2)) + " Hz"
                            current: page.sel && page.sel.mode === modelData
                            onClicked: page.edit(page.sel.name, { mode: modelData })
                        }
                    }
                }

                Row {
                    visible: page.sel !== null && page.sel.enabled
                    width: parent.width
                    spacing: 6
                    FieldLabel { anchors.verticalCenter: parent.verticalCenter; text: "SCALE"; width: 90 }
                    Repeater {
                        model: [1.0, 1.25, 1.5, 1.75, 2.0]
                        Chip {
                            required property real modelData
                            label: modelData.toFixed(2) + "×"
                            current: page.sel && Math.abs(page.sel.scale - modelData) < 0.01
                            onClicked: page.edit(page.sel.name, { scale: modelData })
                        }
                    }
                }

                Row {
                    visible: page.sel !== null && page.sel.enabled
                    width: parent.width
                    spacing: 6
                    FieldLabel { anchors.verticalCenter: parent.verticalCenter; text: "ROTATION"; width: 90 }
                    Repeater {
                        model: [{ t: 0, l: "0°" }, { t: 1, l: "90°" }, { t: 2, l: "180°" }, { t: 3, l: "270°" }]
                        Chip {
                            required property var modelData
                            label: modelData.l
                            current: page.sel && page.sel.transform === modelData.t
                            onClicked: page.edit(page.sel.name, { transform: modelData.t })
                        }
                    }
                }

                Row {
                    visible: page.sel !== null && page.sel.enabled
                    spacing: 0
                    FieldLabel { text: "POSITION" }
                    Text {
                        text: page.sel ? page.sel.x + ", " + page.sel.y + "   ·   " + page.lsize(page.sel).w + "×" + page.lsize(page.sel).h + " logical" : ""
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            // apply / keep
            Rectangle {
                width: parent.width
                height: 48
                radius: Theme.radius
                visible: page.trialPrev !== null || page.dirty || page.saveError !== ""
                color: page.trialPrev !== null ? Theme.alpha(Theme.accent, 0.10) : "transparent"
                border.width: 1
                border.color: page.trialPrev !== null ? Theme.accent
                            : page.problem !== "" || page.saveError !== "" ? Theme.danger : Theme.border

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: applyRow.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.Wrap
                    text: page.trialPrev !== null ? "Keep these settings?  Reverting in " + page.trialLeft + " s"
                        : page.problem !== "" ? page.problem
                        : page.dirty ? "Unapplied changes"
                        : "Couldn't save to machine.lua: " + page.saveError
                    color: page.trialPrev !== null ? Theme.accent
                         : page.problem !== "" || (!page.dirty && page.saveError !== "") ? Theme.danger : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                Row {
                    id: applyRow
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Btn {
                        visible: page.trialPrev !== null
                        label: "REVERT"
                        onClicked: page.revert()
                    }
                    Btn {
                        visible: page.trialPrev !== null
                        label: "KEEP"
                        primary: true
                        onClicked: page.keep()
                    }
                    Btn {
                        visible: page.trialPrev === null && page.dirty
                        label: "RESET"
                        onClicked: page.resetDraft()
                    }
                    Btn {
                        visible: page.trialPrev === null && page.dirty
                        label: "APPLY"
                        primary: true
                        active: page.problem === ""
                        onClicked: page.apply()
                    }
                }
            }

            Text {
                visible: !Compositor.hyprland
                text: "niri: changes last until niri restarts; set them in config.kdl to keep them."
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
            }
        }

        // -------------------------
        // BRIGHTNESS
        // -------------------------
        Item {
            visible: page.hasBacklight
            width: parent.width
            height: 58

            Slider {
                anchors.fill: parent

                label: "BRIGHTNESS"
                icon: "\uf185"
                value: page.brightnessValue
                accentColor: Theme.accent2

                onCommitted: (value) =>
                    page.commitBrightness(value)
            }
        }

        // -------------------------
        // NIGHT LIGHT
        // -------------------------
        Item {
            width: parent.width
            height: 58

            property int controlMargin: 25

            Row {
                anchors.fill: parent
                spacing: parent.controlMargin

                Slider {
                    width:
                        parent.width -
                        70 -
                        parent.spacing

                    height: parent.height

                    label: "NIGHT LIGHT  ·  " + NightLight.temperature + "K"
                    icon: ""
                    value: NightLight.value
                    accentColor: Theme.accent

                    onMoved: (value) =>
                        NightLight.value = value
                }

                Rectangle {
                    width: 70
                    height: 36
                    radius: Theme.radius
                    anchors.verticalCenter: parent.verticalCenter

                    color:
                        NightLight.active
                            ? Theme.alpha(Theme.accent, 0.1)
                            : Theme.alpha("#A0A0A0", 0.15)

                    border.width: 1
                    border.color: NightLight.active ? Theme.accent : "#A0A0A0"

                    Text {
                        anchors.centerIn: parent
                        text: NightLight.active ? "ON" : "OFF"
                        color: NightLight.active ? Theme.accent : "#A0A0A0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NightLight.toggle()
                    }
                }
            }
        }

        // -------------------------
        // NIGHT LIGHT SCHEDULE
        // -------------------------
        Column {
            width: parent.width
            spacing: 12

            // mode selector + status
            Item {
                width: parent.width
                height: 28

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        text: "SCHEDULE"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }

                    Repeater {
                        model: [
                            { mode: "manual", label: "MANUAL" },
                            { mode: "sun",    label: "SUNSET" },
                            { mode: "custom", label: "CUSTOM" }
                        ]

                        Rectangle {
                            required property var modelData
                            readonly property bool selected: NightLight.mode === modelData.mode

                            width: modeText.implicitWidth + 22
                            height: 26
                            radius: Theme.radius
                            color: selected ? Theme.alpha(Theme.accent, 0.12)
                                 : modeMouse.containsMouse ? Theme.bgCard : "transparent"
                            border.width: 1
                            border.color: selected ? Theme.accent : Theme.border

                            Text {
                                id: modeText
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.selected ? Theme.accent : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 2
                                font.bold: parent.selected
                            }

                            MouseArea {
                                id: modeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NightLight.mode = modelData.mode
                            }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: NightLight.status
                    color: NightLight.active ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }
            }

            // sunset mode: show today's times
            Row {
                visible: NightLight.mode === "sun"
                x: 102
                spacing: 18

                Repeater {
                    model: [
                        { label: "SUNSET",  min: NightLight.sun.set },
                        { label: "SUNRISE", min: NightLight.sun.rise }
                    ]
                    Row {
                        required property var modelData
                        spacing: 8
                        Text {
                            text: modelData.label
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            anchors.baseline: sunTime.baseline
                        }
                        Text {
                            id: sunTime
                            text: NightLight.fmt(modelData.min)
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // custom mode: start/end pickers (± 15 min, or scroll)
            Row {
                visible: NightLight.mode === "custom"
                x: 102
                spacing: 22

                Repeater {
                    model: [
                        { label: "FROM", key: "start" },
                        { label: "TO",   key: "end" }
                    ]

                    Row {
                        id: picker
                        required property var modelData
                        readonly property int minutes: NightLight[modelData.key]
                        spacing: 8

                        function shift(delta) {
                            NightLight[modelData.key] = ((minutes + delta) % 1440 + 1440) % 1440
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            text: picker.modelData.label
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }

                        Repeater {
                            model: ["−", "time", "+"]

                            Rectangle {
                                required property string modelData
                                readonly property bool isTime: modelData === "time"

                                width: isTime ? 92 : 26
                                height: 26
                                radius: Theme.radius
                                color: !isTime && stepMouse.containsMouse ? Theme.bgCard : "transparent"
                                border.width: 1
                                border.color: !isTime && stepMouse.containsMouse ? Theme.accent : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.isTime ? NightLight.fmt(picker.minutes) : parent.modelData
                                    color: parent.isTime ? Theme.text : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: parent.isTime ? 12 : 13
                                }

                                MouseArea {
                                    id: stepMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: parent.isTime ? Qt.SizeVerCursor : Qt.PointingHandCursor
                                    onClicked: {
                                        if (parent.modelData === "−") picker.shift(-15)
                                        else if (parent.modelData === "+") picker.shift(15)
                                    }
                                    onWheel: wheel => picker.shift(wheel.angleDelta.y > 0 ? 15 : -15)
                                }
                            }
                        }
                    }
                }
            }
        }

    }
    }

    Component.onCompleted: {
        brightnessGet.running = true
    }
}
