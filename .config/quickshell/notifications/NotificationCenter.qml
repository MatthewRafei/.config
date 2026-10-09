import Quickshell
import Quickshell.Wayland
import QtQuick
import qs

// Notification center: slides in from the right edge under the bar.
// Opened by the bar's bell or `qs ipc call notifs toggle`.
// Esc or clicking outside closes it.
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-notification-center"
    WlrLayershell.keyboardFocus: Notifs.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    visible: Notifs.centerOpen || panel.slide < 1

    // click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: Notifs.centerOpen = false
    }

    Rectangle {
        id: panel

        property real slide: Notifs.centerOpen ? 0 : 1
        Behavior on slide { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutCubic } }

        width: 400
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        x: parent.width - width - 12 + slide * (width + 24)
        opacity: 1 - slide

        color: Theme.alpha(Theme.bgPanel, 0.96)
        border.color: Theme.border
        radius: Theme.radius

        focus: Notifs.centerOpen
        Keys.onEscapePressed: Notifs.centerOpen = false

        // swallow clicks so they don't close the panel
        MouseArea { anchors.fill: parent }

        // ---- header ----
        Item {
            id: header
            x: 18
            y: 16
            width: parent.width - 36
            height: 24

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    text: "// NOTIFICATIONS"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
                Text {
                    text: Notifs.count
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: [
                        { label: Notifs.dnd ? "DND ON" : "DND", active: Notifs.dnd, act: () => Notifs.dnd = !Notifs.dnd },
                        { label: "CLEAR", active: false, act: () => Notifs.clearAll() }
                    ]
                    Rectangle {
                        required property var modelData
                        width: btnText.implicitWidth + 18
                        height: 22
                        radius: Theme.radius
                        color: modelData.active ? Theme.alpha(Theme.accent, 0.15)
                             : btnMouse.containsMouse ? Theme.bgCard : "transparent"
                        border.color: modelData.active || btnMouse.containsMouse ? Theme.accent : Theme.border
                        Text {
                            id: btnText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: modelData.active || btnMouse.containsMouse ? Theme.accent : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }
                        MouseArea {
                            id: btnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.act()
                        }
                    }
                }
            }
        }

        Rectangle {
            id: rule
            anchors.top: header.bottom
            anchors.topMargin: 12
            x: 18
            width: parent.width - 36
            height: 1
            color: Theme.border
        }

        // ---- list ----
        ListView {
            id: list
            anchors.top: rule.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            x: 12
            width: parent.width - 24
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds

            // newest first
            model: Notifs.list.slice().reverse()

            delegate: NotificationCard {
                required property var modelData
                width: list.width
                notif: modelData
            }

            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed } }
        }

        // empty state
        Column {
            visible: Notifs.count === 0
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ALL CLEAR"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.letterSpacing: 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifs.dnd ? "do not disturb is on" : "nothing new"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 1
            }
        }
    }
}
