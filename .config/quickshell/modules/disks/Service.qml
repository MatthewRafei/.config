import Quickshell
import QtQuick
import qs

// Disks module: disk usage (DiskLens.qml, disklens.py) and removable drives
// (Drives.qml, drives.py), for the Disks page and the drives chip.
Scope {
    readonly property alias lens: lensObj
    readonly property alias drives: drivesObj
    DiskLens { id: lensObj }
    Drives { id: drivesObj }
}
