import QtQuick
import Quickshell
import qs
import qs.widgets

// claude code (Service.qml): how many are working, red with how many
// need you, dim when none run. click = sessions dropdown,
// right-click = open the one that needs you
BarChip {
    property var service
    property var bar

    id: agentsChip
    shown: service.available
    icon: "󰚩"
    value: service.waiting.length > 0 ? String(service.waiting.length)
         : service.busy.length > 0 ? String(service.busy.length) : ""
    accent: service.waiting.length > 0 ? Theme.danger
          : service.busy.length > 0 ? Theme.accent
          : service.sessions.length > 0 ? Theme.text
          : Theme.textFaint
    // breathes while an agent works
    pulse: service.busy.length > 0 && service.waiting.length === 0 ? 1800 : 0
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) service.next()
        else Quickshell.execDetached(["qs", "ipc", "call", "quick", "agents"])
    }
}
