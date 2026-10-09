import QtQuick
import Quickshell
import qs
import qs.widgets

// Settings > Modules: every optional feature (MODULES.md), with what it
// does in the background and where it came from. A module this machine
// can't run says what it needs. Choices are per machine.
Item {
    id: page

    property int rightMargin: 36

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width - page.rightMargin
            spacing: 12

            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MODULES"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    font.letterSpacing: 3
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Modules.list.filter(m => m.active).length + " OF " + Modules.list.length + " ON"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.border }
            Hint { text: "Optional features. One that's off isn't loaded at all: nothing runs and nothing is polled, so switch off what this machine doesn't need (on battery especially). Choices are kept per machine." }

            Repeater {
                model: Modules.list
                Rectangle {
                    id: card
                    required property var modelData
                    readonly property var m: modelData
                    readonly property bool blocked: m.missing.length > 0
                    width: col.width
                    height: cardCol.implicitHeight + 22
                    radius: Theme.radius
                    color: m.active ? Theme.alpha(Theme.accent, 0.05) : "transparent"
                    border.color: m.active ? Theme.alpha(Theme.accent, 0.5) : Theme.border
                    opacity: blocked && !m.enabled ? 0.6 : 1

                    Text {
                        id: ic
                        x: 14
                        y: 13
                        width: 26
                        text: card.m.icon
                        color: card.m.active ? Theme.accent : Theme.textDim
                        font.family: Theme.iconFont
                        font.pixelSize: 17
                    }
                    Column {
                        id: cardCol
                        x: 46
                        y: 11
                        width: card.width - x - 78
                        spacing: 3
                        Text {
                            text: card.m.name
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: card.m.active
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: card.m.description
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            visible: card.m.cost !== ""
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "⟳ " + card.m.cost
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            visible: card.blocked
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "needs " + card.m.missing.join(", ")
                            color: Theme.danger
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Repeater {
                            model: card.m.credits
                            Text {
                                required property string modelData
                                width: cardCol.width
                                elide: Text.ElideRight
                                text: "from " + modelData.replace(/^https?:\/\//, "")
                                color: creditMouse.containsMouse ? Theme.accent : Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                MouseArea {
                                    id: creditMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["xdg-open", parent.modelData])
                                }
                            }
                        }
                    }
                    // the switch (a module that can't run can still be switched off)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        y: 13
                        width: 44
                        height: 22
                        radius: 11
                        opacity: card.blocked && !card.m.enabled ? 0.4 : 1
                        color: card.m.enabled ? Theme.accent : Theme.trackBg
                        border.color: Theme.border
                        Rectangle {
                            width: 16; height: 16; radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            x: card.m.enabled ? parent.width - width - 3 : 3
                            color: Theme.text
                            Behavior on x { NumberAnimation { duration: Theme.animFast } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !card.blocked || card.m.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Modules.setEnabled(card.m.id, !card.m.enabled)
                        }
                    }
                }
            }

            Text {
                visible: Modules.list.length === 0
                text: Modules.ready ? "No modules in " + Modules.dir : "Reading modules…"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
