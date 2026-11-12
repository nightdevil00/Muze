# Muze — build log

Muze is an Arch Linux ISO + desktop built around a **QuickShell** shell for
**Hyprland**, with wallpaper-driven **matugen** colours, a settings page for the
shell and Hyprland, a curated set of defaults, and an offline/online installer
with dual-boot support.

This file is the running record of every change made while building it, as
requested in `instructions.txt` step 7.

---

## 0. Decisions (confirmed with the user)

| Decision | Choice |
| --- | --- |
| Shell foundation | `Shells/quickshell-config-main (1)` (doannc2212 modular QuickShell config) + a custom Muze layer |
| Live ISO | Boots into the **full Muze desktop** (autologin Hyprland + QuickShell), configs via `/etc/skel` |
| Installer | **Hybrid** (bundled offline repo + online fallback), **custom TUI**, `install.toml` config contract |
| Disk / boot | x86_64 UEFI, GPT, **Btrfs subvolumes**, optional **LUKS2**, **Limine** (Windows chainload), zram, NetworkManager + PipeWire |
| Agentic level | **L1**: hardware detection + profile proposal, config-first (show `install.toml` as a diff, user approves), no local model, cloud optional |

Source material (all read/explored):
- `OfflineArch/` — `build_iso.sh`, `install_arch.sh`, `README.md`, flow SVG
- `System_Repair/` — `system_repair.sh`, `README.md`
- `Shells/` — Ambxst, dux-shell, impasto, Luci, omarchy, quickshell-1.1.0,
  three `quickshell-config-main` variants, ryoku, SekaiPop, serpantinum

Environment: Arch Linux, Hyprland 0.57.2 running on Wayland, `yay` present,
network online. `quickshell` 0.3.2, `matugen` 4.2.0 and `awww` are in the
official `extra` repo — no AUR helper is needed for the core.

---

## 1. Packages installed for building/testing (step 8)

```
sudo pacman -S --needed quickshell matugen awww jq fzf dialog libnotify upower \
    bluez-utils adw-gtk-theme qt6ct gnome-themes-extra wl-clipboard imagemagick \
    hyprlock hypridle xdg-desktop-portal-gtk papirus-icon-theme thunar \
    ttf-jetbrains-mono-nerd noto-fonts-emoji
```

Already present on the host: `hyprland`, `archiso`, `limine`, `btrfs-progs`,
`cryptsetup`, `networkmanager`, `pipewire*`, `wireplumber`, `brightnessctl`,
`playerctl`, `grim`, `slurp`, `kitty`, `waybar`, `zram-generator`,
`power-profiles-daemon`, `polkit` agent, portals, `yay`.

---

## 2. Codebase survey — what was reused

