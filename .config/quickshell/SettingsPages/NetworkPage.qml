import QtQuick
import Quickshell.Io
import "../"

Item {
    id: page

    property bool wifiEnabled: true
    property var networks: []
    property bool scanning: false
    property string pendingSsid: ""

    // wired vs wireless view comes from Net.qml (wired when a cable is in
    // use, or when Wi-Fi can't be managed here)
    readonly property bool wired: Net.mode === "wired"
    property var ifaces: []     // wired interfaces, see pWired
    property string gateway: ""
    property string gatewayDev: ""
    property var dns: []

    // ------------------------------------------------------------------
    // VPNs: Tailscale (Vpn.qml) and NetworkManager VPN / WireGuard profiles
    // ------------------------------------------------------------------

    property var nmVpns: []     // [{ name, type, active }]
    property string vpnBusy: "" // name of the profile being switched

    function refreshVpns() {
        if (!pVpns.running) pVpns.running = true
        Vpn.refresh()
    }

    function setNmVpn(name, on) {
        page.vpnBusy = name
        pVpnSwitch.command = ["nmcli", "connection", on ? "up" : "down", "id", name]
        pVpnSwitch.running = true
    }

    Process {
        id: pVpns
        command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    // nmcli -t escapes ':' inside fields as '\:'
                    const f = line.replace(/\\:/g, "\u0001").split(":").map(x => x.replace(/\u0001/g, ":"))
                    if (f.length < 3) continue
                    if (f[1] === "vpn" || f[1] === "wireguard")
                        out.push({ name: f[0], type: f[1] === "vpn" ? "VPN" : "WIREGUARD", active: f[2] === "yes" })
                }
                page.nmVpns = out
            }
        }
    }

    Process {
        id: pVpnSwitch
        onExited: { page.vpnBusy = ""; page.refreshVpns() }
    }

    Timer {
        interval: 3000
        repeat: true
        running: page.visible
        triggeredOnStart: true
        onTriggered: page.refreshVpns()
    }

    // on/off pill, same look as the Wi-Fi switch
    component Toggle: Rectangle {
        id: tog
        property bool on: false
        property bool busy: false
        signal toggled()

        width: 44
        height: 22
        radius: 11
        opacity: busy ? 0.5 : 1
        color: on ? Theme.accent : Theme.trackBg
        border.color: Theme.border
        border.width: 1

        Rectangle {
            width: 16
            height: 16
            radius: 8
            color: Theme.text
            anchors.verticalCenter: parent.verticalCenter
            x: tog.on ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: Theme.animFast } }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !tog.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: tog.toggled()
        }
    }

    // ------------------------------------------------------------------
    // Global content margins
    // ------------------------------------------------------------------

    property int contentMargin: 0
    property int contentRightMargin: 48
    property int contentTopMargin: 0
    property int contentBottomMargin: 0

    // ------------------------------------------------------------------
    // Wi-Fi radio
    // ------------------------------------------------------------------

    Process {
        id: pRadioGet
        command: ["nmcli", "radio", "wifi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.wifiEnabled = text.trim() === "enabled"
            }
        }
    }

    Process {
        id: pRadioSet

        stdout: StdioCollector {
            onStreamFinished: {
                pRadioGet.running = true

                if (page.wifiEnabled)
                    page.scan()
                else
                    page.networks = []
            }
        }
    }

    function setWifiEnabled(on) {
        pRadioSet.command = [
            "nmcli",
            "radio",
            "wifi",
            on ? "on" : "off"
        ]
        pRadioSet.running = true
    }

    // ------------------------------------------------------------------
    // Scan
    // ------------------------------------------------------------------

    Process {
        id: pRescan
        command: ["nmcli", "device", "wifi", "rescan"]

        stdout: StdioCollector {
            onStreamFinished: {
                rescanSettle.restart()
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                rescanSettle.restart()
            }
        }
    }

    Timer {
        id: rescanSettle
        interval: 1200

        onTriggered: {
            page.scanning = false
            pList.running = true
        }
    }

    function scan() {
        if (!page.wifiEnabled)
            return

        page.scanning = true
        pRescan.running = true
    }

    // ------------------------------------------------------------------
    // Network list
    // ------------------------------------------------------------------

    Process {
        id: pList

        command: [
            "nmcli",
            "-t",
            "-f", "IN-USE,SSID,SIGNAL,SECURITY",
            "device",
            "wifi",
            "list"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = text.trim().split("\n")

                for (var i = 0; i < lines.length; ++i) {
                    var line = lines[i].trim()

                    if (!line)
                        continue

                    /*
                     * nmcli terse output uses ':' as the separator.
                     * A literal ':' inside an SSID is escaped as '\:'.
                     *
                     * Find the first three unescaped ':' characters.
                     */
                    var fields = []
                    var current = ""
                    var escaped = false

                    for (var j = 0; j < line.length; ++j) {
                        var ch = line[j]

                        if (escaped) {
                            current += ch
                            escaped = false
                        } else if (ch === "\\") {
                            escaped = true
                        } else if (ch === ":" && fields.length < 3) {
                            fields.push(current)
                            current = ""
                        } else {
                            current += ch
                        }
                    }

                    fields.push(current)

                    if (fields.length < 4)
                        continue

                    var inUse = fields[0]
                    var ssid = fields[1]
                    var signal = parseInt(fields[2])
                    var security = fields[3]

                    if (!ssid)
                        continue

                    if (isNaN(signal))
                        signal = 0

                    out.push({
                        ssid: ssid,
                        signal: signal,
                        secured: security !== "" && security !== "--",
                        connected: inUse === "*"
                    })
                }

                page.networks = out
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                // Keep the UI alive even if NetworkManager emits stderr.
            }
        }
    }

    // ------------------------------------------------------------------
    // Connect / disconnect
    // ------------------------------------------------------------------

    Process {
        id: pConnect

        stdout: StdioCollector {
            onStreamFinished: {
                page.pendingSsid = ""
                pList.running = true
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                page.pendingSsid = ""
                pList.running = true
            }
        }
    }

    function connectOpen(ssid) {
        pConnect.command = [
            "nmcli",
            "device",
            "wifi",
            "connect",
            ssid
        ]
        pConnect.running = true
    }

    function connectSecured(ssid, password) {
        pConnect.command = [
            "nmcli",
            "device",
            "wifi",
            "connect",
            ssid,
            "password",
            password
        ]
        pConnect.running = true
    }

    function disconnect(ssid) {
        pConnect.command = [
            "nmcli",
            "connection",
            "down",
            "id",
            ssid
        ]
        pConnect.running = true
    }

    // ------------------------------------------------------------------
    // Wired details (no NetworkManager needed: /sys, ip, resolv.conf)
    // ------------------------------------------------------------------

    Process {
        id: pWired

        command: [
            "sh",
            "-c",
            "for d in /sys/class/net/*; do " +
            "  [ -e $d/device ] && [ ! -d $d/wireless ] || continue; " +
            "  echo if ${d##*/} $(cat $d/operstate) $(cat $d/speed 2>/dev/null || echo -1) $(cat $d/address); " +
            "done; " +
            // iproute2 JSON when available, otherwise ask NetworkManager
            "if ip -j addr >/dev/null 2>&1; then " +
            "  echo addr $(ip -j addr); " +
            "  echo route $(ip -j route show default 2>/dev/null); " +
            "  awk '/^nameserver/ { print \"dns\", $2 }' /etc/resolv.conf 2>/dev/null; " +
            "else " +
            "  for d in /sys/class/net/*; do " +
            "    [ -e $d/device ] && [ ! -d $d/wireless ] || continue; " +
            "    nmcli -t -f IP4.ADDRESS,IP6.ADDRESS,IP4.GATEWAY,IP4.DNS dev show ${d##*/} 2>/dev/null | sed \"s/^/nm ${d##*/} /\"; " +
            "  done; " +
            "fi"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                var ifs = [], addrs = [], routes = [], dns = [], nmInfo = {}
                var lines = text.split("\n")

                for (var i = 0; i < lines.length; ++i) {
                    var t = lines[i].trim()
                    var sp = t.indexOf(" ")
                    var key = sp < 0 ? t : t.slice(0, sp)
                    var rest = sp < 0 ? "" : t.slice(sp + 1)

                    if (key === "if") {
                        var f = rest.split(/\s+/)
                        ifs.push({
                            name: f[0],
                            up: f[1] === "up",
                            speed: +f[2],
                            mac: f[3] || "",
                            ipv4: "",
                            ipv6: ""
                        })
                    } else if (key === "addr" && rest) {
                        try { addrs = JSON.parse(rest) } catch (e) {}
                    } else if (key === "route" && rest) {
                        try { routes = JSON.parse(rest) } catch (e) {}
                    } else if (key === "dns" && rest) {
                        dns.push(rest)
                    } else if (key === "nm" && rest) {
                        // "<iface> IP4.ADDRESS[1]:10.0.0.2/24" (NetworkManager fallback)
                        var nsp = rest.indexOf(" ")
                        var nif = rest.slice(0, nsp)
                        var kv = rest.slice(nsp + 1)
                        var colon = kv.indexOf(":")
                        var field = kv.slice(0, colon).replace(/\[.*\]$/, "")
                        var val = kv.slice(colon + 1)
                        if (!val || val === "--")
                            continue
                        nmInfo[nif] = nmInfo[nif] || {}
                        if (field === "IP4.ADDRESS" && !nmInfo[nif].ipv4) nmInfo[nif].ipv4 = val
                        // prefer a global IPv6 address over the link-local one
                        if (field === "IP6.ADDRESS" && (!nmInfo[nif].ipv6 || nmInfo[nif].ipv6.startsWith("fe80")))
                            nmInfo[nif].ipv6 = val
                        if (field === "IP4.GATEWAY") nmInfo[nif].gateway = val
                        if (field === "IP4.DNS") (nmInfo[nif].dns = nmInfo[nif].dns || []).push(val)
                    }
                }

                for (var n in nmInfo) {
                    var w = ifs.find(x => x.name === n)
                    if (w) {
                        w.ipv4 = nmInfo[n].ipv4 || ""
                        w.ipv6 = nmInfo[n].ipv6 || ""
                    }
                    // NetworkManager only reports a gateway on the default route's device
                    if (nmInfo[n].gateway && w && w.up && routes.length === 0) {
                        routes = [{ gateway: nmInfo[n].gateway, dev: n }]
                        dns = nmInfo[n].dns || []
                    }
                }

                for (var j = 0; j < ifs.length; ++j) {
                    var a = addrs.find(x => x.ifname === ifs[j].name)
                    if (!a || !a.addr_info)
                        continue

                    var v4 = a.addr_info.find(x => x.family === "inet")
                    // prefer a global IPv6 address over the link-local one
                    var v6 = a.addr_info.find(x => x.family === "inet6" && x.scope === "global")
                          || a.addr_info.find(x => x.family === "inet6")

                    if (v4) ifs[j].ipv4 = v4.local + "/" + v4.prefixlen
                    if (v6) ifs[j].ipv6 = v6.local + "/" + v6.prefixlen
                }

                // connected interfaces first
                ifs.sort((x, y) => (y.up ? 1 : 0) - (x.up ? 1 : 0))

                page.ifaces = ifs
                page.gateway = routes.length > 0 ? (routes[0].gateway || "") : ""
                page.gatewayDev = routes.length > 0 ? (routes[0].dev || "") : ""
                page.dns = dns
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: page.wired
        triggeredOnStart: true
        onTriggered: if (!pWired.running) pWired.running = true
    }

    function speedText(mbps) {
        if (!(mbps > 0))
            return "unknown"
        return mbps >= 1000 ? (mbps / 1000) + " Gb/s" : mbps + " Mb/s"
    }

    function refreshWireless() {
        pRadioGet.running = true
        pList.running = true
    }

    onWiredChanged: if (!wired) refreshWireless()

    Component.onCompleted: {
        Net.refresh()
        if (!page.wired)
            refreshWireless()
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------

    Column {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        anchors.leftMargin: page.contentMargin
        anchors.rightMargin: page.contentRightMargin
        anchors.topMargin: page.contentTopMargin
        anchors.bottomMargin: page.contentBottomMargin

        spacing: 12

        // ------------------------------------------------------------------
        // Header
        // ------------------------------------------------------------------

        Row {
            id: header

            width: parent.width
            height: 28
            spacing: 16

            Text {
                text: "NETWORK"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 3

                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: modeLabel
                text: page.wired ? "WIRED" : "WI-FI"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2

                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: Math.max(
                    0,
                    parent.width
                    - 18
                    - 100
                    - 44
                    - 16
                    - modeLabel.width
                    - 16
                )

                height: 1
            }

            Text {
                visible: !page.wired
                text: page.scanning ? "SCANNING..." : "󰑐"

                color: page.scanning
                       ? Theme.textDim
                       : Theme.accent

                font.family: Theme.fontFamily
                font.pixelSize: 22

                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent

                    enabled: !page.scanning &&
                             page.wifiEnabled

                    onClicked: page.scan()
                }
            }

            Rectangle {
                visible: !page.wired
                width: 44
                height: 22
                radius: 11

                anchors.verticalCenter: parent.verticalCenter

                color: page.wifiEnabled
                       ? Theme.accent
                       : Theme.trackBg

                border.color: Theme.border
                border.width: 1

                Rectangle {
                    width: 16
                    height: 16
                    radius: 8

                    color: Theme.text

                    anchors.verticalCenter: parent.verticalCenter

                    x: page.wifiEnabled
                       ? parent.width - width - 3
                       : 3

                    Behavior on x {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent

                    onClicked: {
                        page.setWifiEnabled(
                            !page.wifiEnabled
                        )
                    }
                }
            }
        }

        // ------------------------------------------------------------------
        // Divider
        // ------------------------------------------------------------------

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.border
        }

        // ------------------------------------------------------------------
        // Content
        // ------------------------------------------------------------------

        Item {
            width: parent.width
            height: parent.height
                    - header.height
                    - 12
                    - 1

            Flickable {
                anchors.fill: parent
                clip: true

                contentWidth: width
                contentHeight: list.height

                Column {
                    id: list

                    width: parent.width
                    spacing: 6

                    // ------------------------------------------------------
                    // VPN
                    // ------------------------------------------------------

                    Text {
                        visible: Vpn.installed || page.nmVpns.length > 0
                        text: "// VPN"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.letterSpacing: 3
                    }

                    // Tailscale
                    Rectangle {
                        id: tsCard
                        visible: Vpn.installed

                        readonly property var rows: [
                            { k: "STATUS", v: Vpn.state === "Running" ? "Connected"
                                            : Vpn.state === "NeedsLogin" ? "Logged out (run: tailscale up)"
                                            : Vpn.state === "Stopped" ? "Disconnected"
                                            : Vpn.state.toLowerCase() },
                            { k: "ADDRESS", v: Vpn.selfIp || "none" },
                            { k: "DEVICE", v: Vpn.selfName || "none" },
                            { k: "TAILNET", v: Vpn.tailnet || "none" },
                            { k: "DEVICES", v: Vpn.onlineCount + " of " + Vpn.peers.length + " online" }
                        ]

                        width: list.width
                        height: tsCol.height + 24
                        radius: Theme.radius
                        color: Vpn.running ? Theme.alpha(Theme.accent, 0.10) : "#00000000"
                        border.width: 1
                        border.color: Vpn.running ? Theme.accent : Theme.border

                        Column {
                            id: tsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8

                            // name + switch
                            Item {
                                width: parent.width
                                height: 22

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 9
                                    Text {
                                        text: "󰖂"
                                        color: Vpn.running ? Theme.accent : Theme.textDim
                                        font.family: Theme.iconFont
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        text: "Tailscale"
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 12
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Vpn.busy !== "" ? "···"
                                            : Vpn.running ? (Vpn.exitNode !== "" ? "VIA " + Vpn.exitNode.toUpperCase() : "CONNECTED")
                                            : "OFF"
                                        color: Vpn.running ? Theme.ok : Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                    }
                                    Toggle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        on: Vpn.running
                                        busy: Vpn.busy === "up" || Vpn.busy === "down"
                                        onToggled: Vpn.toggle()
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: Theme.border }

                            Text {
                                visible: Vpn.error !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: Vpn.error
                                color: Theme.danger
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }

                            Repeater {
                                model: tsCard.rows
                                delegate: Row {
                                    required property var modelData
                                    width: tsCol.width
                                    spacing: 12
                                    Text {
                                        width: 80
                                        text: modelData.k
                                        color: Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        width: parent.width - 92
                                        text: modelData.v
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // exit node chips: none + peers that offer it
                            Row {
                                visible: Vpn.running
                                width: tsCol.width
                                spacing: 12
                                Text {
                                    width: 80
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "EXIT NODE"
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.letterSpacing: 1
                                }
                                Flow {
                                    width: parent.width - 92
                                    spacing: 6
                                    Repeater {
                                        model: [{ name: "None", ip: "", exit: Vpn.exitNode === "", online: true }]
                                               .concat(Vpn.peers.filter(p => p.exitOption))
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: exitTxt.implicitWidth + 18
                                            height: 22
                                            radius: Theme.radius
                                            opacity: modelData.online ? 1 : 0.45
                                            color: modelData.exit ? Theme.alpha(Theme.accent, 0.15)
                                                 : exitMouse.containsMouse ? Theme.bgCard : "transparent"
                                            border.color: modelData.exit ? Theme.accent : Theme.border
                                            Text {
                                                id: exitTxt
                                                anchors.centerIn: parent
                                                text: modelData.name
                                                color: modelData.exit ? Theme.accent : Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                            }
                                            MouseArea {
                                                id: exitMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: !modelData.exit && Vpn.busy === ""
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Vpn.useExit(modelData.ip)
                                            }
                                        }
                                    }
                                    Text {
                                        visible: !Vpn.peers.some(p => p.exitOption)
                                        height: 22
                                        verticalAlignment: Text.AlignVCenter
                                        text: "no device on the tailnet offers one"
                                        color: Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }

                    // NetworkManager VPN / WireGuard profiles
                    Repeater {
                        model: page.nmVpns
                        delegate: Rectangle {
                            required property var modelData
                            width: list.width
                            height: 46
                            radius: Theme.radius
                            color: modelData.active ? Theme.alpha(Theme.accent, 0.10) : "#00000000"
                            border.width: 1
                            border.color: modelData.active ? Theme.accent : Theme.border

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 9
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰌆"
                                    color: modelData.active ? Theme.accent : Theme.textDim
                                    font.family: Theme.iconFont
                                    font.pixelSize: 14
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.type
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.vpnBusy === modelData.name ? "···" : modelData.active ? "CONNECTED" : ""
                                    color: Theme.ok
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.letterSpacing: 1
                                }
                                Toggle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    on: modelData.active
                                    busy: page.vpnBusy === modelData.name
                                    onToggled: page.setNmVpn(modelData.name, !modelData.active)
                                }
                            }
                        }
                    }

                    Text {
                        visible: !Vpn.installed && page.nmVpns.length === 0
                        width: parent.width
                        text: "No VPNs. Install Tailscale, or add a WireGuard / OpenVPN profile with NetworkManager (nmcli connection import ...)."
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Item { width: 1; height: 14 }

                    Text {
                        text: page.wired ? "// WIRED" : "// WI-FI"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.letterSpacing: 3
                    }

                    // ------------------------------------------------------
                    // Wired
                    // ------------------------------------------------------

                    Text {
                        visible: page.wired && page.ifaces.length === 0

                        width: parent.width

                        text: "No wired network adapter found"

                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        horizontalAlignment:
                            Text.AlignHCenter
                    }

                    Repeater {
                        model: page.wired ? page.ifaces : []

                        delegate: Rectangle {
                            id: ifCard

                            required property var modelData

                            readonly property bool isDefault:
                                modelData.name === page.gatewayDev

                            readonly property var rows: modelData.up ? [
                                { k: "IPV4", v: modelData.ipv4 || "none" },
                                { k: "IPV6", v: modelData.ipv6 || "none" },
                                { k: "GATEWAY", v: isDefault && page.gateway ? page.gateway : "none" },
                                { k: "DNS", v: isDefault && page.dns.length ? page.dns.join(", ") : "none" },
                                { k: "SPEED", v: page.speedText(modelData.speed) },
                                { k: "MAC", v: modelData.mac }
                            ] : [
                                { k: "MAC", v: modelData.mac }
                            ]

                            width: list.width
                            height: ifCol.height + 24
                            radius: Theme.radius

                            color: modelData.up
                                   ? Theme.alpha(Theme.accent, 0.10)
                                   : "#00000000"

                            border.width: 1
                            border.color: modelData.up
                                          ? Theme.accent
                                          : Theme.border

                            Column {
                                id: ifCol

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14

                                spacing: 8

                                // name + state
                                Item {
                                    width: parent.width
                                    height: 20

                                    Row {
                                        anchors.verticalCenter:
                                            parent.verticalCenter

                                        spacing: 9

                                        Text {
                                            text: "󰈀"

                                            color: ifCard.modelData.up
                                                   ? Theme.accent
                                                   : Theme.textDim

                                            font.family: Theme.iconFont
                                            font.pixelSize: 14
                                        }

                                        Text {
                                            text: ifCard.modelData.name

                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter:
                                            parent.verticalCenter

                                        text: ifCard.modelData.up
                                              ? "CONNECTED"
                                              : "CABLE UNPLUGGED"

                                        color: ifCard.modelData.up
                                               ? Theme.ok
                                               : Theme.textFaint

                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    color: Theme.border
                                }

                                // details
                                Repeater {
                                    model: ifCard.rows

                                    delegate: Row {
                                        required property var modelData

                                        width: ifCol.width
                                        spacing: 12

                                        Text {
                                            width: 80

                                            text: modelData.k

                                            color: Theme.textFaint
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.letterSpacing: 1
                                        }

                                        Text {
                                            width: parent.width - 92

                                            text: modelData.v

                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11

                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Wi-Fi hardware that can't be used without NetworkManager
                    Text {
                        visible: page.wired &&
                                 Net.wifiIface !== "" &&
                                 !Net.nmRunning

                        width: parent.width
                        topPadding: 6

                        text: "Wi-Fi adapter " + Net.wifiIface +
                              " found. Start NetworkManager to manage Wi-Fi here."

                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap

                        horizontalAlignment:
                            Text.AlignHCenter
                    }

                    // ------------------------------------------------------
                    // Wi-Fi disabled
                    // ------------------------------------------------------

                    Text {
                        visible: !page.wired && !page.wifiEnabled

                        width: parent.width

                        text: "Wi-Fi is disabled"

                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        horizontalAlignment:
                            Text.AlignHCenter
                    }

                    // ------------------------------------------------------
                    // Scanning
                    // ------------------------------------------------------

                    Text {
                        visible: !page.wired &&
                                 page.wifiEnabled &&
                                 page.scanning &&
                                 page.networks.length === 0

                        width: parent.width

                        text: "Scanning for networks..."

                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        horizontalAlignment:
                            Text.AlignHCenter
                    }

                    // ------------------------------------------------------
                    // Nothing found
                    // ------------------------------------------------------

                    Text {
                        visible: !page.wired &&
                                 page.wifiEnabled &&
                                 !page.scanning &&
                                 page.networks.length === 0

                        width: parent.width

                        text: "No Wi-Fi networks found"

                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 12

                        horizontalAlignment:
                            Text.AlignHCenter
                    }

                    // ------------------------------------------------------
                    // Networks
                    // ------------------------------------------------------

                    Repeater {
                        model: page.wired ? [] : page.networks

                        delegate: Column {
                            required property var modelData

                            width: list.width
                            spacing: 6

                            // --------------------------------------------------
                            // Network card
                            // --------------------------------------------------

                            Rectangle {
                                width: parent.width
                                height: 46
                                radius: Theme.radius

                                color: modelData.connected
                                       ? Theme.alpha(
                                             Theme.accent,
                                             0.10
                                         )
                                       : "#00000000"

                                border.width: 1

                                border.color:
                                    modelData.connected
                                    ? Theme.accent
                                    : Theme.border

                                // ----------------------------------------------
                                // Left side
                                // ----------------------------------------------

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 14

                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    spacing: 9

                                    Text {
                                        text: modelData.signal > 66
                                              ? ""
                                              : modelData.signal > 33
                                                ? ""
                                                : ""

                                        color: modelData.connected
                                               ? Theme.accent
                                               : Theme.textDim

                                        font.family: Theme.iconFont
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        visible:
                                            modelData.secured

                                        text: ""

                                        color: Theme.textFaint

                                        font.family:
                                            Theme.iconFont

                                        font.pixelSize: 10
                                    }

                                    Text {
                                        text: modelData.ssid

                                        color: Theme.text

                                        font.family:
                                            Theme.fontFamily

                                        font.pixelSize: 12

                                        elide:
                                            Text.ElideRight

                                        width: Math.min(
                                            implicitWidth,
                                            list.width - 170
                                        )
                                    }
                                }

                                // ----------------------------------------------
                                // Connect / disconnect
                                // ----------------------------------------------

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14

                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    text: modelData.connected
                                          ? "DISCONNECT"
                                          : "CONNECT"

                                    color: modelData.connected
                                           ? Theme.danger
                                           : Theme.accent

                                    font.family:
                                        Theme.fontFamily

                                    font.pixelSize: 10

                                    MouseArea {
                                        anchors.fill: parent

                                        onClicked: {
                                            if (
                                                modelData.connected
                                            ) {
                                                page.disconnect(
                                                    modelData.ssid
                                                )
                                            } else if (
                                                modelData.secured
                                            ) {
                                                page.pendingSsid =
                                                    page.pendingSsid ===
                                                    modelData.ssid
                                                    ? ""
                                                    : modelData.ssid
                                            } else {
                                                page.connectOpen(
                                                    modelData.ssid
                                                )
                                            }
                                        }
                                    }
                                }
                            }

                            // --------------------------------------------------
                            // Password row
                            // --------------------------------------------------

                            Row {
                                visible:
                                    page.pendingSsid ===
                                    modelData.ssid

                                width: parent.width
                                height: 32
                                spacing: 10

                                Rectangle {
                                    width: 220
                                    height: 32

                                    color: Theme.bgCard

                                    border.color:
                                        Theme.accent

                                    border.width: 1

                                    radius: Theme.radius

                                    TextInput {
                                        id: pwField

                                        anchors.fill: parent
                                        anchors.margins: 8

                                        color: Theme.text

                                        font.family:
                                            Theme.fontFamily

                                        font.pixelSize: 12

                                        echoMode:
                                            TextInput.Password

                                        focus:
                                            page.pendingSsid ===
                                            modelData.ssid

                                        Keys.onReturnPressed: {
                                            page.connectSecured(
                                                modelData.ssid,
                                                text
                                            )
                                        }
                                    }
                                }

                                Text {
                                    text: "CONNECT"

                                    color: Theme.accent2

                                    font.family:
                                        Theme.fontFamily

                                    font.pixelSize: 11

                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    MouseArea {
                                        anchors.fill: parent

                                        onClicked: {
                                            page.connectSecured(
                                                modelData.ssid,
                                                pwField.text
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
