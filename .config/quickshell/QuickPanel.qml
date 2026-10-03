import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import QtQuick

// Quick toggles dropped down from the bar's NET / BT chips.
//
//   wi-fi      radio on/off, rescan, networks sorted by signal; click to
//              connect (known networks reconnect, new secured ones ask for
//              the password inline), click the current one to disconnect
//   bluetooth  power on/off, paired devices with battery; click to
//              connect/disconnect (pair new devices in Settings)
//
//   qs ipc call quick net | bt | close
PanelWindow {
    id: root

    property string mode: ""          // "", "net" or "bt"
    readonly property bool open: mode !== ""

    function toggle(m) {
        mode = mode === m ? "" : m
        if (mode === "net") net.refresh()
    }

    IpcHandler {
        target: "quick"
        function net(): void { root.toggle("net") }
        function bt(): void { root.toggle("bt") }
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
                visible: head.showRescan && head.on
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
                width: 190
                elide: Text.ElideRight
                text: row.label
                color: row.active ? Theme.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: row.active
            }
        }

        Text {
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

            // ------------------------------------------------ footer
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Text {
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
                        root.mode = ""
                        Quickshell.execDetached(["qs", "ipc", "call", "settings", "open"])
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
