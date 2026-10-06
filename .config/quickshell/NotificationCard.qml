import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick

// One notification. Used by the popups (popup: true → slides in, times out
// with a draining bar, hover pauses) and by the notification center.
//
// click        default action (if the app offers one), then dismiss
// right-click  dismiss
Item {
    id: card

    property var notif: null
    property bool popup: false

    readonly property bool critical: notif !== null && notif.urgency === NotificationUrgency.Critical
    readonly property color stripe: critical ? Theme.danger : Theme.accent
    // browsers mark website notifications that ask to stay up ("require
    // interaction") as critical; those still time out, a bit later
    readonly property bool fromBrowser: notif !== null
        && /chrom|firefox|brave|vivaldi|librewolf/i.test((notif.appName || "") + " " + (notif.desktopEntry || ""))
    readonly property int timeoutMs: {
        if (!notif) return 0
        if (fromBrowser) return notif.expireTimeout > 0 ? Math.min(notif.expireTimeout * 1000, 15000) : critical ? 12000 : 8000
        if (critical) return 0
        return notif.expireTimeout > 0 ? notif.expireTimeout * 1000 : 6000
    }

    implicitHeight: body.implicitHeight + 28
    height: implicitHeight

    // slide in from the right
    property real slide: popup ? 1 : 0
    Component.onCompleted: if (popup) slideIn.start()
    NumberAnimation { id: slideIn; target: card; property: "slide"; from: 1; to: 0; duration: 320; easing.type: Easing.OutCubic }
    transform: Translate { x: card.slide * (card.width + 24) }
    opacity: 1 - card.slide

    // popup lifetime
    property real life: 1
    NumberAnimation on life {
        id: lifeAnim
        running: card.popup && card.timeoutMs > 0
        paused: running && mouse.containsMouse
        from: 1
        to: 0
        duration: card.timeoutMs
        onFinished: {
            if (card.notif && card.notif.transient)
                card.notif.expire()
            else
                Notifs.dropPopup(card.notif)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: card.popup ? Theme.alpha(Theme.bgPanel, 0.94) : Theme.bgCard
        border.color: mouse.containsMouse ? Theme.borderAccent : Theme.border
        radius: Theme.radius
        clip: true

        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

        // urgency stripe
        Rectangle {
            width: 2
            height: parent.height - 16
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            color: card.stripe
        }

        // draining timeout bar
        Rectangle {
            visible: card.popup && card.timeoutMs > 0
            anchors.bottom: parent.bottom
            height: 2
            width: parent.width * card.life
            color: Theme.alpha(card.stripe, 0.6)
        }
    }

    Row {
        id: body
        x: 20
        y: 14
        width: parent.width - 34
        spacing: 12

        // image (e.g. album art, avatar) > app icon > initial
        Item {
            id: iconBox
            width: 36
            height: 36
            readonly property string imageSrc: card.notif ? card.notif.image : ""
            readonly property string iconSrc: card.notif && card.notif.appIcon !== ""
                ? (card.notif.appIcon.startsWith("/") || card.notif.appIcon.startsWith("file:")
                    ? card.notif.appIcon
                    : Quickshell.iconPath(card.notif.appIcon, true))
                : ""

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.trackBg
                visible: img.status !== Image.Ready && icon.status !== Image.Ready
                Text {
                    anchors.centerIn: parent
                    text: card.notif && card.notif.appName ? card.notif.appName.charAt(0).toUpperCase() : "!"
                    color: card.stripe
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }
            }
            Image {
                id: img
                anchors.fill: parent
                source: iconBox.imageSrc
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(72, 72)
                asynchronous: true
                visible: status === Image.Ready
            }
            IconImage {
                id: icon
                anchors.fill: parent
                source: img.visible ? "" : iconBox.iconSrc
                visible: !img.visible && status === Image.Ready
            }
        }

        Column {
            width: parent.width - iconBox.width - parent.spacing
            spacing: 4

            // app · time · close
            Item {
                width: parent.width
                height: 12

                Text {
                    anchors.left: parent.left
                    anchors.right: meta.left
                    anchors.rightMargin: 8
                    elide: Text.ElideRight
                    text: card.notif ? (card.notif.appName || "notification").toUpperCase() : ""
                    color: card.critical ? Theme.danger : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 2
                }

                Row {
                    id: meta
                    anchors.right: parent.right
                    spacing: 8
                    Text {
                        text: Notifs.timeOf(card.notif)
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                    Text {
                        text: "✕"
                        color: closeMouse.containsMouse ? Theme.danger : Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (card.notif) card.notif.dismiss()
                        }
                    }
                }
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: card.notif ? card.notif.summary : ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                textFormat: Text.PlainText
            }

            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 4 : 8
                elide: Text.ElideRight
                text: card.notif ? card.notif.body : ""
                textFormat: Text.StyledText
                linkColor: Theme.accent
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // action buttons (the "default" action is the click itself)
            Flow {
                readonly property var shown: {
                    var out = []
                    var acts = card.notif ? card.notif.actions : []
                    for (var i = 0; i < acts.length; i++)
                        if (acts[i].identifier !== "default" && acts[i].text !== "")
                            out.push(acts[i])
                    return out
                }
                visible: shown.length > 0
                width: parent.width
                spacing: 6
                topPadding: 4

                Repeater {
                    model: parent.shown
                    Rectangle {
                        required property var modelData
                        width: actText.implicitWidth + 20
                        height: 22
                        radius: Theme.radius
                        color: actMouse.containsMouse ? Theme.alpha(Theme.accent, 0.15) : "transparent"
                        border.color: actMouse.containsMouse ? Theme.accent : Theme.border
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: modelData.text.toUpperCase()
                            color: actMouse.containsMouse ? Theme.accent : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                modelData.invoke()
                                if (card.notif && !card.notif.resident)
                                    card.notif.dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    // whole-card click; sits under the close/action buttons
    MouseArea {
        id: mouse
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            if (!card.notif) return
            if (m.button === Qt.LeftButton)
                Notifs.activate(card.notif)
            if (!card.notif.resident || m.button === Qt.RightButton)
                card.notif.dismiss()
        }
    }
}
