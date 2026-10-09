import QtQuick
import Quickshell
import qs
import qs.widgets

// Settings > Fingerprint: pick a finger from the list, enroll it (the icon
// fills in as the reader takes each scan), test it, delete it.
// State and fprintd talk live in page.service.qml.
Item {
    id: page
    property var service

    property int contentRightMargin: 48
    property string selected: page.service.fingers.length ? page.service.fingers[0] : "right-index-finger"

    readonly property bool enrolling: page.service.mode === "enroll"
    readonly property bool waiting: enrolling || page.service.mode === "verify"
    // the big icon shows the selected finger: full if enrolled, filling while enrolling
    readonly property real iconProgress: enrolling || page.service.result === "done" ? page.service.progress
        : page.service.has(selected) ? 1 : 0
    readonly property bool done: !enrolling && iconProgress >= 1
    // the selected finger is on the reader for someone else (e.g. root)
    readonly property string owner: page.service.owner(selected)

    // last scan feedback for the disc: "" | "ok" | "retry" | "match" | "nomatch"
    property string scanKind: ""
    Timer { id: scanReset; interval: 700; onTriggered: page.scanKind = "" }
    Connections {
        target: page.service
        function onScan(kind) { page.scanKind = kind; scanReset.restart() }
    }

    Component.onCompleted: page.service.refresh()

    function pick(f) {
        if (page.service.busy) return
        selected = f
        page.service.say("", false)
        page.service.result = ""
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
                text: !page.service.loaded ? "SCANNING…"
                    : !page.service.available ? "NO READER"
                    : page.service.deviceName.toUpperCase() + "  ·  " + page.service.fingers.length + " ENROLLED"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        Text {
            visible: page.service.loaded && !page.service.available
            width: parent.width
            wrapMode: Text.Wrap
            text: "No fingerprint reader found. Is fprintd installed (apk add fprintd libfprint-udev)?"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Row {
            visible: page.service.available
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
                    text: (page.enrolling ? "ENROLLING " : page.service.mode === "verify" ? "TESTING " : "")
                        + page.service.label(page.enrolling ? page.service.target : page.selected)
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
                    visible: page.service.stages > 0
                    Repeater {
                        model: page.service.stages
                        Rectangle {
                            required property int index
                            readonly property bool lit: page.enrolling || page.service.result === "done"
                                ? index < page.service.stage : page.service.has(page.selected)
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
                    text: page.service.message !== "" ? page.service.message
                        : page.service.has(page.selected) ? "Enrolled. Test it, or re-enroll to replace it."
                        : page.owner !== "" ? "Enrolled for " + page.owner + ", not you. Remove that print to enroll this finger."
                        : "Not enrolled yet."
                    color: page.service.messageBad ? Theme.danger : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    HudButton {
                        visible: !page.service.busy && page.owner !== ""
                        label: "REMOVE " + page.owner.toUpperCase() + "'S PRINT"
                        danger: true
                        onClicked: page.service.remove(page.selected, page.owner)
                    }
                    HudButton {
                        visible: !page.service.busy && page.owner === ""
                        label: page.service.has(page.selected) ? "RE-ENROLL" : "ENROLL"
                        on: !page.service.has(page.selected)
                        onClicked: page.service.enroll(page.selected)
                    }
                    HudButton {
                        visible: !page.service.busy && page.service.has(page.selected)
                        label: "TEST"
                        onClicked: page.service.verify(page.selected)
                    }
                    HudButton {
                        visible: !page.service.busy && page.service.has(page.selected)
                        label: "DELETE"
                        danger: true
                        onClicked: page.service.remove(page.selected)
                    }
                    HudButton {
                        visible: page.service.busy
                        label: "CANCEL"
                        onClicked: page.service.cancel()
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
                                    readonly property bool enrolled: page.service.has(finger)
                                    readonly property string owner: page.service.owner(finger)
                                    readonly property bool sel: page.selected === finger
                                    readonly property bool active: page.service.busy && page.service.target === finger

                                    width: handCol.width
                                    height: 32
                                    radius: Theme.radius
                                    color: sel ? Theme.alpha(Theme.accent, 0.12)
                                        : rowMouse.containsMouse ? Theme.bgCard : "transparent"
                                    border.color: sel ? Theme.accent : Theme.border
                                    opacity: page.service.busy && !active ? 0.5 : 1

                                    FingerprintIcon {
                                        id: mini
                                        x: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 20
                                        height: 20
                                        progress: row.active && page.enrolling ? page.service.progress : row.enrolled || row.owner !== "" ? 1 : 0
                                        baseColor: Theme.alpha(Theme.textDim, 0.5)
                                        litColor: row.enrolled || row.active ? Theme.accent : Theme.textDim
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
                                        text: row.active ? (page.enrolling ? "…" : "TESTING") : row.enrolled ? "✓"
                                            : row.owner !== "" ? row.owner.toUpperCase() : ""
                                        color: row.enrolled || row.active ? Theme.accent : Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: row.enrolled || row.active ? 11 : 9
                                        font.letterSpacing: row.owner !== "" && !row.enrolled ? 1 : 0
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: page.service.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        onClicked: page.pick(row.finger)
                                    }
                                }
                            }
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 8
                    topPadding: 4
                    visible: !page.service.busy
                    HudButton {
                        visible: !page.service.othersChecked
                        label: page.service.checkingOthers ? "CHECKING…" : "CHECK OTHER USERS"
                        onClicked: page.service.checkOthers()
                    }
                    HudButton {
                        visible: page.service.fingers.length > 0
                        label: "TEST ANY FINGER"
                        onClicked: page.service.verify("")
                    }
                    HudButton {
                        visible: page.service.fingers.length > 0
                        label: "DELETE ALL"
                        danger: true
                        onClicked: page.service.remove("")
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Enrolled fingers unlock the lock screen. Enrolling and deleting ask for your password first."
                        + " Prints enrolled for another user (say, with doas fprintd-enroll) block that finger; CHECK OTHER USERS finds them."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }
        }
    }
}
