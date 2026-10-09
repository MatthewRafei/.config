import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import QtQuick

// Quick toggles dropped down from the bar's NET / BT / volume chips.
//
//   wi-fi      radio on/off, rescan, networks sorted by signal; click to
//              connect (known networks reconnect, new secured ones ask for
//              the password inline), click the current one to disconnect
//   bluetooth  power on/off, paired devices with battery; click to
//              connect/disconnect (pair new devices in Settings)
//   vpn        tailscale up/down, this machine's address (click = copy),
//              exit node choice, devices on the tailnet (click = copy ip)
//
//   sound      output volume and device, input volume and device, and a
//              volume for every app playing (or recording) audio; click an
//              icon to mute, scroll a slider for ±5%
//
//   recorder   screen recording (Recorder.qml): monitor or a dragged-out
//              area, audio source, start/stop, recent recordings
//
//   agents     Claude Code sessions (Agents.qml): open / stop them, start a
//              kept one (survives closing its terminal), resume a recent one
//
//   qs ipc call quick net | bt | vpn | audio | rec | agents | close
PanelWindow {
    id: root

    property string mode: ""          // "", "net", "bt", "vpn", "audio", "rec" or "agents"
    readonly property bool open: mode !== ""

    function toggle(m) {
        mode = mode === m ? "" : m
        if (mode === "net") net.refresh()
        if (mode === "vpn") Vpn.refresh()
        if (mode === "rec") Recorder.refreshRecent()
        if (mode === "agents") Agents.refreshMore()
    }

    Binding { target: Vpn; property: "fast"; value: root.mode === "vpn" }
    Binding { target: Agents; property: "fast"; value: root.mode === "agents" }

    IpcHandler {
        target: "quick"
        function net(): void { root.toggle("net") }
        function bt(): void { root.toggle("bt") }
        function vpn(): void { root.toggle("vpn") }
        function audio(): void { root.toggle("audio") }
        function rec(): void { root.toggle("rec") }
        function agents(): void { root.toggle("agents") }
        function close(): void { root.mode = "" }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-quick"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: open || panel.opacity > 0

    MouseArea {
        anchors.fill: parent
        onClicked: root.mode = ""
    }

    // ================================================================ sound
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var audioNodes: Pipewire.nodes.values.filter(n => n.audio)
    function mediaClass(n) { return n.properties["media.class"] || "" }
    readonly property var outputs: audioNodes.filter(n => mediaClass(n) === "Audio/Sink")
    readonly property var inputs: audioNodes.filter(n => mediaClass(n) === "Audio/Source")
    // apps playing, then apps recording (not PipeWire's own internal streams)
    readonly property var streams: audioNodes.filter(n => mediaClass(n) === "Stream/Output/Audio")
        .concat(audioNodes.filter(n => mediaClass(n) === "Stream/Input/Audio"))

    // .audio is only live on tracked nodes
    PwObjectTracker { objects: root.mode === "audio" ? root.audioNodes : [] }

    // the last couple of words of a device name ("... Controller Speaker" -> "SPEAKER")
    function shortName(n) {
        const w = nodeName(n).split(/\s+/)
        let t = w[w.length - 1] || ""
        if (w.length > 1 && (w[w.length - 2] + " " + t).length <= 18) t = w[w.length - 2] + " " + t
        return t.toUpperCase()
    }
    function nodeName(n) {
        return n ? (n.description || n.nickname || n.name || "unknown") : "none"
    }
    function appName(n) {
        const p = n.properties
        return p["application.name"] || p["application.process.binary"] || n.description || n.name || "app"
    }

    // ================================================================ wi-fi
    QtObject {
        id: net

        property bool radio: true
        property var networks: []        // [{ ssid, signal, secure, active, known }]
        property var known: []
        property string pending: ""      // ssid we're connecting to
        property string askPassword: ""  // ssid whose password row is open
        property string error: ""

        function refresh() {
            pRadio.running = true
            pKnown.running = true      // then pScan, which needs the saved list
        }

        // split nmcli terse output on unescaped ':'
        function fields(line) {
            const out = []
            let cur = ""
            for (let i = 0; i < line.length; i++) {
                const c = line[i]
                if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
                if (c === ":") { out.push(cur); cur = ""; continue }
                cur += c
            }
            out.push(cur)
            return out
        }

        function activate(n) {
            error = ""
            if (n.active) {
                run(["nmcli", "connection", "down", "id", n.ssid], n.ssid)
            } else if (n.known) {
                run(["nmcli", "connection", "up", "id", n.ssid], n.ssid)
            } else if (n.secure) {
                askPassword = askPassword === n.ssid ? "" : n.ssid
            } else {
                run(["nmcli", "device", "wifi", "connect", n.ssid], n.ssid)
            }
        }

        function connectWith(ssid, password) {
            askPassword = ""
            run(["nmcli", "device", "wifi", "connect", ssid, "password", password], ssid)
        }

        function run(cmd, ssid) {
            pending = ssid
            pAct.command = cmd
            pAct.running = true
        }
    }

    Process {
        id: pRadio
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector { onStreamFinished: net.radio = text.trim() === "enabled" }
    }

    Process {
        id: pKnown
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                net.known = text.trim().split("\n")
                    .map(l => net.fields(l))
                    .filter(f => f[1] === "802-11-wireless")
                    .map(f => f[0])
                pScan.running = true
            }
        }
    }

    Process {
        id: pScan
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const best = {}
                for (const line of text.trim().split("\n")) {
                    if (!line) continue
                    const f = net.fields(line)
                    const ssid = f[1]
                    if (!ssid) continue
                    const n = {
                        ssid: ssid,
                        signal: parseInt(f[2]) || 0,
                        secure: (f[3] || "").trim() !== "" && f[3] !== "--",
                        active: f[0] === "*",
                        known: net.known.indexOf(ssid) >= 0
                    }
                    const prev = best[ssid]
                    if (!prev || n.active || (!prev.active && n.signal > prev.signal))
                        best[ssid] = n
                }
                net.networks = Object.values(best).sort((a, b) =>
                    (b.active - a.active) || (b.known - a.known) || (b.signal - a.signal))
            }
        }
    }

    Process {
        id: pAct
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t) net.error = t.replace(/^Error:\s*/, "").split("\n")[0]
            }
        }
        onExited: { net.pending = ""; net.refresh() }
    }

    // ================================================================ bluetooth
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btDevices: {
        if (!adapter) return []
        return adapter.devices.values
            .filter(d => d.paired || d.connected)
            .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || ""))
    }

    // ================================================================ panel
    component Head: Item {
        id: head
        property string title
        property bool on: true
        property bool showRescan: false
        property bool showToggle: true
        signal toggled()
        signal rescan()

        width: parent.width
        height: 26

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 3
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                visible: head.showRescan && (head.on || !head.showToggle)
                width: 26; height: 22
                radius: Theme.radius
                color: rescanMouse.containsMouse ? Theme.bgCard : "transparent"
                border.color: rescanMouse.containsMouse ? Theme.accent : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: rescanMouse.containsMouse ? Theme.accent : Theme.textDim
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: rescanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: head.rescan()
                }
            }

            Rectangle {
                visible: head.showToggle
                width: 44; height: 22
                radius: Theme.radius
                color: head.on ? Theme.alpha(Theme.accent, 0.15) : "transparent"
                border.color: head.on ? Theme.accent : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: head.on ? "ON" : "OFF"
                    color: head.on ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: head.toggled()
                }
            }
        }
    }

    // small caps label between sections
    component Label2: Text {
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
        topPadding: 6
    }

    // a node's volume: mute button, name, slider (drag or scroll), percent
    component VolRow: Item {
        id: vr
        property var node: null
        property string icon: "󰕾"
        property string mutedIcon: "󰝟"
        property string label
        property string sub
        readonly property bool ok: node !== null && node.audio !== null
        readonly property bool muted: ok && node.audio.muted
        readonly property real vol: ok ? node.audio.volume : 0

        function setVol(v) {
            if (!ok) return
            node.audio.muted = false
            node.audio.volume = Math.max(0, Math.min(1, v))
        }

        width: parent ? parent.width : 0
        height: 40

        Rectangle {
            id: muteBtn
            width: 26; height: 26
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.radius
            color: vr.muted ? Theme.alpha(Theme.danger, 0.15)
                 : muteMouse.containsMouse ? Theme.bgCard : "transparent"
            border.color: vr.muted ? Theme.danger : muteMouse.containsMouse ? Theme.accent : Theme.border
            Text {
                anchors.centerIn: parent
                text: vr.muted ? vr.mutedIcon : vr.icon
                color: vr.muted ? Theme.danger : Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: 13
            }
            MouseArea {
                id: muteMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (vr.ok) vr.node.audio.muted = !vr.node.audio.muted
            }
        }

        Column {
            anchors.left: muteBtn.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Item {
                width: parent.width
                height: nameText.implicitHeight
                Text {
                    id: nameText
                    width: parent.width - pct.width - 8
                    elide: Text.ElideRight
                    text: vr.label + (vr.sub ? "  ·  " + vr.sub : "")
                    color: vr.muted ? Theme.textDim : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
                Text {
                    id: pct
                    anchors.right: parent.right
                    text: vr.muted ? "MUTED" : Math.round(vr.vol * 100) + "%"
                    color: vr.muted ? Theme.danger : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }

            // track
            Item {
                width: parent.width
                height: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.trackBg
                    Rectangle {
                        width: parent.width * Math.min(1, vr.vol)
                        height: parent.height
                        radius: 2
                        color: vr.muted ? Theme.textFaint : Theme.accent
                    }
                }
                Rectangle {
                    visible: trackMouse.containsMouse || trackMouse.pressed
                    x: (parent.width - width) * Math.min(1, vr.vol)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10
                    radius: 5
                    color: Theme.accent
                }
                MouseArea {
                    id: trackMouse
                    anchors.fill: parent
                    anchors.topMargin: -6
                    anchors.bottomMargin: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => vr.setVol(mouse.x / width)
                    onPositionChanged: mouse => { if (pressed) vr.setVol(mouse.x / width) }
                    onWheel: wheel => vr.setVol(vr.vol + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                }
            }
        }
    }

    // one row in either list
    component Row2: Rectangle {
        id: row
        property string icon
        property string label
        property string detail
        property string tag
        property bool active: false
        property bool busy: false
        property real level: -1         // 0..1 signal bars, -1 = none
        signal clicked()

        width: parent ? parent.width : 0
        height: 36
        radius: Theme.radius
        color: active ? Theme.alpha(Theme.accent, 0.10)
             : rowMouse.containsMouse ? Theme.bgCard : "transparent"

        Rectangle {
            visible: row.active
            width: 2
            height: parent.height - 12
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.accent
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 10

            // signal bars or an icon
            Item {
                width: 18
                height: 14
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    visible: row.level >= 0
                    anchors.bottom: parent.bottom
                    spacing: 2
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            width: 3
                            height: 4 + index * 3
                            anchors.bottom: parent.bottom
                            color: row.level * 4 > index ? (row.active ? Theme.accent : Theme.text) : Theme.trackBg
                        }
                    }
                }

                Text {
                    visible: row.level < 0
                    anchors.centerIn: parent
                    text: row.icon
                    color: row.active ? Theme.accent : Theme.textDim
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // as wide as the tag on the right allows
                width: row.width - 12 - 18 - 10 - 12 - (tagText.text ? tagText.implicitWidth + 10 : 0)
                elide: Text.ElideRight
                text: row.label
                color: row.active ? Theme.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: row.active
            }
        }

        Text {
            id: tagText
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: row.busy ? "···" : (row.tag || row.detail)
            color: row.busy || row.tag ? Theme.accent : Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }
    }

    // a Claude Code session: status, title, folder · age, kept or not, stop
    component AgentRow: Rectangle {
        id: ar
        property var s
        property bool armed: false
        readonly property color tint: s.status === "waiting" ? Theme.danger
            : s.status === "busy" ? Theme.accent : s.status === "new" ? Theme.text : Theme.textDim

        width: parent ? parent.width : 0
        height: 40
        radius: Theme.radius
        color: arMouse.containsMouse ? Theme.bgCard : "transparent"

        Rectangle {
            width: 2
            height: parent.height - 12
            anchors.verticalCenter: parent.verticalCenter
            color: ar.tint
            visible: ar.s.status === "waiting" || ar.s.status === "busy"
        }

        // status dot, pulsing while it works
        Rectangle {
            id: dot
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: ar.tint
            SequentialAnimation on opacity {
                running: ar.s.status === "busy"
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) dot.opacity = 1
            }
        }

        Column {
            x: 32
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - tags.width - 16
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: ar.s.title
                color: ar.s.status === "waiting" ? Theme.danger : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: (ar.s.status === "waiting" ? "NEEDS YOU" : ar.s.status === "busy" ? "WORKING"
                       : ar.s.status === "new" ? "NEW" : "IDLE")
                    + " " + Agents.ago(ar.s.since) + "  ·  " + Agents.pretty(ar.s.cwd || "")
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 8
                font.letterSpacing: 1
            }
        }

        Row {
            id: tags
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            // kept sessions survive their terminal; the others end with it
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ar.s.tmux !== "" ? (ar.s.attached > 0 ? "KEPT" : "KEPT · BG") : "TERMINAL"
                color: ar.s.tmux !== "" ? Theme.accent : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 8
                font.letterSpacing: 1
            }
            Rectangle {
                visible: ar.s.tmux !== ""
                width: ar.armed ? stopText.implicitWidth + 12 : 22
                height: 22
                radius: Theme.radius
                color: ar.armed ? Theme.alpha(Theme.danger, 0.15) : "transparent"
                border.color: ar.armed || stopMouse.containsMouse ? Theme.danger : Theme.border
                Text {
                    id: stopText
                    anchors.centerIn: parent
                    text: ar.armed ? "STOP?" : "󰅖"
                    color: ar.armed || stopMouse.containsMouse ? Theme.danger : Theme.textDim
                    font.family: ar.armed ? Theme.fontFamily : Theme.iconFont
                    font.pixelSize: ar.armed ? 8 : 12
                    font.bold: ar.armed
                }
                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (ar.armed) { ar.armed = false; Agents.stop(ar.s) }
                        else { ar.armed = true; disarm.restart() }
                    }
                }
                Timer { id: disarm; interval: 3000; onTriggered: ar.armed = false }
            }
        }

        MouseArea {
            id: arMouse
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.mode = ""; Agents.open(ar.s) }
        }
    }

    Rectangle {
        id: panel

        width: 340
        height: Math.min(content.implicitHeight + 28, root.height - 20)
        x: parent.width - width - 12
        y: 10
        radius: Theme.radius
        color: Theme.alpha(Theme.bgPanel, 0.96)
        border.color: Theme.border
        clip: true

        opacity: root.open ? 1 : 0
        transform: Translate { y: root.open ? 0 : -8 }
        Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        focus: root.open
        Keys.onEscapePressed: root.mode = ""

        MouseArea { anchors.fill: parent }   // keep clicks inside

        Column {
            id: content
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 8

            // ------------------------------------------------ wi-fi
            Column {
                visible: root.mode === "net"
                width: parent.width
                spacing: 4

                Head {
                    title: "// WI-FI"
                    on: net.radio
                    showRescan: true
                    onToggled: {
                        Quickshell.execDetached(["nmcli", "radio", "wifi", net.radio ? "off" : "on"])
                        net.radio = !net.radio
                        refreshLater.restart()
                    }
                    onRescan: net.refresh()
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }

                Text {
                    visible: net.error !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: net.error
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    topPadding: 4
                }

                Text {
                    visible: net.radio && net.networks.length === 0
                    text: "scanning…"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    topPadding: 6
                }

                Flickable {
                    width: parent.width
                    height: Math.min(netList.implicitHeight, 360)
                    contentHeight: netList.implicitHeight
                    clip: true
                    visible: net.radio

                    Column {
                        id: netList
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: net.networks

                            Column {
                                id: netItem
                                required property var modelData
                                width: netList.width
                                spacing: 4

                                Row2 {
                                    label: netItem.modelData.ssid
                                    level: netItem.modelData.signal / 100
                                    active: netItem.modelData.active
                                    busy: net.pending === netItem.modelData.ssid
                                    tag: netItem.modelData.active ? "CONNECTED" : ""
                                    detail: (netItem.modelData.secure ? "󰌾 " : "") + (netItem.modelData.known ? "SAVED" : "")
                                    onClicked: net.activate(netItem.modelData)
                                }

                                // inline password for new secured networks
                                Rectangle {
                                    visible: net.askPassword === netItem.modelData.ssid
                                    width: parent.width
                                    height: visible ? 34 : 0
                                    radius: Theme.radius
                                    color: Theme.bgCard
                                    border.color: pw.activeFocus ? Theme.accent : Theme.border

                                    TextInput {
                                        id: pw
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                                        onAccepted: if (text !== "") net.connectWith(netItem.modelData.ssid, text)
                                        Keys.onEscapePressed: net.askPassword = ""

                                        Text {
                                            visible: pw.text === ""
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "password, then ↵"
                                            color: Theme.textFaint
                                            font: pw.font
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ bluetooth
            Column {
                visible: root.mode === "bt"
                width: parent.width
                spacing: 4

                Head {
                    title: "// BLUETOOTH"
                    on: root.adapter !== null && root.adapter.enabled
                    onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }

                Text {
                    visible: root.adapter === null || !root.adapter.enabled || root.btDevices.length === 0
                    text: root.adapter === null ? "no adapter"
                        : !root.adapter.enabled ? "bluetooth is off"
                        : "no paired devices"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    topPadding: 6
                }

                Repeater {
                    model: root.adapter && root.adapter.enabled ? root.btDevices : []

                    Row2 {
                        required property var modelData
                        icon: modelData.icon && modelData.icon.indexOf("audio") >= 0 ? "󰋋"
                            : modelData.icon && modelData.icon.indexOf("input") >= 0 ? "󰌌"
                            : modelData.icon && modelData.icon.indexOf("phone") >= 0 ? "󰏲"
                            : "󰂯"
                        label: modelData.name || modelData.address
                        active: modelData.connected
                        busy: modelData.state === BluetoothDeviceState.Connecting
                           || modelData.state === BluetoothDeviceState.Disconnecting
                        tag: modelData.connected
                            ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%  " : "") + "CONNECTED"
                            : ""
                        detail: "PAIRED"
                        onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                    }
                }
            }

            // ------------------------------------------------ tailscale
            Column {
                visible: root.mode === "vpn"
                width: parent.width
                spacing: 4

                Head {
                    title: "// TAILSCALE"
                    on: Vpn.running
                    onToggled: Vpn.toggle()
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }

                Text {
                    visible: Vpn.error !== "" || (Vpn.state !== "" && Vpn.state !== "Running" && Vpn.state !== "Stopped")
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: Vpn.error !== "" ? Vpn.error
                        : Vpn.state === "NeedsLogin" ? "Logged out. Run:  tailscale up  in a terminal to log in."
                        : Vpn.state.toLowerCase() + "…"
                    color: Vpn.error !== "" ? Theme.danger : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    topPadding: 4
                }

                // this machine
                Row2 {
                    icon: "󰖂"
                    label: Vpn.selfName + "  (this device)"
                    active: Vpn.running
                    busy: Vpn.busy === "up" || Vpn.busy === "down"
                    tag: copied.running ? "COPIED" : ""
                    detail: Vpn.running ? Vpn.selfIp : "STOPPED"
                    onClicked: if (Vpn.selfIp !== "") { Vpn.copy(Vpn.selfIp); copied.restart() }
                }

                // exit node: none + every peer that offers it
                Text {
                    visible: Vpn.running && Vpn.peers.some(p => p.exitOption)
                    text: "EXIT NODE"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    topPadding: 8
                }
                Row2 {
                    visible: Vpn.running && Vpn.peers.some(p => p.exitOption)
                    icon: "󰅖"
                    label: "None (direct)"
                    active: Vpn.exitNode === ""
                    busy: Vpn.busy === "exit" && pendingExit === ""
                    onClicked: { pendingExit = ""; Vpn.useExit("") }
                }
                Repeater {
                    model: Vpn.running ? Vpn.peers.filter(p => p.exitOption) : []
                    Row2 {
                        required property var modelData
                        icon: "󰖟"
                        label: modelData.name
                        active: modelData.exit
                        busy: Vpn.busy === "exit" && pendingExit === modelData.ip
                        tag: modelData.exit ? "IN USE" : ""
                        detail: modelData.online ? "" : "OFFLINE"
                        onClicked: if (!modelData.exit) { pendingExit = modelData.ip; Vpn.useExit(modelData.ip) }
                    }
                }

                // devices
                Text {
                    visible: Vpn.running && Vpn.peers.length > 0
                    text: "DEVICES  " + Vpn.onlineCount + " / " + Vpn.peers.length + " ONLINE"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    topPadding: 8
                }
                Flickable {
                    visible: Vpn.running
                    width: parent.width
                    height: Math.min(peerList.implicitHeight, 260)
                    contentHeight: peerList.implicitHeight
                    clip: true

                    Column {
                        id: peerList
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: Vpn.peers
                            Row2 {
                                required property var modelData
                                icon: modelData.os === "android" || modelData.os === "iOS" ? "󰏲"
                                    : modelData.os === "windows" ? "󰖳"
                                    : modelData.os === "macOS" ? "󰀵"
                                    : modelData.os === "linux" ? "󰌽"
                                    : "󰒋"
                                label: modelData.name
                                active: false
                                opacity: modelData.online ? 1 : 0.45
                                tag: copiedIp === modelData.ip && copied.running ? "COPIED" : ""
                                detail: modelData.online ? modelData.ip : "OFFLINE"
                                onClicked: { copiedIp = modelData.ip; Vpn.copy(modelData.ip); copied.restart() }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ recorder
            Column {
                visible: root.mode === "rec"
                width: parent.width
                spacing: 4

                Head {
                    title: "// SCREEN RECORDER"
                    on: Recorder.active
                    onToggled: { if (!Recorder.active) root.mode = ""; Recorder.toggle() }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }

                Text {
                    visible: Recorder.error !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: Recorder.error
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    topPadding: 4
                }

                Label2 { text: "RECORD" }
                Repeater {
                    model: Quickshell.screens
                    Row2 {
                        required property var modelData
                        icon: "󰍹"
                        label: Quickshell.screens.length > 1 ? "Screen  " + modelData.name : "Whole screen"
                        detail: Recorder.px(modelData.width, modelData.height, modelData)
                        active: Recorder.mode === "screen" && Recorder.screenName() === modelData.name
                        onClicked: { Recorder.mode = "screen"; Recorder.output = modelData.name }
                    }
                }
                Row2 {
                    icon: "󰩭"
                    label: "Pick an area"
                    detail: Recorder.region.width > 0 ? Recorder.px(Recorder.region.width, Recorder.region.height, Recorder.screen) : "DRAG A BOX"
                    active: Recorder.mode === "region"
                    onClicked: Recorder.mode = "region"
                }

                Label2 { text: "AUDIO" }
                Row2 {
                    icon: "󰝟"
                    label: "No audio"
                    active: Recorder.audio === "none"
                    onClicked: Recorder.audio = "none"
                }
                Row2 {
                    visible: root.sink !== null
                    icon: "󰓃"
                    label: "Desktop audio"
                    detail: root.sink ? root.shortName(root.sink) : ""
                    active: Recorder.audio === "desktop"
                    onClicked: Recorder.audio = "desktop"
                }
                Row2 {
                    visible: root.source !== null
                    icon: "󰍬"
                    label: "Microphone"
                    detail: root.source ? root.shortName(root.source) : ""
                    active: Recorder.audio === "mic"
                    onClicked: Recorder.audio = "mic"
                }

                Item { width: 1; height: 4 }

                // start / stop
                Rectangle {
                    id: recBtn
                    readonly property bool live: Recorder.state === "recording"
                    width: parent.width
                    height: 40
                    radius: Theme.radius
                    color: live ? Theme.alpha(Theme.danger, recMouse.containsMouse ? 0.25 : 0.15)
                         : Theme.alpha(Theme.accent, recMouse.containsMouse ? 0.22 : 0.12)
                    border.color: live ? Theme.danger : Theme.accent

                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: recBtn.live ? "󰓛" : "󰑊"
                            color: recBtn.live ? Theme.danger : Theme.accent
                            font.family: Theme.iconFont
                            font.pixelSize: 16
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: recBtn.live ? "STOP  ·  " + Recorder.clock
                                : Recorder.state === "countdown" ? "STARTING IN " + Recorder.countdown + "  ·  CANCEL"
                                : Recorder.state === "saving" ? "SAVING…"
                                : Recorder.mode === "region" ? "PICK AREA AND RECORD" : "START RECORDING"
                            color: recBtn.live ? Theme.danger : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 2
                        }
                    }
                    MouseArea {
                        id: recMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Recorder.state === "idle") root.mode = ""   // out of the shot
                            Recorder.toggle()
                        }
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "3 S COUNTDOWN  ·  MOD+ALT+R  ·  AREA: +SHIFT"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    font.letterSpacing: 1
                    topPadding: 2
                }

                Label2 { visible: Recorder.recent.length > 0; text: "RECENT" }
                Repeater {
                    model: Recorder.recent
                    Row2 {
                        required property var modelData
                        icon: "󰕧"
                        label: modelData.name.replace(/^Recording_/, "").replace(/\.mp4$/, "").replace("_", "  ")
                        detail: modelData.size
                        onClicked: { root.mode = ""; Recorder.open(modelData.path) }
                    }
                }
            }

            // ------------------------------------------------ sound
            Column {
                visible: root.mode === "audio"
                width: parent.width
                spacing: 4

                Head {
                    title: "// SOUND"
                    on: root.sink !== null && root.sink.audio !== null && !root.sink.audio.muted
                    onToggled: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }

                Label2 { text: "OUTPUT" }
                VolRow {
                    node: root.sink
                    label: root.nodeName(root.sink)
                }
                Repeater {
                    model: root.outputs.length > 1 ? root.outputs : []
                    Row2 {
                        required property var modelData
                        height: 30
                        icon: /head|line/i.test(root.nodeName(modelData)) ? "󰋋"
                            : /hdmi|displayport/i.test(root.nodeName(modelData)) ? "󰍹" : "󰓃"
                        label: root.nodeName(modelData)
                        active: root.sink !== null && modelData.id === root.sink.id
                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }

                Label2 { text: "INPUT" }
                VolRow {
                    node: root.source
                    icon: "󰍬"
                    mutedIcon: "󰍭"
                    label: root.nodeName(root.source)
                }
                Repeater {
                    model: root.inputs.length > 1 ? root.inputs : []
                    Row2 {
                        required property var modelData
                        height: 30
                        icon: /webcam|camera/i.test(root.nodeName(modelData)) ? "󰄀" : "󰍬"
                        label: root.nodeName(modelData)
                        active: root.source !== null && modelData.id === root.source.id
                        onClicked: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }

                Label2 { text: "APPS" }
                Text {
                    visible: root.streams.length === 0
                    text: "nothing playing"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    topPadding: 2
                }
                Flickable {
                    width: parent.width
                    height: Math.min(appList.implicitHeight, 260)
                    contentHeight: appList.implicitHeight
                    clip: true
                    visible: root.streams.length > 0

                    Column {
                        id: appList
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: root.streams
                            VolRow {
                                required property var modelData
                                readonly property bool rec: root.mediaClass(modelData) === "Stream/Input/Audio"
                                node: modelData
                                icon: rec ? "󰍬" : "󰎆"
                                mutedIcon: rec ? "󰍭" : "󰝟"
                                label: root.appName(modelData)
                                sub: modelData.properties["media.name"] || ""
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ claude code
            Column {
                visible: root.mode === "agents"
                width: parent.width
                spacing: 4

                Head {
                    title: "// CLAUDE CODE  ·  " + Agents.sessions.length + " RUNNING"
                    showToggle: false
                    showRescan: true
                    onRescan: Agents.refreshMore()
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }

                Text {
                    visible: Agents.sessions.length === 0
                    text: "NOTHING RUNNING"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    topPadding: 6
                }

                Label2 { visible: Agents.waiting.length > 0; text: "NEEDS YOU"; color: Theme.danger }
                Repeater { model: Agents.waiting; AgentRow { required property var modelData; s: modelData } }
                Label2 { visible: Agents.busy.length > 0; text: "WORKING" }
                Repeater { model: Agents.busy; AgentRow { required property var modelData; s: modelData } }
                Label2 { visible: Agents.idle.length > 0; text: "IDLE" }
                Repeater { model: Agents.idle; AgentRow { required property var modelData; s: modelData } }

                Label2 { text: "NEW KEPT SESSION  ·  SURVIVES CLOSING" }
                Repeater {
                    // home, the folders Claude knows, and wherever sessions run now
                    model: [Agents.home].concat(Agents.projects)
                        .concat(Agents.sessions.map(x => x.cwd))
                        .filter((d, i, a) => d && a.indexOf(d) === i)
                    Row2 {
                        required property string modelData
                        height: 30
                        icon: "󰐕"
                        label: Agents.pretty(modelData)
                        onClicked: { root.mode = ""; Agents.newSession(modelData, "") }
                    }
                }
                HudField {
                    id: agentDir
                    width: parent.width
                    placeholder: "other folder…  (enter to start)"
                    onAccepted: {
                        let d = text.trim().replace(/^~(?=\/|$)/, Agents.home)
                        if (d === "") return
                        text = ""
                        root.mode = ""
                        Agents.newSession(d, "")
                    }
                }

                Label2 { visible: Agents.recent.length > 0; text: "RESUME AS KEPT" }
                Repeater {
                    model: Agents.recent.slice(0, 5)
                    Row2 {
                        required property var modelData
                        height: 30
                        icon: "󰑐"
                        label: modelData.title
                        detail: Agents.ago(modelData.mtime)
                        onClicked: { root.mode = ""; Agents.newSession(modelData.cwd, modelData.sid) }
                    }
                }
            }

            // ------------------------------------------------ footer
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Text {
                text: root.mode === "rec" ? "OPEN RECORDINGS FOLDER  →" : "ALL SETTINGS  →"
                color: footMouse.containsMouse ? Theme.accent : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2
                MouseArea {
                    id: footMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const sound = root.mode === "audio"
                        if (root.mode === "rec") { root.mode = ""; Recorder.open(""); return }
                        root.mode = ""
                        Quickshell.execDetached(sound ? ["qs", "ipc", "call", "settings", "page", "Sound"]
                                                      : ["qs", "ipc", "call", "settings", "open"])
                    }
                }
            }
        }
    }

    property string pendingExit: ""
    property string copiedIp: ""
    Timer { id: copied; interval: 1500 }

    Timer {
        id: refreshLater
        interval: 1500
        onTriggered: net.refresh()
    }
}
