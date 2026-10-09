import QtQuick
import qs
import qs.widgets

// dim when stopped, accent + % while syncing, red on errors.
// click = web UI (starts it first if needed), right-click = start / stop
BarChip {
    property var service
    property var bar
    readonly property var st: service

    visible: st && st.installed
    icon: !st || !st.running ? "󰓨" : st.failing ? "󰓧" : "󰓦"
    value: st && st.running && st.syncing ? Math.floor(st.completion) + "%" : ""
    accent: !st || !st.running ? Theme.textFaint
          : st.failing ? Theme.danger
          : st.syncing || st.scanning || st.busy ? Theme.accent
          : Theme.text
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) st.toggle()
        else st.open()
    }
}
