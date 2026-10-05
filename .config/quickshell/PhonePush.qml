import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick

// Pushes to the phone through ntfy (~/.local/bin/ntfy-send, server and topic
// in ~/.config/ntfy/config) while nobody is at the desk: the screen is locked
// or there's been no input for `idleMin` minutes. Sends desktop notifications
// (not transient ones, and only critical ones under do-not-disturb) and a few
// machine events: low/critical battery, charger, Tailscale dropping.
//
//   qs ipc call phone away       "true" / "false" (the Claude Code hook asks)
//   qs ipc call phone test       send a test push now, away or not
Scope {
    id: root

    property bool locked: false
    property int idleMin: 2
    readonly property bool away: locked || idle.isIdle

    readonly property string sendCmd: Quickshell.env("HOME") + "/.local/bin/ntfy-send"

    function push(title, message, prio, tags) {
        Quickshell.execDetached([sendCmd, "-t", title, "-p", String(prio || 3), "-g", tags || "", message || title])
    }

    function pushIfAway(title, message, prio, tags) {
        if (away && armed) push(title, message, prio, tags)
    }

    // notification bodies may carry markup
    function plain(t) {
        return String(t || "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
            .replace(/&#39;/g, "'").replace(/&amp;/g, "&")
    }

    // no input at all, inhibitors ignored: a playing video still counts as away
    IdleMonitor {
        id: idle
        timeout: root.idleMin * 60
        respectInhibitors: false
    }

    // properties settle while the shell starts; don't treat that as events
    property bool armed: false
    Timer { interval: 10000; running: true; onTriggered: root.armed = true }

    Connections {
        target: Notifs
        function onReceived(n) {
            if (!n || n.transient) return
            const crit = n.urgency === NotificationUrgency.Critical
            if (Notifs.dnd && !crit) return
            const app = n.appName || "Notification"
            const summary = root.plain(n.summary)
            root.pushIfAway(summary !== "" ? summary : app,
                            root.plain(n.body) || app,
                            crit ? 5 : n.urgency === NotificationUrgency.Low ? 2 : 3,
                            "computer")
        }
    }

    property bool lowSent: false
    property bool critSent: false
    Connections {
        target: Power
        function onBatteryChanged() {
            if (!Power.hasBattery) return
            const b = Power.battery
            if (Power.onAC || b > Power.lowThreshold + 2) { root.lowSent = false; root.critSent = false }
            if (Power.onAC) return
            if (b <= 10 && !root.critSent) {
                root.critSent = true
                root.pushIfAway("Battery critical: " + b + "%", "nox will die soon. Plug it in.", 5, "rotating_light,battery")
            } else if (b <= Power.lowThreshold && !root.lowSent) {
                root.lowSent = true
                root.pushIfAway("Battery low: " + b + "%", "nox is running on battery.", 4, "battery")
            }
        }
        function onOnACChanged() {
            if (!Power.hasBattery) return
            if (Power.onAC) root.pushIfAway("Charger connected", "nox is charging (" + Power.battery + "%).", 2, "electric_plug")
            else root.pushIfAway("Charger disconnected", "nox is on battery (" + Power.battery + "%).", 4, "electric_plug,warning")
        }
    }

    // The ntfy server is reached over the tailnet, so the "down" push only
    // arrives if the LAN route works; the "back" push says how long it was out.
    property real vpnDownAt: 0
    Connections {
        target: Vpn
        function onRunningChanged() {
            if (!Vpn.installed || !root.armed) return
            if (!Vpn.running) {
                root.vpnDownAt = Date.now()
                root.pushIfAway("Tailscale disconnected", "nox dropped off the tailnet (" + (Vpn.state || "stopped") + ").", 4, "warning")
            } else if (root.vpnDownAt > 0) {
                const min = Math.round((Date.now() - root.vpnDownAt) / 60000)
                root.vpnDownAt = 0
                root.pushIfAway("Tailscale reconnected", "nox is back on the tailnet after " + (min < 1 ? "under a minute" : min + " min") + ".", 2, "link")
            }
        }
    }

    IpcHandler {
        target: "phone"
        function away(): string { return root.away ? "true" : "false" }
        function test(): void { root.push("Test from nox", "PhonePush is wired up (away: " + root.away + ").", 3, "test_tube") }
    }
}
