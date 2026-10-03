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

    // battery details (sysfs; energy in Wh, power in W)
    property string batStatus: ""
    property real energyNow: 0
    property real energyFull: 0
    property real energyDesign: 0
    property real powerW: 0
    property int cycles: -1
    property string batModel: ""

    readonly property real health: energyDesign > 0 ? energyFull / energyDesign : -1
    // hours until empty (discharging) or full (charging), -1 if unknown
    readonly property real hoursLeft: powerW < 0.1 ? -1
        : batStatus === "Charging" ? Math.max(0, energyFull - energyNow) / powerW
        : batStatus === "Discharging" ? energyNow / powerW
        : -1

    function fmtHours(h) {
        if (h < 0) return "—"
        const m = Math.round(h * 60)
        return Math.floor(m / 60) + "h " + (m % 60 < 10 ? "0" : "") + (m % 60) + "m"
    }

    Process {
        id: batProbe
        // energy_* may be charge_* (µAh) on some batteries; convert with voltage
        command: ["sh", "-c",
            "for a in /sys/class/power_supply/A*/online; do [ -r \"$a\" ] && { echo ac $(cat \"$a\"); break; }; done; "
            + "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] || continue; "
            + "echo bat $(cat \"$b/capacity\"); "
            + "for f in status energy_now energy_full energy_full_design power_now charge_now charge_full charge_full_design current_now voltage_now cycle_count manufacturer model_name; do "
            + "[ -r \"$b/$f\" ] && echo \"$f $(cat \"$b/$f\" 2>/dev/null)\"; done; break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = {}
                for (const line of text.split("\n")) {
                    const i = line.indexOf(" ")
                    if (i > 0) v[line.slice(0, i)] = line.slice(i + 1).trim()
                }
                if (v.ac !== undefined) root.onAC = v.ac === "1"
                if (v.bat === undefined) return
                root.battery = parseInt(v.bat)
                root.hasBattery = true
                root.batStatus = v.status || ""
                const volts = (parseFloat(v.voltage_now) || 0) / 1e6
                const e = (k, c) => v[k] !== undefined ? parseFloat(v[k]) / 1e6
                                  : v[c] !== undefined ? parseFloat(v[c]) / 1e6 * volts : 0
                root.energyNow = e("energy_now", "charge_now")
                root.energyFull = e("energy_full", "charge_full")
                root.energyDesign = e("energy_full_design", "charge_full_design")
                root.powerW = v.power_now !== undefined ? parseFloat(v.power_now) / 1e6
                            : (parseFloat(v.current_now) || 0) / 1e6 * volts
                root.cycles = v.cycle_count !== undefined ? parseInt(v.cycle_count) : -1
                root.batModel = [v.manufacturer, v.model_name].filter(x => x).join(" ")
            }
        }
    }

    Timer {
        interval: 10000
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
