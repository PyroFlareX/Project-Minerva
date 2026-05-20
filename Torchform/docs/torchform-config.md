# Torchform DE — Configuration Reference

Torchform is configured through TOML files. The shell merges them in priority order:

```
~/.config/torchform/config.toml   (user — highest priority)
/etc/torchform/config.toml        (system)
config/torchform.toml             (repo dev fallback)
built-in defaults                 (lowest priority)
```

Any section or key can be omitted — the built-in default applies. You only need to include what
you want to override.

---

## `[general]`

```toml
[general]
demo_mode = ""        # Overlay to open on launch: "radial" | "palette" | "switcher" | "idle" | ""
data_dir  = "~/.local/share/torchform"   # App state, file browser root. ~ is expanded.
```

---

## `[theme]`

Selects the visual appearance of the shell. You can either point to a theme file or inline the
colours directly.

### Using a theme file

```toml
[theme]
name       = "Torchform OS"
theme_file = "~/.config/torchform/themes/my-theme.toml"
```

`theme_file` takes precedence over inline `[theme.colors]` / `[theme.typography]` if both are
present. The file must be a TOML with the same sections described below.

Three themes ship in `config/themes/`:

| File | Name | Character |
| --- | --- | --- |
| `minerva-dark.toml` | Minerva Dark | Near-black, electric teal `#00d4ff` |
| `ember-light.toml` | Ember Light | Light, warm orange |
| `torchform-os.toml` | Torchform OS | Near-black `#07070f`, yellow `#e8ff47` |

### Inline colours

```toml
[theme.colors]
# Backgrounds
bg_base        = "#07070f"   # Primary display background
bg_surface     = "#0e0e1c"   # Card / panel surfaces
bg_elevated    = "#15152a"   # Elevated surfaces (modals, menus)
bg_overlay     = "#07070fcc" # Semi-transparent overlay (alpha in last 2 hex digits)

# Accent
accent         = "#e8ff47"   # Primary accent colour
accent_dim     = "#a8c000"   # Dimmed / inactive variant
accent_glow    = "#e8ff4722" # Subtle glow used on focus rings

# Interactive
primary        = "#5b9cf6"   # Informational blue
primary_hover  = "#7ab3ff"
secondary      = "#b088f0"

# Semantic
success        = "#3dd68c"
warning        = "#f7b731"
error          = "#ff4466"

# Text
text_primary   = "#e8eaf0"   # Main body text
text_secondary = "#8c92a4"   # Labels, secondary info
text_disabled  = "#3a3d55"   # Placeholders, disabled items
text_on_accent = "#07070f"   # Text drawn on the accent colour (must contrast)
text_on_primary = "#ffffff"

# Borders
border         = "#1e1e35"
border_focused = "#e8ff47"   # Focus ring colour (usually matches accent)
border_subtle  = "#111125"

# Lower companion display
lower_bg       = "#05050c"
lower_surface  = "#0b0b18"
lower_accent   = "#e8ff47"
```

### Typography

```toml
[theme.typography]
font_sans    = "Inter, DejaVu Sans, sans-serif"
font_mono    = "DM Mono, JetBrains Mono, DejaVu Sans Mono, monospace"
font_display = "Barlow Condensed, Inter, DejaVu Sans, sans-serif"
```

`font_display` is used for the lock-screen clock, panel headers, app-bar titles, and section
labels. It falls back to Inter if Barlow Condensed is not installed.

Font stacks are CSS-style — the first available font wins.

---

## `[apps]`

Maps command IDs to the external Wayland binary to launch on real hardware. If the binary is not
found, the built-in stub widget is shown instead. Set to `""` to always use the stub.

```toml
[apps]
settings = "gnome-control-center"
files    = "thunar"
editor   = "micro"
browser  = "firefox"
network  = "nm-connection-editor"
gpio     = ""          # stub only
camera   = ""          # stub only — use libcamera on hardware
media    = "vlc"       # or "mpv"
keyboard = ""          # always native stub
```

---

## `[icons]`

Override the icon for any palette command ID or system action. Values are Unicode characters.
Omit this section to use built-in defaults.

```toml
[icons]
"app.settings" = "⚙"
"app.files"    = "📁"
"sys.sleep"    = "💤"
```

---

## `[input]`

Quick mapping of shell actions to physical buttons. This section is a shorthand — for full
per-button control use `keybinds.toml` instead.

```toml
[input]
palette   = "select"
switcher  = "start"
confirm   = "a"
back      = "b"
radial_l1 = "l2"
radial_l2 = "r2"
```

---

## `[radial.system]`

Configures the 8 slots of the system radial menu (opened by holding L2 or R2). Slots are ordered
clockwise from the top: 0 = top, 1 = top-right, 2 = right, …, 7 = top-left.

```toml
[[radial.system.slots]]
label   = "Brightness"
icon    = "☀"
action  = "sys.brightness"
nested  = true       # true = opens a sub-menu
enabled = true       # false = greyed out, not selectable
```

Any palette command ID (e.g. `"app.settings"`) or system action ID (e.g. `"sys.sleep"`) can be
used as the `action`.

---

## `[launch]`

Environment variables injected into every spawned process, and per-app overrides.

