import QtQuick
import qs

// A bar chip: "LABEL value" or an icon + value, with an optional 8-segment
// gauge underneath. Used by the bar and by module chips (MODULES.md).
//
//   clicked(mouse)   left / right / middle (check mouse.button)
//   wheel(wheel)
Item {
    id: chip
    property string label
    property string icon            // shown instead of `label` when set
    property string value
    property real gauge: -1
    property color accent: Theme.text
    signal clicked(var mouse)
    signal wheel(var wheel)

    implicitWidth: chipRow.implicitWidth + 14
    height: 36

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        radius: Theme.radius
        color: chipMouse.containsMouse ? Theme.bgCard : "transparent"
        border.color: chipMouse.containsMouse ? Theme.border : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    Row {
        id: chipRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: chip.gauge >= 0 ? -2 : 0
        spacing: 6
        Text {
            visible: chip.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.icon
            color: chip.accent === Theme.text ? Theme.textDim : chip.accent
            font.family: Theme.iconFont
            font.pixelSize: 14
        }
        Text {
            visible: chip.label !== "" && chip.icon === ""
            anchors.baseline: valueText.baseline
            text: chip.label
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 2
        }
        Text {
            id: valueText
            visible: chip.value !== ""
            text: chip.value
            color: chip.accent
            font.family: Theme.fontFamily
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: Theme.animMed } }
        }
    }

    // 8-segment mini gauge
    Row {
        visible: chip.gauge >= 0
        anchors.horizontalCenter: chipRow.horizontalCenter
        anchors.top: chipRow.bottom
        anchors.topMargin: 2
        spacing: 1
        Repeater {
            model: 8
            Rectangle {
                required property int index
                width: (chipRow.width - 7) / 8
                height: 2
                color: index < Math.round(chip.gauge * 8)
                    ? (chip.accent === Theme.text ? Theme.accent : chip.accent)
                    : Theme.trackBg
            }
        }
    }

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => chip.clicked(mouse)
        onWheel: wheel => chip.wheel(wheel)
    }
}
