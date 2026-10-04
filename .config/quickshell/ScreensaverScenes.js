.pragma library
// Animated ASCII screensaver scenes (used by Screensaver.qml).
//
// A scene is { id, name, colors: [layer colours], init(ctx), frame(ctx, t, dt) }.
// frame() draws into ctx.layers (character grids, one per colour; spaces are
// transparent so layers stack) and may set ctx.title / ctx.sub / ctx.titleColor
// / ctx.titleOpacity. ctx: { cols, rows, asp (cell height / width), os, logo }.

// ------------------------------------------------------------------ grid
function Grid(c, r) {
    this.c = c; this.r = r; this.a = []
    for (let y = 0; y < r; y++) this.a.push(new Array(c).fill(" "))
}
Grid.prototype.clear = function () {
    for (let y = 0; y < this.r; y++) this.a[y].fill(" ")
}
Grid.prototype.put = function (x, y, ch) {
    x = Math.round(x); y = Math.round(y)
    if (x >= 0 && y >= 0 && x < this.c && y < this.r) this.a[y][x] = ch
}
Grid.prototype.get = function (x, y) {
    return (x >= 0 && y >= 0 && x < this.c && y < this.r) ? this.a[y][x] : " "
}
Grid.prototype.text = function (x, y, s) {
    for (let i = 0; i < s.length; i++) this.put(x + i, y, s[i])
}
Grid.prototype.center = function (y, s) { this.text(Math.floor((this.c - s.length) / 2), y, s) }
Grid.prototype.sprite = function (x, y, lines) {
    for (let j = 0; j < lines.length; j++)
        for (let i = 0; i < lines[j].length; i++)
            if (lines[j][i] !== " ") this.put(x + i, y + j, lines[j][i])
}
Grid.prototype.str = function () {
    let out = ""
    for (let y = 0; y < this.r; y++) out += this.a[y].join("") + (y < this.r - 1 ? "\n" : "")
    return out
}

function newLayers(ctx, n) {
    ctx.layers = []
    for (let i = 0; i < n; i++) ctx.layers.push(new Grid(ctx.cols, ctx.rows))
}
function clearAll(ctx) { for (const g of ctx.layers) g.clear() }

function rnd(a, b) { return a + Math.random() * (b - a) }
function irnd(a, b) { return Math.floor(rnd(a, b + 1)) }
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)] }
function clamp(v, a, b) { return v < a ? a : v > b ? b : v }
function fade(t, start, len) { return clamp((t - start) / len, 0, 1) }

// title helper: fade in at `at`, out at `until`
function title(ctx, t, text, sub, color, at, until) {
    ctx.title = text; ctx.sub = sub || ""; ctx.titleColor = color
    ctx.titleOpacity = Math.min(fade(t, at, 2), 1 - fade(t, until, 1.5))
}

const RAMP = " .:-=+*#%@"

// braille art -> dot image { w, h, dots[y][x] }. Each braille character is
// 2 x 4 dots: bits 0-2 and 6 are the left column, 3-5 and 7 the right.
function brailleDots(lines) {
    const DOT = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2], [0, 3], [1, 3]]
    const w = lines[0].length * 2, h = lines.length * 4
    const dots = []
    for (let y = 0; y < h; y++) dots.push(new Array(w).fill(false))
    for (let r = 0; r < lines.length; r++)
        for (let c = 0; c < lines[r].length; c++) {
            const m = lines[r].charCodeAt(c) - 0x2800
            for (let k = 0; k < 8; k++)
                if (m & (1 << k)) dots[r * 4 + DOT[k][1]][c * 2 + DOT[k][0]] = true
        }
    return { w: w, h: h, dots: dots }
}

// quarter blocks indexed by mask (1 top-left, 2 top-right, 4 bottom-left, 8 bottom-right)
const QUAD = " ▘▝▀▖▌▞▛▗▚▐▜▄▙▟█"

