pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// What happens when the machine sits idle: screensaver, lock, screen off.
// Edited in Settings > Screensaver, kept per machine in
// ~/.cache/quickshell/idle.json. Screensaver.qml and Lock.qml read it; the
// screen-off step lives here.
//
// Everything respects idle inhibitors (video, games) and Caffeine.
Singleton {
    id: root

    property alias screensaver: st.screensaver       // run the screensaver at all
    property alias screensaverMin: st.screensaverMin // idle minutes before it starts
    property alias sceneSec: st.sceneSec             // seconds per scene, 0 = never change
    property alias lockMin: st.lockMin               // idle minutes before locking, 0 = never
    property alias screenOffMin: st.screenOffMin     // idle minutes before the screen turns off, 0 = never
    property alias onBattery: st.onBattery           // screensaver on battery too (else skip it)
    property alias showName: st.showName             // scene name in the corner
    property alias disabled: st.disabled             // scene ids left out of the rotation

    function sceneEnabled(id) { return disabled.indexOf(id) < 0 }
    function setSceneEnabled(id, on) {
        const d = disabled.filter(x => x !== id)
        if (!on) d.push(id)
        disabled = d
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/idle.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: st
            property bool screensaver: true
            property int screensaverMin: 3
            property int sceneSec: 60
            property int lockMin: 5
            property int screenOffMin: 0
            property bool onBattery: true
            property bool showName: true
            property var disabled: []
        }
    }

    // ---------------- screen off ----------------
    IdleMonitor {
        enabled: root.screenOffMin > 0
        timeout: Math.max(1, root.screenOffMin) * 60
        respectInhibitors: true
        onIsIdleChanged: {
            if (!enabled) return
            if (Compositor.hyprland)
                Quickshell.execDetached(["hyprctl", "dispatch", "dpms", isIdle ? "off" : "on"])
            else if (isIdle)
                // niri turns the outputs back on by itself at the next input
                Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"])
        }
    }
}