```toml
[launch.env]
SDL_VIDEODRIVER    = "wayland"
QT_QPA_PLATFORM    = "wayland"
GDK_BACKEND        = "wayland"
MOZ_ENABLE_WAYLAND = "1"
EGL_PLATFORM       = "wayland"
CLUTTER_BACKEND    = "wayland"

# Per-app override example:
[launch.apps."app.browser"]
binary = "chromium"
args   = ["--ozone-platform=wayland", "--kiosk"]
mode   = "kiosk"

[launch.apps."app.browser".env]
CHROMIUM_FLAGS = "--disable-gpu-sandbox"
```

Available `mode` hints: `"wayland"`, `"sdl"`, `"gl"`, `"retroarch"`, `"kiosk"`.

---

## Keybinds (`keybinds.toml`)

The keybinds file maps raw hardware input names to `ShellAction` names. It is separate from the
main config so you can swap button layouts without touching themes or app settings.

Default location: `~/.config/torchform/keybinds.toml`
Dev fallback: `config/keybinds.toml`

### Format

```toml
[binds]
<raw_input> = "<action_name>"
```

### Raw input names

| Name | Description |
| --- | --- |
| `button_a` | Face button A |
| `button_b` | Face button B |
| `button_x` | Face button X |
| `button_y` | Face button Y |
| `button_select` | Select button |
| `button_start` | Start button |
| `l1` | Left bumper (ZL) |
| `r1` | Right bumper (ZR) |
| `l2_hold_true` | Left trigger pressed |
| `l2_hold_false` | Left trigger released |
| `r2_hold_true` | Right trigger pressed |
| `r2_hold_false` | Right trigger released |
| `dpad_up/down/left/right` | D-pad directions |
| `select_long` | Select held for ~1 second |
| `l2_r2_brightness_up/down` | L2+R2 chord + brightness |
| `l2_r2_volume_up/down` | L2+R2 chord + volume |
| `l2_r2_wifi` | L2+R2 chord + Wi-Fi |
| `l2_r2_bt` | L2+R2 chord + Bluetooth |

### Action names

| Action | Effect |
| --- | --- |
| `confirm` | A button — activate focused item |
| `cancel` | B button — back / dismiss |
| `go_home` | Return to Home screen |
| `lock` | Go to Lock screen |
| `open_palette` | Toggle command palette |
| `open_switcher` | Toggle App Switcher |
| `open_quick_settings` | Slide in Quick Settings panel |
| `open_notifications` | Slide in Notifications panel |
| `radial_hold_true` | Open radial menu |
| `radial_hold_false` | Close/activate radial menu |
| `nav_up/down/left/right` | D-pad navigation |
| `workspace_prev/next` | Cycle workspaces |
| `brightness_up/down` | Adjust display brightness |
| `volume_up/down` | Adjust audio volume |
| `wifi_toggle` | Toggle Wi-Fi |
| `bluetooth_toggle` | Toggle Bluetooth |
| `cellular_toggle` | Toggle cellular data |
| `vpn_toggle` | Toggle VPN |
| `sleep` | Suspend the device |
| `lower_backspace` | Lower display backspace (virtual keyboard) |
| `lower_submit` | Lower display submit (virtual keyboard) |

### Default keybinds

```toml
[binds]
button_a      = "confirm"
button_b      = "cancel"
button_select = "go_home"
button_start  = "open_switcher"
button_x      = "open_palette"

l2_hold_true  = "radial_hold_true"
l2_hold_false = "radial_hold_false"
r2_hold_true  = "radial_hold_true"
r2_hold_false = "radial_hold_false"

dpad_up    = "nav_up"
dpad_down  = "nav_down"
dpad_left  = "nav_left"
dpad_right = "nav_right"

l1 = "open_notifications"
r1 = "open_quick_settings"

select_long           = "lock"
l2_r2_brightness_up   = "brightness_up"
l2_r2_brightness_down = "brightness_down"
l2_r2_volume_up       = "volume_up"
l2_r2_volume_down     = "volume_down"
l2_r2_wifi            = "wifi_toggle"
l2_r2_bt              = "bluetooth_toggle"
```

To disable a binding, remove or comment out the line. To swap two actions, exchange their values.
Unknown action names are silently ignored with a log warning.

---

## Theme file format

A standalone theme file (referenced by `theme_file`) has the same structure as the inline
`[theme.colors]` and `[theme.typography]` sections, plus a `name` field:

```toml
name = "My Theme"

[colors]
bg_base     = "#07070f"
accent      = "#e8ff47"
# ... (all keys listed in the [theme.colors] section above)

[typography]
font_sans    = "Inter, sans-serif"
font_mono    = "JetBrains Mono, monospace"
font_display = "Barlow Condensed, sans-serif"
```

All colour values are 6-digit (`#rrggbb`) or 8-digit (`#rrggbbaa`) hex strings.

---

## Example: minimal user config

```toml
# ~/.config/torchform/config.toml

[theme]
theme_file = "~/.config/torchform/themes/torchform-os.toml"

[apps]
browser = "firefox"
media   = "mpv"
files   = "thunar"

[[radial.system.slots]]
label  = "Terminal"
icon   = "⬛"
action = "app.terminal"

[[radial.system.slots]]
label  = "Browser"
icon   = "🌐"
action = "app.browser"

[[radial.system.slots]]
label  = "Sleep"
icon   = "💤"
action = "sys.sleep"
enabled = true
```

```toml
# ~/.config/torchform/keybinds.toml
[binds]
# Swap l1/r1 back to workspace cycling if you prefer that
l1 = "workspace_prev"
r1 = "workspace_next"
```
