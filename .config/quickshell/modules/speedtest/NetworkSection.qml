import QtQuick
import qs

// Settings > Network: internet speed test (download, upload, ping against
// speed.cloudflare.com, speedtest.py).
Column {
    id: sec
    property var service
    spacing: 6

    Text {
        text: "// SPEED TEST"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.letterSpacing: 3
    }

    Rectangle {
        width: parent.width
        height: speedCol.height + 24
        radius: Theme.radius
        color: Theme.bgCard
        border.width: 1
        border.color: Theme.border

        Column {
            id: speedCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Item {
                width: parent.width
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 32

                    Repeater {
                        model: [
                            { k: "DOWNLOAD", icon: "󰇚", v: sec.service.mbps(sec.service.down), live: sec.service.phase === "down" },
                            { k: "UPLOAD", icon: "󰕒", v: sec.service.mbps(sec.service.up), live: sec.service.phase === "up" },
                            { k: "PING", icon: "󰓅", v: sec.service.ping >= 0 ? Math.round(sec.service.ping) + " ms" : "--", live: sec.service.phase === "ping" }
                        ]
                        delegate: Column {
                            required property var modelData
                            spacing: 4
                            Text {
                                text: modelData.k
                                color: modelData.live ? Theme.accent : Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.letterSpacing: 1
                            }
                            Row {
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.icon
                                    color: Theme.accent
                                    font.family: Theme.iconFont
                                    font.pixelSize: 15
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.live ? "testing…" : modelData.v
                                    color: modelData.live ? Theme.textDim : Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 17
                                    font.bold: !modelData.live
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: runText.implicitWidth + 24
                    height: 28
                    radius: Theme.radius
                    color: sec.service.running ? "transparent"
                         : Theme.alpha(Theme.accent, runMouse.containsMouse ? 0.25 : 0.15)
                    border.color: sec.service.running ? Theme.border : Theme.accent
                    Text {
                        id: runText
                        anchors.centerIn: parent
                        text: sec.service.running ? "TESTING…" : "󰑐  RUN TEST"
                        color: sec.service.running ? Theme.textDim : Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    MouseArea {
                        id: runMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: sec.service.running ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: sec.service.run()
                    }
                }
            }

            Text {
                width: parent.width
                text: sec.service.error !== "" ? sec.service.error
                    : sec.service.running ? "About 15 seconds. Uses a few hundred MB."
                    : "Last tested " + sec.service.ago() + "  ·  speed.cloudflare.com"
                color: sec.service.error !== "" ? Theme.danger : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }

    Item { width: 1; height: 14 }
}
