pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// CPU / memory / temperature / battery / uptime, shared by the bar and the
// telemetry HUD. Reads /proc and /sys straight through FileView instead of
// forking a shell every tick. Samples every 2 s, or every second while some
// consumer (the HUD) holds `fast`.
Singleton {
    id: root

    property int fastUsers: 0
    readonly property int interval: fastUsers > 0 ? 1000 : 2000

    property real cpu: 0
    property real mem: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real temp: -1
    property int bat: -1
    property string batStatus: ""
    property real uptime: 0

    // fired after each CPU sample (the HUD's sparkline follows it)
    signal sampled()

    property real _lastBusy: -1
    property real _lastIdle: -1
    property string _tempPath: ""
    property string _batDir: ""

    Timer {
        interval: root.interval
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload()
            meminfo.reload()
            uptimeFile.reload()
            if (root._tempPath) tempFile.reload()
            if (root._batDir) { batCap.reload(); batStat.reload() }
        }
    }

    // find the coretemp sensor and the battery once
    Process {
        running: true
        command: ["sh", "-c",
            "for h in /sys/class/hwmon/hwmon*; do " +
            "  [ \"$(cat $h/name 2>/dev/null)\" = coretemp ] && { echo temp $h/temp1_input; break; }; " +
            "done; " +
            "for b in /sys/class/power_supply/BAT*; do [ -r $b/capacity ] && { echo bat $b; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.split("\n")) {
                    const p = l.trim().split(" ")
                    if (p[0] === "temp") root._tempPath = p[1]
                    else if (p[0] === "bat") root._batDir = p[1]
                }
            }
        }
    }

    FileView {
        id: stat
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const t = text()
            const p = t.slice(0, t.indexOf("\n")).trim().split(/\s+/)
            // cpu user nice system idle iowait irq softirq steal
            const busy = +p[1] + +p[2] + +p[3] + +p[6] + +p[7] + +p[8]
            const idle = +p[4] + +p[5]
            if (root._lastBusy >= 0) {
                const db = busy - root._lastBusy, di = idle - root._lastIdle
                root.cpu = (db + di) > 0 ? db / (db + di) : 0
            }
            root._lastBusy = busy
            root._lastIdle = idle
            root.sampled()
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const t = text()
            const total = +(/MemTotal:\s+(\d+)/.exec(t) || [0, 0])[1]
            const avail = +(/MemAvailable:\s+(\d+)/.exec(t) || [0, 0])[1]
            root.mem = total > 0 ? (total - avail) / total : 0
            root.memUsedGb = (total - avail) / 1048576
            root.memTotalGb = total / 1048576
        }
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: root.uptime = Math.floor(parseFloat(text()))
    }

    FileView {
        id: tempFile
        path: root._tempPath
        printErrors: false
        onLoaded: root.temp = +text().trim() / 1000
    }

    FileView {
        id: batCap
        path: root._batDir ? root._batDir + "/capacity" : ""
        printErrors: false
        onLoaded: root.bat = +text().trim()
    }

    FileView {
        id: batStat
        path: root._batDir ? root._batDir + "/status" : ""
        printErrors: false
        onLoaded: root.batStatus = text().trim()
    }
}
