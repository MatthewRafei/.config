# dotfiles

A "HUD" style Wayland desktop for **Chimera Linux**: the [niri](https://github.com/YaLTeR/niri)
scrolling compositor (or [Hyprland](https://hyprland.org), see [Hyprland](#hyprland)) plus a
[Quickshell](https://quickshell.org) shell (bar, notifications,
settings, calendar, lock screen, screensaver, telemetry HUD). The colours of everything follow
the current wallpaper.

The repo is a **bare git repo** whose work tree is `$HOME`. Files live where they are used;
there are no symlinks and no install script that copies files.

```
.bashrc                        prompt (starship), PATH, the `dots` alias
.config/niri/config.kdl        compositor: startup programs, keybinds, layout, colours
.config/hypr/hyprland.lua      the same for Hyprland (Lua config); loads machine.lua + colors.lua
.config/quickshell/            the shell (started by niri as `qs`)
  shell.qml                    entry point: lists every component below
  Compositor.qml               niri/Hyprland detection: workspaces, focused window, actions
  Theme.qml                    colours/fonts; colours come live from ~/.cache/theme/palette.json
  Bar.qml                      top bar (workspaces, quote/face, clock, media, stats, tray, power)
  Notifs.qml + Notification*.qml   notification daemon + popups + center (Mod+N)
  SettingsWindow.qml + SettingsPages/  settings (Mod+S): system, sound, monitors, wifi, bluetooth, power
  Calendar*.qml, CalendarLib.js, EventForm.qml   calendar dropdown + big calendar window (Mod+C); events in ~/.calendar/*.ics (Syncthing-friendly)
  Lock.qml, LockSurface.qml, pam/   lock screen (Mod+Shift+L, after 5 min idle, before suspend)
  Screensaver.qml, ScreensaverScenes.js, screensaver/   ASCII screensaver after 3 min idle
  TelemetryHud.qml             desktop HUD with graphs (Mod+H)
  Power.qml, PowerMenu.qml     power profiles, battery, charge limit; power menu (Mod+Shift+E)
  NightLight.qml               night light (drives ~/.local/bin/nightlightd)
  QuickPanel.qml, VolumeOsd.qml, PerspectivePanel.qml, Hud*.qml, Slider.qml   shared UI bits
  hyprquickpaper/              wallpaper picker, a separate qs config (Mod+Shift+W)
  quotes/quotes                quotes shown in the bar and on the lock screen
.config/theme/wallpaper-theme  derives a palette from the wallpaper and recolours everything
.config/{alacritty,fuzzel,gtk-3.0,gtk-4.0,mpv,starship.toml}   app configs (colour keys rewritten by wallpaper-theme)
.config/gammastep/config.ini.example   location template for the night light's sunset mode
.local/bin/                    pkg + pkg-open (package finder, Mod+Shift+P), cliphist-menu (Mod+V),
                               chromium (wrapper that applies the theme), fortune, papirus-folders
.local/share/applications/chromium.desktop   launcher entry pointing at the wrapper
.local/src/nightlightd/        small C gamma daemon (build it, see below)
.local/src/battery-charge-limit/   root helper for the battery charge limit (optional install)
```

## Install on a new machine

These steps assume Chimera Linux with a normal user who can use `doas`. On another distro the
package names differ; see [Other distros](#other-distros).

### 1. Packages

```sh
doas apk add niri quickshell alacritty fuzzel nautilus chromium \
    cliphist wl-clipboard xwayland-satellite blueman bluez networkmanager \
    pipewire wireplumber pavucontrol playerctl brightnessctl power-profiles-daemon \
    starship fzf fastfetch imagemagick python jq git flatpak mpv awww \
    fonts-nerd-jetbrains-mono papirus-icon-theme \
    clang gmake pkgconf wayland-devel wayland-progs
```

Optional: `orca` (screen reader, Super+Alt+S); `brillo` (brightness keys use it when present and
fall back to `brightnessctl`); a polkit agent (niri starts `polkit-gnome-authentication-agent-1`
if it exists).

Enable the services (Chimera uses dinit):

```sh
doas dinitctl enable networkmanager
doas dinitctl enable bluetoothd
doas dinitctl enable power-profiles-daemon
```

### 2. Check out the dotfiles

```sh
git clone --bare git@github.com:MatthewRafei/dotfiles.git "$HOME/.dotfiles"   # or the https URL
alias dots='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
dots config status.showUntrackedFiles no

# move aside anything the checkout would overwrite, then check out
mkdir -p ~/.dotfiles-backup
dots checkout 2>&1 | grep -E '^\s+\.' | awk '{print $1}' | while read -r f; do
    mkdir -p "$HOME/.dotfiles-backup/$(dirname "$f")"; mv "$HOME/$f" "$HOME/.dotfiles-backup/$f"
done
dots checkout
```

### 3. Machine-specific fixes

A few files have to contain absolute paths. Point them at this user's home:

```sh
sed -i "s|/home/malac0da|$HOME|g" ~/.local/share/applications/chromium.desktop ~/.config/gtk-3.0/bookmarks
```

(On Chimera `sed -i` is BSD sed: use `sed -i '' "s|...|...|g" file`, or
`perl -pi -e "s|/home/malac0da|$HOME|g" file` on either system.)

Night light "sunset" mode needs a location. This file is not tracked so coordinates stay private:

```sh
cp ~/.config/gammastep/config.ini.example ~/.config/gammastep/config.ini
# then set lat= and lon= in config.ini
```

### 4. Build and install the helpers

```sh
# night light daemon -> ~/.local/bin/nightlightd
make -C ~/.local/src/nightlightd install        # gmake; on Chimera `make` is gmake if installed as above

# Papirus must live in ~/.local/share/icons so papirus-folders can recolour it without root
mkdir -p ~/.local/share/icons
cp -r /usr/share/icons/Papirus /usr/share/icons/Papirus-Dark ~/.local/share/icons/

# optional, laptops only: battery charge limit (Settings > Power). Installs a root helper and a
# doas/sudo rule that allows only that helper.
doas sh ~/.local/src/battery-charge-limit/install.sh
```

### 5. Wallpaper and first theme

Put wallpapers in `~/Pictures/Wallpapers/`, then start niri. This machine logs in with greetd +
tuigreet (`doas apk add greetd tuigreet`, then in `/etc/greetd/config.toml` set
`command = "tuigreet --cmd niri"` under `[default_session]`, and `doas dinitctl enable greetd`);
running `niri` from a TTY also works. Press **Mod+Shift+W** and apply a wallpaper. That runs
`~/.config/theme/wallpaper-theme`, which writes `~/.cache/theme/palette.json`,
`~/.config/alacritty/colors.toml`, the fastfetch and mpv themes, and the colour keys in niri,
fuzzel, gtk and starship. Until it has run once, alacritty warns about the missing `colors.toml`.

To theme from the command line: `~/.config/theme/wallpaper-theme /path/to/image`
(`--print` shows the palette without writing anything).

### 6. Check it works

```sh
niri validate                    # compositor config parses
qs log | tail -20                # shell log: should end with "Configuration Loaded"; no errors
qs ipc show                      # every IPC target the shell exposes
qs ipc call screensaver start    # preview the screensaver (move the mouse to dismiss)
```

## Keybinds

| Keys | Action |
|---|---|
| Mod+Return | Terminal (alacritty) |
| Mod+D | Launcher (fuzzel) |
| Mod+Shift+D | Files (Nautilus) |
| Mod+W | Chromium |
| Mod+S | Settings |
| Mod+C | Calendar |
| Mod+N | Notification center |
| Mod+H | Telemetry HUD |
| Mod+V | Clipboard history |
| Mod+Shift+P | Package finder (apk + flatpak) |
| Mod+Shift+W | Wallpaper picker |
| Mod+Shift+L | Lock |
| Mod+Shift+E | Power menu |
| Mod+P / Mod+Ctrl+P / Mod+Alt+P | Screenshot region / screen / window |
| Mod+Shift+/ | All niri keybinds |

## Idle behaviour

Screensaver after 3 minutes (`Screensaver.qml`, `timeout: 180`), lock after 5 minutes
(`Lock.qml`, `timeout: 300`). Both respect idle inhibitors (video players). The screen also
locks before suspend.

Screensaver scenes are in `ScreensaverScenes.js`. Hand-drawn scenes: Half-Life, your OS (logo
from fastfetch: Chimera, Gentoo, ...), Naruto, Death Note. GIF scenes come from
`screensaver/gifs/` and are converted to coloured block characters by `screensaver/gif2ascii.py`.
The converted frames are cached in `~/.cache/screensaver/` per screen size. To add one, drop a GIF
in `screensaver/gifs/` and add a `gifScene(...)` line in `ScreensaverScenes.js`.

## Hyprland

The shell detects the compositor at runtime (`Compositor.qml`, from `HYPRLAND_INSTANCE_SIGNATURE`
/ `NIRI_SOCKET`), so the same files work under both. `~/.config/hypr/hyprland.lua` is the shared
config: the shell, startup programs and the keybinds in the table below. Two untracked files sit
next to it:

- `machine.lua`: this machine's monitors, workspace pins, extra programs and binds. It is loaded
  last; to change a bind the shared file sets, `hl.unbind` it first.
- `colors.lua`: border colours, written by `wallpaper-theme`.

Extra packages: `hyprland`, `hyprshot` (screenshots go to `~/Pictures/Screenshots`), and
`hyprpolkitagent` or polkit-gnome. Not needed: `xwayland-satellite`. Notes:

- With a Lua config, `hyprctl dispatch` takes Lua: `hyprctl dispatch 'hl.dsp.focus({ workspace = "m+1" })'`.
  Check a config with `Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`.
- The Monitors page changes outputs with `hyprctl eval 'hl.monitor({...})'` (until reload).
- The package finder (Mod+Shift+P) is apk-only, so it isn't bound under Hyprland yet.
- `~/.local/bin/chromium` falls back to `google-chrome-stable` (Chrome isn't themed).
- Don't run waybar, mako, swww or gammastep alongside: the shell replaces them.

## Other distros

Nothing is Chimera-only except package names, `doas`, and dinit. Notes:

- Use your package manager's names for the list above. `awww` is the wallpaper daemon
  (the successor to swww); `wayland-progs` provides `wayland-scanner`.
- Lock screen auth uses `~/.config/quickshell/pam/password.conf` (`pam_unix`), so no system PAM
  file is needed.
- The OS scene in the screensaver and the package finder detect the system at runtime; the
  package finder only supports apk and flatpak.
- Desktops without a backlight: the brightness slider hides itself; nothing to install.
- Gentoo: niri, quickshell, cliphist and xwayland-satellite are in GURU. The font is
  `media-fonts/nerdfonts` with `USE=jetbrainsmono` (the default build is symbols only, and every
  config then falls back to a proportional font); without root, unpack `JetBrainsMono.tar.xz` from
  the Nerd Fonts releases into `~/.local/share/fonts` and run `fc-cache -f`. Lock before suspend
  needs elogind (`elogind-inhibit`), the OpenRC default.

## For Claude Code (or another agent) setting this up

Follow the steps above in order. Things that will trip you up:

- **The repo is bare.** Always use `git --git-dir=$HOME/.dotfiles --work-tree=$HOME ...`
  (alias `dots`). Never `git init` in `$HOME`, and never run `git add -A` or `git add .`: the
  work tree is the whole home directory. Add files by path.
- **Back up before overwriting.** Step 2 moves conflicting files to `~/.dotfiles-backup/`. Don't
  delete the user's existing configs.
- **Root steps need the user.** `apk add`, `dinitctl enable` and the charge-limit install need
  `doas`. Ask the user to run them (for example with `! doas ...` in Claude Code) rather than
  storing or guessing a password.
- **Chimera userland is BSD.** `sed -i` needs `''`; there is no `tac`, and GNU-only flags of
  `tail`, `tar` and `grep -P` don't work. Prefer `perl -pi -e` or a Python one-off for edits.
- **niri's PATH lacks `~/.local/bin`.** Keybinds call scripts as `spawn-sh "~/.local/bin/..."`.
  Keep that pattern for new binds.
- **Quickshell reloads itself** when a `.qml` file in `~/.config/quickshell` changes. Edits to the
  `.js` file only take effect after a reload: `touch ~/.config/quickshell/shell.qml`. Check
  `qs log` after every change. `qs ipc call <target> <function>` drives every component without
  touching the mouse.
- **Screenshots for checking your work:** `niri msg action screenshot-screen --write-to-disk true`
  writes to `~/Pictures/Screenshots/`. Each one adds a notification; clear them with
  `qs ipc call notifs clear`.
- **Hardware differences are handled at runtime.** Without a battery, the bar and Settings hide
  the battery and charge-limit UI. Without power-profiles-daemon, the profile buttons hide.
  Don't hard-code hardware paths.
- **Keep private data out of the repo.** No location in `gammastep/config.ini`, no calendar files
  (`~/.calendar`), no tokens. The repo is public.
- If a QML component fails to load, the whole shell can come up without a bar. Read `qs log`,
  fix the error, and the shell reloads on save.
- On a live reload (save while the shell runs) a component that fails to load can be dropped
  silently: the old version keeps running and `qs log` still says "Configuration Loaded". After
  changing a file with an `IpcHandler`, check `qs ipc show` lists what you expect. Properties
  from newer Quickshell docs (e.g. `FileView.printErrors`) may not exist in the packaged version.
