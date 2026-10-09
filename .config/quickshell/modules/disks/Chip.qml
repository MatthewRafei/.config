import QtQuick
import Quickshell
import qs
import qs.widgets

// removable drives (Drives.qml): only while one is plugged in. red with
// the write rate while data is still going out (not safe to pull yet).
// click = Settings > Disks, right-click = eject all, middle = open the first mounted one
BarChip {
    property var service
    property var bar

    id: drivesChip
    shown: service.drives.present
    icon: "󰕓"
    value: service.drives.writing ? service.drives.fmtRate(service.drives.writeRate)
         : service.drives.drives.length > 1 ? String(service.drives.drives.length) : ""
    accent: service.drives.writing ? Theme.danger
          : service.drives.mounted.length > 0 ? Theme.accent
          : Theme.text
    pulse: service.drives.writing ? 1200 : 0
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) service.drives.ejectAll()
        else if (mouse.button === Qt.MiddleButton) { if (service.drives.mounted.length) service.drives.open(service.drives.mounted[0].mountpoint) }
        else Quickshell.execDetached(["qs", "ipc", "call", "settings", "page", "Disks"])
    }
}
