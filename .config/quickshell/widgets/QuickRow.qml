import QtQuick
import qs

// A quick panel list row: icon or signal bars, label, detail / tag on the right.
Rectangle {
    id: row
    property string icon
    property string label
    property string detail
    property string tag
    property bool active: false
    property bool busy: false
    property real level: -1         // 0..1 signal bars, -1 = none
    signal clicked()

    width: parent ? parent.width : 0
    height: 36
    radius: Theme.radius
    color: active ? Theme.alpha(Theme.accent, 0.10)
         : rowMouse.containsMouse ? Theme.bgCard : "transparent"

    Rectangle {
        visible: row.active
        width: 2
        height: parent.height - 12
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accent
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        spacing: 10

        // signal bars or an icon
        Item {
            width: 18
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            Row {
                visible: row.level >= 0
                anchors.bottom: parent.bottom
                spacing: 2
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: 3
                        height: 4 + index * 3
                        anchors.bottom: parent.bottom
                        color: row.level * 4 > index ? (row.active ? Theme.accent : Theme.text) : Theme.trackBg
                    }
                }
            }

            Text {
                visible: row.level < 0
                anchors.centerIn: parent
                text: row.icon
                color: row.active ? Theme.accent : Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: 14
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // as wide as the tag on the right allows
            width: row.width - 12 - 18 - 10 - 12 - (tagText.text ? tagText.implicitWidth + 10 : 0)
            elide: Text.ElideRight
            text: row.label
            color: row.active ? Theme.accent : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: row.active
        }
    }

    Text {
        id: tagText
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: row.busy ? "···" : (row.tag || row.detail)
        color: row.busy || row.tag ? Theme.accent : Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 1
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
