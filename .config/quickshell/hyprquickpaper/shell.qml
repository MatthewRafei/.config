import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel

// Wallpaper picker: slanted-slice carousel.
//
// The selected wallpaper opens up into a wide card; its neighbours stay as
// thin slanted slices that fade with distance. A blurred copy of the
// selection fills the screen behind it. Opens on the wallpaper awww is
// currently showing.
//
//   ← → / h l / wheel   browse        PgUp PgDn   jump 10
//   Enter / Space       apply         R           random
//   Esc / q / w         close         click card  select, click again = apply
//
// Applying also runs ~/.config/theme/wallpaper-theme to recolour the system.
//
// Launched from niri: Mod+Shift+W → qs -n -p ~/.config/quickshell/hyprquickpaper
PanelWindow {
    id: main

    // ---- Look ----
    readonly property real cardHeight: 340
    readonly property real expandedWidth: 580
    readonly property real sliceWidth: 84
    readonly property real slant: 0.22          // shear factor of every card
    readonly property int spacing: 8
    readonly property color accent: pal.accent
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "wallpaper-picker"

    // ---- Config ----
    FileView {
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: configs
            // default matches config.json, so the folder is never empty
            property string wallpaper_path: "~/Pictures/Wallpapers/"
            property string cache_path
            property string border_color
        }
    }

    // accent follows the system theme (see ~/.config/theme/wallpaper-theme)
    FileView {
        path: Quickshell.env("HOME") + "/.cache/theme/palette.json"
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter {
            id: pal
            property string accent: "#ffffff"
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["bash", Quickshell.shellPath("cache.sh"), Quickshell.shellDir])
        // just applied a wallpaper here? start on it without waiting for awww
        if (lastApplied.fresh) {
            currentPath = lastApplied.file
            queried = true
            syncToCurrent()
        }
    }

    FolderListModel {
        id: folderModel
        folder: main.wallFolder
        showDirs: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.PNG", "*.JPG", "*.JPEG"]
        sortField: FolderListModel.Name
        caseSensitive: false
        onCountChanged: main.syncToCurrent()
        onStatusChanged: main.syncToCurrent()
    }

    // files keep arriving and get re-sorted after Ready; follow every change
    Connections {
        target: folderModel
        function onRowsInserted() { Qt.callLater(main.syncToCurrent) }
        function onRowsRemoved() { Qt.callLater(main.syncToCurrent) }
        function onRowsMoved() { Qt.callLater(main.syncToCurrent) }
        function onLayoutChanged() { Qt.callLater(main.syncToCurrent) }
        function onModelReset() { Qt.callLater(main.syncToCurrent) }
        function onDataChanged() { Qt.callLater(main.syncToCurrent) }
    }

    // ---- Currently displayed wallpaper ----
    // Two sources, and we only jump once we have an answer:
    //  - lastApplied: what this picker last set, saved with a timestamp on
    //    apply. Trusted for 10s, which covers reopening mid-transition.
    //  - awww query: the truth otherwise (e.g. wallpaper set elsewhere).
    // If awww hasn't answered in 1.5s we go with whatever we have.
    readonly property string stateFile: Quickshell.env("HOME") + "/.cache/quickshell/wallpaper-last"
    property string currentPath: ""
    property bool queried: false

    FileView {
        id: lastApplied
        path: main.stateFile
        blockLoading: true
        // "<epoch ms>\n<path>"
        readonly property var parts: (text() || "").split("\n")
        readonly property bool fresh: parts.length > 1 && Date.now() - parseInt(parts[0]) < 10000
        readonly property string file: parts.length > 1 ? parts[1] : ""
    }


    Process {
        command: ["awww", "query"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (main.queried && lastApplied.fresh) return   // just applied: keep ours
                var m = text.match(/image: (.*)$/m)
                main.currentPath = m ? m[1].trim() : lastApplied.file
                main.queried = true
                main.syncToCurrent()
            }
        }
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: {
            if (main.queried) return
            main.currentPath = lastApplied.file
            main.queried = true
            main.syncToCurrent()
        }
    }

    // FolderListModel reports Ready before the folder has fully loaded and
    // keeps inserting files, which shifts indices. So re-sync on every model
    // change until the user moves the selection themselves.
    property bool userMoved: false
    property int targetIndex: -1

    readonly property string wallFolder: configs.wallpaper_path ? "file://" + main.expand(configs.wallpaper_path) : ""

    function syncToCurrent() {
        if (userMoved || !queried || folderModel.count === 0 || folderModel.status !== FolderListModel.Ready)
            return
        // an empty folder means "the working directory" to FolderListModel;
        // only sync once it is really listing the wallpapers
        if (!wallFolder || String(folderModel.folder) !== wallFolder)
            return
        var idx = -1
        for (var i = 0; i < folderModel.count; i++) {
            if (folderModel.get(i, "filePath") === currentPath) {
                idx = i
                break
            }
        }
        if (idx < 0)
            return
        targetIndex = idx
        if (idx === list.currentIndex)
            return
        // current first, so the card is already expanded when centring on it
        list.currentIndex = idx
        list.positionViewAtIndex(idx, ListView.Center)
    }

    // ---- Actions ----
    property bool closing: false

    function step(delta) {
        if (folderModel.count === 0) return
        userMoved = true
        list.currentIndex = Math.max(0, Math.min(folderModel.count - 1, list.currentIndex + delta))
    }

    function apply() {
        if (folderModel.count === 0 || closing) return
        var path = folderModel.get(list.currentIndex, "filePath")
        // wipe at the same angle as the card slant
        Quickshell.execDetached([
            "awww", "img", path,
            "--transition-type", "wipe",
            "--transition-angle", "78",
            "--transition-step", "90",
            "--transition-fps", "60",
            "--transition-duration", "1.2"
        ])
        // recolour the whole system from the new wallpaper
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/theme/wallpaper-theme", path])
        // remember it, so reopening during the transition starts here
        lastApplied.setText(Date.now() + "\n" + path)
        close()
    }

    function close() {
        if (closing) return
        closing = true
        quitTimer.start()
    }

    Timer {
        id: quitTimer
        interval: 260
        onTriggered: Qt.quit()
    }

    function thumbFor(fileName) {
        return "file://" + expand(configs.cache_path) + fileName
    }

    // config.json paths may start with ~ so it works for any user
    function expand(p) {
        return p.startsWith("~/") ? Quickshell.env("HOME") + p.slice(1) : p
    }

    // =========================================================
    // Backdrop: blurred selection + dark tint. Click to close.
    // =========================================================
    Item {
        id: root
        anchors.fill: parent
        // fade in on open, out on close
        property real intro: 0
        property real outro: 1
        NumberAnimation on intro { from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation on outro { running: main.closing; to: 0; duration: 240; easing.type: Easing.OutCubic }
        opacity: intro * outro

        Item {
            id: bgLayer
            anchors.fill: parent
            visible: false
            layer.enabled: true

            property string target: list.currentItem ? list.currentItem.thumbSource : ""
            onTargetChanged: {
                bgOld.source = bgNew.source
                bgOld.opacity = 1
                bgNew.opacity = 0
                bgNew.source = target
            }

            Image {
                id: bgOld
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Image {
                id: bgNew
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0
                onStatusChanged: if (status === Image.Ready) bgFade.restart()
                NumberAnimation on opacity { id: bgFade; running: false; to: 1; duration: 450; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        MultiEffect {
            anchors.fill: parent
            source: bgLayer
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            brightness: -0.15
            saturation: 0.2
            opacity: 0.55
        }

        // scanlines, to match the rest of the shell
        Canvas {
            anchors.fill: parent
            opacity: 0.5
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "rgba(0,0,0,0.35)"
                for (var y = 0; y < height; y += 3)
                    ctx.fillRect(0, y, width, 1)
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: main.close()
            onWheel: wheel => main.step(wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? -1 : 1)
        }

        // =====================================================
        // Carousel
        // =====================================================
        ListView {
            id: list

            width: parent.width
            height: main.cardHeight
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: main.closing ? 30 : -20
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            orientation: ListView.Horizontal
            model: folderModel
            spacing: main.spacing
            interactive: false
            cacheBuffer: 1200
            focus: true

            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: width / 2 - main.expandedWidth / 2
            preferredHighlightEnd: width / 2 + main.expandedWidth / 2
            highlightMoveDuration: 380
            highlightMoveVelocity: -1

            // StrictlyEnforceRange makes the view pick currentIndex from
            // whatever is centred, and the cards are still animating width
            // right after the initial jump, so it can drift a few cards off.
            // Hold the synced card until the user moves.
            onCurrentIndexChanged: {
                if (!main.userMoved && main.targetIndex >= 0 && currentIndex !== main.targetIndex)
                    Qt.callLater(() => {
                        if (!main.userMoved && list.currentIndex !== main.targetIndex)
                            list.currentIndex = main.targetIndex
                    })
            }

            Keys.onPressed: event => {
                main.userMoved = true
                switch (event.key) {
                case Qt.Key_Left: case Qt.Key_H: main.step(-1); break
                case Qt.Key_Right: case Qt.Key_L: main.step(1); break
                case Qt.Key_PageUp: main.step(-10); break
                case Qt.Key_PageDown: main.step(10); break
                case Qt.Key_Home: list.currentIndex = 0; break
                case Qt.Key_End: list.currentIndex = folderModel.count - 1; break
                case Qt.Key_R:
                    list.currentIndex = Math.floor(Math.random() * folderModel.count)
                    break
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
                    main.apply()
                    break
                case Qt.Key_Escape: case Qt.Key_Q: case Qt.Key_W:
                    main.close()
                    break
                default:
                    return
                }
                event.accepted = true
            }

            delegate: Item {
                id: card

                required property int index
                required property string fileName
                required property string filePath

                readonly property bool isCurrent: ListView.isCurrentItem
                readonly property int distance: Math.abs(index - list.currentIndex)
                readonly property bool isApplied: filePath === main.currentPath
                property bool useFull: false
                readonly property string thumbSource: useFull ? "file://" + filePath : main.thumbFor(fileName)

                width: isCurrent ? main.expandedWidth : main.sliceWidth
                height: list.height
                Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                opacity: Math.max(0.15, 1 - distance * 0.09)
                Behavior on opacity { NumberAnimation { duration: 300 } }

                // slanted, clipped frame
                Item {
                    id: frame
                    anchors.fill: parent
                    clip: true
                    // current card sits slightly forward
                    scale: card.isCurrent ? 1.0 : 0.94
                    Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                    transform: Shear {
                        xFactor: -main.slant
                        origin.y: frame.height / 2
                    }

                    // image counter-sheared so the picture itself stays upright
                    Image {
                        id: img
                        height: parent.height
                        width: parent.width + main.slant * parent.height
                        x: -main.slant * parent.height / 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        source: card.thumbSource
                        sourceSize.height: main.cardHeight
                        onStatusChanged: if (status === Image.Error && !card.useFull) card.useFull = true

                        transform: Shear {
                            xFactor: main.slant
                            origin.y: img.height / 2
                        }
                    }

                    // loading shimmer
                    Rectangle {
                        anchors.fill: parent
                        visible: img.status !== Image.Ready
                        color: "#0d0d0d"
                    }

                    // dim the non-selected slices
                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        opacity: card.isCurrent ? 0 : (cardMouse.containsMouse ? 0.15 : 0.45)
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    // bottom gradient for the label
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 90
                        opacity: card.isCurrent ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: "#cc000000" }
                        }
                    }

                    // border
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: card.isCurrent ? 2 : 1
                        border.color: card.isCurrent ? main.accent
                                    : card.isApplied ? "#80ffffff"
                                    : "#1e1e1e"
                    }

                    // "applied" tick on the slice showing the live wallpaper
                    Rectangle {
                        visible: card.isApplied
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 10
                        width: 6; height: 6
                        color: "#00ff9c"
                    }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (card.isCurrent) main.apply()
                        else { main.userMoved = true; list.currentIndex = card.index }
                    }
                    onWheel: wheel => main.step(wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? -1 : 1)
                }
            }
        }

        // =====================================================
        // Info + hints
        // =====================================================
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: list.bottom
            anchors.topMargin: 28
            spacing: 10
            opacity: main.closing ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                Text {
                    anchors.baseline: nameText.baseline
                    text: {
                        var n = folderModel.count
                        var w = String(n).length
                        var i = String(list.currentIndex + 1)
                        while (i.length < w) i = "0" + i
                        return i + " / " + n
                    }
                    color: "#888888"
                    font.family: main.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }

                Text {
                    id: nameText
                    text: list.currentItem ? list.currentItem.fileName : ""
                    color: "#ffffff"
                    font.family: main.fontFamily
                    font.pixelSize: 14
                    elide: Text.ElideMiddle
                    width: Math.min(implicitWidth, 520)
                }

                Rectangle {
                    visible: list.currentItem !== null && list.currentItem.isApplied
                    anchors.verticalCenter: nameText.verticalCenter
                    width: appliedText.implicitWidth + 12
                    height: 18
                    color: "transparent"
                    border.color: "#00ff9c"
                    Text {
                        id: appliedText
                        anchors.centerIn: parent
                        text: "CURRENT"
                        color: "#00ff9c"
                        font.family: main.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "←  →  BROWSE    ENTER  APPLY    R  RANDOM    ESC  CLOSE"
                color: "#4a4a4a"
                font.family: main.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 2
            }
        }

        // header
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: list.top
            anchors.bottomMargin: 34
            text: "// WALLPAPER"
            color: "#888888"
            font.family: main.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 4
        }
    }
}