| Source | What was taken |
| --- | --- |
| `Shells/quickshell-config-main (1)/` | Whole shell scaffold: `bar/` (time, workspaces, media, volume, brightness, CPU, network, battery, temperature, tray), `app-launcher/`, `notifications/`, `osd/`, `wallpaper/`, `monitor-manager/`, `idle-inhibitor/`, `theme-switcher/` (206 themes + matugen wallpaper mode). Copied into `Muze/shell/`. |
| `Shells/ryoku-1.0.9/ryoku/shell/matugen/` | Systemwide matugen template idea + `gtk3/gtk4`, `kitty`, `qt6ct`, `btop`, `colors.json` templates. Adapted to matugen 4.2 role names. |
| `Shells/ryoku-1.0.9/system/packages/` | Reference for Arch package lists, hardware conditionals, Limine/snapper boot chain. |
| `Shells/omarchy-4.5.0/` | "Omarchy-style" defaults reference; `themes/tokyo-night/backgrounds/4-sunset-lake.webp` used as the default wallpaper. |
| `Shells/quickshell-config-main (2)/` | Pattern for a tabbed Settings UI and `settings.json` persistence (`property Process` trick for `QtObject` singletons). |
| `Shells/SekaiPop-main/install-deps.sh` | Reference for Arch/AUR package tiers. |
| `OfflineArch/` | ISO build approach (releng + offline repo), dualboot/free-space detection, Btrfs subvolumes, LUKS2, Limine config, zram, iwd/network setup. |
| `System_Repair/` | Rescue/mount logic (to be folded into the installer's Repair mode). |

Rejected as a base: `quickshell-1.1.0` (pywal, older API), the big `(2)`
config (references `~/.config/hypr/scripts/*` that are not shipped), the Nix
flakes, and the dynamic-island shells (different UI paradigm).

---

## 3. Changes to the shell (step 3)

All paths relative to `/home/mihai/Projects/Muze/`.

### 3.1 `shell/` — QuickShell config (installs to `~/.config/quickshell`)

- Copied all 9 upstream modules. Replaced `Hack Nerd Font` with
  `JetBrainsMono Nerd Font` everywhere (installed as `ttf-jetbrains-mono-nerd`).
- **`shell/shell.qml`** — rewritten entry point: adds `Settings { theme: ts.theme }`
  and `import "root:/settings"`, keeps the shared `ts.theme` palette wired into
  every module.
- **`shell/settings/qmldir`** — registers `MuzeSettings` (singleton),
  `Settings`, `MuzeDefaultTheme`.
- **`shell/settings/MuzeSettings.qml`** (new) — persistent JSON config at
  `~/.config/muze/settings.json`. Holds appearance + bar + Hyprland options,
  serialises with `JSON.stringify`, writes via `Process`, live-reloads with
  `FileView`, and re-runs `muze-hypr-apply` on external edits. Helpers are
  declared as *typed properties* because `QtObject` has no default property.
- **`shell/settings/Settings.qml`** (new) — tabbed Muze settings page
  (Appearance / Top bar / Hyprland / Bluetooth / Displays / Power / About).
  Toggles, steppers,
  choice rows, action buttons, live palette swatches, keybind reference.
  Opens via `qs ipc call muze settings` (SUPER + comma).
- **`shell/settings/MuzeDefaultTheme.qml`** — fallback palette (renamed from
  `DefaultTheme.qml` to avoid a type-name clash with `bar/DefaultTheme.qml`).
- **`shell/bar/Bar.qml`** — imports `root:/settings`; bar height and opacity now
  come from settings; every plugin has an individual `visible` binding
  (`showClock`, `showWorkspaces`, `showMedia`, `showVolume`, `showBrightness`,
  `showCpu`, `showNetwork`, `showBattery`, `showTemperature`, `showTray`).
  Bar colour uses `Qt.rgba(...)` so opacity is real, not a whole-window fade.
- **`shell/bar/Time.qml`** — 12/24-hour + seconds formats driven by settings.
- **`shell/theme-switcher/wallpaper-theme/set.sh`** — rewritten to delegate to
  `muze-theme --colors-only <image>` (with a standalone matugen fallback).

### 3.2 `config/matugen/` — systemwide colour generation

- **`config.toml`** (new) — core templates rendered on every recolour:
  Quickshell palette JSON, `~/.cache/muze/colors.json`, Hyprland borders,
  kitty, foot, qt6ct, btop, fuzzel, hyprlock. `post_hook`s reload Hyprland /
  kitty / foot.
- **`apps.toml`** (new) — GTK3/GTK4 CSS, gated by the "Theme third-party apps"
  toggle.
- **`templates/`** — `muze-palette.json` (from upstream), `colors.json`,
  `gtk3-colors.css`, `gtk4-colors.css`, `kitty-colors.conf`,
  `qt6ct-colors.conf`, `btop.theme` (from ryoku), plus new `hypr-colors.conf`,
  `foot-colors.ini`, `fuzzel.ini`, `hyprlock-colors.conf`.
- **Important fix:** matugen **4.2** removed the legacy `colors.foreground`,
  `colors.cursor` and `colors.color0..15` roles that ryoku's templates use.
  All templates were rewritten to use Material 3 roles
  (`colors.on_surface.default.hex`) and the generated `base16.baseXX.default.hex`
  palette. `qt6ct` now uses `.alpha_hex` (`#AARRGGBB`) instead of `*_argb`.
  Verified: every template renders without `ResolveError`.

### 3.3 `bin/` — CLI helpers (install to `~/.local/bin`)

- **`muze-theme`** — `muze-theme <image>` sets the wallpaper via `awww`, runs
  matugen with the core config, optionally renders app templates (per the
  `themeApps` setting), remembers the last wallpaper in
  `~/.cache/muze/current-wallpaper`. Flags: `--colors-only` (used by the QML
  wallpaper hook), `--refresh` (re-render after a settings change).
- **`muze-hypr-apply`** — renders `settings.json` into
  `~/.config/hypr/conf.d/10-muze-look.conf` and `hyprctl reload`. Sanitises all
  values so a broken JSON file can never produce a broken Hyprland config.
  `--dry-run` prints instead of writing.
- **`muze-idle`** — renders `power.*` into `~/.config/muze/hypridle.conf` and
  (re)starts `hypridle -c` only when the file changed. Screen lock, DPMS off and
  suspend have independent toggles/timeouts; `--dry-run` prints the config.
  Called by `muze-session-start` and by the Settings → Power tab.

### 3.4 `assets/`

- **`muze-default.webp`** — default wallpaper (from omarchy's Tokyo Night set).
  Installed to `~/Pictures/Wallpapers/` so the wallpaper picker finds it.

---

## 4. Test results (step 3 → 4)

Ran on the live Hyprland/Wayland session:

1. `qs --no-duplicate` → **"Configuration Loaded"**, no QML errors. Two
   upstream warnings are harmless (module paths with `-`, notification daemon
   already owned by the host, portal app-id registration).
2. Screenshots confirmed: Muze top bar with all plugins, Muze settings page,
   theme switcher (wallpaper palette mode), wallpaper picker.
3. `qs ipc show` lists all targets (`muze`, `bar`, `theme`, `wallpaper`,
   `monitors`, `launcher`, `notifications`, `idle`); toggling each produced no
   errors.
4. `muze-theme` generated 11 output files (shell palette, Hyprland colours,
   kitty, foot, fuzzel, qt6ct, btop, GTK3, GTK4, hyprlock, colors.json).
5. A wallpaper change through the QML picker regenerated the palette and
   repainted the shell — the full wallpaper → matugen → systemwide chain works.
6. Editing `settings.json` externally live-reloaded the singleton and
   re-applied the Hyprland config (verified `rounding = 20` → `12`).
7. `MuzeSettings.save()` created a complete default `settings.json` on first run.

Test instance stopped afterwards (`qs kill`); host `waybar` restarted.

---

## 5. Desktop config (step 4/5 groundwork)

**Important discovery:** Hyprland **0.57** switched to a **Lua** config
(`hyprland.lua`, `hl.*` API). The classic `.conf` syntax is no longer parsed,
and `hyprctl keyword` returns "unknown request". `hyprland --verify-config`
confirms our config is valid; `hyprctl eval 'hl.config({...})'` works at runtime.
So Muze ships Lua, and the two generated files are Lua modules loaded with
`dofile` (not `require`) so `hyprctl reload` always re-reads them.

- **`config/hypr/hyprland.lua`** — monitors, env, autostart, input, all
  keybinds (incl. `SUPER+,` settings, `SUPER+I` installer), window/layer rules,
  misc. Verified with `hyprland --verify-config` → **config ok**.
- **`config/hypr/muze/look.lua`** — generated by `muze-hypr-apply` from
  `settings.json`. **`colors.lua`** — generated by matugen (or the theme
  switcher). **`user.lua`** — hand overrides loaded last.
  **`monitors.lua`** — written by the display manager (`require("monitors")` is
  literal because upstream MonitorService greps for it).
- **`config/hypr/hypridle.conf`, `hyprlock.conf`** (hyprlock is fully generated
  by matugen — no `source` directive needed), **`config/kitty/kitty.conf`**,
  **`foot/foot.ini`, `fuzzel/fuzzel.ini`, `qt6ct/qt6ct.conf`,
  `gtk-3.0/settings.ini`, `mimeapps.list`** — defaults, each including its
  matugen-generated colour sibling.
- **`bin/muze-session-start`** — Hyprland autostart: portals/polkit, awww daemon,
  wallpaper + palette, QuickShell, hypridle.
- **`bin/muze-snapshot`** — Btrfs snapshot before agent-driven changes (L1).
- **`install.sh`** — installs `shell/ → ~/.config/quickshell`,
  `config/ → ~/.config`, `bin/ → ~/.local/bin`, wallpaper + desktop entry.
  `--target DIR`, `--skel` (HOME-relative paths for `/etc/skel`), `--owner`.
- **`Version`**: `0.1.0`; `README.md` with layout, keybinds, build instructions.

Changes to the shell for Lua: `muze-hypr-apply` now emits `hl.config({...})`;
matugen's `hypr-colors.conf` template was replaced by `hypr-colors.lua` and
`hyprlock-colors.conf` by a full `hyprlock.conf` template; `Theme.qml`'s
`applyHyprlandBorders()` now writes `muze/colors.lua` and calls
`hyprctl reload` (curated themes and wallpaper mode both drive Hyprland borders).

## 6. Package lists (step 4)

Validated every name against the live Arch repos.

- `packages/base.packages` — core, Btrfs/LUKS/Limine/snapper/zram, PipeWire,
  NetworkManager, Bluetooth, microcode, power.
- `packages/desktop.packages` — QuickShell, matugen, awww, Hyprland, Qt6/GTK,
  fonts, shell dependencies, defaults (chromium, thunar, kitty, fuzzel, ...).
  **No AUR package is required for the core experience.**
- `packages/hardware.packages` — CPU/GPU/laptop conditionals.
- `packages/profiles/{minimal,student,dev,gaming,creative}.packages` — the
  installer's selectable package sets.
- `packages/offline-extra.packages` — what is baked into the ISO's offline repo
  on top of base+desktop+minimal (browser alternative, GPU drivers, LTS kernel).
  Profiles beyond minimal are online-only unless added here.
- `packages/aur.packages` — optional online-only AUR set, installed on first boot.

## 7. Installer (step 6)

- **`installer/install.toml.example`** — the documented config contract
  (`[system] [disk] [boot] [packages] [agent] [muze]`). Everything is decided
  here, shown to the user as a diff, approved, then applied identically.
- **`installer/muze-detect`** — L1: reads `/sys`/`lsblk`/`blkid`, detects UEFI,
  CPU/GPU, RAM, battery, disks, free space, Windows EFI; proposes profiles,
  encryption, install mode. Outputs pretty / `--shell` / `--json` / `--toml`.
  Fixed: zram devices are no longer mistaken for installable disks.
- **`installer/muze-install`** — hybrid custom TUI. UI backend auto-selects
  `gum` → `dialog` → plain read. Six steps: hardware, identity, disk, packages,
  Muze defaults, review. Writes `install.toml`, shows it, lets the user edit it,
  then executes. `--config FILE` for reproducible/unattended installs,
  `--detect`, `--repair`.
- **`installer/lib/apply.sh`** — deterministic executor: validates UEFI + disk,
  resolves offline/online, builds the package list (base + desktop + L1 hardware
  + profiles + browser + extras), optional pre-install snapshot, fullwipe or
  dualboot partitioning, LUKS2, Btrfs subvolumes
  (`@ @home @log @pkg @.snapshots @var @root` — matches System_Repair),
  pacstrap, chroot config, Limine with `path:` syntax + Windows chainload +
  `EFI/BOOT` fallback, snapper, NetworkManager, zram, first-boot AUR helper,
  copy of Muze into the target home via `install.sh`, `settings.json` from
  `[muze]`, cleanup.
- **`installer/muze-repair`** — `System_Repair/system_repair.sh` with
  `@snapshots` added to the recognised subvolume names.

Fixes over `OfflineArch/install_arch.sh`: no `$PASSWORD` before assignment,
consistent Limine `path:` keys, 512 MiB ESP instead of 2 GiB, aligned dualboot
partitions, real package profiles, configurable browser/flatpak/AUR, explicit
fallback EFI binary, generated `settings.json`, and no hardcoded network stack
override (NetworkManager is enabled instead).

## 8. ISO (step 5)

- **`iso/overlay/airootfs/`** — adds a `live` user (UID 1000) to `/etc/passwd`
  and `/etc/shadow`; `getty@tty1` autologins `live` into
  `/usr/local/bin/muze-live-login` which runs `dbus-run-session -- Hyprland`
  (falls back to a shell); `getty@tty2` autologins `root`. Also `profile.d`,
  `sudoers.d/live`, `motd`, online `pacman.conf`, `pacman-offline.conf`,
  `muze-install` / `muze-repair` wrappers.
- **`iso/build_iso.sh`** — copies releng, overlays `iso/overlay/`, runs
  `install.sh --skel` into `/etc/skel` (mkarchiso copies it to
  `/home/live/.config` for UID-1000 users), copies the source tree to
  `/opt/muze`, downloads all default packages + deps into
  `/var/cache/offline-repo` (`repo-add`), appends desktop packages to
  `packages.x86_64`, updates `profiledef.sh` metadata + file permissions, runs
  `mkarchiso`, copies the ISO to the project root.

## 9. Integration test results

- `install.sh --target <temp home>` produced 77 config files; all required paths
  present.
- `muze-hypr-apply --dry-run` and `muze-theme --colors-only` both succeed in a
  clean temp `$HOME`; all 11 colour outputs regenerate.
- `hyprland --verify-config` → **config ok**.
- `qs --no-duplicate` → **Configuration Loaded**, no QML errors after all the
  Lua/settings changes (only the benign portal/notification warnings).
- Screenshots of the Muze bar, Settings page, theme switcher and wallpaper
  picker confirmed on the live Hyprland session; a wallpaper change regenerated
  the palette end-to-end.
- `foot --config foot.ini --check-config`, `fuzzel --check-config` and
  `hyprlock -c hyprlock.conf` all parse cleanly after fixing config syntax:
  - foot uses `[colors-dark]` with bare `RRGGBB` values (not `[colors]`/`#hex`),
    and `include=~/...` at the top level.
  - fuzzel needs an absolute-ish `~` path for `include`.
  - hyprlock has no `general:grace`/`no_fade_in`/`placeholder_text_color`
    options; those were removed.
- `muze-install --config ... --dry-run --yes` prints the planned install without
  touching a disk.
- `muze-detect` fixed to ignore zram/loop devices when listing installable disks.

## 10. ISO build

- First `build_iso.sh` run downloaded **671 packages / 2.4 GiB** into the
  bundled offline repo, then was interrupted by a concurrent edit to the script
  (bash re-reads running scripts). The second run reuses the cached repo via
  `KEEP_WORK=1 SKIP_DOWNLOAD=1`.
- Fixes found during the build (applied to the source, included in the final
  ISO build): offline package checks must look at the bundled `.pkg.tar.zst`
  files instead of `pacman -Si` (which queries the host's sync db);
  `hwclock --systohc || true`; no multi-GB repo copied into the target;
  `wallpaper.conf` rewritten to the installed system's path; single-browser
  filtering; `--dry-run` installer flag.

## 10b. ISO verification + archiso permission fix

The second build produced `/home/mihai/Projects/Muze/muze-2026.11.12-x86_64.iso`
(**5.0 GiB**, sha256 `545389436259ab047334604d720b5c5a7593ee4cbccfaae5dbd1d87f8a3b1c1e`).
Mounting the ISO and its `airootfs.sfs` confirmed:

- `/etc/passwd` contains the `live` user (UID 1000), `/home/live/.config/quickshell/shell.qml`,
  `settings/Settings.qml`, `hypr/hyprland.lua`, `hypr/muze/colors.lua`,
  `matugen/config.toml`, `muze/settings.json`, `.local/bin/muze-theme` and the
  default wallpaper are all present.
- `getty@tty1` autologins `live`; `/var/cache/offline-repo` has **671 packages**
  and a valid `offline.db`.
- ISO is bootable (`ISO 9660 ... (bootable)`, label `MUZE_202611`).

**Bug found:** `mkarchiso` copies `airootfs` with
`cp -af --no-preserve=ownership,mode`, which strips the exec bit from every
custom file. In the built ISO `/home/live/.local/bin/muze-session-start` and the
`/opt/muze/installer/*` scripts were `644`, so the live desktop autostart and
the installer wrappers would fail. Fixed by:
- `iso/overlay/airootfs/root/customize_airootfs.sh` — archiso runs this in the
  chroot after `/etc/skel` is copied to `/home/live`; it restores `755` on the
  helper scripts and `440` on `sudoers.d/live`.
- `muze-install` / `muze-repair` wrappers now use `exec bash
  /opt/muze/installer/...`, so they no longer depend on the exec bit there.

These two fixes require one more (cached) `mkarchiso` run to be baked in.

## 11. Host setup (so Muze can be used locally)

At the user's request, the running Hyprland session now uses Muze instead of
waybar. All changes are reversible:

- `pkill -x waybar` (Hyprland `exec-once` only fires at session start, so a
  config reload cannot bring it back).
- Backed up `~/.config/hypr/hyprland.lua` → `~/.config/hypr/hyprland.lua.pre-muze`.
- In the `hyprland.start` autostart block, `waybar` + `hyprpaper` were replaced
  by `muze-session-start` (awww wallpaper daemon, palette regeneration,
  QuickShell, hypridle).
- Appended a guarded `pcall(dofile, ...)` loop for
  `~/.config/hypr/muze/{look,colors,user}.lua` so the Settings → Hyprland tab
  (`muze-hypr-apply`) and matugen (`muze-theme`) can override the defaults
  without clobbering the user's hand-written monitor/keybind config.
- Added Muze IPC binds to the existing config: `SUPER+D` launcher,
  `SUPER+,` settings, `SUPER+T` theme, `SUPER+W` wallpaper, `SUPER+O` displays,
  `SUPER+C` caffeine, `SUPER+N` dismiss notifications,
  `SUPER+SHIFT+N` DND. `SUPER+SPACE` (fuzzel) and all existing binds are intact.
- Re-synced the latest `bin/`, `config/matugen/`, `config/hypr/muze/` and the
  generated colour files into `~/.config`.
- `hyprctl reload` → `hyprland --verify-config` reports **config ok**.
- Started `muze-session-start`: `qs` 1, `awww-daemon` 1, `hypridle` 1,
  `waybar` 0. Screenshot confirms the Muze bar and the matugen-derived
  pink/purple Hyprland window borders. All IPC targets respond
  (`muze`, `bar`, `theme`, `wallpaper`, `monitors`, `launcher`,
  `notifications`, `idle`).

Revert with:
`cp ~/.config/hypr/hyprland.lua.pre-muze ~/.config/hypr/hyprland.lua && qs kill; waybar &`

## 12. Second round of fixes (user feedback)

Seven issues reported while playing with the live desktop; all fixed in the
source tree and applied to the running session.

1. **Settings page cramped / cut-off text.** Window widened 880 → 980, sidebar
   158 → 168, the content `Flickable` is 24 px narrower (explicit right
   padding), the content `ColumnLayout` is 20 px narrower, and `SubLabel` got
   `Layout.rightMargin: 16` + `rightPadding: 12`. All long text now wraps.
2. **"Regenerate colours" reset the wallpaper to the default.** `muze-theme`
   now treats `~/.config/quickshell/wallpaper.conf` (written by the wallpaper
   picker) as the source of truth, `--refresh` implies `--colors-only` (it
   never touches awww), and the Settings button calls
   `muze-theme --colors-only --refresh`.
3. **Wallpaper not applied to the second display.** New `bin/muze-wallpaper`
   queries `awww query`, addresses every output explicitly with `-o`, and uses
   a per-output `fade` transition instead of awww's `grow` (whose single global
   circle centre could leave the secondary monitor on the old image). Both
   `muze-theme` and `WallpaperService.qml` now use it. Verified: `awww query`
   shows the same image on `eDP-1` and `HDMI-A-4`.
   `WallpaperManager.applyWallpaper()` also always regenerates the palette now.
4. **Temperature plugin showed no value.** `sensors` is not guaranteed; the
   widget now calls `bin/muze-temperature`, which reads
   `/sys/class/thermal/thermal_zone*/temp` directly (hottest zone, millidegrees
   → °C) with a `sensors` fallback. Verified: `73°C` in the bar.
   `showTemperature` now defaults to `true`.
5. **Drag-reorderable plugins + two new bar buttons.**
   - `MuzeSettings.pluginOrder` (persisted in `settings.json`), `movePlugin()`,
     `pluginLabels`, `pluginVisible()`.
   - `bar/Bar.qml` rewritten: all widgets are inline `Component`s rendered by a
     `Repeater` over `pluginOrder` via `Loader`; the "title" plugin takes
     `Layout.fillWidth` so the original left/centre/right feel is preserved.
   - Fixed left **Arch logo** button (`objectName`/`Accessible.name` =
     `apps-menu`, `shell/assets/apps-menu.svg`) → `qs ipc call launcher toggle`.
   - Fixed right **settings** gear button → `qs ipc call muze settings`.
   - Settings → Top bar has a drag-to-reorder list (press on a row, move,
     release) plus the existing per-plugin visibility toggles.
   - Added `qs ipc call muze bar|displays` shortcuts.
6. **`beach.jpg` is now the default wallpaper.** Found the user's
   `~/Pictures/Wallpapers/Beach.jpg` (5120×2880, 10 MB), downscaled to
   2560×1440 q88 (1.1 MB) as `assets/beach.jpg`. All references updated:
   `install.sh`, `muze-session-start`, `muze-theme` fallback, the generated
   `hyprlock.conf` template, `installer/lib/apply.sh` (wallpaper.conf + first
   boot), `README.md`. The palette/colour files in `config/` were regenerated
   from it. Legacy `muze-default.webp` assets removed.
7. **Monitor manager was broken on Hyprland 0.57.** `hyprctl keyword monitor`
   returns "Unknown request"; `MonitorService.buildMonitorArg()` now emits
   `eval hl.monitor({...})` (verified with a no-op `--batch` call), the Lua
   persistence message replaces the `monitors.conf` hint, `sourceCheck`
   accepts a `dofile` of `monitors.lua`, and `hyprland.lua` now `dofile`s
   `monitors.lua` (not `require`) so `hyprctl reload` re-reads it. Settings
   text updated from `conf.d/10-muze-look.conf` to `muze/look.lua`.

Also installed `qemu-full`, `edk2-ovmf`, `dnsmasq` and added
`iso/test-iso.sh` (UEFI/OVMF + virtio-gpu + KVM) for VM testing.

## 13. ISO: exec-bit fix

`mkarchiso` copies `airootfs` with `--no-preserve=ownership,mode`, which strips
the exec bit from custom files (verified: `/home/live/.local/bin/*` and
`/opt/muze/installer/*` were `644` in the built ISO). Fixed with
`iso/overlay/airootfs/root/customize_airootfs.sh` (restores `755` after skel
copy) plus `file_permissions` entries for `/etc/skel/.local/bin/`,
`/opt/muze/bin/` and `/opt/muze/installer/`, and `bash` wrappers in
`/usr/local/bin`.

## 14. Drag fix + Bluetooth

**Drag scrolling:** the plugin list's `MouseArea` now sets
`preventStealing: true` and suspends the page `Flickable` (`interactive = false`)
for the whole gesture, so a drag can no longer be stolen and turned into a
scroll. A ghost row follows the pointer and a drop line shows the target slot.
Added a precise alternative: tap a row to select it, then "↑ Move up" /
"↓ Move down" (also keyboard/mouse accessible). `PanelWindow.onVisibleChanged`
restores scrolling if the panel closes mid-drag.

**Bluetooth (new):**
- Quickshell ships a native `Quickshell.Bluetooth` service (BlueZ over D-Bus),
  so no `bluetoothctl` polling is needed. Added
  `shell/bluetooth/BluetoothService.qml` (singleton + `qmldir`) exposing
  adapter availability/power/discovering, device list, connected name/count.
- `bar/Bar.qml`: new `cBluetooth` pill — icon + "No BT" / "On" / "Off" /
  connected device name. Left click toggles power, right click opens Settings →
  Bluetooth. Registered in `componentFor()`.
- `settings/Settings.qml`: new **Bluetooth** tab — adapter toggle, scan toggle,
  "N connected · M known", and a device list with Connect / Disconnect / Forget
  and battery %. New IPC `qs ipc call muze bluetooth`, About keybind entry.
- `MuzeSettings`: `showBluetooth` toggle, `bluetooth` added to `pluginOrder`,
  `pluginLabels`, `pluginToggleKey`, `save()`/`load()`, plus a migration that
  appends newly added plugins to older `settings.json` files.
- `config/muze/settings.json` updated; `packages/desktop.packages` now includes
  `bluez` + `bluez-utils` for the live ISO (`base.packages` already had them and
  the offline repo already contains both).
- Verified on the live session: the bar pill shows the connected
  "HUAWEI FreeBuds SE 3", and Settings → Bluetooth lists 8 devices with a
  working adapter toggle (rfkill is soft-blocked on this host, so the adapter
  reports off until unblocked).

## 15. Bluetooth follow-ups

1. **Compact Bluetooth pill.** The bar plugin used to show the whole connected
   device name ("HUAWEI FreeBuds SE 3") and got too wide. It is now a fixed
   26 px icon-only pill with a green dot when a device is connected; the full
   state/name appears in a hover tooltip and in `Accessible.name`.
2. **Audio profile selection.** New `bin/muze-bluetooth-audio` parses
   `pactl list cards`, keeps only BlueZ cards (optionally filtered by MAC), and
   reports the active profile plus available profiles (A2DP / HSP-HFP / ...).
   `set CARD PROFILE` calls `pactl set-card-profile`. Settings → Bluetooth has
   an **Audio profile** section: one row per headset with a button per profile,
   the active one highlighted. The list refreshes when the tab opens, every 6 s
   while visible, and right after a switch. Verified against a synthetic
   `bluez_card.*` sample (parser + QML Repeater instantiate with no runtime
   errors). `libpulse` + `pipewire-pulse` added to `packages/desktop.packages`
   so `pactl` is present in the live ISO.
3. **Show/hide the bar buttons.** `showSettingsButton` and `showAppsMenu` are
   persisted settings with toggles in Settings → Top bar ("Show plugins").
   Bar.qml binds the two fixed `Loader`s' `visible` to them. Both default on.

Also added a precise reorder alternative to the drag list: tap a row to select
it, then "↑ Move up" / "↓ Move down" (drag still works with
`preventStealing` + Flickable suspension + a pointer-following ghost).

## 16. Final polish

- `bar/Time.qml` guards `MuzeSettings.use24h` / `clockSeconds` during the first
  evaluation (removes two "Unable to assign [undefined] to QString" warnings).
- `MonitorService.sourceCheck` accepts any `monitors.lua` reference, so
  persistence is detected both in Muze's own `hyprland.lua` and in the host's
  hand-written config.
- `iso/test-iso.sh` — QEMU boot helper (OVMF UEFI, KVM, virtio-gpu, user
  networking). Options validated with a paused `-S` run. Usage:
  `./iso/test-iso.sh [path/to.iso]`, `RAM=8192 CPUS=6 ./iso/test-iso.sh`.
- Verified the live drag feature end-to-end: the user's `settings.json` now has
  a custom `pluginOrder`, and the bar reflects the persisted order.

## 17. Universal clipboard + Limine snapshots

Two Omarchy-derived features were added on request.

### 17.1 Universal clipboard

`Super + A / C / V / X` now work in every app, mirroring Omarchy:

- New `shell/clipboard/` module:
  - `capture.sh` — emits one compact JSON entry (`jq -Rsc`) per clipboard
    selection: text, or an image written to
    `~/.local/state/muze/clipboard-images/<sha256>.<ext>` (deduplicated by
    hash). Skips `x-kde-passwordManagerHint` and `CLIPBOARD_STATE=sensitive`;
    every read is `timeout 2s` so a stuck owner cannot wedge the watcher.
  - `ClipboardService.qml` — singleton that runs `wl-paste --watch sh
    capture.sh` (invoked through `sh` because archiso strips exec bits),
    keeps the history in memory, caps the list, and exposes
    `copyItem(index)` / `clear()` / `toggle()` IPC handlers.
  - `ClipboardPanel.qml` — searchable overlay: ↑/↓ + Return, click to copy
    (images included), "Clear history", Esc to close.
  - `qmldir` + wiring in `shell/shell.qml`.
- `config/hypr/muze/clipboard.lua` re-binds the shortcuts. Terminals get
  `Ctrl+Shift+C/V`; everything else gets `Ctrl+C/V`. The dispatcher is
  `hl.dsp.send_key_state` with an explicit down/up split (50 ms timer), the
  pattern Omarchy uses to avoid Hyprland's `send_shortcut` leaving a synthetic
  modifier stuck. `wtype` cannot be used: the physically held SUPER merges
  into the injected chord.
- `Super + Ctrl + V` opens the history overlay (`qs ipc call clipboard
  toggle`).
- Because SUPER+C/V were already used, the old binds moved to
  `Super + Shift + C` (idle/caffeine toggle) and `Super + Shift + V`
  (floating toggle).
- `install.sh` and `customize_airootfs.sh` chmod `capture.sh` 755 (mkarchiso
  strips exec bits with `cp --no-preserve=mode`).
- Verified live: `hyprctl binds` shows the new binds, history capture works
  for text and images, images dedupe by hash, and the IPC pick path pastes
  back the selected entry.

### 17.2 Limine snapshot boot entries

- `limine-mkinitcpio-hook` (provides/conflicts `limine-entry-tool`) plus
  `limine-snapper-sync` come from the AUR — listed in
  `packages/aur.packages`, never vendored.
- The two packages are **pre-built on the host and cached** in
  `packages/aur-cache/`. `build_iso.sh` bakes that cache into the offline
  repo, so offline installs get snapshot support with no network.
- `installer/lib/apply.sh`:
  - stages `/var/cache/muze-aur/*.pkg.tar.zst` before the chroot,
  - writes `/etc/snapper/configs/root` + `SNAPPER_CONFIGS="root"` by hand
    (`snapper create-config` cannot work in a chroot: no snapperd, and
    `/.snapshots` already exists),
  - `pacman -U`s the cached packages inside the chroot,
  - pins `TARGET_OS_NAME="Muze Linux"` / `ESP_PATH="/boot"` in
    `/etc/default/limine` and `/etc/limine-snapper-sync.conf`,
  - keeps a flat `/boot/limine.conf` fallback and a Windows chainload entry,
  - enables `limine-snapper-sync.service` and `snapper-cleanup.timer`.
- `/etc/os-release` is branded (`NAME="Muze"`, `PRETTY_NAME="Muze Linux"`) so
  `limine-entry-tool` names the generated entry "Muze Linux" — the name
  `TARGET_OS_NAME` matches. `muze-first-boot` retries the AUR install online
  and enables the service if the packages were missing.
- Verified on the host: config `root` created, baseline snapshot "Muze
  baseline" made, `/boot/limine.conf` now contains a `//Snapshots` submenu
  with `subvol=/@snapshots/1/snapshot`.

## 18. Remaining

- [ ] Definitive ISO build (idle control + clipboard + baked AUR packages) and
      a VM boot test with `./iso/test-iso.sh`
- [ ] Test `Super + C` / `Super + V` inside a real app (synthetic key
      injection from `hyprctl` does not reach clients, so this needs a human
      keystroke)
- [ ] Optional: cloud profile proposal (L1), first-boot wizard (L2), profile
      import/export

## 19. Why the session locked and suspended

Root cause: `muze-session-start` started `hypridle` with the shipped
`~/.config/hypr/hypridle.conf`, which hard-codes:

| timeout | action |
| --- | --- |
| 300 s | `loginctl lock-session` (hyprlock) |
| 360 s | `hyprctl dispatch dpms off` |
| 900 s | `systemctl suspend` |

There was no Muze setting to turn those off. `Super + Shift + C` only toggled a
runtime Wayland idle inhibitor (Caffeine) whose state was lost whenever
QuickShell restarted, so "screen lock off" was not sticky. The 12:08 suspend
came from the 900 s listener: logind logged `suspend requested from client
PID ... ('systemctl') (unit user@1000.service)`.

Fix:

- `bin/muze-idle` generates `~/.config/muze/hypridle.conf` from the new
  `power` block in `settings.json` and restarts `hypridle` only when the
  generated config changed. `0` minutes also disables an action.
- `Settings -> Power` exposes independent toggles + timeouts for lock,
  display-off and suspend. With lock off, `before_sleep_cmd` is omitted so a
  manual suspend does not lock either.
- `muze-session-start` now calls `muze-idle` instead of starting `hypridle`
  with the static config.
- Caffeine (`Super + Shift + C`) persists in
  `~/.local/state/muze/caffeine`, so a shell restart no longer silently
  re-arms the idle timers.
- `config/muze/settings.json` ships the new defaults (lock 5 min, display off
  6 min, suspend 15 min) for fresh installs; existing `settings.json` files
  without a `power` block are migrated in memory with the same defaults.

## 20. Power menu

`Muze` now ships a QuickShell power menu with **Lock screen**, **Log out**,
**Reboot**, and **Shutdown** actions.

- **Component:** `shell/power-menu/PowerMenu.qml`, registered in
  `shell/shell.qml`. Actions: lock → `loginctl lock-session`; log out →
  `hyprctl dispatch 'hl.dsp.exit()'`; reboot → `systemctl reboot`; shutdown →
  `systemctl poweroff`.
- **IPC:** `qs ipc call power toggle|open|close` (target `power`).
- **Bar plugin:** `power` ("Power menu", 󰐥) in `shell/bar/Bar.qml`, wired into
  the bar plugin system so it can be **reordered and shown/hidden** in
  **Settings → Top bar** (Arrange plugins / Show plugins). Backed by
  `showPower` and `pluginOrder` in `MuzeSettings` / `settings.json` (migrated
  for existing configs).
- **Keybinds:** repo `config/hypr/hyprland.lua` binds `SUPER+SHIFT+M` to
  `qs ipc call power toggle`. Host configs may differ (e.g. this session binds
  `SUPER+M` to the power menu in `~/.config/hypr/hyprland.lua`); bind to the
  IPC command as preferred.

## 21. Screen recorder plugin

A bar plugin for screen recording using `gpu-screen-recorder`.

- **Helper:** `bin/muze-record` (`toggle|start|stop|status`) starts/stops
  `gpu-screen-recorder` (saves on `SIGINT`) and writes recordings to
  `~/Videos/Muze-YYYYmmdd-HHMMSS.mp4`. Default capture args:
  `-w screen -f 60 -a default_output -o <file>` (override by passing extra
  args to `muze-record start/toggle`).
- **Bar plugin:** `screenrecorder` ("Screen recorder", 󰻂/󰑊) in
  `shell/bar/Bar.qml` (`cScreenRecorder`, toggles recording; shows active
  state). Movable/shown-hidden in **Settings → Top bar** via
  `showScreenRecorder` and `pluginOrder` in `MuzeSettings`/`settings.json`
  (migrated for existing configs; visible by default).
- **Keybind:** `SUPER + SHIFT + R` toggles recording (`muze-record toggle`)
  in repo/host Hyprland configs; listed in **Settings → About → Keybinds**.
- **Packages:** `gpu-screen-recorder` (official repos) and
  `intel-media-driver` added to `packages/desktop.packages`. On this hybrid
  system, recording works on both GPUs: eDP (Intel, `h264_vaapi`) and HDMI
  (NVIDIA, `h264_nvenc`) via `gpu-screen-recorder`.

## 22. Dock

Implemented a QuickShell dock for Muze inspired by Omarchy's dock.

- **Components:** `shell/dock/Dock.qml` and `shell/dock/DockModel.js`,
  registered in `shell/shell.qml` (`theme: ts.theme`).
- **Behavior:** shows pinned apps and running Hyprland toplevels (desktop-entry
  matched) with icons, running indicators, and launch pulse. **Left-click**
  focus/activate an existing window (cycles windows) or launch; **middle-click**
  launch a new instance; **right-click** opens a context menu to
  pin/unpin on the fly (persisted), focus/open, new window, or quit.
  Multi-monitor layer surfaces (`muze-dock`), with input masked to the
  dock/edge/menu so windows behind remain clickable.
- **Configuration:** `~/.config/muze/settings.json` `dock` block
  (`enabled`, `position`: `bottom|top|left|right`, `autohide`, `iconSize`,
  `screen`: `"all"` or a monitor name, `pinned`) wired through `MuzeSettings`
  and **Settings → Dock** (enable, auto-hide, icon size, screens, position,
  pinned list/unpin). Defaults ship in `config/muze/settings.json`.
- **IPC:** `qs ipc call dock toggle|show|hide` (target `dock`).
- **Fixes/polish:** corrected auto-hide reveal/hide and toggle-off visibility,
  dock pill sizing to envelop icons, per-screen vs all-screen placement,
  icon-size control, and stable geometry/layout when switching between
  horizontal and vertical positions.
- **Notes:** core Omarchy-style behavior is in place (pinned+running,
  autohide/position, pin persistence, focus/launch). Further parity possible:
  app grid, drag-reorder on the dock, minimized-window restore integration,
  Omarchy-style floating-workspace-only visibility, and richer per-app
  context menus.

## 23. Bar layout: left/center/right regions and draggable controls

Refined the top bar to prevent plugin/icon spreading and make layout fully configurable.

- **Three sections:** `shell/bar/Bar.qml` now renders the bar as **left / center / right** regions (left and right packed to edges, center anchored/centered) instead of a single spreading row. This keeps icons grouped and avoids gaps across the full bar width.
- **Region-based config:** `MuzeSettings` (`shell/settings/MuzeSettings.qml`) persists plugin placement as `appearance.barLeft`, `appearance.barCenter`, and `appearance.barRight` in `~/.config/muze/settings.json` (with `pluginOrder` kept as a derived/compat view). Existing configs using the old flat `pluginOrder` are migrated automatically into regions.
- **Drag between regions:** **Settings → Top bar → Arrange plugins** provides Left/Center/Right lists so plugins can be reordered within a region and **dragged between regions** (in addition to visibility toggles in "Show plugins").
- **Window title toggle:** the "Window title" plugin is now toggleable like other bar plugins (`showTitle` / **Settings → Top bar → Show plugins → Window title**).
- **Apps menu & settings gear draggable:** the Arch apps-menu and settings button are no longer fixed; they are bar items (`appsmenu`, `settingsbutton`, with existing `showAppsMenu`/`showSettingsButton` visibility toggles) that can be placed and dragged in any region (defaults preserved: apps menu left, settings right).
- **Caffeine bar plugin:** added `caffeine` ("Caffeine (idle inhibit)") as a bar plugin (`showCaffeine`, draggable/hideable in bar regions) wired to `CaffeineService`/`CaffeineToggle`. Toggling inhibits idle via the always-mapped Wayland IdleInhibitor (preventing hypridle lock/sleep while active) and persists state in `~/.local/state/muze/caffeine`; IPC target `idle` remains available.
- **Defaults/migration:** shipped and existing configs are migrated to include region arrays and the draggable control items; title sizing in the center region is constrained to avoid stretching the bar.
