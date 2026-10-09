import Quickshell
import Quickshell.Wayland
import QtQuick
import qs

// Popup stack, top-right under the bar. Newest on top; at most 5 shown.
// Hidden while the notification center is open (it shows them all anyway).
PanelWindow {
    id: root

    anchors { top: true; right: true }
    margins { top: 10; right: 12 }

    implicitWidth: 380
    implicitHeight: Math.max(1, stack.implicitHeight)
    color: "transparent"

    // respect the bar's exclusive zone, reserve nothing ourselves
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: Notifs.popups.count > 0 && !Notifs.centerOpen

    // only the cards take input; the rest of the strip is click-through
    mask: Region { item: stack }

    Column {
        id: stack
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.popups

            Item {
                id: slot
                required property var notif
                required property int index
                width: stack.width
                height: card.height
                visible: index < 5

                NotificationCard {
                    id: card
                    width: parent.width
                    notif: slot.notif
                    popup: true
                }
            }
        }
    }
}
