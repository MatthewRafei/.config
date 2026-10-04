-- Hyprland config: the same desktop as ~/.config/niri/config.kdl
-- (Quickshell bar, notifications, lock, settings; colours follow the wallpaper).
-- Hyprland 0.55+ Lua syntax.
--
-- Not tracked, loaded at the end if present:
--   ~/.config/hypr/colors.lua   border colours, written by ~/.config/theme/wallpaper-theme
--   ~/.config/hypr/machine.lua  this machine: monitors, workspace pins, extra programs and
--                               binds (hl.unbind a key here first to rebind it)
--
-- hyprctl dispatch takes Lua here: hyprctl dispatch 'hl.dsp.focus({ workspace = "2" })'

local mainMod = "SUPER"
local bin = os.getenv("HOME") .. "/.local/bin/"
local function exec(cmd) return hl.dsp.exec_cmd(cmd) end

-- ── Autostart ─────────────────────────────────────────────────────────────────

hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("qs")
    hl.exec_cmd("wl-paste --watch cliphist store")   -- clipboard history (Mod+V)
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS")
    hl.exec_cmd("blueman-applet")
    -- whichever polkit agent is installed
    hl.exec_cmd("[ -x /usr/libexec/hyprpolkitagent ] && exec /usr/libexec/hyprpolkitagent || exec polkit-gnome-authentication-agent-1")
end)

-- ── Environment ───────────────────────────────────────────────────────────────

hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XDG_SESSION_TYPE",             "wayland")
hl.env("XDG_CURRENT_DESKTOP",          "Hyprland")
hl.env("XDG_SESSION_DESKTOP",          "Hyprland")
hl.env("MOZ_ENABLE_WAYLAND",           "1")
hl.env("GDK_BACKEND",                  "wayland")
hl.env("QT_QPA_PLATFORM",              "wayland")
hl.env("XCURSOR_SIZE",                 "24")
hl.env("PROTON_ENABLE_WAYLAND",        "1")
hl.env("ADW_DISABLE_PORTAL",           "1")
hl.env("GTK_THEME",                    "Adwaita:dark")   -- recoloured by wallpaper-theme's gtk.css
hl.env("QS_ICON_THEME",                "Papirus-Dark")   -- quickshell's icons (tray, distro logo)

-- ── General ───────────────────────────────────────────────────────────────────

hl.config({
    general = {
        gaps_in       = 6,
        gaps_out      = 12,
        border_size   = 3,
        layout        = "dwindle",
        allow_tearing = false,
        -- fallback until wallpaper-theme writes colors.lua
        ["col.active_border"]   = { colors = { "rgba(ba86dfff)", "rgba(e18ed6ff)" }, angle = 45 },
        ["col.inactive_border"] = "rgba(281f2eff)",
    },
    decoration = {
        rounding = 0,
        shadow = {
            enabled      = true,
            range        = 25,
            render_power = 3,
            color        = "rgba(00000066)",
            offset       = "0, 4",
        },
        blur = {
            enabled = false,
        },
    },
    animations = {
        enabled = true,
    },
    input = {
        kb_layout          = "us",
        kb_options         = "ctrl:nocaps",
        numlock_by_default = true,
        repeat_rate        = 50,
        repeat_delay       = 300,
        follow_mouse       = 1,
        sensitivity        = 0.0,
        accel_profile      = "flat",
        touchpad = {
            natural_scroll = true,
            tap_to_click   = true,
            scroll_factor  = 0.2,
        },
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
    },
})

-- ── Animations ────────────────────────────────────────────────────────────────

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows",    enabled = true, speed = 7,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7,  bezier = "default"  })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "default"  })
hl.animation({ leaf = "fade",       enabled = true, speed = 7,  bezier = "default"  })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6,  bezier = "default"  })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- ── Keybinds (same layout as niri, see ~/.github/README.md) ──────────────────

-- Apps and shell
hl.bind(mainMod .. " + Return",      exec("alacritty"))
hl.bind(mainMod .. " + D",           exec("fuzzel"))
hl.bind(mainMod .. " + SHIFT + D",   exec("nautilus"))
hl.bind(mainMod .. " + W",           exec(bin .. "chromium"))
hl.bind(mainMod .. " + SHIFT + L",   exec("qs ipc call lock lock"))
hl.bind(mainMod .. " + N",           exec("qs ipc call notifs toggle"))
hl.bind(mainMod .. " + C",           exec("qs ipc call calendar open"))
hl.bind(mainMod .. " + H",           exec("qs ipc call hud toggle || qs -d"))
hl.bind(mainMod .. " + S",           exec("qs ipc call settings toggle || qs -d"))
hl.bind(mainMod .. " + SHIFT + E",   exec("qs ipc call power toggle"))
hl.bind(mainMod .. " + SHIFT + W",   exec("qs -n -p ~/.config/quickshell/hyprquickpaper"))
hl.bind(mainMod .. " + V",           exec(bin .. "cliphist-menu"))
hl.bind(mainMod .. " + ALT + S",     exec("pkill orca || exec orca"), { locked = true })

-- Windows
hl.bind(mainMod .. " + Q",           hl.dsp.window.close())
hl.bind(mainMod .. " + F",           hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + SHIFT + F",   hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + ALT + V",     hl.dsp.window.float({ action = "toggle" }))

-- Focus / move — Mod(+Shift)+Arrow
for key, dir in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
    hl.bind(mainMod .. " + " .. key,                  hl.dsp.focus({ direction = dir }))
    hl.bind(mainMod .. " + SHIFT + " .. key,          hl.dsp.window.move({ direction = dir }))
    hl.bind(mainMod .. " + CTRL + " .. key,           hl.dsp.focus({ monitor = dir }))
    hl.bind(mainMod .. " + CTRL + SHIFT + " .. key,   hl.dsp.window.move({ monitor = dir }))
end

-- Workspaces — Mod(+Shift)+Number
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = tostring(i) }))
end

-- Previous / next workspace on this monitor
hl.bind(mainMod .. " + Page_Up",     hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + Page_Down",   hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + I",           hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + U",           hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + mouse_up",    hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse_down",  hl.dsp.focus({ workspace = "e+1" }))

-- Screenshots (hyprshot), saved like niri's
local shots = "hyprshot -o ~/Pictures/Screenshots -m "
hl.bind(mainMod .. " + P",           exec(shots .. "region"))
hl.bind(mainMod .. " + CTRL + P",    exec(shots .. "output"))
hl.bind(mainMod .. " + ALT + P",     exec(shots .. "window"))

-- Volume
hl.bind("XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",        exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),        { locked = true })
hl.bind("XF86AudioMicMute",     exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),      { locked = true })

-- Media
hl.bind("XF86AudioPlay", exec("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioStop", exec("playerctl stop"),       { locked = true })
hl.bind("XF86AudioPrev", exec("playerctl previous"),   { locked = true })
hl.bind("XF86AudioNext", exec("playerctl next"),       { locked = true })

-- Brightness (laptops; does nothing without a backlight)
hl.bind("XF86MonBrightnessUp",   exec("brillo -A 2.5 || brightnessctl -q set 3%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", exec("brillo -U 2.5 || brightnessctl -q set 3%-"), { locked = true, repeating = true })

-- Move / resize floating windows with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Generated colours and this machine's extras ──────────────────────────────

pcall(require, "colors")
local ok, err = pcall(require, "machine")
if not ok and not tostring(err):find("module 'machine' not found", 1, true) then
    error(err)
end
