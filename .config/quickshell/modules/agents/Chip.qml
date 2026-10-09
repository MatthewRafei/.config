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
    visible: service.available
    icon: "󰚩"
    value: service.waiting.length > 0 ? String(service.waiting.length)
         : service.busy.length > 0 ? String(service.busy.length) : ""
    accent: service.waiting.length > 0 ? Theme.danger
          : service.busy.length > 0 ? Theme.accent
          : service.sessions.length > 0 ? Theme.text
          : Theme.textFaint
    // breathes while an agent works
    SequentialAnimation on opacity {
        running: service.busy.length > 0 && service.waiting.length === 0
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) agentsChip.opacity = 1
    }
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) service.next()
        else Quickshell.execDetached(["qs", "ipc", "call", "quick", "agents"])
    }
}
