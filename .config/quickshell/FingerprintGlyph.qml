import QtQuick

// A procedurally drawn fingerprint. Ridges start grey and fill in with the
// accent colour from the core outwards as `progress` goes 0 -> 1 (enroll
// stages). `scanning` sweeps a scan line over it; flash() tints it briefly
// ("ok" | "retry" | "match" | "nomatch").
Item {
    id: root

    property real progress: 0
    property bool scanning: false
    property bool complete: false
    property color baseColor: Theme.textFaint
    property color litColor: complete ? Theme.ok : Theme.accent
    property int seed: 7

    implicitWidth: 200
    implicitHeight: 250

    property real shown: progress
    Behavior on shown { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }
    onShownChanged: canvas.requestPaint()
    onLitColorChanged: canvas.requestPaint()
    onBaseColorChanged: canvas.requestPaint()

    property color flashColor: Theme.accent
    property real flashAmt: 0
    onFlashAmtChanged: canvas.requestPaint()
    function flash(kind) {
        flashColor = kind === "retry" || kind === "nomatch" ? Theme.danger
                   : kind === "match" ? Theme.ok : Theme.accent2
        flashAnim.restart()
    }
    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: root; property: "flashAmt"; to: 1; duration: 90 }
        NumberAnimation { target: root; property: "flashAmt"; to: 0; duration: 700; easing.type: Easing.OutQuad }
    }

    // ridge polylines, innermost first: [{ pts: [[x,y]...], len }]
    property var segs: []
    property real totalLen: 1
    property int ridgeCount: 1

    function rng(a) {
        return function() {
            a |= 0; a = a + 0x6D2B79F5 | 0
            let t = Math.imul(a ^ a >>> 15, 1 | a)
            t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t
            return ((t ^ t >>> 14) >>> 0) / 4294967296
        }
    }

    // fingertip: an ellipse; ridges are cut to it
    function inTip(p) {
        const dx = (p[0] - width / 2) / (width * 0.47), dy = (p[1] - height * 0.5) / (height * 0.48)
        return dx * dx + dy * dy <= 1
    }

    function build() {
        const w = width, h = height
        if (w <= 0 || h <= 0) return
        const R = rng(seed)
        const cx = w / 2, cy = h * 0.44
        const ridges = 17
        const gap = Math.min(w, h) * 0.034
        const out = []
        let total = 0
        for (let i = 0; i < ridges; i++) {
            const rx = gap * (0.9 + i * 1.05)
            const ry = rx * 1.32
            // the loop opens at the bottom; inner ridges more so
            const open = Math.max(0.12, 0.95 - i * 0.055) + (R() - 0.5) * 0.12
            const a0 = Math.PI / 2 + open, a1 = Math.PI / 2 + 2 * Math.PI - open
            const wob = (R() - 0.5) * 0.05, ph = R() * 6.28
            // a few breaks per ridge, like real ridge endings
            const cuts = [a0]
            const n = i < 2 ? 0 : Math.floor(R() * 3)
            for (let k = 0; k < n; k++) cuts.push(a0 + (a1 - a0) * (0.15 + R() * 0.7))
            cuts.push(a1)
            cuts.sort((x, y) => x - y)
            for (let c = 0; c + 1 < cuts.length; c++) {
                const s = cuts[c] + (c > 0 ? 0.05 + R() * 0.06 : 0)
                const e = cuts[c + 1]
                if (e - s < 0.15) continue
                const steps = Math.max(6, Math.ceil((e - s) * rx / 3))
                let pts = [], len = 0
                const flush = () => {
                    if (pts.length > 2) { out.push({ pts: pts, len: len, ridge: i }); total += len }
                    pts = []; len = 0
                }
                for (let j = 0; j <= steps; j++) {
                    const a = s + (e - s) * j / steps
                    const m = 1 + wob * Math.sin(a * 3 + ph)
                    // lower half drifts outwards so the loop flares into a fingertip
                    const flare = Math.max(0, Math.sin(a)) * rx * 0.18
                    const p = [cx + Math.cos(a) * (rx * m + flare), cy + Math.sin(a) * ry * m]
                    if (!inTip(p)) { flush(); continue }
                    if (pts.length) len += Math.hypot(p[0] - pts[pts.length - 1][0], p[1] - pts[pts.length - 1][1])
                    pts.push(p)
                }
                flush()
            }
        }
        segs = out
        totalLen = Math.max(1, total)
        ridgeCount = ridges
        canvas.requestPaint()
    }

    onWidthChanged: build()
    onHeightChanged: build()
    Component.onCompleted: build()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        function line(ctx, pts, upto) {
            ctx.beginPath()
            ctx.moveTo(pts[0][0], pts[0][1])
            for (let j = 1; j < upto; j++) ctx.lineTo(pts[j][0], pts[j][1])
            ctx.stroke()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.save()
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.lineWidth = Math.max(1.6, width / 95)

            const base = Qt.tint(root.baseColor, Qt.rgba(root.flashColor.r, root.flashColor.g,
                                                        root.flashColor.b, root.flashAmt * 0.8))
            ctx.strokeStyle = base
            for (const s of root.segs) line(ctx, s.pts, s.pts.length)

            // lit part: ridge by ridge from the core outwards, like ink
            // spreading; the ridge being filled grows along its length
            const f = root.shown * root.ridgeCount
            if (f > 0.02) {
                ctx.strokeStyle = root.litColor
                ctx.shadowColor = root.litColor
                ctx.shadowBlur = 8
                for (const s of root.segs) {
                    const part = Math.min(1, f - s.ridge)
                    if (part <= 0) break
                    line(ctx, s.pts, part >= 1 ? s.pts.length : Math.max(2, Math.round(s.pts.length * part)))
                }
            }
            ctx.restore()
        }

    }

    // scan line
    Item {
        anchors.fill: parent
        clip: true
        visible: root.scanning
        Rectangle {
            id: beam
            width: parent.width
            height: 26
            opacity: 0.55
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.85; color: Theme.alpha(Theme.accent, 0.35) }
                GradientStop { position: 1.0; color: Theme.accent }
            }
            SequentialAnimation on y {
                running: root.scanning
                loops: Animation.Infinite
                NumberAnimation { from: -beam.height; to: root.height; duration: 1600; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 250 }
            }
        }
    }
}
