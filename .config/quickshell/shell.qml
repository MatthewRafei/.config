//@ pragma UseQApplication
import Quickshell

// Entry point. Quickshell always loads this file first.
// Everything visible lives in its own component file next to this one;
// this file just mounts them under one ShellRoot.
ShellRoot {
    // singletons are lazy; touch NightLight so its schedule runs from login
    readonly property bool nightLightActive: NightLight.active

    Bar {}
    VolumeOsd {}
    SettingsWindow {}
    TelemetryHud {}
    NotificationPopups {}
    NotificationCenter {}
    Lock {}
    PowerMenu {}
    QuickPanel {}
}
