import QtQuick
import QtQuick.Window

// Matrix digital rain for the screensaver's "matrix" scene, drawn by one
// fragment shader (matrix-rain.frag): every column is a function of time on
// the GPU, so the CPU only advances a clock 30 times a second. The glyphs come
// from an atlas: the alphabet laid out once as ordinary Text (fontconfig
// supplies the katakana from Noto CJK) and captured into a texture.
// Adapted from nzkritik/omarchy-matrix-lock (MIT).
Item {
    id: rain

    property bool playing: true

    // grid pitch in logical px; everything else is in grid rows
    readonly property real cellW: 14
    readonly property real cellH: 18
    readonly property real minSpeed: 4      // rows per second
    readonly property real maxSpeed: 14
    readonly property int minTrail: 8       // glyphs per stream
    readonly property int maxTrail: 36
    readonly property real churn: 0.6       // flickers per glyph per second

    readonly property string alphabet: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾜﾝ012345789Z:.=*+-<>¦|"

    // the film's green: near-white head, bright body, tail falling to black
    property color headColor: "#e6ffe9"
    property color bodyColor: "#4dff6a"
    property color midColor: "#00b83a"
    property color tailColor: "#00521a"

    property real time: 0
    FrameAnimation {
        running: rain.playing && rain.visible && rain.width > 0
        property real pending: 0
        onTriggered: {
            pending += frameTime
            if (pending < 1 / 30) return
            rain.time = (rain.time + Math.min(pending, 0.1)) % 10000
            pending = 0
        }
    }

    // the alphabet, one glyph per cell. Never shown directly.
    Row {
        id: atlasRow
        visible: false
        Repeater {
            model: rain.alphabet.length
            Text {
                required property int index
                width: rain.cellW
                height: rain.cellH
                text: rain.alphabet.charAt(index)
                color: "white"
                font.family: "Noto Sans CJK JP"
                font.pixelSize: Math.round(rain.cellH * 0.82)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
            }
        }
    }

    ShaderEffectSource {
        id: atlas
        sourceItem: atlasRow
        hideSource: true
        // live: a hidden surface drops its GPU resources, and a static capture
        // would come back empty the next time the screensaver shows
        live: true
        textureSize: Qt.size(atlasRow.width * Screen.devicePixelRatio, atlasRow.height * Screen.devicePixelRatio)
        smooth: true
        visible: false
    }

    ShaderEffect {
        id: shader
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("matrix-rain.frag.qsb")
        onStatusChanged: if (status === ShaderEffect.Error) console.log("screensaver: matrix shader:", log)

        property size size: Qt.size(width, height)
        property size cell: Qt.size(rain.cellW, rain.cellH)
        property real time: rain.time
        property real glyphCount: rain.alphabet.length
        property real minSpeed: rain.minSpeed
        property real maxSpeed: rain.maxSpeed
        property real minTrail: rain.minTrail
        property real maxTrail: rain.maxTrail
        property real churn: rain.churn
        property color headColor: rain.headColor
        property color bodyColor: rain.bodyColor
        property color midColor: rain.midColor
        property color tailColor: rain.tailColor
        property variant atlas: atlas
    }
}
