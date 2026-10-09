import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import QtQuick
import qs.widgets

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
    readonly property bool corePage: ["net", "bt", "audio"].indexOf(mode) >= 0
    function close() { mode = "" }

    function toggle(m) {
        mode = mode === m ? "" : m
        if (mode === "net") net.refresh()
    }


    IpcHandler {
        target: "quick"
        function net(): void { root.toggle("net") }
        function bt(): void { root.toggle("bt") }
        function vpn(): void { root.toggle("vpn") }
        function audio(): void { root.toggle("audio") }
        function rec(): void { root.toggle("rec") }
        function agents(): void { root.toggle("agents") }
        // any module's quick page (module.json "quick")
        function page(id: string): void { root.toggle(id) }
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
    component Head: QuickHead {}

    // small caps label between sections
    component Label2: QuickLabel {}

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
    component Row2: QuickRow {}


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


            // ------------------------------------------------ module pages
            // (Modules.qml quickPages), only loaded while open
            Repeater {
                model: Modules.quickPages
                Loader {
                    id: qp
                    required property var modelData
                    width: content.width
                    visible: active
                    active: root.mode === modelData.quick
                    onActiveChanged: if (active) setSource(modelData.url, { service: Modules.service(modelData.id), panel: root })
                    Component.onCompleted: if (active) setSource(modelData.url, { service: Modules.service(modelData.id), panel: root })
                }
            }

            // ------------------------------------------------ footer (core pages)
            Rectangle { visible: root.corePage; width: parent.width; height: 1; color: Theme.border }

            Text {
                visible: root.corePage
                text: "ALL SETTINGS  →"
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
                        root.mode = ""
                        Quickshell.execDetached(sound ? ["qs", "ipc", "call", "settings", "page", "Sound"]
                                                      : ["qs", "ipc", "call", "settings", "open"])
                    }
                }
            }
        }
    }


    Timer {
        id: refreshLater
        interval: 1500
        onTriggered: net.refresh()
    }
}
