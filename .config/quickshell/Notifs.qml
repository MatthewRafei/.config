pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// Notification daemon (replaces mako) + shared state for the popups,
// the notification center and the bar's bell.
//
//   qs ipc call notifs toggle     open/close the notification center
//   qs ipc call notifs dnd        toggle do-not-disturb
//   qs ipc call notifs clear      dismiss everything
Singleton {
    id: root

    property bool dnd: false
    property bool centerOpen: false

    // received-at time (ms) per notification id (the spec doesn't carry
    // one). Kept across shell reloads, which replay the notifications.
    PersistentProperties {
        id: kept
        reloadableId: "notifs"
        property string timesJson: "{}"
    }
    readonly property var times: JSON.parse(kept.timesJson || "{}")
    function _setTime(id, ms) {
        const t = JSON.parse(kept.timesJson || "{}")
        if (ms === undefined) delete t[id]; else t[id] = ms
        kept.timesJson = JSON.stringify(t)
    }

    // oldest first, as tracked by the server
    readonly property var list: server.trackedNotifications.values
    readonly property int count: list.length

    // notifications currently shown as popups, newest first
    readonly property alias popups: popupModel

    ListModel { id: popupModel }

    // every incoming notification (PhonePush forwards these while away)
    signal received(var n)

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true
            n.closed.connect(() => { root.dropPopup(n); root.dropImages(n); root._setTime(n.id) })
            // replayed after a shell reload: already seen, popped up and copied
            if (n.lastGeneration) return
            root._setTime(n.id, Date.now())
            root.keepImages(n)
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                popupModel.insert(0, { notif: n })
            root.received(n)
        }
    }

    // stop showing as a popup (it stays in the center)
    function dropPopup(n) {
        for (var i = popupModel.count - 1; i >= 0; i--) {
            var p = popupModel.get(i).notif
            if (p === n || p === null)
                popupModel.remove(i)
        }
    }

    function clearAll() {
        var l = list.slice()
        for (var i = 0; i < l.length; i++)
            if (l[i]) l[i].dismiss()   // skip ones already gone
        popupModel.clear()
    }

    function timeOf(n) {
        var ms = n ? times[n.id] : undefined
        return ms ? Qt.formatTime(new Date(ms), "hh:mm AP") : ""
    }

    // invoke the "default" action (what clicking the notification means)
    function activate(n) {
        var acts = n.actions
        for (var i = 0; i < acts.length; i++) {
            if (acts[i].identifier === "default") {
                acts[i].invoke()
                return true
            }
        }
        return false
    }

    // ---------------------------------------------------------------- images
    // Chromium (and others) pass the picture and icon as files in a temp
    // dir they delete soon after, so by the time the notification center
    // shows them they're gone. Copy those as they arrive and show the copy;
    // the copy goes when the notification does.
    readonly property string imageCache: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache")
        + "/quickshell/notifs"
    readonly property var _tempDirs: ["/tmp/", "/var/tmp/", (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user") + "/"]

    // a temp file path from an image / icon source, else ""
    function _tempFile(src) {
        src = String(src || "")
        if (src.startsWith("file://")) src = decodeURIComponent(src.slice(7))
        else if (src.startsWith("image://icon/")) src = src.slice(13)   // how Quickshell hands over image-path
        return _tempDirs.some(d => src.startsWith(d)) ? src : ""
    }

    // where the copy of `src` lives (stable across shell reloads: id + path hash)
    function _keptPath(n, kind, src) {
        let h = 0
        for (let i = 0; i < src.length; i++) h = (h * 31 + src.charCodeAt(i)) | 0
        const ext = (src.match(/\.[A-Za-z0-9]{1,5}$/) || [""])[0]
        return imageCache + "/" + n.id + "-" + kind + "-" + (h >>> 0).toString(16) + ext
    }

    function keepImages(n) {
        const pairs = []
        for (const [kind, src] of [["image", n.image], ["icon", n.appIcon]]) {
            const f = _tempFile(src)
            if (f) pairs.push(f, _keptPath(n, kind, f))
        }
        if (!pairs.length) return
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$1" && shift && while [ $# -ge 2 ]; do cp -f "$1" "$2"; shift 2; done',
            "sh", imageCache].concat(pairs))
    }

    function dropImages(n) {
        const files = []
        for (const [kind, src] of [["image", n.image], ["icon", n.appIcon]]) {
            const f = _tempFile(src)
            if (f) files.push(_keptPath(n, kind, f))
        }
        if (files.length) Quickshell.execDetached(["rm", "-f"].concat(files))
    }

    // what a card should load for `src` (the notification's image or appIcon)
    function imageSource(n, kind, src) {
        const f = _tempFile(src)
        return f ? "file://" + _keptPath(n, kind, f) : src
    }

    // copies left behind by a shell restart (their notifications are gone)
    Process {
        running: true
        command: ["sh", "-c", '[ -d "$1" ] && find "$1" -type f -mtime +1 -delete', "sh", root.imageCache]
    }

    IpcHandler {
        target: "notifs"
        function toggle(): void { root.centerOpen = !root.centerOpen }
        function dnd(): void { root.dnd = !root.dnd }
        function clear(): void { root.clearAll() }
    }
}
