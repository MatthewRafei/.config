//@ pragma UseQApplication
import Quickshell

// Entry point. Quickshell always loads this file first.
// Everything visible lives in its own component file next to this one;
// this file just mounts them under one ShellRoot.
ShellRoot {
    // singletons are lazy; touch NightLight so its schedule runs from login
    readonly property bool nightLightActive: NightLight.active
    // and Auth, so the polkit agent (password prompts) is registered
    readonly property bool authAgent: Auth.registered
    // and SpeedTest, so `qs ipc call speedtest run` works with Settings closed
    readonly property bool speedTest: SpeedTest.running
    // and DiskLens, so `qs ipc call disklens scan PATH` works with Settings closed
    readonly property bool diskLens: DiskLens.scanning
    // and AudioFx, which starts and watches EasyEffects (music EQ)
    readonly property bool audioFx: AudioFx.eeRunning
    // and MicFx: noise suppression + the mic effects rack
    readonly property bool micFx: MicFx.loaded

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
    PhonePush { locked: lock.locked }
    PowerMenu {}
    QuickPanel {}
    CalendarPanel {}
    CalendarWindow {}
    EqPanel {}
    Beam {}
    // Lens (text from anywhere on screen): only exists while it's in use
    LazyLoader {
        active: Lens.phase !== "idle"
        Variants {
            model: Quickshell.screens
            LensOverlay {}
        }
    }
}
