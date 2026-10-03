import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects

// What the lock screen looks like (one per monitor). State lives in Lock.qml.
//
// Blurred wallpaper, big clock, a HUD password field that shows one block
// per typed character and shakes on a wrong password, and a fortune.
Item {
    id: root

    property var lock
    property bool preview: false
    signal closePreview()

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // ---------------- backdrop ----------------
    Rectangle {
        anchors.fill: parent
        color: Theme.bgPanel
    }

    Image {
        id: wall
        anchors.fill: parent
        source: Theme.wallpaper ? "file://" + Theme.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1280      // blurred anyway; keeps it cheap
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: wall.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: -0.38
        saturation: 0.1
    }

    // top/bottom vignette
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.alpha(Theme.bgPanel, 0.75) }
            GradientStop { position: 0.35; color: "transparent" }
            GradientStop { position: 0.65; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.alpha(Theme.bgPanel, 0.85) }
        }
    }

    Canvas {
        anchors.fill: parent
        opacity: 0.5
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = "rgba(0,0,0,0.3)"
            for (var y = 0; y < height; y += 3)
                ctx.fillRect(0, y, width, 1)
        }
    }

    // ---------------- input ----------------
    TextInput {
        id: input
        width: 1
        height: 1
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        enabled: root.lock.status !== "checking"

        Component.onCompleted: forceActiveFocus()

        onTextChanged: {
            root.lock.password = text
            if (text !== "" && (root.lock.status === "failed" || root.lock.status === "error"))
                root.lock.status = "idle"
        }
        onAccepted: root.preview ? root.closePreview() : root.lock.tryUnlock()
        Keys.onEscapePressed: root.preview ? root.closePreview() : (text = "")
    }

    // PAM clears the password after every attempt
    Connections {
        target: root.lock
        function onPasswordChanged() {
            if (root.lock.password === "" && input.text !== "")
                input.text = ""
        }
        function onShake() { shakeAnim.restart() }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    // ---------------- content ----------------
    Item {
        id: content
        anchors.fill: parent

        opacity: 0
        scale: 0.97
        Component.onCompleted: { opacity = 1; scale = 1 }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -30
            spacing: 0

            // status header
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Rectangle {
                    width: 6; height: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.lock.status === "failed" || root.lock.status === "error" ? Theme.danger : Theme.accent
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    text: root.preview ? "// LOCKED · PREVIEW" : "// LOCKED"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 4
                }
            }

            Item { width: 1; height: 18 }

            // clock
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                Text {
                    id: bigClock
                    text: Qt.formatDateTime(clock.date, "hh:mm AP").split(" ")[0]
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 128
                    font.weight: Font.Light
                    font.letterSpacing: -4
                }

                Column {
                    anchors.bottom: bigClock.baseline
                    spacing: 6
                    Text {
                        text: Qt.formatDateTime(clock.date, "ss")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 30
                    }
                    Text {
                        text: Qt.formatDateTime(clock.date, "AP")
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 2
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, "dddd  ·  dd MMMM yyyy").toUpperCase()
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.letterSpacing: 4
            }

            Item { width: 1; height: 56 }

            // password field
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 360
                height: 50

                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: field; property: "shake"; to: -14; duration: 50 }
                    NumberAnimation { target: field; property: "shake"; to: 12; duration: 60 }
                    NumberAnimation { target: field; property: "shake"; to: -8; duration: 60 }
                    NumberAnimation { target: field; property: "shake"; to: 5; duration: 60 }
                    NumberAnimation { target: field; property: "shake"; to: 0; duration: 80 }
                }

                Rectangle {
                    id: field
                    property real shake: 0
                    readonly property bool bad: root.lock.status === "failed" || root.lock.status === "error"

                    x: shake
                    width: parent.width
                    height: parent.height
                    radius: Theme.radius
                    color: Theme.alpha(Theme.bgPanel, 0.72)
                    border.width: 1
                    border.color: bad ? Theme.danger
                                : input.text !== "" ? Theme.accent
                                : Theme.borderAccent
                    Behavior on border.color { ColorAnimation { duration: Theme.animMed } }

                    Text {
                        id: passLabel
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "PASS"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 3
                    }

                    // one block per character, caret after
                    Row {
                        id: dots
                        anchors.left: passLabel.right
                        anchors.leftMargin: 14
                        anchors.right: enterHint.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        clip: true

                        Repeater {
                            model: Math.min(input.text.length, 22)
                            Rectangle {
                                width: 8
                                height: 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: field.bad ? Theme.danger : Theme.accent
                                scale: 0
                                Component.onCompleted: scale = 1
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                            }
                        }

                        Rectangle {
                            visible: root.lock.status !== "checking"
                            width: 2
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.accent
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }

                        Text {
                            visible: input.text === "" && root.lock.status === "idle"
                            anchors.verticalCenter: parent.verticalCenter
                            text: "type to unlock"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.italic: true
                        }
                    }

                    Text {
                        id: enterHint
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↵"
                        color: input.text !== "" ? Theme.accent : Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                    }

                    // checking: a light sweeps along the bottom edge
                    Rectangle {
                        visible: root.lock.status === "checking"
                        anchors.bottom: parent.bottom
                        height: 2
                        width: parent.width * 0.3
                        color: Theme.accent
                        SequentialAnimation on x {
                            running: root.lock.status === "checking"
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: field.width * 0.7; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: field.width * 0.7; to: 0; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            Item { width: 1; height: 14 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (root.preview) return "PREVIEW  ·  ENTER OR ESC TO CLOSE"
                    switch (root.lock.status) {
                    case "checking": return "VERIFYING"
                    case "failed": return "ACCESS DENIED" + (root.lock.failures > 1 ? "  ·  " + root.lock.failures : "")
                    case "error": return "PAM ERROR  ·  " + root.lock.errorText.toUpperCase()
                    default: return Quickshell.env("USER").toUpperCase()
                    }
                }
                color: root.lock.status === "failed" || root.lock.status === "error" ? Theme.danger
                     : root.lock.status === "checking" ? Theme.accent
                     : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 3
            }
        }

        // fortune at the bottom
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            width: Math.min(parent.width - 80, 720)
            spacing: 6

            Text {
                id: quoteText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.italic: true
            }
            Text {
                id: quoteAuthor
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1
            }
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "fortune -s -n 140 2>/dev/null || \"$HOME/.local/bin/fortune\" -s -n 140"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.replace(/\t/g, " ").trim().split("\n")
                var m = lines.length > 1 ? lines[lines.length - 1].match(/^\s*--\s*(.+)$/) : null
                if (m)
                    lines.pop()
                var body = lines.join(" ").replace(/\s+/g, " ").trim()
                quoteText.text = body ? "“" + body + "”" : ""
                quoteAuthor.text = m ? "— " + m[1].trim() : ""
            }
        }
    }
}
