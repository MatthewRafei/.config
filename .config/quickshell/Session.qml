pragma Singleton
import Quickshell
import QtQuick

// Session state the core shares with modules (set from shell.qml).
Singleton {
    property bool locked: false      // the lock screen is up
}
