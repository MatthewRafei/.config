pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Power profiles (power-profiles-daemon) + battery-based automatic switching.
//
// `available` is true only when the daemon is running and offers more than
// one profile; the bar chip and the Settings page hide themselves otherwise.
//
// Automatic switching picks a profile from the rules below whenever the
// situation changes (plugged in / unplugged / crossing the low-battery
// threshold). Choosing a profile by hand sticks until the next such change.
// Rules: ~/.cache/quickshell/power.json
//
//   qs ipc call power-profile cycle
Singleton {
    id: root

    // ---------------- persisted rules ----------------
    property alias auto: st.auto
    property alias acProfile: st.acProfile
    property alias batteryProfile: st.batteryProfile
    property alias lowProfile: st.lowProfile
    property alias lowThreshold: st.lowThreshold

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/power.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: st
            property bool auto: true
            property string acProfile: "balanced"
            property string batteryProfile: "balanced"
            property string lowProfile: "power-saver"
            property int lowThreshold: 25
        }
    }

    // ---------------- profiles ----------------
    readonly property var names: ["power-saver", "balanced", "performance"]
    readonly property var labels: ({ "power-saver": "SAVER", "balanced": "BALANCED", "performance": "PERF" })
    readonly property var icons: ({ "power-saver": "󰌪", "balanced": "󰾅", "performance": "󰓅" })

    property int daemonProfiles: 0   // how many profiles the daemon offers
    readonly property bool available: daemonProfiles > 1
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile

    // why performance is being held back right now, if it is
    readonly property string degraded: {
        switch (PowerProfiles.degradationReason) {
        case PerformanceDegradationReason.LapDetected: return "laptop on lap"
        case PerformanceDegradationReason.HighTemperature: return "running hot"
        default: return ""
        }
    }

    // the profiles worth offering in the UI
    readonly property var choices: hasPerformance ? names : names.slice(0, 2)

    readonly property string current: {
        switch (PowerProfiles.profile) {
        case PowerProfile.PowerSaver: return "power-saver"
        case PowerProfile.Performance: return "performance"
        default: return "balanced"
        }
    }

    function set(name) {
        if (!available) return
        if (name === "performance" && !hasPerformance) name = "balanced"
        PowerProfiles.profile = name === "power-saver" ? PowerProfile.PowerSaver
                              : name === "performance" ? PowerProfile.Performance
                              : PowerProfile.Balanced
    }

    function cycle() {
        const c = choices
        set(c[(c.indexOf(current) + 1) % c.length])
    }

    // Is power-profiles-daemon running? (re-checked, so starting it later works)
    Process {
        id: probe
        command: ["sh", "-c",
            "busctl --system get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles Profiles 2>/dev/null"
            + " || busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles Profiles 2>/dev/null"]
        stdout: StdioCollector {
            // "aa{sv} 3 ..." -> 3
            onStreamFinished: {
                const m = text.match(/^aa\{sv\}\s+(\d+)/)
                root.daemonProfiles = m ? parseInt(m[1]) : 0
            }
        }
    }

    // ---------------- battery ----------------
    property bool onAC: true
    property int battery: 100
    property bool hasBattery: false

    Process {
        id: batProbe
        command: ["sh", "-c",
            "for a in /sys/class/power_supply/A*/online; do [ -r \"$a\" ] && { echo ac $(cat \"$a\"); break; }; done; "
            + "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] && { echo bat $(cat \"$b/capacity\"); break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const p = line.trim().split(/\s+/)
                    if (p[0] === "ac") root.onAC = p[1] === "1"
                    if (p[0] === "bat") { root.battery = parseInt(p[1]); root.hasBattery = true }
                }
            }
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!probe.running) probe.running = true
            if (!batProbe.running) batProbe.running = true
        }
    }

    // ---------------- automatic switching ----------------
    // which rule applies right now
    readonly property string situation: !hasBattery || onAC ? "ac"
                                      : battery <= lowThreshold ? "low" : "battery"
    readonly property string wanted: situation === "ac" ? acProfile
                                   : situation === "low" ? lowProfile : batteryProfile

    function applyRules() {
        if (auto && available && current !== wanted) set(wanted)
    }

    // only on a change of situation (or rules), so manual picks stick until then
    onSituationChanged: applyRules()
    onWantedChanged: applyRules()
    onAutoChanged: applyRules()
    onAvailableChanged: applyRules()

    IpcHandler {
        target: "power-profile"
        function cycle(): void { root.cycle() }
        function get(): string { return root.available ? root.current : "unavailable" }
    }
}