// ================================================================== HALF-LIFE
const halfLife = {
    id: "halflife", name: "Half-Life",
    colors: ["#ff8c1a", "#7a3f0a", "#d0d0d0", "#ffd9a8"],
    // the λ logo as braille art (80 x 80 dots). The font has no braille, so it
    // is decoded into a dot image and redrawn with quarter blocks at any size.
    logo: [
        "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣤⣴⣶⣾⣿⣿⣿⣿⣿⣿⣷⣶⣦⣤⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
        "⠀⠀⠀⠀⠀⠀⠀⠀⣀⣴⣾⣿⣿⣿⣿⣿⣿⣿⠿⠿⠿⠿⢿⣿⣿⣿⣿⣿⣿⣷⣦⣀⠀⠀⠀⠀⠀⠀⠀⠀",
        "⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⡿⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⢿⣿⣿⣿⣷⣄⡀⠀⠀⠀⠀⠀",
        "⠀⠀⠀⠀⣠⣾⣿⣿⣿⠟⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠻⣿⣿⣿⣷⣄⠀⠀⠀⠀",
        "⠀⠀⢀⣼⣿⣿⣿⠟⠁⠀⠀⠀⠀⠀⣶⣶⣶⣶⣶⣶⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣿⣧⡀⠀⠀",
        "⠀⢀⣾⣿⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢿⣿⣿⣷⡀⠀",
        "⠀⣾⣿⣿⡿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢿⣿⣿⣷⠀",
        "⢰⣿⣿⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣿⣿⣿⡆",
        "⣾⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⣿⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⣿⣷",
        "⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⣿⣿⣿⣿⣿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿",
        "⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣾⣿⣿⣿⣿⠛⣿⣿⣿⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿",
        "⢿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⣿⣿⣿⡿⠁⠀⢹⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⡿",
        "⠸⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⣰⣿⣿⣿⣿⡟⠁⠀⠀⠀⢻⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⣿⠇",
        "⠀⢿⣿⣿⣷⡄⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⠏⠀⠀⠀⠀⠀⠈⢿⣿⣿⣿⣧⣤⣶⣾⡆⠀⠀⢀⣾⣿⣿⡿⠀",
        "⠀⠈⢿⣿⣿⣿⡄⠀⠀⢀⣾⣿⣿⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⣿⣿⣿⣿⣿⣷⡀⢠⣾⣿⣿⡿⠁⠀",
        "⠀⠀⠈⢻⣿⣿⣿⣦⡀⠿⠿⠿⠿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⡿⠿⠿⠛⠋⠉⢀⣴⣿⣿⣿⡟⠁⠀⠀",
        "⠀⠀⠀⠀⠙⢿⣿⣿⣿⣦⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣴⣿⣿⣿⣿⠋⠀⠀⠀⠀",
        "⠀⠀⠀⠀⠀⠀⠙⢿⣿⣿⣿⣷⣦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣴⣾⣿⣿⣿⡿⠛⠁⠀⠀⠀⠀⠀",
        "⠀⠀⠀⠀⠀⠀⠀⠀⠉⠻⢿⣿⣿⣿⣿⣿⣿⣷⣶⣶⣶⣶⣾⣿⣿⣿⣿⣿⣿⡿⠟⠉⠀⠀⠀⠀⠀⠀⠀⠀",
        "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠻⢿⢿⣿⣿⣿⣿⣿⣿⡿⠿⠟⠛⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"
    ],
    boot: [
        "> HEV MARK IV PROTECTIVE SYSTEM",
        "> BOOT SEQUENCE INITIATED",
        "",
        "  ATMOSPHERIC CONTAMINANT SENSORS ....... ACTIVATED",
        "  VITAL SIGN MONITORING ................. ACTIVATED",
        "  AUTOMATIC MEDICAL SYSTEMS ............. ENGAGED",
        "  DEFENSIVE WEAPON SELECTION SYSTEM ..... ACTIVATED",
        "  MUNITION LEVEL MONITORING ............. ACTIVATED",
        "  COMMUNICATIONS INTERFACE .............. ONLINE",
        "",
        "> HAVE A VERY SAFE DAY.",
        "",
        "> BLACK MESA RESEARCH FACILITY",
        "> SECTOR C  ·  ANOMALOUS MATERIALS"
    ],
    init(ctx) {
        newLayers(ctx, 4)
        const img = brailleDots(this.logo)
        const sw = img.w, sh = img.h, dots = img.dots
        // size: about 80% of the height, kept round (a cell is asp times taller
        // than wide), and clear of the boot log on the left
        const C = ctx.cols, R = ctx.rows, asp = ctx.asp
        let L = Math.floor(Math.min(R * 0.8, (C * 0.5) / asp))
        const W = Math.round(L * asp)
        const x0 = Math.round(C - W - Math.max(4, C * 0.06)), y0 = Math.floor((R - L) / 2)
        // each cell is 2 x 2 quarter-block dots, sampled from the dot image
        const cells = []
        const qw = W * 2, qh = L * 2
        for (let y = 0; y < L; y++)
            for (let x = 0; x < W; x++) {
                let m = 0
                for (let q = 0; q < 4; q++) {
                    const dx = x * 2 + (q & 1), dy = y * 2 + (q >> 1)
                    const sx = Math.floor((dx + 0.5) / qw * sw), sy = Math.floor((dy + 0.5) / qh * sh)
                    if (dots[sy][sx]) m |= 1 << q
                }
                if (m) cells.push({ x: x0 + x, y: y0 + y, ch: QUAD[m],
                                    d: (x / W + y / L) / 2, n: Math.random() })
            }
        ctx.hl = { cells: cells, cx: x0 + W / 2, cy: y0 + L / 2, rad: L * 0.36 }
    },
    frame(ctx, t) {
        clearAll(ctx)
        const C = ctx.cols, R = ctx.rows, asp = ctx.asp, hl = ctx.hl
        // logo: dissolves in, then a bright band sweeps across it every 5 s
        const reveal = fade(t, 0.3, 2.2)
        const band = ((t - 2.5) % 5) / 5 * 1.6 - 0.3
        for (const c of hl.cells) {
            if (c.n > reveal) continue
            const fresh = reveal < 1 && c.n > reveal - 0.08
            const lit = t > 2.5 && Math.abs(c.d - band) < 0.06
            ctx.layers[fresh || lit ? 3 : 0].put(c.x, c.y, c.ch)
        }
        // faint sparks inside the ring
        const pulse = 0.5 + 0.5 * Math.sin(t * 1.5)
        for (let i = 0; i < 18 + pulse * 18; i++) {
            const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random()) * hl.rad
            const x = Math.round(hl.cx + Math.cos(a) * r * asp), y = Math.round(hl.cy + Math.sin(a) * r)
            if (ctx.layers[0].get(x, y) === " " && ctx.layers[3].get(x, y) === " ")
                ctx.layers[1].put(x, y, "·")
        }
        // boot log typing on the left
        const chars = Math.floor(t * 28)
        let used = 0
        const x0 = Math.max(2, Math.floor(C * 0.06)), y0 = Math.floor(R * 0.2)
        for (let i = 0; i < this.boot.length; i++) {
            const line = this.boot[i]
            const show = clamp(chars - used, 0, line.length)
            used += line.length + 4
            if (show <= 0 && line !== "") break
            const s = line.slice(0, show)
            const ok = s.match(/(ACTIVATED|ENGAGED|ONLINE)$/)
            ctx.layers[ok ? 0 : 2].text(x0, y0 + i, s)
            if (show < line.length && Math.floor(t * 3) % 2 === 0) ctx.layers[0].put(x0 + show, y0 + i, "▌")
        }
        title(ctx, t, "", "", "#ff8c1a", 0, 99)
    }
}

