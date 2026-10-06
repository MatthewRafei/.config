import QtQuick

// A simple fingerprint icon: a few bold rounded strokes. With `progress`
// 0 -> 1 the strokes fill in with colour, centre first (enroll stages).
// Used big on the Fingerprint page and tiny in the finger list.
Item {
    id: root

    property real progress: 0
    property color baseColor: Theme.textFaint
    property color litColor: Theme.accent

    implicitWidth: 24
    implicitHeight: 24

    property real shown: progress
    Behavior on shown { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    onShownChanged: canvas.requestPaint()
    onLitColorChanged: canvas.requestPaint()
    onBaseColorChanged: canvas.requestPaint()

    // strokes in a 24 x 24 box, centre first
    function arc(cx, cy, rx, ry, a0, a1) {
        const pts = [], n = Math.ceil(Math.abs(a1 - a0) / 6)
        for (let i = 0; i <= n; i++) {
            const a = (a0 + (a1 - a0) * i / n) * Math.PI / 180
            pts.push([cx + rx * Math.cos(a), cy + ry * Math.sin(a)])
        }
        return pts
    }
    readonly property var strokes: {
        const core = [[12, 10.4], [12, 14.6], [11.4, 17.2]]
        const inner = [[9.6, 16.4]].concat(arc(12, 10.6, 2.4, 2.8, 180, 360), [[14.4, 14.2], [13.9, 18.6]])
        const mid = [[7.2, 15]].concat(arc(12, 10.8, 4.8, 5.4, 180, 360), [[16.8, 13.6], [16.4, 17.4]])
        const outer = arc(12, 11.2, 7.4, 8.2, 158, 372)
        return [core, inner, mid, outer]
    }
    readonly property var lengths: strokes.map(s => {
        let l = 0
        for (let i = 1; i < s.length; i++) l += Math.hypot(s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1])
        return l
    })
    readonly property real total: lengths.reduce((a, b) => a + b, 0)

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        function path(ctx, s, upto) {   // upto: length along the stroke
            ctx.beginPath()
            ctx.moveTo(s[0][0], s[0][1])
            let l = 0
            for (let i = 1; i < s.length; i++) {
                const d = Math.hypot(s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1])
                if (l + d >= upto) {
                    const t = (upto - l) / d
                    ctx.lineTo(s[i - 1][0] + (s[i][0] - s[i - 1][0]) * t, s[i - 1][1] + (s[i][1] - s[i - 1][1]) * t)
                    break
                }
                ctx.lineTo(s[i][0], s[i][1])
                l += d
            }
            ctx.stroke()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const k = Math.min(width, height) / 24
            ctx.translate((width - 24 * k) / 2, (height - 24 * k) / 2)
            ctx.scale(k, k)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.lineWidth = Math.max(1.25, 1.0 / k)   // at least a pixel when tiny

            ctx.strokeStyle = root.baseColor
            for (let i = 0; i < root.strokes.length; i++) path(ctx, root.strokes[i], 1e9)

            let left = root.shown * root.total
            ctx.strokeStyle = root.litColor
            for (let i = 0; i < root.strokes.length && left > 0.05; i++) {
                path(ctx, root.strokes[i], left)
                left -= root.lengths[i]
            }
        }
    }
}
