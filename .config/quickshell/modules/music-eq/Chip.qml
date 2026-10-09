import QtQuick
import Quickshell
import qs
import qs.widgets

// music EQ (service.qml): lit while on. click = EQ widget (bottom left),
// right-click = EQ on / off
BarChip {
    property var service
    property var bar

    visible: service.available
    icon: "󰺢"
    value: service.eqOn && service.preset !== "Flat" ? (service.preset || "custom").toUpperCase() : ""
    accent: !service.eqOn ? Theme.textFaint : service.eeRunning ? Theme.accent : Theme.danger
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) service.setOn(!service.eqOn)
        else service.panelOpen = !service.panelOpen
    }
}
