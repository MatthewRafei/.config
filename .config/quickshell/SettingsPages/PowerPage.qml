import QtQuick
import "../"

// Battery details, power profiles and battery-based automatic switching
// (state in ../Power.qml). Listed when there's a battery or profiles.
Item {
    id: page

    property int rightMargin: 36

    // one row of profile buttons
    component ProfileChoice: Row {
        id: choice
        property string selected
        property bool dim: false
        signal picked(string name)

        spacing: 8
        opacity: dim ? 0.4 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }

        Repeater {
            model: Power.choices

            Rectangle {
                required property string modelData
                readonly property bool on: choice.selected === modelData

                width: 118
                height: 34
                radius: Theme.radius
                color: on ? Theme.alpha(Theme.accent, 0.14)
                     : pickMouse.containsMouse ? Theme.bgCard : "transparent"
                border.width: 1
                border.color: on || pickMouse.containsMouse ? Theme.accent : Theme.border

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: Power.icons[modelData]
                        color: parent.parent.on ? Theme.accent : Theme.textDim
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                    }
                    Text {
                        text: Power.labels[modelData]
                        color: parent.parent.on ? Theme.accent : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: parent.parent.on
                        font.letterSpacing: 1
                    }
                }

                MouseArea {
                    id: pickMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: choice.picked(modelData)
                }
            }
        }
    }

    component RuleLabel: Text {
        property bool active: false
        width: 150
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: active && Power.auto ? Theme.accent : Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 2
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: page.rightMargin
        spacing: 18

        // ---- header ----
        Text {
            text: "POWER"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.bold: true
            font.letterSpacing: 3
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        // ---- battery ----
        Row {
            visible: Power.hasBattery
            width: parent.width
            spacing: 36

            // level
            Column {
                spacing: 8

                Row {
                    spacing: 12
                    Text {
                        id: pct
                        text: Power.battery
                        color: Power.batStatus === "Charging" ? Theme.ok
                             : Power.battery <= 15 ? Theme.danger : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 48
                        font.weight: Font.Light
                    }
                    Column {
                        anchors.bottom: pct.baseline
                        spacing: 4
                        Text {
                            text: "%"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                        }
                        Text {
                            text: Power.batStatus === "Charging" ? "󰂄 CHARGING"
                                : Power.batStatus === "Full" || Power.batStatus === "Not charging" ? "󰚥 PLUGGED IN"
                                : "󰁹 ON BATTERY"
                            color: Power.batStatus === "Charging" ? Theme.ok : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }
                    }
                }

                // segmented level bar
                Row {
                    spacing: 2
                    Repeater {
                        model: 20
                        Rectangle {
                            required property int index
                            width: 9
                            height: 6
                            color: index < Math.round(Power.battery / 5)
                                ? (Power.batStatus === "Charging" ? Theme.ok : Power.battery <= 15 ? Theme.danger : Theme.accent)
                                : Theme.trackBg
                        }
                    }
                }
            }

            // stats
            Grid {
                anchors.verticalCenter: parent.verticalCenter
                columns: 3
                columnSpacing: 32
                rowSpacing: 14

                Repeater {
                    model: [
                        [Power.batStatus === "Charging" ? "UNTIL FULL" : "TIME LEFT", Power.fmtHours(Power.hoursLeft)],
                        ["POWER DRAW", Power.powerW > 0.05 ? Power.powerW.toFixed(1) + " W" : "—"],
                        ["HEALTH", Power.health > 0 ? Math.round(Power.health * 100) + "%" : "—"],
                        ["ENERGY", Power.energyFull > 0 ? Power.energyNow.toFixed(1) + " / " + Power.energyFull.toFixed(1) + " Wh" : "—"],
                        ["CYCLES", Power.cycles >= 0 ? String(Power.cycles) : "—"],
                        ["DESIGN", Power.energyDesign > 0 ? Power.energyDesign.toFixed(1) + " Wh" : "—"]
                    ]
                    Column {
                        required property var modelData
                        spacing: 3
                        Text {
                            text: modelData[0]
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 2
                        }
                        Text {
                            text: modelData[1]
                            color: modelData[0] === "HEALTH" && Power.health > 0 && Power.health < 0.6 ? Theme.danger : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }

        Text {
            visible: Power.hasBattery && Power.batModel !== ""
            text: Power.batModel.toUpperCase() + "  ·  health is capacity now vs. when new"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        // ---- charge limit (only on batteries that support it) ----
        Row {
            visible: Power.hasBattery && Power.chargeLimit >= 0
            spacing: 10

            Column {
                width: 150
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: "CHARGE LIMIT"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    text: Power.chargeLimit >= 100 ? "charges to full" : "stops at " + Power.chargeLimit + "%, resumes below " + (Power.chargeLimit - 5) + "%"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                }
            }

            // with the helper installed: pick a limit
            Repeater {
                model: Power.limitHelper ? [60, 70, 80, 90, 100] : []
                Rectangle {
                    required property int modelData
                    readonly property bool on: Power.chargeLimit === modelData
                    width: 64
                    height: 30
                    radius: Theme.radius
                    anchors.verticalCenter: parent.verticalCenter
                    color: on ? Theme.alpha(Theme.accent, 0.14) : limMouse.containsMouse ? Theme.bgCard : "transparent"
                    border.width: 1
                    border.color: on || limMouse.containsMouse ? Theme.accent : Theme.border
                    Text {
                        anchors.centerIn: parent
                        text: modelData === 100 ? "OFF" : modelData + "%"
                        color: parent.on ? Theme.accent : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: parent.on
                    }
                    MouseArea {
                        id: limMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Power.setChargeLimit(modelData)
                    }
                }
            }

            // without it: say how to enable
            Text {
                visible: !Power.limitHelper
                anchors.verticalCenter: parent.verticalCenter
                text: "one-time setup to change it:  " + Power.limitSetup
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }

        Rectangle { visible: Power.available && Power.hasBattery; width: parent.width; height: 1; color: Theme.border }

        // ---- current profile ----
        Column {
            visible: Power.available
            spacing: 12

            Row {
                spacing: 14
                Text {
                    text: "PROFILE"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 2
                }
            }

            ProfileChoice {
                selected: Power.current
                onPicked: name => Power.set(name)
            }

            Text {
                visible: Power.degraded !== ""
                text: "󰀦  PERFORMANCE LIMITED BY FIRMWARE  ·  " + Power.degraded.toUpperCase()
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 1
            }
        }

        Rectangle { visible: Power.available; width: parent.width; height: 1; color: Theme.border }

        // ---- automatic switching ----
        Column {
            visible: Power.available
            width: parent.width
            spacing: 16

            Item {
                width: parent.width
                height: 34

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text {
                        text: "AUTOMATIC SWITCHING"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Text {
                        text: Power.auto
                            ? "picking a profile by hand lasts until you plug in, unplug or cross the threshold"
                            : "profiles only change when you pick one"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    height: 34
                    radius: Theme.radius
                    color: Power.auto ? Theme.alpha(Theme.accent, 0.1) : Theme.alpha("#A0A0A0", 0.15)
                    border.width: 1
                    border.color: Power.auto ? Theme.accent : "#A0A0A0"
                    Text {
                        anchors.centerIn: parent
                        text: Power.auto ? "ON" : "OFF"
                        color: Power.auto ? Theme.accent : "#A0A0A0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Power.auto = !Power.auto
                    }
                }
            }

            Row {
                spacing: 10
                RuleLabel { text: "PLUGGED IN"; active: Power.situation === "ac" }
                ProfileChoice {
                    dim: !Power.auto
                    selected: Power.acProfile
                    onPicked: name => Power.acProfile = name
                }
            }

            Row {
                visible: Power.hasBattery
                spacing: 10
                RuleLabel { text: "ON BATTERY"; active: Power.situation === "battery" }
                ProfileChoice {
                    dim: !Power.auto
                    selected: Power.batteryProfile
                    onPicked: name => Power.batteryProfile = name
                }
            }

            Row {
                visible: Power.hasBattery
                spacing: 10

                // "BELOW  −  25%  +"
                Row {
                    width: 150
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter

                    RuleLabel { width: implicitWidth; text: "BELOW"; active: Power.situation === "low" }

                    Repeater {
                        model: ["−", "%", "+"]
                        Rectangle {
                            required property string modelData
                            readonly property bool isValue: modelData === "%"
                            width: isValue ? 40 : 22
                            height: 22
                            radius: Theme.radius
                            anchors.verticalCenter: parent.verticalCenter
                            color: !isValue && stepMouse.containsMouse ? Theme.bgCard : "transparent"
                            border.width: isValue ? 0 : 1
                            border.color: stepMouse.containsMouse ? Theme.accent : Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: parent.isValue ? Power.lowThreshold + "%" : parent.modelData
                                color: parent.isValue ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: parent.isValue ? 11 : 12
                            }
                            MouseArea {
                                id: stepMouse
                                anchors.fill: parent
                                hoverEnabled: !parent.isValue
                                cursorShape: parent.isValue ? Qt.SizeVerCursor : Qt.PointingHandCursor
                                function shift(d) { Power.lowThreshold = Math.max(5, Math.min(90, Power.lowThreshold + d)) }
                                onClicked: {
                                    if (parent.modelData === "−") shift(-5)
                                    else if (parent.modelData === "+") shift(5)
                                }
                                onWheel: wheel => shift(wheel.angleDelta.y > 0 ? 5 : -5)
                            }
                        }
                    }
                }

                ProfileChoice {
                    dim: !Power.auto
                    selected: Power.lowProfile
                    onPicked: name => Power.lowProfile = name
                }
            }
        }
    }
}
