import Quickshell
import QtQuick
import qs

// One selection overlay per monitor, only while Lens is in use.
LazyLoader {
    id: overlays
    property var service
    active: !!service && service.phase !== "idle"
    Variants {
        model: Quickshell.screens
        LensOverlay { service: overlays.service }
    }
}
