import Quickshell
import Quickshell.Widgets
import QtQuick
import qs

// A tray app's menu drawn in the HUD style instead of Qt's stock menu.
// Submenus open in place (with a "back" row) rather than as more windows.
// Clicking outside closes it (grabFocus).
//
//   open(trayItem, window, x, y)   show trayItem.menu under (x, y) of window
PopupWindow {
    id: root

    property var trayItem: null
    property var stack: []                 // menu handles, top = what's shown
    readonly property var current: stack.length ? stack[stack.length - 1] : null

    property real wantX: 0
    function open(item, win, x, y) {
        trayItem = item
        stack = [item.menu]
        anchor.window = win
        wantX = x
        anchor.rect.y = y
        visible = true
    }
    // stay on screen: shift left when the menu would run past the right edge
    anchor.rect.x: anchor.window ? Math.max(4, Math.min(wantX, anchor.window.width - implicitWidth - 6)) : wantX
    function close() { visible = false; stack = [] }
    function enter(entry) {
        entry.opened()
        stack = stack.concat([entry])
    }
    function back() {
        const top = stack[stack.length - 1]
        if (top && top.closed) top.closed()
        stack = stack.slice(0, -1)
    }

    grabFocus: true
    color: "transparent"
    implicitWidth: Math.min(360, Math.max(200, col.implicitWidth + 16))
    implicitHeight: col.implicitHeight + 16

    onVisibleChanged: if (!visible) stack = []

    QsMenuOpener {
        id: opener
        menu: root.current
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.alpha(Theme.bgPanel, 0.97)
        border.color: Theme.border

        Column {
            id: col
            x: 8
            y: 8
            width: root.implicitWidth - 16
            spacing: 1

            // in a submenu: the way back
            Rectangle {
                visible: root.stack.length > 1
                width: parent.width
                height: 28
                radius: Theme.radius
                color: backMouse.containsMouse ? Theme.bgCard : "transparent"
                Text {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹  " + (root.current && root.current.text ? root.current.text : "back")
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.back()
                }
            }
            Rectangle {
                visible: root.stack.length > 1
                width: parent.width
                height: 1
                color: Theme.border
            }

            Repeater {
                model: opener.children

                Item {
                    id: row
                    required property var modelData
                    readonly property var e: modelData
                    width: col.width
                    height: e.isSeparator ? 9 : 28

                    // separator
                    Rectangle {
                        visible: row.e.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        x: 6
                        width: parent.width - 12
                        height: 1
                        color: Theme.border
                    }

                    Rectangle {
                        visible: !row.e.isSeparator
                        anchors.fill: parent
                        radius: Theme.radius
                        color: rowMouse.containsMouse && row.e.enabled ? Theme.bgCard : "transparent"

                        // hover accent
                        Rectangle {
                            visible: rowMouse.containsMouse && row.e.enabled
                            width: 2
                            height: parent.height - 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.accent
                        }

                        Row {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // check box / radio, or the entry's icon, or nothing
                            Item {
                                width: 14
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.e.buttonType !== QsMenuButtonType.None || row.e.icon !== ""

                                Rectangle {
                                    visible: row.e.buttonType !== QsMenuButtonType.None
                                    anchors.centerIn: parent
                                    width: 11
                                    height: 11
                                    radius: row.e.buttonType === QsMenuButtonType.RadioButton ? 6 : 2
                                    color: row.e.checkState === Qt.Checked ? Theme.accent : "transparent"
                                    border.color: row.e.checkState === Qt.Checked ? Theme.accent : Theme.textFaint
                                }
                                IconImage {
                                    visible: row.e.buttonType === QsMenuButtonType.None && row.e.icon !== ""
                                    anchors.centerIn: parent
                                    implicitSize: 14
                                    source: row.e.icon
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                // drop the mnemonic underscores apps put in labels
                                text: (row.e.text || "").replace(/_(?=[^_])/g, "")
                                color: !row.e.enabled ? Theme.textFaint
                                     : rowMouse.containsMouse ? Theme.text : Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 300)
                            }
                        }

                        Text {
                            visible: row.e.hasChildren
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: row.e.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.e.hasChildren) root.enter(row.e)
                                else { row.e.triggered(); root.close() }
                            }
                        }
                    }
                }
            }

            Text {
                visible: opener.children.values !== undefined ? opener.children.values.length === 0 : false
                text: "empty menu"
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
                leftPadding: 10
                topPadding: 6
                bottomPadding: 6
            }
        }
    }
}
