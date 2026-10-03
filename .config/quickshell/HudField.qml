import QtQuick

// Single-line HUD text field. Esc isn't handled here so it reaches the
// surrounding panel (which cancels/closes).
Rectangle {
    id: field

    property alias text: input.text
    property alias input: input
    property string placeholder
    signal accepted()
    signal finished()

    height: 30
    radius: Theme.radius
    color: Theme.bgCard
    border.color: input.activeFocus ? Theme.accent : Theme.border

    function focusInput() { input.forceActiveFocus() }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.text
        selectionColor: Theme.alpha(Theme.accent, 0.4)
        selectByMouse: true
        font.family: Theme.fontFamily
        font.pixelSize: 11
        onAccepted: field.accepted()
        onEditingFinished: field.finished()

        Text {
            visible: input.text === "" && !input.activeFocus
            anchors.verticalCenter: parent.verticalCenter
            text: field.placeholder
            color: Theme.textFaint
            font: input.font
        }
    }
}
