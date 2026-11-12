# Muze architecture

## The desktop

```
wallpaper change (awww)
   │
   ├─> ~/.config/quickshell/wallpaper.conf           (current image)
   │
   └─> qs ipc call theme wallpaper <img>
          │
          └─> set.sh -> muze-theme --colors-only <img>
                   │
                   ├─> matugen (config.toml) ─────────────┐
                   │      ├─ quickshell palette JSON ──────┼─> Theme.qml (FileView)
                   │      ├─ hypr/muze/colors.lua ─────────┼─> hyprctl reload
                   │      ├─ kitty / foot / fuzzel / btop ─┤
                   │      ├─ qt6ct / hyprlock ─────────────┤
                   │      └─ ~/.cache/muze/colors.json ────┘
                   │
                   └─> optional matugen (apps.toml) -> GTK 3/4 CSS
                          (gated by settings.json appearance.themeApps)
```

`Theme.qml` is the shared palette object. Every module gets it as
`theme: ts.theme`, so one recolour repaints the bar, launcher, notifications,
OSD, wallpaper picker, display manager and settings page at once. The Settings
page also writes `muze/colors.lua` when a *curated* theme is chosen, so the
compositor border colours always agree with the shell.

## Configuration contract

`~/.config/muze/settings.json` is the single source of truth for the desktop:

| Consumer | Reads | Writes |
| --- | --- | --- |
| `Settings.qml` | all keys | via `MuzeSettings.save()` |
| `muze-hypr-apply` | `hyprland.*` | `hypr/muze/look.lua` |
| `muze-theme` | `appearance.themeMode`, `themeApps` | matugen outputs |
| `muze-idle` | `power.*` | `~/.config/muze/hypridle.conf` |
| Bar / Time / settings UI | `appearance.*` | — |
| `install.toml [muze]` | — | `settings.json` at install time |

Anything edited by hand (or by an agent) in `settings.json` is live-reloaded by
a `FileView` and immediately re-applied. `install.toml` is the equivalent
contract for the install: propose → show diff → approve → apply.

## Hyprland 0.57+ (Lua)

Hyprland no longer parses `.conf`; it executes `hyprland.lua` with the `hl.*`
API. The main file `dofile`s three generated modules (fresh on every reload):

```
hyprland.lua
  dofile monitors.lua        # display manager persistence
  dofile muze/look.lua       # from settings.json
  dofile muze/colors.lua     # from matugen / theme switcher
  dofile muze/user.lua       # hand overrides, last
```

`hyprctl keyword` is gone; `hyprctl eval` and `hyprctl reload` are used instead.

## Install flow

```
muze-install (gum/dialog/plain TUI)
  ├─ muze-detect (L1) -> hardware + proposed profiles
  ├─ six-step wizard -> install.toml
  ├─ show diff, optionally edit, approve
  └─ apply.sh
       ├─ validate UEFI + disk, resolve offline/online repo
       ├─ package list = base + desktop + hardware + profiles + extras
       ├─ optional btrfs snapshot
       ├─ partition (fullwipe | dualboot | manual), LUKS2, btrfs subvols
       ├─ pacstrap -> genfstab -> crypttab
       ├─ chroot: locale/time/user/mkinitcpio/Limine/services/snapper
       ├─ install.sh -> target home, settings.json from [muze]
       └─ first-boot service (optional AUR set + palette regeneration)
```

Btrfs subvolume names match `System_Repair/system_repair.sh`:
`@ @home @log @pkg @.snapshots @var @root`.

## ISO

`archiso` releng is the base. Adding a UID-1000 `live` user to
`airootfs/etc/passwd` makes `mkarchiso` copy `airootfs/etc/skel` into
`/home/live` automatically — that is how the shell, wallpaper and all configs
reach the live desktop. `getty@tty1` autologins that user into
`muze-live-login` → `dbus-run-session -- Hyprland`; tty2 autologins root for
rescue. The offline repo is a local pacman repo generated with `repo-add` from
`pacman -Sw`, so `pacstrap -C /etc/pacman-offline.conf` works with no network.

## Bluetooth

`shell/bluetooth/BluetoothService.qml` wraps Quickshell's native
`Quickshell.Bluetooth` singleton (`defaultAdapter`, `devices`, adapter
`enabled`/`discovering`, device `connected`, `pair()`, `forget()`). The bar has a
compact icon-only pill (hover tooltip / right-click → Settings), and Settings →
Bluetooth shows the adapter toggle, scan, device list, and an **Audio profile**
row per headset. Profiles come from `bin/muze-bluetooth-audio`, which parses
`pactl list cards` for `bluez_card.*` entries and switches with
`pactl set-card-profile <card> <profile>`.

## Agent levels (from message.txt)

- **L0** — classic installer, no AI.
- **L1 (implemented)** — hardware detection + profile proposal, `install.toml`
  shown as a diff for approval, Btrfs snapshot before changes. No model in the
  ISO; cloud proposal is optional and off by default.
- **L2/L3** — first-boot wizard / permanent agent. Not in v1; `install.toml`
  and `settings.json` are designed to be their interfaces.
