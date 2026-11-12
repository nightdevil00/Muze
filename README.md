# Muze

Muze is an Arch Linux ISO and desktop built around a [QuickShell](https://quickshell.org/)
shell for [Hyprland](https://hyprland.org/), with wallpaper-driven
[matugen](https://github.com/InioX/matugen) colours applied systemwide.

- **Top bar** — three configurable regions (**left / center / right**). Plugins
  include time, workspaces, media, window title, volume, brightness, CPU,
  network, **Bluetooth**, battery, temperature, system tray, **screen recorder**,
  **caffeine**, and **power menu**. Plugins are toggleable and can be reordered
  or moved between regions from **Settings → Top bar** (drag-and-drop or precise
  move controls). The Arch apps-menu and settings gear are bar items that can
  be placed in any region or hidden.
- **Dock** — QuickShell dock (Omarchy-inspired) showing pinned apps and running
  Hyprland toplevels with icons, running indicators, focus/launch, context menu
  (pin/unpin, new window, quit), auto-hide, position (`bottom|top|left|right`),
  icon size, and per-screen or all-screen placement. Configured via the `dock`
  block in `~/.config/muze/settings.json` and **Settings → Dock**; IPC
  `qs ipc call dock toggle|show|hide`.
- **Bluetooth** — bar indicator (power toggle on click, Settings on right-click)
  and **Settings → Bluetooth** for adapter power, scanning, device
  connect/disconnect/forget, and **audio profile** selection (A2DP vs HSP/HFP)
  for connected headsets. Backed by Quickshell's native `Quickshell.Bluetooth`
  (BlueZ over D-Bus) plus `pactl` card profiles.
- **Universal clipboard** — `Super + C / V / X / A` copy, paste, cut and
  select-all in every app (terminals get `Ctrl+Shift+C/V` automatically).
  `Super + Ctrl + V` opens the searchable history overlay (text **and**
  images). Backed by `wl-paste --watch`.
- **Power menu** — QuickShell power menu with Lock, Log out, Reboot, and
  Shutdown (`qs ipc call power toggle`; bar plugin; keybind depends on host
  config, e.g. `Super+Shift+M` or `Super+M`).
- **Screen recorder** — bar plugin and `Super + Shift + R` toggle via
  `bin/muze-record` (`gpu-screen-recorder`), saving to `~/Videos/Muze-*.mp4`.
- **Screenshots** — bar plugin and keybinds via `bin/muze-screenshot`
  (`grim`/`slurp`/`wl-copy`), saving files to `~/Pictures/Screenshots/Muze-*.png`.
- **Snapshots** — `snapper` on Btrfs plus
  [`limine-mkinitcpio-hook`](https://aur.archlinux.org/packages/limine-mkinitcpio-hook)
  and
  [`limine-snapper-sync`](https://aur.archlinux.org/packages/limine-snapper-sync)
  from the AUR, so snapshots appear as a **Snapshots** submenu in the Limine
  boot menu. Both packages are pre-built into the ISO's offline repo.
- **Default wallpaper** — `assets/beach.jpg`. Changing it recolours the whole
  system (shell, Hyprland, GTK, Qt, terminals, btop, hyprlock) via matugen, on
  every monitor.
- **Settings page** — Appearance / Top bar / Hyprland / Bluetooth / Displays /
  Power / About, backed by `~/.config/muze/settings.json` (`Super + ,`).
- **Power & idle** — screen lock, display-off and suspend each have their own
  timeout and on/off switch (`Settings -> Power`), generated into hypridle's
  config. `Super + Shift + C` toggles Caffeine (idle inhibit), and its state
  survives shell restarts.
- **Colours** — one wallpaper change repaints the shell, Hyprland borders,
  kitty, foot, fuzzel, GTK 3/4, qt6ct, btop and hyprlock.
- **Defaults** — Hyprland, kitty, fuzzel, chromium, thunar, grim/slurp/swappy,
  hyprlock/hypridle (lock 5 min, display off 6 min, suspend 15 min — all
  configurable), awww wallpapers, zram, snapper snapshots.
- **Installer** — hybrid offline/online, dual-boot, LUKS2, Btrfs subvolumes,
  Limine, package profiles, config-first `install.toml`, L1 hardware proposal.

The full change log is in [`Muze.md`](Muze.md).

## Repository layout

```
Muze/
├── shell/            -> ~/.config/quickshell   (QuickShell/QML desktop)
├── config/           -> ~/.config              (hypr, matugen, kitty, ...)
├── bin/              -> ~/.local/bin           (muze-theme, muze-hypr-apply, ...)
├── assets/           default wallpaper
├── packages/         Arch package lists + installer profiles
├── installer/        muze-install (TUI), muze-detect (L1), install.toml
├── iso/              archiso overlay + build_iso.sh
├── install.sh        install Muze into a home directory / /etc/skel
└── VERSION
```

## Install onto an existing Arch + Hyprland system

```sh
./install.sh                 # installs into $HOME
qs -n -d                     # start the shell
muze-theme ~/Pictures/Wallpapers/beach.jpg
```

Dependencies: `quickshell`, `matugen`, `awww`, `hyprland`, `jq`, `brightnessctl`,
`playerctl`, `ttf-jetbrains-mono-nerd`, plus the Qt6/GTK runtime. See
`packages/desktop.packages`.

## Build the ISO

```sh
sudo ./iso/build_iso.sh
```

The ISO boots into the live Muze desktop (user `live`). Run `sudo muze-install`
(or `Super + I`) to install, `sudo muze-repair` to chroot into an existing
system, or `muze-install --detect` to see the hardware proposal.

Boot it in a VM (requires `qemu-full` + `edk2-ovmf`):

```sh
./iso/test-iso.sh                 # newest muze-*.iso, UEFI + KVM + virtio-gpu
RAM=8192 CPUS=6 ./iso/test-iso.sh
```

## Installer contract

`installer/install.toml.example` documents every option. The agent (L1) proposes
a config, the user sees it as a list of differences and approves or edits it,
and `muze-install --config install.toml` applies it identically every time.
Everything works without AI.

## Keybinds

| Key | Action |
| --- | --- |
| `Super + Return` | Terminal |
| `Super + D` | App launcher |
| `Super + Space` | Fuzzel |
| `Super + ,` / gear in bar | Muze settings |
| `apps-menu` Arch logo in bar | App launcher |
| `Super + T` | Theme switcher |
| `Super + W` | Wallpaper picker |
| `Super + O` | Display manager |
| `Super + C` / `V` / `X` / `A` | Universal copy / paste / cut / select-all |
| `Super + Ctrl + V` | Clipboard history (text + images) |
| `Super + Shift + C` | Caffeine (idle inhibit) |
| `Super + Shift + V` | Toggle floating |
| `Super + Shift + R` | Toggle screen recording |
| `Super + Shift + M` / `Super + M` | Power menu (host config may vary) |
| `Super + I` | Installer (live ISO) |
| `Super + Q` | Close window |

> Keybinds can vary by host/integration; check `config/hypr/hyprland.lua` and your local Hyprland config. Many actions are also available via `qs ipc call ...`.
