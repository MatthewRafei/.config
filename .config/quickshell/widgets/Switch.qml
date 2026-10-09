import QtQuick
import qs

// A labelled on/off switch (full width): label, optional hint underneath.
//   on       the state (owned by the caller)
//   toggled  clicked; the caller flips its own state
Item {
    id: sw
    property string label
    property string hint
    property bool on: false
    signal toggled()

    width: parent ? parent.width : 0
    height: hint ? 40 : 28

    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 60
        spacing: 3
        Text {
            text: sw.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
        Text {
            visible: sw.hint !== ""
            width: parent.width
            elide: Text.ElideRight
            text: sw.hint
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }
    }
    Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        height: 22
        radius: 11
        color: sw.on ? Theme.accent : Theme.trackBg
        border.color: Theme.border
        Rectangle {
            width: 16; height: 16; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: sw.on ? parent.width - width - 3 : 3
            color: Theme.text
            Behavior on x { NumberAnimation { duration: Theme.animFast } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }
}