// ================================================================== OS (Chimera / Gentoo / Tux)
const osScene = {
    id: "os", name: "Linux",
    colors: ["#3d3d4a", "#e0e0e0", "#d6336c", "#888899"],
    log: [
        "[    0.000000] Linux version {kernel}",
        "[    0.000000] Command line: BOOT_IMAGE=/boot/vmlinuz root=UUID=… ro quiet",
        "[    0.012381] ACPI: Early table checksum verification disabled",
        "[    0.153920] smpboot: CPU0: 11th Gen Intel(R) Core(TM)",
        "[    0.402211] PCI: Using configuration type 1 for base access",
        "[    0.611874] clocksource: Switched to clocksource tsc-early",
        "[    1.004417] nvme nvme0: 8/0/0 default/read/poll queues",
        "[    1.229871] i915 0000:00:02.0: [drm] Initialized",
        "[    1.733102] EXT4-fs (nvme0n1p2): mounted filesystem",
        "[  OK  ] Started dinit service manager.",
        "[  OK  ] Started udevd.",
        "[  OK  ] Reached target local filesystems.",
        "[  OK  ] Started dbus.",
        "[  OK  ] Started elogind.",
        "[  OK  ] Started NetworkManager.",
        "[  OK  ] Started bluetoothd.",
        "[  OK  ] Started turnstiled.",
        "[  OK  ] Started greetd.",
        "[  OK  ] Reached target login.",
        "[    4.881032] wlan0: associated",
        "[    5.002917] niri: compositor started",
        "[    5.218004] quickshell: shell loaded"
    ],
    init(ctx) {
        newLayers(ctx, 4)
        this.logo = (ctx.logo || "").split("\n").filter((l, i, a) => l.trim() !== "" || (i > 0 && i < a.length - 1))
        this.lw = Math.max(1, ...this.logo.map(l => l.length))
        this.lines = []
        this.next = 0
    },
    frame(ctx, t) {
        clearAll(ctx)
        const C = ctx.cols, R = ctx.rows
        // boot log scrolling up the left, faint
        while (this.next < t * 3) {
            this.lines.push(this.log[this.lines.length % this.log.length].replace("{kernel}", ctx.kernel || "7.x"))
            this.next++
        }
        const visible = this.lines.slice(-R + 2)
        for (let i = 0; i < visible.length; i++) {
            const l = visible[i]
            const ok = l.indexOf("[  OK  ]") === 0
            ctx.layers[0].text(2, R - 1 - visible.length + i, l.slice(0, Math.floor(C * 0.6)))
            if (ok) ctx.layers[2].text(3, R - 1 - visible.length + i, " OK ")
        }
        // logo decodes in, then holds with a rare glitch
        const lx = Math.floor((C - this.lw) / 2) + Math.floor(C * 0.12), ly = Math.floor((R - this.logo.length) / 2) - 2
        const reveal = fade(t, 1.5, 4)
        const noise = "▓▒░#%&@"
        const glitchRow = Math.random() < 0.04 ? irnd(0, this.logo.length - 1) : -1
        for (let j = 0; j < this.logo.length; j++) {
            const line = this.logo[j]
            const off = j === glitchRow ? irnd(-3, 3) : 0
            for (let i = 0; i < line.length; i++) {
                if (line[i] === " ") continue
                const shown = ((i * 7 + j * 13) % 100) / 100 < reveal
                ctx.layers[1].put(lx + i + off, ly + j, shown ? line[i] : noise[irnd(0, noise.length - 1)])
            }
        }
        title(ctx, t, (ctx.osName || "LINUX").toUpperCase(), "uptime " + (ctx.uptime || ""), "#e0e0e0", 7, 54)
    }
}

