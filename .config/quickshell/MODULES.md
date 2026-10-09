# Modules

The shell is a **core** that runs on any machine with Quickshell, a Wayland
compositor (niri or Hyprland) and PipeWire, plus optional **modules**. Each
module is one folder in `modules/` and is only loaded when this machine has
what it needs **and** it's switched on in Settings > Modules. A module that
isn't loaded doesn't exist at all: no processes, no timers, no IPC target,
no bar chip.

## What is core

Bar (workspaces, title, clock, media, volume, network, bluetooth, stats,
battery, notifications, tray, power), notifications, the settings window and
its built-in pages, lock screen, idle / screensaver, quick panel (network,
bluetooth, sound), volume OSD, power menu, theme, compositor glue, polkit
agent. Core code never assumes a module is there: it asks the registry.

## A module

```
modules/<id>/
    module.json     what it needs and what it adds (below)
    Service.qml     optional: state, processes, IPC (created while active)
    Chip.qml        optional: a bar chip (one per bar)
    Page.qml        optional: its own Settings page
    *.qml           optional: windows, sections for core pages
    ...             helpers (python, shaders, data), LICENSE for ported code
```

`<id>` is the folder name: lowercase, `a-z0-9-`.

### module.json

```json
{
    "name": "Music EQ",
    "description": "Genre presets and a 10-band EQ from the bar",
    "icon": "󰺢",
    "default": false,
    "cost": "runs EasyEffects in the background",
    "credit": "https://github.com/wwmm/easyeffects",

    "requires": {
        "commands": ["easyeffects"],
        "files": ["~/.local/lib/x/y.so"],
        "compositor": ["hyprland"],
        "battery": true,
        "modules": ["calendar"]
    },

    "service": "Service.qml",
    "chip": { "file": "Chip.qml", "order": 40 },
    "page": { "file": "Page.qml", "title": "Audio FX", "icon": "󰍬", "after": "Sound" },
    "sections": [ { "page": "Network", "file": "NetworkSection.qml" } ],
    "quick": { "id": "rec", "file": "QuickPage.qml" },
    "windows": ["EqPanel.qml"]
}
```

| key | meaning |
|---|---|
| `name`, `description`, `icon` | shown in Settings > Modules |
| `default` | on or off on a machine that has never chosen (cheap things on, things that run in the background off) |
| `cost` | what it does in the background, shown next to the switch (omit if nothing) |
| `credit` | where the idea or code came from: a link or a list of links, shown in Settings > Modules and the README |
| `requires.commands` | programs that must be on `PATH` |
| `requires.files` | files that must exist (`~` expanded) |
| `requires.compositor` | only on these compositors |
| `requires.battery` | only on machines with a battery |
| `requires.modules` | other modules that must be active |
| `service` | created once while the module is active; everything else gets it as `service` |
| `chip` | bar chip; `order` sorts chips left to right (core chips sit at 0 and 100) |
| `page` | a Settings page of its own, placed after the page named in `after` |
| `sections` | blocks added to a core Settings page (`System`, `Sound`, `Network`, `Keyboard`, `Monitors`, `Disks` …) |
| `quick` | a page in the quick panel, opened with `qs ipc call quick <id>` |
| `windows` | panels / overlays created at shell level while active |

### The files

Every file the registry creates gets these properties set (declare the ones
you use):

```qml
property var service    // the module's Service object (null if it has none)
property var bar        // Chip.qml only: the bar it sits in
```

* `Service.qml`: a `Scope` (or `QtObject`). It's created when the module
  turns on and destroyed when it turns off, so its timers, processes and
  `IpcHandler`s live and die with it. Helpers started with
  `Quickshell.execDetached` survive a shell reload (good for audio
  processing); stop them in `function moduleStopping()`, which the registry
  calls when the module is switched off (not when the shell exits).
* `Chip.qml`: a `BarChip` (from `qs.widgets`), or anything `36` px high. To hide
  it, set `shown: false` (not `visible`), so it leaves no gap in the bar.
* `Page.qml` / sections: plain `Item`s; a page gets the full page area,
  a section the page's width.
* Windows: `PanelWindow`s / `FloatingWindow`s, or a `Variants` of them.

Imports: `import qs.widgets` for the shared UI (`BarChip`, `HudButton`,
`HudField`, `Slider`, `Switch`, `Section`, `Hint` …) and the core
singletons (`Theme`, `Compositor`, `Notifs` …) are at the shell root
(`import qs`).

### Talking to other modules

Never name another module's files. Ask the registry:

```qml
readonly property var vpn: Modules.service("vpn")     // null when it's off
text: vpn ? vpn.node : ""
```

## The registry (`Modules.qml`)

* Reads every `modules/*/module.json` at start.
* Checks `requires` on this machine and keeps the user's switches in
  `~/.local/share/quickshell/modules.json` (per machine, not in the
  dotfiles); a module with no saved choice uses its `default`.
* Creates and destroys services and windows as modules turn on and off,
  and lists what the bar, the settings window and the quick panel should
  show.
* `qs ipc call modules list | enable ID | disable ID`.

Module state of its own (presets, settings) goes in
`~/.local/share/quickshell/<id>.json`; caches in `~/.cache/quickshell/`.

## Adding a module

1. `mkdir modules/foo`, write `module.json`.
2. Put the logic in `Service.qml`, the UI in `Chip.qml` / `Page.qml` /
   sections / windows, each declaring `property var service`.
3. Restart the shell (`pkill -x qs; qs &`): live reload doesn't always
   notice new files. It appears in Settings > Modules.

## Keeping it light

The shell runs all day, so anything that ticks costs battery:

* No `loops: Animation.Infinite` on something that stays on screen: every
  frame of it redraws the whole window at 60 fps. A chip that should
  "breathe" sets `BarChip.pulse` (stepped, a few frames a second); one-off
  animations on an event are fine.
* Prefer events over polling (`nmcli monitor`, `niri msg event-stream`,
  `udevadm monitor`, FileView `watchChanges`), and when polling, read
  `/proc` / `/sys` with `FileView` and HTTP APIs with `XMLHttpRequest`
  rather than forking a shell. A helper script that answers often should
  stay up and take requests on stdin (see `agents.py serve`), exiting when
  stdin closes.
* Stop timers and clocks while their window is hidden (`running: visible`,
  `SystemClock { enabled: visible }`).
* `SysStats` (core) already samples CPU / memory / temperature / battery /
  uptime; read it instead of sampling again.
