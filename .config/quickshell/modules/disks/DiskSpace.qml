import QtQuick
import Quickshell
import qs
import qs.widgets

// Settings > Disks > SPACE: how full each filesystem is, and what's filling
// it (../root.lens.qml). Scan a folder, then read it as a treemap (each box is
// as big as what it holds, folders show their own contents inside) or as a
// ranked list. Click to select, double-click a folder to go in, right-click
// to open it in the file manager. Nothing is deleted: Trash is one item at a
// time, after a second click.
Column {
    id: root
    property var lens
    width: parent ? parent.width : 0
    spacing: 12

    property string view: "map"        // map | list
    property string selected: ""       // child name of the folder on screen
    property string hovered: ""        // "name" or "name/child" under the mouse
    property bool armTrash: false
    Timer { id: disarm; interval: 4000; onTriggered: root.armTrash = false }

    Component.onCompleted: root.lens.refreshMounts()
    Connections {
        target: root.lens
        function onNodeChanged() { root.selected = ""; root.armTrash = false; map.requestPaint() }
        function onResultChanged() { map.requestPaint() }
    }

    readonly property var node: root.lens.node
    // the folder's entries, biggest first, with the rest as one entry
    readonly property var items: {
        const n = node
        if (!n) return []
        const out = []
        const c = n.c || []
        for (let i = 0; i < c.length; i++) if (c[i].s > 0) out.push(c[i])
        out.sort((a, b) => b.s - a.s)
        if (n.r > 0) out.push({ n: "smaller items", s: n.r, rest: true })
        return out
    }
    readonly property var selNode: {
        for (let i = 0; i < items.length; i++) if (items[i].n === selected && !items[i].rest) return items[i]
        return null
    }

    // ------------------------------------------------------------ colours
    function kind(it) {
        if (it.rest) return "rest"
        if (it.d) return "dir"
        const ext = (it.n.match(/\.([^.]+)$/) || ["", ""])[1].toLowerCase()
        if (/^(mp4|mkv|webm|avi|mov|m4v|wmv|flv|ts)$/.test(ext)) return "video"
        if (/^(png|jpe?g|webp|gif|heic|avif|raw|cr2|nef|arw|dng|tiff?|bmp|psd|kra|xcf)$/.test(ext)) return "image"
        if (/^(flac|mp3|ogg|opus|wav|m4a|aac|aiff?|wv)$/.test(ext)) return "audio"
        if (/^(zip|tar|gz|tgz|xz|zst|bz2|7z|rar|iso|img|qcow2|vdi|vmdk|deb|rpm|appimage|pak|vpk)$/.test(ext)) return "archive"
        return "file"
    }
    function colour(k) {
        return k === "dir" ? Theme.accent : k === "video" ? Theme.accent2 : k === "image" ? Theme.ok
             : k === "audio" ? Qt.hsla(0.58, 0.6, 0.62, 1) : k === "archive" ? Theme.danger
             : k === "rest" ? Theme.textFaint : Theme.textDim
    }
    readonly property var legend: [["dir", "folders"], ["video", "video"], ["image", "images"], ["audio", "audio"],
                                   ["archive", "archives / disk images"], ["file", "other files"]]

    // ------------------------------------------------------------ treemap
    // squarified layout (Bruls, Huizing, van Wijk): rows of near-square boxes
    function squarify(list, x, y, w, h) {
        const out = []
        let total = 0
        for (const it of list) total += it.s
        if (total <= 0 || w < 1 || h < 1) return out
        const areas = list.map(it => it.s / total * w * h)
        let rect = { x: x, y: y, w: w, h: h }, row = [], start = 0, i = 0
        const worst = (r, side) => {
            let s = 0, mx = 0, mn = Infinity
            for (const a of r) { s += a; mx = Math.max(mx, a); mn = Math.min(mn, a) }
            return Math.max(side * side * mx / (s * s), (s * s) / (side * side * mn))
        }
        const place = () => {
            let s = 0
            for (const a of row) s += a
            const horizontal = rect.w >= rect.h
            const thick = horizontal ? s / rect.h : s / rect.w
            let off = 0
            row.forEach((a, k) => {
                const len = a / thick
                out.push(horizontal ? { it: list[start + k], x: rect.x, y: rect.y + off, w: thick, h: len }
                                    : { it: list[start + k], x: rect.x + off, y: rect.y, w: len, h: thick })
                off += len
            })
            if (horizontal) { rect.x += thick; rect.w -= thick } else { rect.y += thick; rect.h -= thick }
            start += row.length
            row = []
        }
        while (i < areas.length) {
            const side = Math.min(rect.w, rect.h)
            if (row.length === 0 || worst(row.concat([areas[i]]), side) <= worst(row, side)) { row.push(areas[i]); i++ }
            else place()
        }
        if (row.length) place()
        return out
    }
    // boxes for the folder on screen, plus each big folder's own contents inside it
    property var boxes: []
    function layout(w, h) {
        const all = []
        // folders show their own contents inside, as deep as the boxes have room
        const nest = (b, depth, top) => {
            b.depth = depth
            b.parent = top
            all.push(b)
            if (!b.it.d || depth >= 3 || b.w < 46 || b.h < 34) return
            const inner = []
            const c = b.it.c || []
            for (let i = 0; i < c.length; i++) if (c[i].s > 0) inner.push(c[i])
            inner.sort((a, q) => q.s - a.s)
            if (b.it.r > 0) inner.push({ n: "smaller items", s: b.it.r, rest: true })
            for (const k of squarify(inner, b.x + 3, b.y + 16, b.w - 6, b.h - 19))
                nest(k, depth + 1, top)
        }
        for (const b of squarify(items, 0, 0, w, h)) nest(b, 0, "")
        boxes = all
    }
    // hover / right-click name for a box: its top-level folder, then the box
    function boxName(b) { return b.depth === 0 ? b.it.n : b.parent + "/…/" + b.it.n }
    function hit(x, y) {
        let found = null
        for (const b of boxes) if (x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h) found = b
        return found
    }

    // ------------------------------------------------------------ pieces
    component Chip: Rectangle {
        id: chip
        property string label
        property bool current: false
        property bool danger: false
        signal clicked()
        width: Math.max(chipText.implicitWidth + 20, 44)
        height: 26
        radius: Theme.radius
        color: current ? Theme.alpha(danger ? Theme.danger : Theme.accent, 0.14) : chipMouse.containsMouse ? Theme.bgCard : "transparent"
        border.width: 1
        border.color: current || chipMouse.containsMouse ? (danger ? Theme.danger : Theme.accent) : Theme.border
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.danger ? Theme.danger : chip.current ? Theme.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: chip.current || chip.danger
            font.letterSpacing: 1
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    Text {
        text: "// SPACE"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.letterSpacing: 3
    }

    // each filesystem: how full, click to scan it
    Repeater {
        model: root.lens.mounts
        delegate: Item {
            id: mrow
            required property var modelData
            readonly property real frac: modelData.used / modelData.total
            width: root.width
            height: 30
            MouseArea {
                id: mMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.lens.scan(mrow.modelData.mount)
            }
            Text {
                id: mName
                width: 120
                elide: Text.ElideMiddle
                text: mrow.modelData.mount
                color: mMouse.containsMouse ? Theme.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                anchors.left: mName.right
                anchors.leftMargin: 10
                anchors.right: mInfo.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: Theme.trackBg
                Rectangle {
                    width: parent.width * Math.min(1, mrow.frac)
                    height: parent.height
                    radius: 3
                    color: mrow.frac > 0.9 ? Theme.danger : mrow.frac > 0.75 ? Theme.accent2 : Theme.accent
                }
            }
            Text {
                id: mInfo
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 190
                horizontalAlignment: Text.AlignRight
                text: root.lens.fmt(mrow.modelData.free) + " free of " + root.lens.fmt(mrow.modelData.total)
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
    }

    // what to scan
    Row {
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 96
            text: "SCAN"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.letterSpacing: 2
        }
        Chip {
            label: "HOME"
            current: root.lens.result && root.lens.result.root === Quickshell.env("HOME")
            onClicked: root.lens.scan(Quickshell.env("HOME"))
        }
        Repeater {
            model: root.lens.mounts.filter(m => m.mount !== "/boot/efi")
            Chip {
                required property var modelData
                label: modelData.mount.toUpperCase()
                current: root.lens.result && root.lens.result.root === modelData.mount
                onClicked: root.lens.scan(modelData.mount)
            }
        }
        HudField {
            width: 200
            height: 26
            placeholder: "or a folder, then ↵"
            onAccepted: { const t = text.trim(); if (t) { root.lens.scan(t); text = "" } }
        }
    }

    // scanning / last scan
    Item {
        width: root.width
        height: 20
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - stopChip.width - 10
            elide: Text.ElideMiddle
            text: root.lens.scanning
                ? "SCANNING " + root.lens.scanTarget + "   ·   " + (root.lens.progress
                    ? root.lens.fmt(root.lens.progress.bytes) + "  ·  " + root.lens.progress.files.toLocaleString(Qt.locale(), "f", 0) + " files  ·  " + root.lens.progress.at
                    : "starting…")
                : root.lens.error !== "" ? root.lens.error
                : root.lens.result ? "Scanned " + root.lens.result.root + "  ·  " + root.lens.result.files.toLocaleString(Qt.locale(), "f", 0)
                    + " files in " + root.lens.result.seconds + " s  ·  " + Qt.formatDateTime(new Date(root.lens.result.at * 1000), "d MMM hh:mm")
                    + (root.lens.result.errors ? "  ·  " + root.lens.result.errors + " unreadable (partial)" : "")
                : "Pick a filesystem or folder to see what's using the space. Hidden folders are included."
            color: root.lens.scanning ? Theme.accent : root.lens.error !== "" ? Theme.danger : Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 10
            SequentialAnimation on opacity {
                running: root.lens.scanning
                loops: Animation.Infinite
                NumberAnimation { to: 0.5; duration: 700 }
                NumberAnimation { to: 1; duration: 700 }
            }
        }
        Chip {
            id: stopChip
            visible: root.lens.scanning
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "CANCEL"
            onClicked: root.lens.cancel()
        }
    }

    // ------------------------------------------------------------ result
    Column {
        visible: root.lens.node !== null
        width: root.width
        spacing: 10

        // where we are, and how to see it
        Item {
            width: parent.width
            height: 26
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Chip {
                    visible: root.lens.path.length > 0
                    label: "←"
                    onClicked: root.lens.up(1)
                }
                Repeater {
                    model: root.lens.result ? [root.lens.result.root].concat(root.lens.path) : []
                    Row {
                        required property string modelData
                        required property int index
                        spacing: 4
                        Text {
                            visible: parent.index > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "/"
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData
                            color: parent.index === root.lens.path.length ? Theme.text : crumbMouse.containsMouse ? Theme.accent : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: parent.index === root.lens.path.length
                            MouseArea {
                                id: crumbMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.lens.goTo(parent.parent.index)
                            }
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 10
                    text: root.lens.node ? root.lens.fmt(root.lens.node.s) : ""
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Chip { label: "MAP"; current: root.view === "map"; onClicked: { root.view = "map"; map.requestPaint() } }
                Chip { label: "LIST"; current: root.view === "list"; onClicked: root.view = "list" }
            }
        }

        // the treemap
        Rectangle {
            visible: root.view === "map"
            width: parent.width
            height: 320
            radius: Theme.radius
            color: Theme.bgCard
            border.color: Theme.border
            clip: true

            Canvas {
                id: map
                anchors.fill: parent
                anchors.margins: 2
                onWidthChanged: requestPaint()
                onPaint: {
                    root.layout(width, height)
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.font = "9px '" + Theme.fontFamily + "'"
                    ctx.textBaseline = "top"
                    for (const b of root.boxes) {
                        const k = root.kind(b.it)
                        const c = root.colour(k)
                        const sel = b.depth === 0 && b.it.n === root.selected && !b.it.rest
                        const hov = root.boxName(b) === root.hovered
                        ctx.fillStyle = Theme.css(c, b.it.d ? 0.08 : (hov ? 0.6 : 0.34))
                        ctx.fillRect(b.x + 1, b.y + 1, Math.max(0, b.w - 2), Math.max(0, b.h - 2))
                        ctx.lineWidth = sel ? 2 : 1
                        ctx.strokeStyle = sel ? Theme.css(Theme.text, 1) : Theme.css(c, hov || b.depth === 0 ? 0.8 : 0.45)
                        ctx.strokeRect(b.x + 1, b.y + 1, Math.max(0, b.w - 2), Math.max(0, b.h - 2))
                        // labels where they fit
                        if (b.depth === 0 && b.w > 50 && b.h > 14) {
                            ctx.fillStyle = Theme.css(Theme.text, 0.95)
                            const label = b.it.n + "  " + root.lens.fmt(b.it.s)
                            ctx.fillText(label.length * 5.6 > b.w - 8 ? b.it.n.slice(0, Math.max(1, Math.floor((b.w - 14) / 5.6))) + "…" : label, b.x + 5, b.y + 4)
                        } else if (b.depth > 0 && b.it.d && b.w > 60 && b.h > 24) {
                            ctx.fillStyle = Theme.css(Theme.text, 0.7)
                            ctx.fillText(b.it.n.length * 5.6 > b.w - 8 ? b.it.n.slice(0, Math.max(1, Math.floor((b.w - 14) / 5.6))) + "…" : b.it.n, b.x + 4, b.y + 4)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: mouse => {
                        const b = root.hit(mouse.x, mouse.y)
                        const h = b ? root.boxName(b) : ""
                        if (h !== root.hovered) { root.hovered = h; map.requestPaint() }
                    }
                    onExited: { root.hovered = ""; map.requestPaint() }
                    onClicked: mouse => {
                        const b = root.hit(mouse.x, mouse.y)
                        if (!b) return
                        const top = b.depth === 0 ? b.it.n : b.parent
                        if (mouse.button === Qt.RightButton) {
                            root.lens.open(root.lens.childPath(top))
                            return
                        }
                        root.selected = top
                        root.armTrash = false
                        map.requestPaint()
                    }
                    onDoubleClicked: mouse => {
                        const b = root.hit(mouse.x, mouse.y)
                        if (!b) return
                        const top = b.depth === 0 ? b.it : root.lens.kid(root.lens.node, b.parent)
                        if (top && top.d) root.lens.enter(top.n)
                    }
                }
            }
        }

        // the ranked list
        Column {
            visible: root.view === "list"
            width: parent.width
            spacing: 1
            Repeater {
                model: root.view === "list" ? root.items.slice(0, 40) : []
                delegate: Rectangle {
                    id: lrow
                    required property var modelData
                    readonly property real frac: root.lens.node && root.lens.node.s > 0 ? modelData.s / root.lens.node.s : 0
                    width: root.width
                    height: 26
                    radius: Theme.radius
                    color: modelData.n === root.selected ? Theme.alpha(Theme.accent, 0.12) : lMouse.containsMouse ? Theme.bgCard : "transparent"
                    // share of the folder, behind the row
                    Rectangle {
                        width: parent.width * lrow.frac
                        height: parent.height
                        radius: Theme.radius
                        color: Theme.alpha(root.colour(root.kind(lrow.modelData)), 0.12)
                    }
                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 200
                        elide: Text.ElideMiddle
                        text: (lrow.modelData.d ? "󰉋  " : lrow.modelData.rest ? "    " : "󰈔  ") + lrow.modelData.n
                        color: lrow.modelData.rest ? Theme.textFaint : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: (lrow.frac * 100).toFixed(lrow.frac < 0.1 ? 1 : 0) + "%     " + root.lens.fmt(lrow.modelData.s)
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: lMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (lrow.modelData.rest) return
                            if (mouse.button === Qt.RightButton) root.lens.open(root.lens.childPath(lrow.modelData.n))
                            else { root.selected = lrow.modelData.n; root.armTrash = false }
                        }
                        onDoubleClicked: if (lrow.modelData.d) root.lens.enter(lrow.modelData.n)
                    }
                }
            }
        }

        // what's under the mouse / selected, and what to do with it
        Item {
            width: parent.width
            height: 28
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - acts.width - 12
                elide: Text.ElideMiddle
                text: {
                    const s = root.selNode
                    if (!s) return root.hovered !== "" ? root.hovered : "Click to select · double-click a folder to go in · right-click to open it"
                    const pct = root.lens.node.s > 0 ? (s.s / root.lens.node.s * 100).toFixed(1) + "% of this folder" : ""
                    return s.n + "   " + root.lens.fmt(s.s) + "   ·   " + pct
                        + (s.d ? "   ·   " + (s.k || 0).toLocaleString(Qt.locale(), "f", 0) + " items" : "")
                        + (s.m ? "   ·   modified " + Qt.formatDate(new Date(s.m * 1000), "d MMM yyyy") : "")
                }
                color: root.selNode ? Theme.text : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
            Row {
                id: acts
                visible: root.selNode !== null
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Chip {
                    visible: root.selNode !== null && root.selNode.d === true
                    label: "GO IN"
                    onClicked: root.lens.enter(root.selected)
                }
                Chip {
                    label: "OPEN"
                    onClicked: root.lens.open(root.selNode && root.selNode.d ? root.lens.childPath(root.selected) : root.lens.nodePath)
                }
                Chip {
                    label: root.armTrash ? "MOVE TO TRASH?" : "TRASH"
                    danger: true
                    current: root.armTrash
                    onClicked: {
                        if (root.armTrash) { root.armTrash = false; root.lens.trash(root.selected) }
                        else { root.armTrash = true; disarm.restart() }
                    }
                }
            }
        }

        // the colours
        Flow {
            visible: root.view === "map"
            width: parent.width
            spacing: 14
            Repeater {
                model: root.legend
                Row {
                    required property var modelData
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9; height: 9
                        color: Theme.alpha(root.colour(parent.modelData[0]), 0.5)
                        border.color: root.colour(parent.modelData[0])
                    }
                    Text {
                        text: parent.modelData[1]
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }
            }
        }
    }
}
