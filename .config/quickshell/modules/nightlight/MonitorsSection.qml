import QtQuick
import qs
import qs.widgets

// Settings > Monitors: night light strength and on / off, and its schedule
// (always, sunset to sunrise, or custom times).
Column {
    id: sec
    property var service
    spacing: 20

    // -------------------------
    // NIGHT LIGHT
    // -------------------------
    Item {
        width: parent.width
        height: 58

        property int controlMargin: 25

        Row {
            anchors.fill: parent
            spacing: parent.controlMargin

            Slider {
                width:
                    parent.width -
                    70 -
                    parent.spacing

                height: parent.height

                label: "NIGHT LIGHT  ·  " + sec.service.temperature + "K"
                icon: ""
                value: sec.service.value
                accentColor: Theme.accent

                onMoved: (value) =>
                    sec.service.value = value
            }

            Rectangle {
                width: 70
                height: 36
                radius: Theme.radius
                anchors.verticalCenter: parent.verticalCenter

                color:
                    sec.service.active
                        ? Theme.alpha(Theme.accent, 0.1)
                        : Theme.alpha("#A0A0A0", 0.15)

                border.width: 1
                border.color: sec.service.active ? Theme.accent : "#A0A0A0"

                Text {
                    anchors.centerIn: parent
                    text: sec.service.active ? "ON" : "OFF"
                    color: sec.service.active ? Theme.accent : "#A0A0A0"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sec.service.toggle()
                }
            }
        }
    }

    // -------------------------
    // NIGHT LIGHT SCHEDULE
    // -------------------------
    Column {
        width: parent.width
        spacing: 12

        // mode selector + status
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    text: "SCHEDULE"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }

                Repeater {
                    model: [
                        { mode: "manual", label: "MANUAL" },
                        { mode: "sun",    label: "SUNSET" },
                        { mode: "custom", label: "CUSTOM" }
                    ]

                    Rectangle {
                        required property var modelData
                        readonly property bool selected: sec.service.mode === modelData.mode

                        width: modeText.implicitWidth + 22
                        height: 26
                        radius: Theme.radius
                        color: selected ? Theme.alpha(Theme.accent, 0.12)
                             : modeMouse.containsMouse ? Theme.bgCard : "transparent"
                        border.width: 1
                        border.color: selected ? Theme.accent : Theme.border

                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.selected ? Theme.accent : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            font.bold: parent.selected
                        }

                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sec.service.mode = modelData.mode
                        }
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: sec.service.status
                color: sec.service.active ? Theme.accent : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 2
            }
        }

        // sunset mode: show today's times
        Row {
            visible: sec.service.mode === "sun"
            x: 102
            spacing: 18

            Repeater {
                model: [
                    { label: "SUNSET",  min: sec.service.sun.set },
                    { label: "SUNRISE", min: sec.service.sun.rise }
                ]
                Row {
                    required property var modelData
                    spacing: 8
                    Text {
                        text: modelData.label
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2
                        anchors.baseline: sunTime.baseline
                    }
                    Text {
                        id: sunTime
                        text: sec.service.fmt(modelData.min)
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }
        }

        // custom mode: start/end pickers (± 15 min, or scroll)
        Row {
            visible: sec.service.mode === "custom"
            x: 102
            spacing: 22

            Repeater {
                model: [
                    { label: "FROM", key: "start" },
                    { label: "TO",   key: "end" }
                ]

                Row {
                    id: picker
                    required property var modelData
                    readonly property int minutes: sec.service[modelData.key]
                    spacing: 8

                    function shift(delta) {
                        sec.service[modelData.key] = ((minutes + delta) % 1440 + 1440) % 1440
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        text: picker.modelData.label
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    Repeater {
                        model: ["−", "time", "+"]

                        Rectangle {
                            required property string modelData
                            readonly property bool isTime: modelData === "time"

                            width: isTime ? 92 : 26
                            height: 26
                            radius: Theme.radius
                            color: !isTime && stepMouse.containsMouse ? Theme.bgCard : "transparent"
                            border.width: 1
                            border.color: !isTime && stepMouse.containsMouse ? Theme.accent : Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: parent.isTime ? sec.service.fmt(picker.minutes) : parent.modelData
                                color: parent.isTime ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: parent.isTime ? 12 : 13
                            }

                            MouseArea {
                                id: stepMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: parent.isTime ? Qt.SizeVerCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (parent.modelData === "−") picker.shift(-15)
                                    else if (parent.modelData === "+") picker.shift(15)
                                }
                                onWheel: wheel => picker.shift(wheel.angleDelta.y > 0 ? 15 : -15)
                            }
                        }
                    }
                }
            }
        }
    }
}
