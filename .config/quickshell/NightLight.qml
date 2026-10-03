pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Night light (gammastep -O <K>) with an optional schedule.
//
// Lives for the whole session (shell.qml instantiates it), so the schedule
// runs with the settings window closed and the setting is restored at login.
// State: ~/.cache/quickshell/nightlight.json
//
// mode  "manual"  on/off by hand
//       "sun"     sunset → sunrise, location from ~/.config/gammastep/config.ini
//       "custom"  start → end (minutes after midnight)
//
// Toggling while a schedule is in charge overrides it until the next
// scheduled change.
//
//   qs ipc call nightlight toggle
Singleton {
    id: root

    // ---------------- persisted settings ----------------
    property alias enabled: st.enabled
    property alias value: st.value
    property alias mode: st.mode
    property alias start: st.start
    property alias end: st.end

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/nightlight.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: st
            property bool enabled: false
            property real value: 0.5
            property string mode: "manual"
            property int start: 20 * 60
            property int end: 7 * 60
        }
    }

    // ---------------- location (for sunset mode) ----------------
    property real lat: 0.0
    property real lon: 0.0

    FileView {
        path: Quickshell.env("HOME") + "/.config/gammastep/config.ini"
        onLoaded: {
            const t = text()
            const la = t.match(/^\s*lat\s*=\s*(-?[\d.]+)/m)
            const lo = t.match(/^\s*lon\s*=\s*(-?[\d.]+)/m)
            if (la) root.lat = parseFloat(la[1])
            if (lo) root.lon = parseFloat(lo[1])
        }
    }

    // ---------------- schedule ----------------
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property int nowMin: clock.date.getHours() * 60 + clock.date.getMinutes()
    readonly property var sun: sunTimes(clock.date, lat, lon)
    readonly property bool scheduled: mode !== "manual"
    readonly property int winStart: mode === "sun" ? sun.set : start
    readonly property int winEnd: mode === "sun" ? sun.rise : end
    readonly property bool inWindow: winStart <= winEnd
        ? (nowMin >= winStart && nowMin < winEnd)
        : (nowMin >= winStart || nowMin < winEnd)   // window crosses midnight

    // -1 none, 0 forced off, 1 forced on (only meaningful when scheduled)
    property int overrideState: -1
    onInWindowChanged: overrideState = -1
    onModeChanged: overrideState = -1

    readonly property bool active: scheduled
        ? (overrideState >= 0 ? overrideState === 1 : inWindow)
        : enabled

    readonly property int temperature: Math.round(2500 + value * 4000)

    readonly property string status: {
        if (!scheduled)
            return ""
        if (active && inWindow) return "ON UNTIL " + fmt(winEnd)
        if (!active && !inWindow) return "STARTS " + fmt(winStart)
        if (!active && inWindow) return "PAUSED UNTIL " + fmt(winEnd)
        return "ON · OVERRIDE"
    }

    function toggle() {
        if (scheduled)
            overrideState = active ? 0 : 1
        else
            enabled = !enabled
    }

    function fmt(min) {
        const d = new Date(2000, 0, 1, Math.floor(min / 60), min % 60)
        return Qt.formatTime(d, "hh:mm AP")
    }

    // NOAA sunrise/sunset approximation; returns local minutes after midnight
    function sunTimes(date, lat, lon) {
        const rad = Math.PI / 180
        const n = Math.floor((date - new Date(date.getFullYear(), 0, 0)) / 86400000)
        const lngHour = lon / 15

        function calc(rising) {
            const t = n + ((rising ? 6 : 18) - lngHour) / 24
            const M = 0.9856 * t - 3.289
            let L = M + 1.916 * Math.sin(M * rad) + 0.020 * Math.sin(2 * M * rad) + 282.634
            L = ((L % 360) + 360) % 360
            let RA = Math.atan(0.91764 * Math.tan(L * rad)) / rad
            RA = ((RA % 360) + 360) % 360
            RA = (RA + Math.floor(L / 90) * 90 - Math.floor(RA / 90) * 90) / 15
            const sinDec = 0.39782 * Math.sin(L * rad)
            const cosDec = Math.cos(Math.asin(sinDec))
            const cosH = (Math.cos(90.833 * rad) - sinDec * Math.sin(lat * rad)) / (cosDec * Math.cos(lat * rad))
            if (cosH > 1 || cosH < -1)
                return rising ? 7 * 60 : 19 * 60   // polar day/night: sane fallback
            const H = (rising ? 360 - Math.acos(cosH) / rad : Math.acos(cosH) / rad) / 15
            const T = H + RA - 0.06571 * t - 6.622
            const local = (T - lngHour) - date.getTimezoneOffset() / 60
            return Math.round((((local % 24) + 24) % 24) * 60)
        }

        return { rise: calc(true), set: calc(false) }
    }

    // ---------------- applying ----------------
    property int appliedTemp: -2   // -2 unknown (forces first apply), -1 off

    function apply() {
        const want = active ? temperature : -1
        if (want === appliedTemp)
            return
        appliedTemp = want
        Quickshell.execDetached(["sh", "-c", want < 0
            ? "pkill -x gammastep"
            : "pkill -x gammastep; sleep 0.05; setsid gammastep -O " + want + " >/dev/null 2>&1 &"])
    }

    onActiveChanged: apply()
    onTemperatureChanged: if (active) applyTimer.restart()   // slider drags

    Timer {
        id: applyTimer
        interval: 150
        onTriggered: root.apply()
    }

    Component.onCompleted: apply()

    IpcHandler {
        target: "nightlight"
        function toggle(): void { root.toggle() }
        function status(): string {
            return (root.active ? "on " : "off ") + root.temperature + "K " + root.mode + " " + root.status
        }
    }
}
