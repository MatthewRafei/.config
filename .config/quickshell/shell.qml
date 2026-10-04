//@ pragma UseQApplication
import Quickshell

// Entry point. Quickshell always loads this file first.
// Everything visible lives in its own component file next to this one;
// this file just mounts them under one ShellRoot.
ShellRoot {
    // singletons are lazy; touch NightLight so its schedule runs from login
    readonly property bool nightLightActive: NightLight.active

    // one bar per monitor
    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
        }
    }
    VolumeOsd {}
    SettingsWindow {}
    TelemetryHud {}
    NotificationPopups {}
    NotificationCenter {}
    Lock { id: lock }
    Screensaver { locked: lock.locked }
    PowerMenu {}
    QuickPanel {}
    CalendarPanel {}
    CalendarWindow {}
}
