import QtQuick
import Quickshell
import "../"

// Settings > Lens: options for reading text off the screen (Lens.qml) and the
// languages tesseract reads with.
Item {
    id: page

    property int contentRightMargin: 48

    readonly property var rows: [
        { k: "LINES", opts: [{ l: "JOIN PARAGRAPHS", v: true }, { l: "KEEP BREAKS", v: false }],
          get: () => Lens.joinLines, set: v => Lens.joinLines = v },
        { k: "AFTER COPY", opts: [{ l: "CLOSE", v: true }, { l: "STAY OPEN", v: false }],
          get: () => Lens.closeAfterCopy, set: v => Lens.closeAfterCopy = v },
        { k: "WHEN READ", opts: [{ l: "WAIT FOR ME", v: false }, { l: "COPY ALL", v: true }],
          get: () => Lens.autoCopy, set: v => Lens.autoCopy = v },
        { k: "UNSURE BELOW", opts: [40, 50, 60, 70, 80].map(n => ({ l: n + "%", v: n })),
          get: () => Lens.minConf, set: v => Lens.minConf = v }
    ]

    Component.onCompleted: Lens.refresh()

    function tryIt() {
        // close Settings first so it isn't in the frozen picture
        Quickshell.execDetached(["sh", "-c", "qs ipc call settings hide; sleep 0.4; qs ipc call lens start"])
    }

    component Label: Text {
        width: 100
        height: 22
        verticalAlignment: Text.AlignVCenter
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    Column {
        anchors.fill: parent
        anchors.rightMargin: page.contentRightMargin
        spacing: 12

        Row {
            width: parent.width
            height: 28
            spacing: 16
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "LENS"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 3
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "COPY TEXT FROM ANYWHERE ON SCREEN"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 2
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        // tesseract missing
        Rectangle {
            visible: !Lens.available
            width: parent.width
            height: missCol.implicitHeight + 24
            radius: Theme.radius
            color: Theme.alpha(Theme.danger, 0.08)
            border.color: Theme.danger
            Column {
                id: missCol
                x: 14; y: 12
                width: parent.width - 28
                spacing: 6
                Text {
                    text: "TESSERACT ISN'T INSTALLED"
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Lens reads text with tesseract. Install it, then check again:\n"
                        + "Gentoo   sudo emerge app-text/tesseract\nChimera  doas apk search tesseract"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    lineHeight: 1.3
                }
                HudButton { label: "CHECK AGAIN"; onClicked: Lens.refresh() }
            }
        }

        // options
        Rectangle {
            width: parent.width
            height: setCol.implicitHeight + 24
            radius: Theme.radius
            color: "transparent"
            border.color: Theme.border

            Column {
                id: setCol
                x: 14; y: 12
                width: parent.width - 28
                spacing: 6

                Repeater {
                    model: page.rows
                    delegate: Row {
                        id: srow
                        required property var modelData
                        width: setCol.width
                        spacing: 12
                        Label { text: srow.modelData.k }
                        Flow {
                            width: parent.width - 112
                            spacing: 4
                            Repeater {
                                model: srow.modelData.opts
                                HudButton {
                                    required property var modelData
                                    label: modelData.l
                                    on: srow.modelData.get() === modelData.v
                                    onClicked: srow.modelData.set(modelData.v)
                                }
                            }
                        }
                    }
                }

                // reading languages: what tesseract has installed
                Row {
                    visible: Lens.available
                    width: setCol.width
                    spacing: 12
                    Label { text: "LANGUAGES" }
                    Flow {
                        width: parent.width - 112
                        spacing: 4
                        Repeater {
                            model: Lens.installed
                            HudButton {
                                required property string modelData
                                label: modelData.toUpperCase()
                                on: Lens.langList.indexOf(modelData) >= 0
                                onClicked: Lens.setLang(modelData, !on)
                            }
                        }
                    }
                }
                Text {
                    visible: Lens.available
                    width: parent.width
                    wrapMode: Text.Wrap
                    topPadding: 2
                    text: "Reading with " + Lens.langs.split("+").join(" + ").toUpperCase()
                        + ". More languages: L10N + app-text/tessdata_fast on Gentoo, the tesseract data packages on Chimera."
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    spacing: 8
                    topPadding: 4
                    HudButton {
                        label: "▶  TRY IT"
                        on: true
                        onClicked: page.tryIt()
                    }
                }
            }
        }

        // how to use it
        Text {
            text: "// USE"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 2
        }
        Grid {
            columns: 2
            columnSpacing: 24
            rowSpacing: 8
            Repeater {
                // key, what it does, key, what it does, ...
                model: [
                    Compositor.niri ? "MOD+SHIFT+T" : "SUPER+SHIFT+T", "freeze the screen, drag a box round some text",
                    "DRAG", "over the words to select them, a toolbar pops up",
                    "CTRL+DRAG", "select just the words inside the rectangle",
                    "DRAG OUTSIDE", "read a different box (any monitor)",
                    "CTRL+A", "select everything",
                    "CTRL+C / ENTER", "copy (everything, when nothing is selected)",
                    "RIGHT CLICK", "clear the selection",
                    "ESC", "close"
                ]
                Text {
                    required property string modelData
                    required property int index
                    readonly property bool key: index % 2 === 0
                    text: modelData
                    color: key ? Theme.accent : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: key
                    font.letterSpacing: key ? 1 : 0
                }
            }
        }
    }
}
