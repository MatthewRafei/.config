import QtQuick
import Quickshell
import "../"

// Settings > Fingerprint: pick a finger from the list, enroll it (the icon
// fills in as the reader takes each scan), test it, delete it.
// State and fprintd talk live in Fingerprint.qml.
Item {
    id: page

    property int contentRightMargin: 48
    property string selected: Fingerprint.fingers.length ? Fingerprint.fingers[0] : "right-index-finger"

    readonly property bool enrolling: Fingerprint.mode === "enroll"
    readonly property bool waiting: enrolling || Fingerprint.mode === "verify"
    // the big icon shows the selected finger: full if enrolled, filling while enrolling
    readonly property real iconProgress: enrolling || Fingerprint.result === "done" ? Fingerprint.progress
        : Fingerprint.has(selected) ? 1 : 0
    readonly property bool done: !enrolling && iconProgress >= 1

    // last scan feedback for the disc: "" | "ok" | "retry" | "match" | "nomatch"
    property string scanKind: ""
    Timer { id: scanReset; interval: 700; onTriggered: page.scanKind = "" }
    Connections {
        target: Fingerprint
        function onScan(kind) { page.scanKind = kind; scanReset.restart() }
    }

    Component.onCompleted: Fingerprint.refresh()

    function pick(f) {
        if (Fingerprint.busy) return
        selected = f
        Fingerprint.say("", false)
        Fingerprint.result = ""
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

            // ---------------- the selected finger ----------------
            Column {
                id: scanner
                width: 270
                spacing: 16

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (page.enrolling ? "ENROLLING " : Fingerprint.mode === "verify" ? "TESTING " : "")
                        + Fingerprint.label(page.enrolling ? Fingerprint.target : page.selected)
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 2
                }

                // icon in a soft disc; the disc goes green / red for a moment on each scan
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 170
                    height: 170
                    radius: width / 2
                    readonly property color tint: page.scanKind === "retry" || page.scanKind === "nomatch" ? Theme.danger
                        : page.scanKind === "ok" || page.scanKind === "match" || page.done ? Theme.ok
                        : Theme.accent
                    color: Theme.alpha(tint, page.scanKind !== "" ? 0.22 : page.waiting ? 0.14 : 0.07)
                    border.width: page.waiting ? 2 : 1
                    border.color: Theme.alpha(tint, page.waiting || page.scanKind !== "" ? 0.8 : 0.25)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    FingerprintIcon {
                        anchors.centerIn: parent
                        width: 104
                        height: 104
                        progress: page.iconProgress
                        baseColor: Theme.alpha(Theme.textDim, 0.45)
                        litColor: page.done ? Theme.ok : Theme.accent
                    }
                }

                // one pip per scan the reader needs
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
                            width: 16
                            height: 4
                            radius: 2
                            color: lit ? (page.done ? Theme.ok : Theme.accent) : Theme.trackBg
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
                        : "Not enrolled yet."
                    color: Fingerprint.messageBad ? Theme.danger : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    HudButton {
                        visible: !Fingerprint.busy
                        label: Fingerprint.has(page.selected) ? "RE-ENROLL" : "ENROLL"
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

            Rectangle { width: 1; height: parent.height; color: Theme.border }

            // ---------------- finger list ----------------
            Column {
                id: list
                width: parent.width - scanner.width - 1 - 2 * parent.spacing
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 12

                    Repeater {
                        model: ["left", "right"]
                        delegate: Column {
                            id: handCol
                            required property string modelData
                            width: (list.width - 12) / 2
                            spacing: 4

                            Text {
                                text: handCol.modelData.toUpperCase() + " HAND"
                                bottomPadding: 2
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.letterSpacing: 2
                            }

                            Repeater {
                                model: ["thumb", "index-finger", "middle-finger", "ring-finger", "little-finger"]
                                delegate: Rectangle {
                                    id: row
                                    required property string modelData
                                    readonly property string finger: handCol.modelData + "-" + modelData
                                    readonly property bool enrolled: Fingerprint.has(finger)
                                    readonly property bool sel: page.selected === finger
                                    readonly property bool active: Fingerprint.busy && Fingerprint.target === finger

                                    width: handCol.width
                                    height: 32
                                    radius: Theme.radius
                                    color: sel ? Theme.alpha(Theme.accent, 0.12)
                                        : rowMouse.containsMouse ? Theme.bgCard : "transparent"
                                    border.color: sel ? Theme.accent : Theme.border
                                    opacity: Fingerprint.busy && !active ? 0.5 : 1

                                    FingerprintIcon {
                                        id: mini
                                        x: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 20
                                        height: 20
                                        progress: row.active && page.enrolling ? Fingerprint.progress : row.enrolled ? 1 : 0
                                        baseColor: Theme.alpha(Theme.textDim, 0.5)
                                        litColor: Theme.accent
                                    }

                                    Text {
                                        anchors.left: mini.right
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.modelData.replace("-finger", "").replace(/^./, c => c.toUpperCase())
                                        color: row.sel || row.enrolled ? Theme.text : Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.active ? (page.enrolling ? "…" : "TESTING") : row.enrolled ? "✓" : ""
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Fingerprint.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        onClicked: page.pick(row.finger)
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    spacing: 8
                    topPadding: 4
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
                    text: "Enrolled fingers unlock the lock screen. Enrolling and deleting ask for your password first."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }
        }
    }
}
