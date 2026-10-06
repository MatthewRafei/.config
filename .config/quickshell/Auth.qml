pragma Singleton
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick

// Polkit authentication agent: when something asks for your password to do
// an admin-ish thing (enrolling a fingerprint, managing devices...), this
// shows a HUD prompt instead of the request just failing.
// shell.qml touches `registered` so the agent is up from login.
Singleton {
    id: root

    readonly property bool registered: agent.isRegistered
    readonly property bool active: agent.isActive
    readonly property var flow: agent.flow

    signal shake()

    PolkitAgent {
        id: agent
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() { root.shake() }
    }

    PanelWindow {
        id: win
        // mapped only while a request is up, so it lands on the focused monitor
        visible: root.active
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.alpha("#000000", 0.55)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "quickshell-polkit"

        MouseArea { anchors.fill: parent }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 440
            height: col.implicitHeight + 48
            radius: 6
            color: Theme.alpha(Theme.bgPanel, 0.96)
            border.color: Theme.accent

            Rectangle { width: 30; height: 2; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 10 } }
            Rectangle { width: 2; height: 30; color: Theme.accent2; anchors { top: parent.top; left: parent.left; margins: 10 } }
            Rectangle { width: 30; height: 2; color: Theme.accent2; anchors { bottom: parent.bottom; right: parent.right; margins: 10 } }
            Rectangle { width: 2; height: 30; color: Theme.accent2; anchors { bottom: parent.bottom; right: parent.right; margins: 10 } }

            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
                NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; to: 10; duration: 70 }
                NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; to: -6; duration: 60 }
                NumberAnimation { target: card; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
            }
            Connections {
                target: root
                function onShake() { shakeAnim.restart() }
            }

            Column {
                id: col
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 12

                Row {
                    spacing: 8
                    Text {
                        text: "󰌾"
                        color: Theme.accent
                        font.family: Theme.iconFont
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "// AUTHENTICATION REQUIRED"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.letterSpacing: 3
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.flow ? root.flow.message : ""
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }

                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: root.flow ? root.flow.actionId : ""
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }

                HudField {
                    id: field
                    width: parent.width
                    placeholder: root.flow && root.flow.inputPrompt
                        ? root.flow.inputPrompt.replace(/:\s*$/, "").toLowerCase() : "password"
                    input.echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    input.enabled: root.flow && root.flow.isResponseRequired
                    onAccepted: submit.clicked()
                    input.Keys.onEscapePressed: cancel.clicked()
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    text: !root.flow ? ""
                        : root.flow.failed ? "Wrong password, try again."
                        : root.flow.supplementaryMessage
                    color: root.flow && (root.flow.failed || root.flow.supplementaryIsError) ? Theme.danger : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8
                    HudButton {
                        id: cancel
                        label: "CANCEL"
                        onClicked: if (root.flow) root.flow.cancelAuthenticationRequest()
                    }
                    HudButton {
                        id: submit
                        label: "AUTHENTICATE"
                        on: true
                        onClicked: {
                            if (!root.flow || !root.flow.isResponseRequired || field.text === "") return
                            root.flow.submit(field.text)
                            field.text = ""
                        }
                    }
                }
            }
        }

        // a new request (or a retry after a wrong password) wants fresh input
        Connections {
            target: root.flow
            ignoreUnknownSignals: true
            function onIsResponseRequiredChanged() {
                if (root.flow.isResponseRequired) field.focusInput()
            }
        }
        onVisibleChanged: if (visible) { field.text = ""; field.focusInput() }
    }
}