// ================================================================== NARUTO
const naruto = {
    id: "naruto", name: "Naruto",
    colors: ["#b3001b", "#0d0d0d", "#e8e8e8", "#7a0012"],
    cloud: [
        "   .--.   .-.",
        " .(    )-(   ).",
        "(___.__)__)___)"
    ],
    init(ctx) {
        newLayers(ctx, 4)
        this.clouds = []
        for (let i = 0; i < 6; i++) this.clouds.push({ x: rnd(-20, ctx.cols), y: rnd(2, ctx.rows - 5), v: rnd(0.4, 1) })
    },
    frame(ctx, t) {
        clearAll(ctx)
        const C = ctx.cols, R = ctx.rows, asp = ctx.asp
        for (const c of this.clouds) {
            c.x += c.v * 0.5
            if (c.x > C) { c.x = -16; c.y = rnd(2, R - 5) }
            ctx.layers[3].sprite(c.x, c.y, this.cloud)
        }
        // sharingan: red iris, black pupil, three tomoe spinning
        const cx = C / 2, cy = R / 2, rad = Math.min(R * 0.38, C / asp * 0.25)
        const spin = t * 1.8
        for (let y = Math.floor(cy - rad); y <= cy + rad; y++)
            for (let x = Math.floor(cx - rad * asp); x <= cx + rad * asp; x++) {
                const dx = (x - cx) / asp, dy = y - cy, d = Math.sqrt(dx * dx + dy * dy) / rad
                if (d > 1) continue
                const a = Math.atan2(dy, dx)
                let tomoe = false
                for (let k = 0; k < 3; k++) {
                    const ta = spin + k * 2.094
                    const tx = Math.cos(ta) * 0.6, ty = Math.sin(ta) * 0.6
                    const ddx = dx / rad - tx, ddy = dy / rad - ty
                    if (ddx * ddx + ddy * ddy < 0.012) tomoe = true
                    // tail: a short arc trailing behind each tomoe
                    const da = ((a - ta) % 6.283 + 6.283) % 6.283
                    if (da > 5.75 && Math.abs(d - 0.62) < 0.05) tomoe = true
                }
                if (d > 0.95 || d < 0.16 || tomoe) ctx.layers[1].put(x, y, "█")
                else if (Math.abs(d - 0.6) < 0.025) ctx.layers[1].put(x, y, "·")
                else ctx.layers[0].put(x, y, d > 0.8 ? "▓" : "█")
            }
        title(ctx, t, "", "", "#b3001b", 0, 99)
    }
}

