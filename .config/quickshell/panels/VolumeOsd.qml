import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import QtQuick
import qs

// Volume and brightness popup, bottom centre. Shows whichever changed last.
// Brightness is read from the kernel backlight (any tool: brillo, brightnessctl,
// the power profile...), so the niri binds don't need to call anything.
PanelWindow {
    id: root

    anchors {
        bottom: true
        left: true
        right: true
    }

    implicitHeight: 120
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: root.showing ? flyout : null
    }

    // -------------------------
    // PipeWire
    // -------------------------

    PwObjectTracker {
        id: audioTracker

        objects: [Pipewire.defaultAudioSink]
    }

    property var sink: Pipewire.defaultAudioSink

    property real volume: {
        if (!sink || !sink.audio)
            return 0

        return sink.audio.volume
    }

    property bool muted: {
        if (!sink || !sink.audio)
            return false

        return sink.audio.muted
    }

    // -------------------------
    // OSD state
    // -------------------------

    property bool showing: false
    property string kind: "volume"       // what the popup shows: "volume" | "brightness"

    function showOsd(what) {
        kind = what || "volume"
        showing = true
        hideTimer.restart()
    }

    // -------------------------
    // Backlight
    // -------------------------

    property string backlight: ""        // /sys/class/backlight/<device>, "" = none
    property real maxBrightness: 0
    property real brightness: -1         // 0..1 perceived, -1 until first read

    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/max_brightness\" ] && { echo \"$d\"; cat \"$d/max_brightness\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n")
                if (l.length < 2) return
                root.maxBrightness = Number(l[1]) || 0
                root.backlight = l[0]
            }
        }
    }

    FileView {
        path: root.backlight !== "" ? root.backlight + "/actual_brightness" : ""
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            if (root.maxBrightness <= 0) return
            // perceived lightness (CIE L*), the scale brightglide steps in, so
            // every key press moves the gauge by the same amount
            const y = Math.max(0, Math.min(1, Number(text().trim()) / root.maxBrightness))
            const b = (y > 0.008856 ? 116 * Math.cbrt(y) - 16 : 903.3 * y) / 100
            const first = root.brightness < 0
            if (Math.abs(b - root.brightness) < 0.0005) return
            root.brightness = b
            if (!first) root.showOsd("brightness")
        }
    }

    Timer {
        id: hideTimer

        interval: 1200
        repeat: false

        onTriggered: root.showing = false
    }

    // -------------------------
    // Detect changes
    // -------------------------

    Connections {
        target: root.sink?.audio ?? null

        function onVolumeChanged() {
            root.showOsd("volume")
        }

        function onMutedChanged() {
            root.showOsd("volume")
        }
    }

    // -------------------------
    // OSD
    // -------------------------

    // same language as the bar: panel colours, square-ish corners, a segmented
    // gauge in the accent colour. Muted dims it; past 100% turns it red.
    readonly property int segments: 20
    readonly property bool isVolume: kind === "volume"
    readonly property real level: isVolume ? (muted ? 0 : volume) : Math.max(0, brightness)
    readonly property color tint: !isVolume ? Theme.accent
                                : muted ? Theme.textFaint
                                : volume > 1.001 ? Theme.danger
                                : Theme.accent

    Rectangle {
        id: flyout

        width: 300
        height: 40

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48

        radius: Theme.radius
        color: Theme.alpha(Theme.bgPanel, 0.94)
        border.color: Theme.border

        opacity: root.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Text {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                text: !root.isVolume
                    ? (root.level < 0.34 ? "󰃞" : root.level < 0.67 ? "󰃟" : "󰃠")
                    : root.muted ? "󰖁"
                    : root.volume <= 0 ? "󰕿"
                    : root.volume < 0.5 ? "󰖀"
                    : "󰕾"
                color: root.tint
                font.family: Theme.iconFont
                font.pixelSize: 16
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }

            // segmented gauge
            Row {
                id: gauge
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - icon.width - value.width - parent.spacing * 2
                height: 8
                spacing: 2
                // brightness keeps one segment lit while the screen is on
                readonly property int lit: root.isVolume
                    ? Math.round(Math.min(root.level, 1) * root.segments)
                    : Math.max(root.level > 0 ? 1 : 0, Math.round(root.level * root.segments))
                Repeater {
                    model: root.segments
                    Rectangle {
                        required property int index
                        width: (gauge.width - gauge.spacing * (root.segments - 1)) / root.segments
                        height: gauge.height
                        radius: 1
                        color: index < gauge.lit ? root.tint : Theme.trackBg
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }
                }
            }

            Text {
                id: value
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                horizontalAlignment: Text.AlignRight
                readonly property bool mute: root.isVolume && root.muted
                text: mute ? "MUTE" : Math.round(root.level * 100) + "%"
                color: mute ? Theme.textDim : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.letterSpacing: mute ? 1.5 : 0
            }
        }
    }
}
