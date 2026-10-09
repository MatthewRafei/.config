import QtQuick
import qs

// Small outlined HUD button (calendar, etc). `on` = selected/primary look,
// `danger` = red for destructive actions.
Rectangle {
    id: btn

    property string label
    property bool on: false
    property bool danger: false
    property int fontSize: 9
    signal clicked()

    readonly property color tint: danger ? Theme.danger : Theme.accent

    width: btnText.implicitWidth + 20
    height: 26
    radius: Theme.radius
    color: on ? Theme.alpha(tint, 0.15) : btnMouse.containsMouse ? Theme.bgCard : "transparent"
    border.color: on || btnMouse.containsMouse ? tint : Theme.border

    Text {
        id: btnText
        anchors.centerIn: parent
        text: btn.label
        color: btn.on || btnMouse.containsMouse ? btn.tint : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: btn.fontSize
        font.bold: btn.on
        font.letterSpacing: 1
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
