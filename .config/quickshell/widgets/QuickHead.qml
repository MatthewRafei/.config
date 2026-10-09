import QtQuick
import qs

// Quick panel section header: "// TITLE", optional rescan button and ON/OFF toggle.
Item {
    id: head
    property string title
    property bool on: true
    property bool showRescan: false
    property bool showToggle: true
    signal toggled()
    signal rescan()

    width: parent.width
    height: 26

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: head.title
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 3
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Rectangle {
            visible: head.showRescan && (head.on || !head.showToggle)
            width: 26; height: 22
            radius: Theme.radius
            color: rescanMouse.containsMouse ? Theme.bgCard : "transparent"
            border.color: rescanMouse.containsMouse ? Theme.accent : Theme.border
            Text {
                anchors.centerIn: parent
                text: "󰑐"
                color: rescanMouse.containsMouse ? Theme.accent : Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: 13
            }
            MouseArea {
                id: rescanMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: head.rescan()
            }
        }

        Rectangle {
            visible: head.showToggle
            width: 44; height: 22
            radius: Theme.radius
            color: head.on ? Theme.alpha(Theme.accent, 0.15) : "transparent"
            border.color: head.on ? Theme.accent : Theme.border
            Text {
                anchors.centerIn: parent
                text: head.on ? "ON" : "OFF"
                color: head.on ? Theme.accent : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: head.toggled()
            }
        }
    }
}
