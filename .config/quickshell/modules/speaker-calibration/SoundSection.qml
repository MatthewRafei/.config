import QtQuick
import Quickshell
import qs
import qs.widgets

// Speaker calibration (../root.service.qml, backend in ../speaker/), shown at the
// bottom of Settings > Sound: measure the speakers with a mic, the EQ it
// fitted, loudness / deep bass switches, check, A/B against the previous one.
Column {
    id: root
    property var service
    width: parent ? parent.width : 0
    spacing: 4

    Component.onCompleted: root.service.refresh()
    Timer { id: copied; interval: 1500 }

    component Head: Item {
        id: head
        property string title
        property bool on: true
        property bool showRescan: false
        property bool showToggle: true
        signal toggled()
        signal rescan()

        width: parent.width
        height: 26

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 3
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                visible: head.showRescan && (head.on || !head.showToggle)
                width: 26; height: 22
                radius: Theme.radius
                color: rescanMouse.containsMouse ? Theme.bgCard : "transparent"
                border.color: rescanMouse.containsMouse ? Theme.accent : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: rescanMouse.containsMouse ? Theme.accent : Theme.textDim
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: rescanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: head.rescan()
                }
            }

            Rectangle {
                visible: head.showToggle
                width: 44; height: 22
                radius: Theme.radius
                color: head.on ? Theme.alpha(Theme.accent, 0.15) : "transparent"
                border.color: head.on ? Theme.accent : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: head.on ? "ON" : "OFF"
                    color: head.on ? Theme.accent : Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 1
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: head.toggled()
                }
            }
        }
    }

    component Label2: Text {
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 2
        topPadding: 6
    }

    component Row2: Rectangle {
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

    // ================================================================ speaker EQ graph
    // magnitude of one RBJ biquad section at `f`, in dB
    function biquadDb(b0, b1, b2, a0, a1, a2, w) {
        const c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w)
        const nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2)
        const dr = a0 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2)
        return 10 * Math.log10(Math.max((nr * nr + ni * ni) / Math.max(dr * dr + di * di, 1e-24), 1e-24))
    }
    function sectionDb(shape, f, corner, q, gain) {
        const rate = 48000
        const w0 = 2 * Math.PI * corner / rate, alpha = Math.sin(w0) / (2 * Math.max(q, 0.05))
        const c = Math.cos(w0), w = 2 * Math.PI * f / rate, A = Math.pow(10, gain / 40)
        const r2 = 2 * Math.sqrt(A) * alpha
        if (shape === "highpass")
            return biquadDb((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha, w)
        if (shape === "lowshelf")
            return biquadDb(A * ((A + 1) - (A - 1) * c + r2), 2 * A * ((A - 1) - (A + 1) * c),
                            A * ((A + 1) - (A - 1) * c - r2), (A + 1) + (A - 1) * c + r2,
                            -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - r2, w)
        if (shape === "highshelf")
            return biquadDb(A * ((A + 1) + (A - 1) * c + r2), -2 * A * ((A - 1) + (A + 1) * c),
                            A * ((A + 1) + (A - 1) * c - r2), (A + 1) - (A - 1) * c + r2,
                            2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - r2, w)
        return biquadDb(1 + alpha * A, -2 * c, 1 - alpha * A, 1 + alpha / A, -2 * c, 1 - alpha / A, w)
    }
    function paintEq(ctx, w, h, fit) {
        ctx.reset()
        if (!fit) return
        const sections = []
        const hp = fit.highpass || {}
        for (let i = 0; i < Number(hp.stages || fit.highpass_stages || 2); i++)
            sections.push({ shape: "highpass", f: Number(hp.frequency_hz || fit.highpass_hz || 55), q: Number(hp.q || 0.707), g: 0, node: false })
        for (const it of (fit.filters || []))
            sections.push({ shape: it.type || "peaking", f: Number(it.frequency_hz), q: Number(it.q), g: Number(it.gain_db), node: true })
        if (fit.bass_shelf)
            sections.push({ shape: "lowshelf", f: Number(fit.bass_shelf.frequency_hz), q: Number(fit.bass_shelf.q), g: Number(fit.bass_shelf.gain_db), node: true })

        const pl = 24, pr = 4, pt = 6, pb = 14
        const fmin = 30, fmax = 20000, dmin = -18, dmax = 9
        const X = f => pl + Math.log(f / fmin) / Math.log(fmax / fmin) * (w - pl - pr)
        const Y = d => pt + (dmax - Math.max(dmin, Math.min(dmax, d))) / (dmax - dmin) * (h - pt - pb)
        const N = 140, fs = []
        for (let p = 0; p < N; p++) fs.push(fmin * Math.pow(fmax / fmin, p / (N - 1)))

        ctx.font = "8px '" + Theme.fontFamily + "'"
        ctx.lineWidth = 1
        ctx.textAlign = "right"; ctx.textBaseline = "middle"
        for (let d = dmin; d <= dmax; d += 3) {
            ctx.strokeStyle = Theme.css(Theme.textFaint, d === 0 ? 0.8 : 0.25)
            ctx.beginPath(); ctx.moveTo(pl, Y(d)); ctx.lineTo(w - pr, Y(d)); ctx.stroke()
            if (d % 6 === 0) { ctx.fillStyle = Theme.css(Theme.textFaint, 1); ctx.fillText((d > 0 ? "+" : "") + d, pl - 4, Y(d)) }
        }
        ctx.textAlign = "center"; ctx.textBaseline = "top"
        const ticks = [[50, "50"], [100, "100"], [200, "200"], [500, "500"], [1000, "1k"], [2000, "2k"], [5000, "5k"], [10000, "10k"]]
        for (const [f, l] of ticks) {
            ctx.strokeStyle = Theme.css(Theme.textFaint, 0.25)
            ctx.beginPath(); ctx.moveTo(X(f), pt); ctx.lineTo(X(f), h - pb); ctx.stroke()
            ctx.fillStyle = Theme.css(Theme.textFaint, 1); ctx.fillText(l, X(f), h - pb + 3)
        }

        const sum = fs.map(() => 0)
        for (const s of sections) {
            const curve = fs.map(f => sectionDb(s.shape, f, s.f, s.q, s.g))
            curve.forEach((v, i) => sum[i] += v)
            if (!s.node) continue
            ctx.fillStyle = Theme.css(Theme.accent2, 0.10)
            ctx.strokeStyle = Theme.css(Theme.accent2, 0.45)
            ctx.beginPath(); ctx.moveTo(X(fs[0]), Y(0))
            curve.forEach((v, i) => ctx.lineTo(X(fs[i]), Y(v)))
            ctx.lineTo(X(fs[N - 1]), Y(0)); ctx.closePath(); ctx.fill()
            ctx.beginPath(); curve.forEach((v, i) => i ? ctx.lineTo(X(fs[i]), Y(v)) : ctx.moveTo(X(fs[i]), Y(v))); ctx.stroke()
        }
        // what the speakers actually get
        ctx.strokeStyle = Theme.css(Theme.accent, 1)
        ctx.lineWidth = 2
        ctx.beginPath(); sum.forEach((v, i) => i ? ctx.lineTo(X(fs[i]), Y(v)) : ctx.moveTo(X(fs[i]), Y(v))); ctx.stroke()
        // input gain ahead of the limiter
        const net = Number(fit.net_input_gain_db !== undefined ? fit.net_input_gain_db : -(fit.headroom_db || 1))
        ctx.setLineDash([3, 3]); ctx.lineWidth = 1
        ctx.strokeStyle = Theme.css(Theme.textDim, 0.8)
        ctx.beginPath(); ctx.moveTo(pl, Y(net)); ctx.lineTo(w - pr, Y(net)); ctx.stroke()
        ctx.setLineDash([])
        ctx.fillStyle = Theme.css(Theme.textDim, 1); ctx.textAlign = "left"; ctx.textBaseline = "bottom"
        ctx.fillText("gain " + (net > 0 ? "+" : "") + net.toFixed(1) + " dB", pl + 3, Y(net) - 1)
    }

    Column {
        id: spk
            width: parent.width
        spacing: 4
        property bool armed: false      // two clicks to remove the calibration
        Timer { id: spkDisarm; interval: 3000; onTriggered: spk.armed = false }

        Head {
            title: "// SPEAKER CALIBRATION"
            on: root.service.enabled && !root.service.bypassed
            showToggle: root.service.calibrated
            showRescan: true
            onToggled: if (!root.service.busy) {
                if (!root.service.enabled) root.service.useCalibratedOutput()
                else root.service.bypass()
            }
            onRescan: root.service.refresh()
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        Text {
            id: spkMsg
            width: parent.width
            wrapMode: Text.Wrap
            text: root.service.working || root.service.message === "" ? root.service.summary() : root.service.message
            color: root.service.working ? Theme.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
            topPadding: 4
            SequentialAnimation on opacity {
                running: root.service.working
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) spkMsg.opacity = 1
            }
        }
        Text {
            visible: root.service.error !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.service.error
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }
        Text {
            visible: !root.service.working && root.service.qualityText() !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.service.qualityText()
            color: Theme.danger
            font.family: Theme.fontFamily
            font.pixelSize: 8
        }
        // a failure can suggest another microphone, for this run only
        Row2 {
            readonly property int offered: root.service.offer ? root.service.indexOf(root.service.microphones, root.service.offer.microphone) : -1
            visible: offered >= 0 && !root.service.busy
            height: 30
            icon: "󰍬"
            label: offered >= 0 ? "Measure with " + root.service.microphones[offered].description + " instead" : ""
            onClicked: root.service.calibrate(root.service.microphones[offered].name,
                root.service.microphones[offered].internal && Number(root.service.microphones[offered].channels || 1) > 1 ? "all" : 0)
        }

        // what measuring still needs
        Column {
            visible: !root.service.canMeasure
            width: parent.width
            spacing: 4
            Label2 { text: "MISSING  ·  " + (root.service.support.missing || []).join("  ").toUpperCase(); color: Theme.danger }
            Text {
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: root.service.support.command || ""
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 8
            }
            Row2 {
                height: 30
                icon: root.service.support.fixable ? "󰄠" : "󰆏"
                label: root.service.support.fixable ? "Install numpy + scipy (venv)" : "Copy the command"
                tag: !root.service.support.fixable && copied.running ? "COPIED" : ""
                busy: root.service.busy && root.service.phase === "support"
                onClicked: {
                    if (root.service.support.fixable) root.service.installSupport()
                    else { root.service.copy(root.service.support.command); copied.restart() }
                }
            }
        }

        // a new calibration plays and waits for a decision
        Column {
            visible: root.service.previewing
            width: parent.width
            spacing: 2
            Label2 { text: "NEW CALIBRATION  ·  KEEP IT?"; color: Theme.accent }
            Row2 {
                height: 30; icon: "󰄬"; label: "Apply the new calibration"
                busy: root.service.busy && root.service.phase === "previewapply"
                onClicked: if (!root.service.busy) root.service.applyPreview()
            }
            Row2 {
                height: 30; icon: "󰕍"; label: "Keep the previous one"
                busy: root.service.busy && root.service.phase === "previewdiscard"
                onClicked: if (!root.service.busy) root.service.discardPreview()
            }
            Row2 {
                visible: (root.service.status.compare || {}).available === true
                height: 30; icon: "󰓦"
                label: (root.service.status.compare || {}).active === "previous" ? "Hear the new one" : "Hear the previous one"
                detail: "LEVEL MATCHED"
                busy: root.service.busy && root.service.phase === "compare"
                onClicked: if (!root.service.busy) root.service.compare()
            }
        }

        // sound went to another output (headphones, an app)
        Row2 {
            visible: root.service.calibrated && !root.service.enabled && root.service.status.service === "active"
            height: 30
            icon: "󰓃"
            label: "Play through Calibrated Speakers"
            busy: root.service.busy && root.service.phase === "output"
            onClicked: if (!root.service.busy) root.service.useCalibratedOutput()
        }

        // the EQ the calibration applies: each section faint, their sum bright
        Label2 {
            visible: eq.visible
            text: "EQUALIZER" + (root.service.bypassed ? "  ·  SWITCHED OFF" : "  ·  " + ((root.service.profile || {}).fit || {}).filter_count + " SECTIONS")
        }
        Canvas {
            id: eq
            readonly property var fit: root.service.profile ? root.service.profile.fit : null
            visible: fit !== null && fit !== undefined
            width: parent.width
            height: 110
            opacity: root.service.bypassed ? 0.35 : 1
            onFitChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()
            onWidthChanged: requestPaint()
            Connections {
                target: Theme
                function onAccentChanged() { eq.requestPaint() }
            }
            onPaint: root.paintEq(getContext("2d"), width, height, fit)
        }

        Column {
            visible: root.service.calibrated
            width: parent.width
            spacing: 2
            Label2 { text: "SOUND" }
            Row2 {
                height: 30; icon: "󰓃"; label: "Loudness  ·  fuller, more bass"
                active: root.service.bass === "full"; tag: active ? "ON" : ""; detail: "OFF"
                busy: root.service.busy && root.service.phase === "relevel"
                onClicked: root.service.setBass(root.service.bass !== "full")
            }
            Row2 {
                height: 30; icon: "󰝝"; label: "Make it louder"
                active: root.service.loudness !== "protected"; tag: active ? "ON" : ""; detail: "OFF"
                onClicked: root.service.setLouder(root.service.loudness === "protected")
            }
            Row2 {
                height: 30; icon: "󰋋"; label: "Deep bass  ·  virtual low notes"
                active: root.service.status.deepBass === "on"; tag: active ? "ON" : ""; detail: "OFF"
                busy: root.service.busy && root.service.phase === "deepbass"
                onClicked: if (!root.service.busy) root.service.deepBass()
            }
            Row2 {
                height: 30; icon: "󰕾"; label: "Follow volume  ·  ISO 226 loudness"
                active: root.service.status.loudnessCompensation === "on"
                tag: active ? (root.service.status.loudnessTracker === "running" ? "ON" : "ON · STALLED") : ""
                detail: "OFF"
                busy: root.service.busy && root.service.phase === "loudness"
                onClicked: if (!root.service.busy) root.service.loudnessCompensation()
            }
            Row2 {
                height: 30; icon: "󰔏"; label: "Voicing"
                tag: root.service.voicing === "warm" ? "WARM" : ""; detail: "FLAT"
                busy: root.service.busy && root.service.phase === "refit"
                onClicked: root.service.setVoicing(root.service.voicing === "warm" ? "neutral" : "warm")
            }

            Label2 { text: "CHECK" }
            Text {
                visible: !!root.service.status.verification
                width: parent.width
                wrapMode: Text.Wrap
                text: root.service.verificationSummary(root.service.status.verification)
                color: root.service.status.verification && !root.service.status.verification.stale
                       && root.service.status.verification.verdict === "fail" ? Theme.danger : Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 9
                bottomPadding: 2
            }
            Row2 {
                height: 30; icon: "󰗠"
                label: "Check the calibration"
                detail: root.service.profileMicConnected ? "SWEEPS AGAIN" : "ITS MIC IS UNPLUGGED"
                opacity: root.service.profileMicConnected && root.service.canMeasure ? 1 : 0.45
                busy: root.service.busy && root.service.phase === "verify"
                onClicked: if (!root.service.busy && root.service.profileMicConnected && root.service.canMeasure) root.service.verify()
            }
            Row2 {
                visible: !!root.service.status.verification && !root.service.status.verification.stale
                         && root.service.status.verification.verdict !== "inconclusive"
                height: 30; icon: "󰁨"
                label: "Improve from the check"
                busy: root.service.busy && root.service.phase === "refine"
                onClicked: if (!root.service.busy) root.service.refine()
            }
        }

        Label2 { text: "SPEAKERS" }
        Repeater {
            model: root.service.sinks
            Row2 {
                required property var modelData
                required property int index
                height: 30
                icon: /head|line/i.test(modelData.description) ? "󰋋"
                    : /hdmi|displayport/i.test(modelData.description) ? "󰍹" : "󰓃"
                label: modelData.description
                active: index === root.service.sinkIndex
                detail: (root.service.profile && (root.service.profile.speaker || {}).name === modelData.name) ? "CALIBRATED" : ""
                onClicked: if (!root.service.busy) root.service.pickSink(index)
            }
        }

        Label2 { text: "MICROPHONE  ·  AT YOUR SEAT" }
        Repeater {
            model: root.service.microphones
            Row2 {
                required property var modelData
                required property int index
                readonly property int chans: Math.max(1, Number(modelData.channels || 1))
                height: 30
                icon: "󰍬"
                label: modelData.description
                active: index === root.service.micIndex
                opacity: modelData.available === false ? 0.45 : 1
                // a multi-channel interface: click again to step through its inputs
                tag: active && chans > 1 ? (root.service.micArray ? "ALL " + chans : "CH " + (root.service.channel + 1) + "/" + chans) : ""
                detail: modelData.available === false ? "EMPTY JACK"
                      : modelData.silenced ? "MUTED"
                      : modelData.internal ? "BUILT-IN" : ""
                onClicked: if (!root.service.busy) root.service.pickMic(index)
            }
        }
        Text {
            visible: (root.service.status.unusableMicrophones || []).length > 0
            width: parent.width
            wrapMode: Text.Wrap
            text: (root.service.status.unusableMicrophones || []).join(", ") + ": headset mics can't measure speakers"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 8
        }

        Item { width: 1; height: 4 }

        Rectangle {
            id: calBtn
            readonly property bool usable: !root.service.busy && root.service.canMeasure && root.service.sink !== null && root.service.mic !== null
            width: parent.width
            height: 40
            radius: Theme.radius
            opacity: usable || root.service.measuring ? 1 : 0.45
            color: Theme.alpha(Theme.accent, calMouse.containsMouse && usable ? 0.22 : 0.12)
            border.color: Theme.accent
            Row {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    id: spkIcon
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰊚"
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 16
                    RotationAnimation on rotation {
                        running: root.service.measuring
                        from: 0; to: 360; duration: 1600; loops: Animation.Infinite
                        onRunningChanged: if (!running) spkIcon.rotation = 0
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.service.measuring ? "MEASURING  ·  KEEP QUIET"
                        : root.service.calibrated ? "CALIBRATE AGAIN" : "CALIBRATE SPEAKERS"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 2
                }
            }
            MouseArea {
                id: calMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: calBtn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (calBtn.usable) root.service.calibrate()
            }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "SIX SWEEPS  ·  ~30 S  ·  PAUSE MUSIC, KEEP THE ROOM QUIET"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 8
            font.letterSpacing: 1
            topPadding: 2
        }

        Row2 {
            visible: root.service.calibrated && root.service.status.service === "active"
            height: 30
            icon: "󰅖"
            label: "Remove the calibration"
            tag: spk.armed ? "CLICK AGAIN" : ""
            busy: root.service.busy && root.service.phase === "disable"
            onClicked: {
                if (root.service.busy) return
                if (spk.armed) { spk.armed = false; root.service.disable() }
                else { spk.armed = true; spkDisarm.restart() }
            }
        }
    }
}
