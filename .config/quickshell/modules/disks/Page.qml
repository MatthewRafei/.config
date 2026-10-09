import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.widgets

// Removable drives first (../page.service.drives.qml: mount, open, safe eject), then the
// SMART health of every NVMe / SATA drive, read through UDisks2 (no root, no
// smartctl) by status.py, from qadram/omarchy-nvme-health.
// Health refreshes when the page opens and every minute while it's open.
Item {
    id: page
    property var service

    property var disks: []
    property string message: ""
    property bool loading: true
    property int rightMargin: 36

    function refresh() {
        if (!pStatus.running) pStatus.running = true
    }

    Process {
        id: pStatus
        command: ["python3", "-I", Quickshell.shellPath("modules/disks/status.py"), "--all"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                page.loading = false
                try {
                    const d = JSON.parse(text)
                    page.disks = d.disks || []
                    page.message = d.ok ? (d.message || "") : (d.message || "Could not read disk health")
                } catch (e) {
                    page.message = "Could not read disk health"
                }
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: page.visible
        onTriggered: page.refresh()
    }

    // "290 d", "3 y 41 d"
    function hours(h) {
        if (h === null || h === undefined) return "—"
        const d = Math.floor(h / 24)
        if (d < 1) return h + " h"
        if (d < 365) return d + " days  (" + h.toLocaleString(Qt.locale(), "f", 0) + " h)"
        return Math.floor(d / 365) + " y " + (d % 365) + " d  (" + h.toLocaleString(Qt.locale(), "f", 0) + " h)"
    }
    function tib(v) {
        if (v === null || v === undefined) return "—"
        return v < 1 ? Math.round(v * 1024) + " GiB" : v.toFixed(v < 10 ? 2 : 1) + " TiB"
    }
    function size(b) {
        if (!b) return ""
        return b >= 1e12 ? (b / 1e12).toFixed(1) + " TB" : Math.round(b / 1e9) + " GB"
    }
    function num(v) { return v === null || v === undefined ? "—" : String(v) }
    function lifeColor(p) {
        return p === null || p === undefined ? Theme.textDim : p <= 10 ? Theme.danger : p <= 50 ? Theme.accent2 : Theme.ok
    }
    function tempColor(d) {
        if (d.temperatureC === null || d.temperatureC === undefined) return Theme.text
        if (d.critTempC && d.temperatureC >= d.critTempC) return Theme.danger
        if (d.warnTempC && d.temperatureC >= d.warnTempC) return Theme.accent2
        return Theme.text
    }

    Component.onCompleted: page.service.drives.refresh()

    // small square action button for the removable drive rows
    component ActBtn: Rectangle {
        id: ab
        property string icon
        property string label
        property bool danger: false
        property bool busy: false
        signal clicked()
        width: abRow.implicitWidth + 16
        height: 26
        radius: Theme.radius
        color: abMouse.containsMouse ? Theme.alpha(danger ? Theme.danger : Theme.accent, 0.12) : "transparent"
        border.color: abMouse.containsMouse ? (danger ? Theme.danger : Theme.accent) : Theme.border
        opacity: busy ? 0.6 : 1
        Row {
            id: abRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: ab.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: ab.icon
                color: ab.danger ? Theme.danger : Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: 12
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ab.busy ? "…" : ab.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1
            }
        }
        MouseArea {
            id: abMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!ab.busy) ab.clicked()
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width - page.rightMargin
            spacing: 20

            // header
            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DISKS"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    font.letterSpacing: 3
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: pStatus.running ? "READING…" : "󰑐"
                    color: pStatus.running ? Theme.textDim : Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: pStatus.running ? 10 : 22
                    font.letterSpacing: pStatus.running ? 2 : 0
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.refresh()
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

            // ---------------------------------------------- removable
            Text {
                text: "// REMOVABLE"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 3
            }
            Text {
                visible: !page.service.drives.present
                text: "Nothing plugged in. USB sticks, SD cards and external disks show up here (and in the bar) the moment you connect them."
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Repeater {
                model: page.service.drives.drives
                delegate: Rectangle {
                    id: rcard
                    required property var modelData
                    readonly property var d: modelData
                    readonly property bool writing: d.writing > 0 || (page.service.drives.rates[d.name] || 0) > 4096
                    readonly property bool waiting: page.service.drives.pendingEject[d.path] === true
                    width: col.width
                    height: rcol.height + 28
                    radius: Theme.radius
                    color: writing ? Theme.alpha(Theme.danger, 0.06) : Theme.alpha(Theme.accent, 0.05)
                    border.width: 1
                    border.color: writing ? Theme.danger : Theme.border

                    Column {
                        id: rcol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 10

                        // the drive: name, how it's attached, writes, eject
                        Item {
                            width: parent.width
                            height: 26
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 9
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rcard.d.tran === "mmc" ? "󰟜" : rcard.d.size > 256e9 ? "󰋊" : "󰕓"
                                    color: rcard.writing ? Theme.danger : Theme.accent
                                    font.family: Theme.iconFont
                                    font.pixelSize: 15
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rcard.d.title
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rcard.d.name + "  ·  " + (rcard.d.tran || "").toUpperCase() + "  ·  " + page.service.drives.fmtBytes(rcard.d.size)
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Text {
                                    visible: rcard.writing
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "WRITING  " + page.service.drives.fmtRate(page.service.drives.rates[rcard.d.name] || 0)
                                    color: Theme.danger
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1
                                    SequentialAnimation on opacity {
                                        running: rcard.writing
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.4; duration: 600 }
                                        NumberAnimation { to: 1; duration: 600 }
                                    }
                                }
                                ActBtn {
                                    icon: "󰕔"
                                    label: rcard.waiting ? "EJECTS WHEN DONE" : "EJECT"
                                    busy: page.service.drives.working[rcard.d.path] === "eject"
                                    onClicked: rcard.waiting ? page.service.drives.clearPending(rcard.d.path) : page.service.drives.eject(rcard.d)
                                }
                            }
                        }

                        Text {
                            visible: page.service.drives.errorDev === rcard.d.path
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: page.service.drives.error
                            color: Theme.danger
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            visible: rcard.d.volumes.length === 0
                            text: "No filesystem on it (blank or unformatted)."
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }

                        // one row per volume
                        Repeater {
                            model: rcard.d.volumes
                            delegate: Column {
                                id: vrow
                                required property var modelData
                                readonly property var v: modelData
                                readonly property string busyKind: page.service.drives.working[v.path] || ""
                                readonly property real used: v.use ? parseInt(v.use) / 100 : -1
                                width: rcol.width
                                spacing: 6

                                Rectangle { width: parent.width; height: 1; color: Theme.border }

                                Item {
                                    width: parent.width
                                    height: 28
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - acts.width - 12
                                        spacing: 2
                                        Text {
                                            text: (vrow.v.label || vrow.v.name) + "   " + (vrow.v.crypto ? "LUKS" + (vrow.v.innerFstype ? " · " + vrow.v.innerFstype : "") : vrow.v.fstype)
                                                + (vrow.v.readonly ? "   READ-ONLY" : "")
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideMiddle
                                            text: vrow.v.locked ? "locked" : vrow.v.mountpoint
                                                ? vrow.v.mountpoint + (vrow.v.avail !== null && vrow.v.avail !== undefined ? "   ·   " + page.service.drives.fmtBytes(vrow.v.avail) + " free" : "")
                                                : "not mounted   ·   " + page.service.drives.fmtBytes(vrow.v.size)
                                            color: Theme.textFaint
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                    }
                                    Row {
                                        id: acts
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6
                                        ActBtn {
                                            visible: !vrow.v.locked && vrow.v.mountpoint === ""
                                            icon: "󰉋"; label: "MOUNT & OPEN"
                                            busy: vrow.busyKind === "mount"
                                            onClicked: page.service.drives.mount(vrow.v, true)
                                        }
                                        ActBtn {
                                            visible: vrow.v.mountpoint !== ""
                                            icon: "󰉖"; label: "OPEN"
                                            onClicked: page.service.drives.open(vrow.v.mountpoint)
                                        }
                                        ActBtn {
                                            visible: vrow.v.mountpoint !== ""
                                            icon: "󰉒"; label: "UNMOUNT"
                                            busy: vrow.busyKind === "unmount"
                                            onClicked: page.service.drives.unmount(vrow.v)
                                        }
                                        ActBtn {
                                            visible: vrow.v.crypto && !vrow.v.locked
                                            icon: "󰌾"; label: "LOCK"
                                            busy: vrow.busyKind === "lock"
                                            onClicked: page.service.drives.lock(vrow.v)
                                        }
                                    }
                                }

                                // free space
                                Rectangle {
                                    visible: vrow.used >= 0 && vrow.v.mountpoint !== ""
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Theme.trackBg
                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1, vrow.used))
                                        height: parent.height
                                        radius: 2
                                        color: vrow.used > 0.9 ? Theme.danger : Theme.accent
                                    }
                                }

                                // encrypted: passphrase right here
                                HudField {
                                    visible: vrow.v.locked
                                    width: parent.width
                                    placeholder: "passphrase to unlock, then ↵"
                                    input.echoMode: TextInput.Password
                                    onAccepted: { if (text !== "") page.service.drives.unlock(vrow.v, text); text = "" }
                                }

                                // a busy unmount says who's in the way
                                Row {
                                    visible: page.service.drives.busyDev === vrow.v.path
                                    width: parent.width
                                    spacing: 10
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - lazyBtn.width - 10
                                        wrapMode: Text.Wrap
                                        text: "Still in use" + (page.service.drives.busyHolders.length ? " by " + page.service.drives.busyHolders.join(", ") : "")
                                            + ". Close it there, or detach now and let it finish when they let go."
                                        color: Theme.danger
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                    ActBtn {
                                        id: lazyBtn
                                        icon: "󰅙"; label: "DETACH ANYWAY"; danger: true
                                        onClicked: page.service.drives.unmountLazy(vrow.v)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 6 }
            DiskSpace { width: col.width; lens: page.service.lens }

            Item { width: 1; height: 6 }
            Text {
                text: "// INTERNAL"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.letterSpacing: 3
            }

            Text {
                visible: page.message !== "" || (page.loading && page.disks.length === 0)
                width: parent.width
                wrapMode: Text.Wrap
                text: page.loading ? "Reading SMART data…" : page.message
                color: page.loading ? Theme.textDim : Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            Repeater {
                model: page.disks

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property var d: modelData
                    readonly property bool bad: d.error !== undefined || d.warning === true

                    width: col.width
                    height: cardCol.height + 28
                    radius: Theme.radius
                    color: bad ? Theme.alpha(Theme.danger, 0.06) : Theme.alpha(Theme.accent, 0.05)
                    border.width: 1
                    border.color: bad ? Theme.danger : Theme.border

                    Column {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 12

                        // name + verdict
                        Item {
                            width: parent.width
                            height: 20
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 9
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.d.protocol === "nvme" ? "󰋊" : "󰨣"
                                    color: Theme.accent
                                    font.family: Theme.iconFont
                                    font.pixelSize: 15
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.d.model || card.d.device
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (card.d.device || "").replace("/dev/", "") + (card.d.sizeBytes ? "  ·  " + page.size(card.d.sizeBytes) : "")
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.d.error !== undefined ? "NO SMART DATA" : card.d.warning ? "NEEDS ATTENTION" : "HEALTHY"
                                color: card.bad ? Theme.danger : Theme.ok
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1
                            }
                        }

                        Text {
                            visible: card.d.error !== undefined
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: card.d.error || ""
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        // remaining life
                        Column {
                            visible: card.d.lifeRemainingPercent !== null && card.d.lifeRemainingPercent !== undefined
                            width: parent.width
                            spacing: 6
                            Item {
                                width: parent.width
                                height: lifeText.implicitHeight
                                Text {
                                    text: "LIFE LEFT"
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.letterSpacing: 2
                                }
                                Text {
                                    id: lifeText
                                    anchors.right: parent.right
                                    text: card.d.lifeRemainingPercent + "%"
                                    color: page.lifeColor(card.d.lifeRemainingPercent)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Theme.trackBg
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(100, card.d.lifeRemainingPercent || 0)) / 100
                                    height: parent.height
                                    radius: 3
                                    color: page.lifeColor(card.d.lifeRemainingPercent)
                                }
                            }
                        }

                        // what the drive's controller is complaining about
                        Text {
                            visible: (card.d.criticalWarnings || []).length > 0
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "Controller warnings: " + (card.d.criticalWarnings || []).join(", ")
                            color: Theme.danger
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        Rectangle { visible: card.d.error === undefined; width: parent.width; height: 1; color: Theme.border }

                        // the figures, two columns
                        Grid {
                            visible: card.d.error === undefined
                            width: parent.width
                            columns: 2
                            rowSpacing: 8
                            columnSpacing: 24
                            Repeater {
                                model: [
                                    { k: "TEMPERATURE", v: card.d.temperatureC !== null && card.d.temperatureC !== undefined
                                        ? Math.round(card.d.temperatureC) + " °C" + (card.d.warnTempC ? "   (warns at " + Math.round(card.d.warnTempC) + ")" : "") : "—",
                                      c: page.tempColor(card.d) },
                                    { k: "POWERED ON", v: page.hours(card.d.powerOnHours) },
                                    { k: "WRITTEN", v: page.tib(card.d.tbwTiB) },
                                    { k: "READ", v: page.tib(card.d.readTiB) },
                                    { k: "SPARE", v: card.d.availableSparePercent !== null && card.d.availableSparePercent !== undefined ? card.d.availableSparePercent + "%" : "—",
                                      c: card.d.availableSparePercent !== null && card.d.availableSparePercent < 10 ? Theme.danger : Theme.text },
                                    card.d.protocol === "nvme"
                                        ? { k: "MEDIA ERRORS", v: page.num(card.d.mediaErrors), c: card.d.mediaErrors > 0 ? Theme.danger : Theme.text }
                                        : { k: "REALLOCATED", v: page.num(card.d.reallocatedSectors), c: card.d.reallocatedSectors > 0 ? Theme.danger : Theme.text },
                                    { k: "ERROR LOG", v: page.num(card.d.errorLogEntries) },
                                    { k: "POWER CYCLES", v: page.num(card.d.powerCycles) },
                                    { k: "UNSAFE SHUTDOWNS", v: page.num(card.d.unsafeShutdowns) },
                                    { k: "SERIAL", v: card.d.serial || "—" }
                                ].filter(r => r.v !== "—")
                                delegate: Row {
                                    required property var modelData
                                    width: (cardCol.width - 24) / 2
                                    spacing: 10
                                    Text {
                                        width: 130
                                        text: modelData.k
                                        color: Theme.textFaint
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        width: parent.width - 140
                                        elide: Text.ElideRight
                                        text: modelData.v
                                        color: modelData.c || Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: page.disks.length > 0
                width: parent.width
                wrapMode: Text.Wrap
                text: "From the drives' own SMART logs via UDisks2. Life left is the controller's wear estimate; "
                    + "it flags a drive at 10% life, 10% spare, any media error or any controller warning."
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
    }
}
