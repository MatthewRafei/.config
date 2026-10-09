import QtQuick
import Quickshell
import qs
import qs.widgets

// Quick panel page (qs ipc call quick rec): what to record, audio, start /
// stop, recent recordings.
Column {
    id: page
    property var service
    property var panel

    Component.onCompleted: service.refreshRecent()

    width: parent.width
    spacing: 4

    QuickHead {
        title: "// SCREEN RECORDER"
        on: page.service.active
        onToggled: { if (!page.service.active) page.panel.close(); page.service.toggle() }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.border }

    Text {
        visible: page.service.error !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: page.service.error
        color: Theme.danger
        font.family: Theme.fontFamily
        font.pixelSize: 9
        topPadding: 4
    }

    QuickLabel { text: "RECORD" }
    Repeater {
        model: Quickshell.screens
        QuickRow {
            required property var modelData
            icon: "󰍹"
            label: Quickshell.screens.length > 1 ? "Screen  " + modelData.name : "Whole screen"
            detail: page.service.px(modelData.width, modelData.height, modelData)
            active: page.service.mode === "screen" && page.service.screenName() === modelData.name
            onClicked: { page.service.mode = "screen"; page.service.output = modelData.name }
        }
    }
    QuickRow {
        icon: "󰩭"
        label: "Pick an area"
        detail: page.service.region.width > 0 ? page.service.px(page.service.region.width, page.service.region.height, page.service.screen) : "DRAG A BOX"
        active: page.service.mode === "region"
        onClicked: page.service.mode = "region"
    }

    QuickLabel { text: "AUDIO" }
    QuickRow {
        icon: "󰝟"
        label: "No audio"
        active: page.service.audio === "none"
        onClicked: page.service.audio = "none"
    }
    QuickRow {
        visible: root.sink !== null
        icon: "󰓃"
        label: "Desktop audio"
        detail: root.sink ? root.shortName(root.sink) : ""
        active: page.service.audio === "desktop"
        onClicked: page.service.audio = "desktop"
    }
    QuickRow {
        visible: root.source !== null
        icon: "󰍬"
        label: "Microphone"
        detail: root.source ? root.shortName(root.source) : ""
        active: page.service.audio === "mic"
        onClicked: page.service.audio = "mic"
    }

    Item { width: 1; height: 4 }

    // start / stop
    Rectangle {
        id: recBtn
        readonly property bool live: page.service.state === "recording"
        width: parent.width
        height: 40
        radius: Theme.radius
        color: live ? Theme.alpha(Theme.danger, recMouse.containsMouse ? 0.25 : 0.15)
             : Theme.alpha(Theme.accent, recMouse.containsMouse ? 0.22 : 0.12)
        border.color: live ? Theme.danger : Theme.accent

        Row {
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: recBtn.live ? "󰓛" : "󰑊"
                color: recBtn.live ? Theme.danger : Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: 16
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: recBtn.live ? "STOP  ·  " + page.service.clock
                    : page.service.state === "countdown" ? "STARTING IN " + page.service.countdown + "  ·  CANCEL"
                    : page.service.state === "saving" ? "SAVING…"
                    : page.service.mode === "region" ? "PICK AREA AND RECORD" : "START RECORDING"
                color: recBtn.live ? Theme.danger : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 2
            }
        }
        MouseArea {
            id: recMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (page.service.state === "idle") page.panel.close()   // out of the shot
                page.service.toggle()
            }
        }
    }
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "3 S COUNTDOWN  ·  MOD+ALT+R  ·  AREA: +SHIFT"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 8
        font.letterSpacing: 1
        topPadding: 2
    }

    QuickLabel { visible: page.service.recent.length > 0; text: "RECENT" }
    Repeater {
        model: page.service.recent
        QuickRow {
            required property var modelData
            icon: "󰕧"
            label: modelData.name.replace(/^Recording_/, "").replace(/\.mp4$/, "").replace("_", "  ")
            detail: modelData.size
            onClicked: { page.panel.close(); page.service.open(modelData.path) }
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.border }
    Text {
        text: "OPEN RECORDINGS FOLDER  →"
        color: footMouse.containsMouse ? Theme.accent : Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
        MouseArea {
            id: footMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { page.panel.close(); page.service.open("") }
        }
    }
}