// ================================================================== DEATH NOTE
const deathNote = {
    id: "deathnote", name: "Death Note",
    colors: ["#2a2a2a", "#d8d8d8", "#7a1a1a", "#555555"],
    rules: [
        "HOW TO USE IT",
        "",
        "I.",
        "The human whose name is written in this note shall die.",
        "",
        "This note will not take effect unless the writer has the",
        "person's face in their mind when writing his or her name.",
        "",
        "If the cause of death is written within 40 seconds of",
        "writing the person's name, it will happen.",
        "",
        "If the cause of death is not specified, the person will",
        "simply die of a heart attack."
    ],
    init(ctx) { newLayers(ctx, 4) },
    frame(ctx, t) {
        clearAll(ctx)
        const C = ctx.cols, R = ctx.rows
        const w = Math.min(70, C - 6), x0 = Math.floor((C - w) / 2), y0 = 4
        for (let y = y0; y < R - 3; y += 2) ctx.layers[0].text(x0, y + 1, "_".repeat(w))
        for (let y = y0; y < R - 3; y++) ctx.layers[2].put(x0 + 5, y, "│")
        ctx.layers[1].center(1, "D E A T H   N O T E")
        let chars = Math.floor(t * 14), row = 0
        for (const line of this.rules) {
            const n = clamp(chars, 0, line.length)
            ctx.layers[line === "HOW TO USE IT" || line === "I." ? 2 : 1].text(x0 + 8, y0 + row * 2, line.slice(0, n))
            if (n < line.length && n >= 0) { ctx.layers[3].put(x0 + 8 + n, y0 + row * 2, "✎"); break }
            chars -= line.length + 6
            row++
        }
        title(ctx, t, "", "", "#d8d8d8", 0, 99)
    }
}

