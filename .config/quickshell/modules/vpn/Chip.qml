import QtQuick
import Quickshell
import qs
import qs.widgets

// tailscale: dim when stopped, accent + node name through an exit node.
// click = VPN dropdown, right-click = connect / disconnect
BarChip {
    property var service
    property var bar

    shown: service.installed
    icon: "󰖂"
    value: service.running && service.exitNode !== ""
        ? (service.exitNode.length > 12 ? service.exitNode.slice(0, 11) + "…" : service.exitNode)
        : ""
    accent: !service.running ? Theme.textFaint
          : service.exitNode !== "" ? Theme.accent
          : Theme.text
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            service.toggle()
        else
            Quickshell.execDetached(["qs", "ipc", "call", "quick", "vpn"])
    }
}
