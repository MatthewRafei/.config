pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Which network the machine is on, shared by the bar chip and the Settings
// Network page. Wi-Fi comes from NetworkManager when it is running; wired
// links are read straight from /sys so they work without it. Only physical
// devices count (/sys/class/net/*/device), so docker/veth/lo are ignored.
//
// mode: "wireless" when Wi-Fi can actually be managed here (NetworkManager
// running and a Wi-Fi adapter present) and no wired link is in use,
// otherwise "wired".
Singleton {
    id: net

    property bool nmRunning: false
    property string ssid: ""        // connected Wi-Fi network, "" if none
    property int signal: 0
    property string ethIface: ""    // first wired link that is up
    property string wifiIface: ""   // Wi-Fi adapter, connected or not

    readonly property bool wired: ssid === "" && ethIface !== ""
    readonly property string mode: !wired && nmRunning && wifiIface !== "" ? "wireless" : "wired"

    function refresh() {
        if (!proc.running) proc.running = true
    }

    Process {
        id: proc
        command: [
            "sh",
            "-c",
            "nmcli -t -f RUNNING general 2>/dev/null | sed 's/^/nm /'; " +
            "nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -1 | sed 's/^/wifi /'; " +
            "for d in /sys/class/net/*; do " +
            "  [ -e $d/device ] || continue; " +
            "  if [ -d $d/wireless ]; then echo wlan ${d##*/}; " +
            "  elif [ \"$(cat $d/operstate)\" = up ]; then echo eth ${d##*/}; fi; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var nm = false, ssid = "", signal = 0, eth = "", wlan = ""
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var t = lines[i].trim()
                    if (t.startsWith("nm ")) {
                        nm = t.slice(3) === "running"
                    } else if (t.startsWith("wifi ")) {
                        // terse format: yes:<ssid>:<signal>; ssid itself may contain escaped colons
                        t = t.slice(5)
                        var last = t.lastIndexOf(":")
                        signal = +t.slice(last + 1)
                        ssid = t.slice(4, last).replace(/\\:/g, ":")
                    } else if (t.startsWith("eth ")) {
                        if (!eth) eth = t.slice(4)
                    } else if (t.startsWith("wlan ")) {
                        if (!wlan) wlan = t.slice(5)
                    }
                }
                net.nmRunning = nm
                net.ssid = ssid
                net.signal = signal
                net.ethIface = eth
                net.wifiIface = wlan
            }
        }
    }

    // NetworkManager tells us when something changes (`nmcli monitor`
    // prints a line per event), so the timer only needs to catch Wi-Fi
    // signal drift. Without nmcli it falls back to a 5 s poll.
    Process {
        id: monitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: settle.restart() }
        onRunningChanged: if (!running) monitorRetry.start()
    }
    Timer { id: monitorRetry; interval: 30000; onTriggered: monitor.running = true }
    Timer { id: settle; interval: 400; onTriggered: net.refresh() }

    Timer {
        interval: monitor.running ? 20000 : 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: net.refresh()
    }
}
