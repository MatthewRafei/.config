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

    // received-at time per notification id (the spec doesn't carry one)
    property var times: ({})

    // oldest first, as tracked by the server
    readonly property var list: server.trackedNotifications.values
    readonly property int count: list.length

    // notifications currently shown as popups, newest first
    readonly property alias popups: popupModel

    ListModel { id: popupModel }

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
            root.times[n.id] = new Date()
            n.closed.connect(() => root.dropPopup(n))
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                popupModel.insert(0, { notif: n })
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
            l[i].dismiss()
        popupModel.clear()
    }

    function timeOf(n) {
        var d = n ? times[n.id] : null
        return d ? Qt.formatTime(d, "hh:mm AP") : ""
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

    IpcHandler {
        target: "notifs"
        function toggle(): void { root.centerOpen = !root.centerOpen }
        function dnd(): void { root.dnd = !root.dnd }
        function clear(): void { root.clearAll() }
    }
}
