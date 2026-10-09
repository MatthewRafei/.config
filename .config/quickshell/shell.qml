//@ pragma UseQApplication
import Quickshell
import QtQuick

// Entry point. Quickshell always loads this file first.
// Everything visible lives in its own component file next to this one;
// this file just mounts them under one ShellRoot.
ShellRoot {
    // the module registry: starts the active modules (MODULES.md)
    readonly property bool modulesReady: Modules.ready
    // and Auth, so the polkit agent (password prompts) is registered
    readonly property bool authAgent: Auth.registered
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
    NotificationPopups {}
    NotificationCenter {}
    Lock { id: lock }
    Binding { target: Session; property: "locked"; value: lock.locked }
    Screensaver { locked: lock.locked }
    PowerMenu {}
    QuickPanel {}
    EqPanel {}
}
