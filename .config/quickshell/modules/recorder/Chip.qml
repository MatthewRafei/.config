import QtQuick
import Quickshell
import qs
import qs.widgets

// screen recorder (wf-recorder): dim when idle, countdown, then red with
// the running time. click = recorder panel (or stop while recording),
// right-click = start / stop with the last settings
BarChip {
    property var service
    property var bar

    shown: service.available
    icon: service.state === "recording" ? "󰻃" : "󰑊"
    value: service.state === "countdown" ? String(service.countdown)
         : service.state === "recording" ? service.clock
         : service.state === "saving" ? "…" : ""
    accent: service.state === "recording" ? Theme.danger
          : service.state === "idle" ? Theme.textFaint
          : Theme.accent
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton || service.state === "recording" || service.state === "countdown")
            service.toggle()
        else
            Quickshell.execDetached(["qs", "ipc", "call", "quick", "rec"])
    }
}
