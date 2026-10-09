import QtQuick
import qs

// A bar chip: "LABEL value" or an icon + value, with an optional 8-segment
// gauge underneath. Used by the bar and by module chips (MODULES.md).
//
//   clicked(mouse)   left / right / middle (check mouse.button)
//   wheel(wheel)
//   shown            false hides it; use this rather than `visible` in module chips
//   pulse            ms per breath while > 0 (stepped opacity, cheap); 0 = still
Item {
    id: chip
    property string label
    property string icon            // shown instead of `label` when set
    property string value
    property real gauge: -1
    property color accent: Theme.text
    // hide the chip (and, in the bar's module slot, the space it takes)
    property bool shown: true
    visible: shown
    // breathe while > 0 (ms per breath). Stepped, a few frames a second:
    // a smooth opacity loop keeps the bar redrawing at 60 fps.
    property int pulse: 0
    property int _step: 0
    readonly property var _steps: [1, 0.85, 0.65, 0.5, 0.65, 0.85]
    opacity: pulse > 0 ? _steps[_step] : 1
    Timer {
        interval: Math.max(100, chip.pulse / 6)
        repeat: true
        running: chip.pulse > 0 && chip.visible
        onTriggered: chip._step = (chip._step + 1) % 6
        onRunningChanged: chip._step = 0
    }
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
