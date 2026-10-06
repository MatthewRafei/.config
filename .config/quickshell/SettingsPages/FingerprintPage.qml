import QtQuick
import Quickshell
import "../"

// Settings > Fingerprint: pick a finger on the hands, enroll it (the print
// fills in with colour as the reader collects each scan), test it, delete it.
// State and fprintd talk live in Fingerprint.qml.
Item {
    id: page

    property int contentRightMargin: 48
    property string selected: Fingerprint.fingers.length ? Fingerprint.fingers[0] : "right-index-finger"

    // the glyph shows the selected finger: lit if enrolled, filling while enrolling
    readonly property bool enrolling: Fingerprint.mode === "enroll"
    readonly property real glyphProgress: enrolling || Fingerprint.result === "done" ? Fingerprint.progress
        : Fingerprint.has(selected) ? 1 : 0

    Component.onCompleted: Fingerprint.refresh()

    Connections {
        target: Fingerprint
        function onScan(kind) { glyph.flash(kind) }
    }

    Column {
        anchors.fill: parent
        anchors.rightMargin: page.contentRightMargin
        spacing: 12

        // ---------------- header ----------------
        Row {
            width: parent.width
            height: 28
            spacing: 16
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "FINGERPRINT"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 3
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: !Fingerprint.loaded ? "SCANNING…"
                    : !Fingerprint.available ? "NO READER"
                    : Fingerprint.deviceName.toUpperCase() + "  ·  " + Fingerprint.fingers.length + " ENROLLED"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        Text {
            visible: Fingerprint.loaded && !Fingerprint.available
            width: parent.width
            wrapMode: Text.Wrap
            text: "No fingerprint reader found. Is fprintd installed (apk add fprintd libfprint-udev)?"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Row {
            visible: Fingerprint.available
            width: parent.width
            height: parent.height - y
            spacing: 24

            // ---------------- scanner panel ----------------
            Rectangle {
                id: scanner
                width: 290
                height: parent.height
                radius: Theme.radius
                color: "transparent"
                border.color: page.enrolling || Fingerprint.mode === "verify" ? Theme.accent : Theme.border
                Behavior on border.color { ColorAnimation { duration: Theme.animMed } }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 18
                    width: parent.width - 36
                    spacing: 14

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.enrolling ? "// ENROLLING " + Fingerprint.label(Fingerprint.target)
                            : Fingerprint.mode === "verify" ? "// TESTING"
                            : "// " + Fingerprint.label(page.selected)
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }

                    Item {
                        width: parent.width
                        height: 230

                        // pulsing halo while the reader is waiting for a finger
                        Rectangle {
                            anchors.centerIn: glyph
                            width: glyph.width + 30
                            height: glyph.height + 20
                            radius: width / 2
                            color: "transparent"
                            border.color: Theme.accent
                            border.width: 1
                            visible: glyph.scanning
                            SequentialAnimation on opacity {
                                running: glyph.scanning
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.05; to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.45; to: 0.05; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }

                        FingerprintGlyph {
                            id: glyph
                            anchors.centerIn: parent
                            width: 170
                            height: 215
                            progress: page.glyphProgress
                            scanning: page.enrolling || Fingerprint.mode === "verify"
                            complete: !page.enrolling && page.glyphProgress >= 1
                            // a different print per finger, same one each time
                            seed: 11 + Fingerprint.fingerIds.indexOf(page.enrolling ? Fingerprint.target : page.selected) * 7
                        }
                    }

                    // stage pips
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5
                        visible: Fingerprint.stages > 0
                        Repeater {
                            model: Fingerprint.stages
                            Rectangle {
                                required property int index
                                readonly property bool lit: page.enrolling || Fingerprint.result === "done"
                                    ? index < Fingerprint.stage : Fingerprint.has(page.selected)
                                width: 18
                                height: 4
                                radius: 2
                                color: lit ? (glyph.complete ? Theme.ok : Theme.accent) : Theme.trackBg
                                Behavior on color { ColorAnimation { duration: Theme.animMed } }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        height: 30
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: Fingerprint.message !== "" ? Fingerprint.message
                            : Fingerprint.has(page.selected) ? "Enrolled. Test it, or re-enroll to replace it."
                            : "Not enrolled. Press ENROLL and follow along."
                        color: Fingerprint.messageBad ? Theme.danger : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        HudButton {
                            visible: !Fingerprint.busy
                            label: Fingerprint.has(page.selected) ? "󰑓  RE-ENROLL" : "󰈷  ENROLL"
                            on: !Fingerprint.has(page.selected)
                            onClicked: Fingerprint.enroll(page.selected)
                        }
                        HudButton {
                            visible: !Fingerprint.busy && Fingerprint.has(page.selected)
                            label: "TEST"
                            onClicked: Fingerprint.verify(page.selected)
                        }
                        HudButton {
                            visible: !Fingerprint.busy && Fingerprint.has(page.selected)
                            label: "DELETE"
                            danger: true
                            onClicked: Fingerprint.remove(page.selected)
                        }
                        HudButton {
                            visible: Fingerprint.busy
                            label: "CANCEL"
                            onClicked: Fingerprint.cancel()
                        }
                    }
                }
            }

            // ---------------- hands ----------------
            Column {
                width: parent.width - scanner.width - parent.spacing
                spacing: 14

                Text {
                    text: "// PICK A FINGER"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 44

                    Repeater {
                        model: ["left", "right"]
                        delegate: Column {
                            id: hand
                            required property string modelData
                            spacing: 8

                            // fingers: little..thumb on the left hand, mirrored on the right
                            Row {
                                id: fingersRow
                                spacing: 5
                                height: 150
                                Repeater {
                                    model: Fingerprint.fingerIds.filter(f => f.indexOf(hand.modelData) === 0)
                                    delegate: Item {
                                        id: fing
                                        required property string modelData
                                        readonly property string kind: modelData.split("-")[1]
                                        readonly property bool enrolled: Fingerprint.has(modelData)
                                        readonly property bool sel: page.selected === modelData
                                        readonly property bool active: Fingerprint.busy && Fingerprint.target === modelData
                                        // thumbs get room to splay out from the hand
                                        width: kind === "thumb" ? 34 : 22
                                        height: fingersRow.height

                                        Rectangle {
                                            id: pill
                                            width: 22
                                            x: fing.kind === "thumb" && hand.modelData === "left" ? 12 : 0
                                            height: ({ thumb: 66, index: 116, middle: 124, ring: 118, little: 92 })[fing.kind]
                                            // thumbs sit lower, angled out
                                            y: parent.height - height - (fing.kind === "thumb" ? -6 : 22)
                                            rotation: fing.kind === "thumb" ? (hand.modelData === "left" ? 14 : -14) : 0
                                            transformOrigin: Item.Bottom
                                            radius: width / 2
                                            color: fing.enrolled ? Theme.alpha(Theme.accent, fing.sel ? 0.45 : 0.25)
                                                : fingMouse.containsMouse || fing.sel ? Theme.bgCard : "transparent"
                                            border.width: fing.sel ? 2 : 1
                                            border.color: fing.sel ? Theme.accent2
                                                : fing.enrolled ? Theme.accent
                                                : fingMouse.containsMouse ? Theme.textDim : Theme.textFaint
                                            Behavior on color { ColorAnimation { duration: Theme.animFast } }

                                            // a print on the fingertip
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: 6
                                                text: "󰈷"
                                                font.family: Theme.iconFont
                                                font.pixelSize: 13
                                                color: fing.enrolled ? Theme.accent : Theme.textFaint
                                                opacity: fing.enrolled || fing.sel || fingMouse.containsMouse ? 1 : 0.5
                                                SequentialAnimation on opacity {
                                                    running: fing.active
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 0.15; duration: 500 }
                                                    NumberAnimation { to: 1; duration: 500 }
                                                }
                                            }

                                            MouseArea {
                                                id: fingMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Fingerprint.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                onClicked: if (!Fingerprint.busy) { page.selected = fing.modelData; Fingerprint.say("", false); Fingerprint.result = "" }
                                            }
                                        }
                                    }
                                }
                            }

                            // palm
                            Rectangle {
                                width: fingersRow.width + 6
                                x: -3
                                height: 54
                                radius: 14
                                color: "transparent"
                                border.color: Theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: hand.modelData.toUpperCase()
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.letterSpacing: 3
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.border }

                // enrolled list
                Text {
                    text: "// ENROLLED"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Text {
                        visible: Fingerprint.fingers.length === 0
                        text: "none yet"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.italic: true
                    }
                    Repeater {
                        model: Fingerprint.fingers
                        HudButton {
                            required property string modelData
                            label: "󰈷  " + Fingerprint.label(modelData)
                            on: page.selected === modelData
                            onClicked: if (!Fingerprint.busy) page.selected = modelData
                        }
                    }
                }

                Row {
                    spacing: 8
                    visible: Fingerprint.fingers.length > 0 && !Fingerprint.busy
                    HudButton {
                        label: "TEST ANY FINGER"
                        onClicked: Fingerprint.verify("")
                    }
                    HudButton {
                        label: "DELETE ALL"
                        danger: true
                        onClicked: Fingerprint.remove("")
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    topPadding: 4
                    text: "Enrolled fingers unlock the lock screen. Enrolling and deleting ask for your password first."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }
        }
    }
}
