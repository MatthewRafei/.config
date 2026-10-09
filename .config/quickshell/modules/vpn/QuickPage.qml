import QtQuick
import Quickshell
import qs
import qs.widgets

// Quick panel page (qs ipc call quick vpn): Tailscale up / down, this
// machine's address, exit node, devices on the tailnet (click = copy ip).
Column {
    id: page
    property var service
    property var panel

    property string pendingExit: ""
    property string copiedIp: ""
    Timer { id: copied; interval: 1500 }
    Binding { target: page.service; property: "fast"; value: true }
    Component.onCompleted: service.refresh()

    width: parent.width
    spacing: 4

    QuickHead {
        title: "// TAILSCALE"
        on: page.service.running
        onToggled: page.service.toggle()
    }

    Rectangle { width: parent.width; height: 1; color: Theme.border }

    Text {
        visible: page.service.error !== "" || (page.service.state !== "" && page.service.state !== "Running" && page.service.state !== "Stopped")
        width: parent.width
        wrapMode: Text.Wrap
        text: page.service.error !== "" ? page.service.error
            : page.service.state === "NeedsLogin" ? "Logged out. Run:  tailscale up  in a terminal to log in."
            : page.service.state.toLowerCase() + "…"
        color: page.service.error !== "" ? Theme.danger : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 9
        topPadding: 4
    }

    // this machine
    QuickRow {
        icon: "󰖂"
        label: page.service.selfName + "  (this device)"
        active: page.service.running
        busy: page.service.busy === "up" || page.service.busy === "down"
        tag: copied.running ? "COPIED" : ""
        detail: page.service.running ? page.service.selfIp : "STOPPED"
        onClicked: if (page.service.selfIp !== "") { page.service.copy(page.service.selfIp); copied.restart() }
    }

    // exit node: none + every peer that offers it
    Text {
        visible: page.service.running && page.service.peers.some(p => p.exitOption)
        text: "EXIT NODE"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
        topPadding: 8
    }
    QuickRow {
        visible: page.service.running && page.service.peers.some(p => p.exitOption)
        icon: "󰅖"
        label: "None (direct)"
        active: page.service.exitNode === ""
        busy: page.service.busy === "exit" && pendingExit === ""
        onClicked: { pendingExit = ""; page.service.useExit("") }
    }
    Repeater {
        model: page.service.running ? page.service.peers.filter(p => p.exitOption) : []
        QuickRow {
            required property var modelData
            icon: "󰖟"
            label: modelData.name
            active: modelData.exit
            busy: page.service.busy === "exit" && pendingExit === modelData.ip
            tag: modelData.exit ? "IN USE" : ""
            detail: modelData.online ? "" : "OFFLINE"
            onClicked: if (!modelData.exit) { pendingExit = modelData.ip; page.service.useExit(modelData.ip) }
        }
    }

    // devices
    Text {
        visible: page.service.running && page.service.peers.length > 0
        text: "DEVICES  " + page.service.onlineCount + " / " + page.service.peers.length + " ONLINE"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
        topPadding: 8
    }
    Flickable {
        visible: page.service.running
        width: parent.width
        height: Math.min(peerList.implicitHeight, 260)
        contentHeight: peerList.implicitHeight
        clip: true

        Column {
            id: peerList
            width: parent.width
            spacing: 2
            Repeater {
                model: page.service.peers
                QuickRow {
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
                    onClicked: { copiedIp = modelData.ip; page.service.copy(modelData.ip); copied.restart() }
                }
            }
        }
    }
}
