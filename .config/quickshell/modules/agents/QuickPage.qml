import QtQuick
import Quickshell
import qs
import qs.widgets

// Quick panel page (qs ipc call quick agents): sessions by state, start a
// kept one in a folder, resume a recent one as kept.
Column {
    id: page
    property var service
    property var panel

    // a Claude Code session: status, title, folder · age, kept or not, stop
    component AgentRow: Rectangle {
        id: ar
        property var s
        property bool armed: false
        readonly property color tint: s.status === "waiting" ? Theme.danger
            : s.status === "busy" ? Theme.accent : s.status === "new" ? Theme.text : Theme.textDim

        width: parent ? parent.width : 0
        height: 40
        radius: Theme.radius
        color: arMouse.containsMouse ? Theme.bgCard : "transparent"

        Rectangle {
            width: 2
            height: parent.height - 12
            anchors.verticalCenter: parent.verticalCenter
            color: ar.tint
            visible: ar.s.status === "waiting" || ar.s.status === "busy"
        }

        // status dot, pulsing while it works
        Rectangle {
            id: dot
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: ar.tint
            SequentialAnimation on opacity {
                running: ar.s.status === "busy"
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) dot.opacity = 1
            }
        }

        Column {
            x: 32
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - tags.width - 16
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: ar.s.title
                color: ar.s.status === "waiting" ? Theme.danger : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: (ar.s.status === "waiting" ? "NEEDS YOU" : ar.s.status === "busy" ? "WORKING"
                       : ar.s.status === "new" ? "NEW" : "IDLE")
                    + " " + page.service.ago(ar.s.since) + "  ·  " + page.service.pretty(ar.s.cwd || "")
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 8
                font.letterSpacing: 1
            }
        }

        Row {
            id: tags
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            // kept sessions survive their terminal; the others end with it
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ar.s.tmux !== "" ? (ar.s.attached > 0 ? "KEPT" : "KEPT · BG") : "TERMINAL"
                color: ar.s.tmux !== "" ? Theme.accent : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 8
                font.letterSpacing: 1
            }
            Rectangle {
                visible: ar.s.tmux !== ""
                width: ar.armed ? stopText.implicitWidth + 12 : 22
                height: 22
                radius: Theme.radius
                color: ar.armed ? Theme.alpha(Theme.danger, 0.15) : "transparent"
                border.color: ar.armed || stopMouse.containsMouse ? Theme.danger : Theme.border
                Text {
                    id: stopText
                    anchors.centerIn: parent
                    text: ar.armed ? "STOP?" : "󰅖"
                    color: ar.armed || stopMouse.containsMouse ? Theme.danger : Theme.textDim
                    font.family: ar.armed ? Theme.fontFamily : Theme.iconFont
                    font.pixelSize: ar.armed ? 8 : 12
                    font.bold: ar.armed
                }
                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (ar.armed) { ar.armed = false; page.service.stop(ar.s) }
                        else { ar.armed = true; disarm.restart() }
                    }
                }
                Timer { id: disarm; interval: 3000; onTriggered: ar.armed = false }
            }
        }

        MouseArea {
            id: arMouse
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.panel.close(); page.service.open(ar.s) }
        }
    }

    // live updates while it's open
    Binding { target: page.service; property: "fast"; value: true }
    Component.onCompleted: service.refreshMore()

    width: parent.width
    spacing: 4

    QuickHead {
        title: "// CLAUDE CODE  ·  " + page.service.sessions.length + " RUNNING"
        showToggle: false
        showRescan: true
        onRescan: page.service.refreshMore()
    }

    Rectangle { width: parent.width; height: 1; color: Theme.border }

    Text {
        visible: page.service.sessions.length === 0
        text: "NOTHING RUNNING"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
        topPadding: 6
    }

    QuickLabel { visible: page.service.waiting.length > 0; text: "NEEDS YOU"; color: Theme.danger }
    Repeater { model: page.service.waiting; AgentRow { required property var modelData; s: modelData } }
    QuickLabel { visible: page.service.busy.length > 0; text: "WORKING" }
    Repeater { model: page.service.busy; AgentRow { required property var modelData; s: modelData } }
    QuickLabel { visible: page.service.idle.length > 0; text: "IDLE" }
    Repeater { model: page.service.idle; AgentRow { required property var modelData; s: modelData } }

    QuickLabel { text: "NEW KEPT SESSION  ·  SURVIVES CLOSING" }
    Repeater {
        // home, the folders Claude knows, and wherever sessions run now
        model: [page.service.home].concat(page.service.projects)
            .concat(page.service.sessions.map(x => x.cwd))
            .filter((d, i, a) => d && a.indexOf(d) === i)
        QuickRow {
            required property string modelData
            height: 30
            icon: "󰐕"
            label: page.service.pretty(modelData)
            onClicked: { page.panel.close(); page.service.newSession(modelData, "") }
        }
    }
    HudField {
        id: agentDir
        width: parent.width
        placeholder: "other folder…  (enter to start)"
        onAccepted: {
            let d = text.trim().replace(/^~(?=\/|$)/, page.service.home)
            if (d === "") return
            text = ""
            page.panel.close()
            page.service.newSession(d, "")
        }
    }

    QuickLabel { visible: page.service.recent.length > 0; text: "RESUME AS KEPT" }
    Repeater {
        model: page.service.recent.slice(0, 5)
        QuickRow {
            required property var modelData
            height: 30
            icon: "󰑐"
            label: modelData.title
            detail: page.service.ago(modelData.mtime)
            onClicked: { page.panel.close(); page.service.newSession(modelData.cwd, modelData.sid) }
        }
    }
}