// ================================================================== GIF scenes
// Pre-rendered from screensaver/gifs by screensaver/gif2ascii.py; the engine
// loads the converted frames into ctx.gif before init(). Each palette colour
// is one layer. Scenes whose GIF is missing are skipped.
function gifScene(id, name, file, opts) {
    opts = opts || {}
    return {
        id: id, name: name, gif: file, convert: opts.convert || [], colors: [],
        init(ctx) {
            const d = ctx.gif
            this.colors = d.palette
            this.cache = []
            this.fi = 0
            this.acc = 0
        },
        layersFor(ctx, f) {
            if (this.cache[f]) return this.cache[f]
            const d = ctx.gif, fr = d.frames[f], w = d.w, pad = " ".repeat(d.x)
            const out = []
            for (let k = 0; k < d.palette.length; k++) {
                const lines = []
                for (let r = 0; r < d.rows; r++) {
                    if (r < d.y || r >= d.y + d.h) { lines.push(""); continue }
                    const o = (r - d.y) * w
                    let line = pad
                    for (let i = 0; i < w; i++) line += fr.k.charCodeAt(o + i) - 48 === k ? fr.c[o + i] : " "
                    lines.push(line.replace(/\s+$/, ""))
                }
                out.push(lines.join("\n"))
            }
            this.cache[f] = out
            return out
        },
        frame(ctx, t, dt) {
            const d = ctx.gif
            this.acc += dt * 1000
            while (this.acc >= Math.max(40, d.delays[this.fi] || 80)) {
                this.acc -= Math.max(40, d.delays[this.fi] || 80)
                this.fi = (this.fi + 1) % d.frames.length
            }
            ctx.raw = this.layersFor(ctx, this.fi)
            if (opts.title) {
                ctx.titleY = opts.titleY || 0.86
                title(ctx, t, opts.title, opts.sub || "", opts.color || "#e8e8e8", opts.at || 6, 54)
            } else title(ctx, t, "", "", "#ffffff", 0, 99)
        }
    }
}

const gifScenes = [
    gifScene("fa-gear", "Factorio", "factorio-gear.gif", { title: "THE FACTORY MUST GROW", color: "#e0a33a", titleY: 0.9 }),
    gifScene("fa-engineer", "Factorio · Engineer", "factorio-engineer.gif"),
    // the console's boot screen: crop to the logo and title, drop the grey background
    gifScene("n64", "Nintendo 64", "nintendo-64.gif", { convert: ["8", "crop=380x228+40+0", "key=auto", "keytol=70"] }),
    gifScene("htb", "Hack The Box", "hackthebox.gif", { convert: ["8", "key=alpha", "size=0.85"] }),
    // still logos: the converter adds a slow bob and a light sweep
    gifScene("emacs", "GNU Emacs", "emacs.png", { convert: ["8", "key=alpha", "still=1", "size=0.75"] }),
    gifScene("vim", "Vim", "vim.png", { convert: ["8", "key=alpha,#000000", "keytol=60", "still=1", "size=0.75"] }),
    // these two have a checkerboard baked in where the transparency was
    gifScene("fa-reactor", "Factorio · Nuclear Reactor", "factorio-reactor.gif",
             { convert: ["8", "key=#3b3b3b,#454545,#404040", "keytol=16"] }),
    gifScene("fa-building", "Factorio", "factorio-building.gif",
             { convert: ["8", "key=#3b3b3b,#454545", "keytol=10"] }),
    gifScene("fa-spin", "Factorio · Gear", "factorio-spinning-gear.gif", { convert: ["8", "key=alpha", "size=0.9"] }),
    gifScene("headcrab", "Half-Life · Headcrab", "headcrab.gif", { convert: ["8", "key=auto", "keytol=40"] }),
    gifScene("bb-doll", "Bloodborne · The Doll", "bloodborne-doll.gif", { convert: ["8", "key=alpha", "pixel=1"] }),
    gifScene("ds-bonfire", "Dark Souls · Bonfire", "bonfire.gif", { convert: ["8", "key=alpha", "pixel=1"] })
]

// hand-drawn scenes
const scenes = [halfLife, osScene, naruto, deathNote].concat(gifScenes)

function list() { return scenes.map(s => s.id) }
function get(id) { return scenes.find(s => s.id === id) || scenes[0] }
function gifs() { return gifScenes.map(s => ({ id: s.id, file: s.gif, convert: s.convert })) }

function render(ctx) {
    if (ctx.raw) return ctx.raw
    return ctx.layers.map(g => g.str())
}
