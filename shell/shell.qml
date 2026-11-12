// Muze -- a QuickShell desktop shell for Hyprland.
//
// Entry point. Modules are kept independent (each has its own DefaultTheme
// fallback) so any one of them can be swapped out or disabled. `ts.theme` is
// the shared palette: either one of 206 curated themes or the matugen palette
// generated from the current wallpaper.
//@ pragma UseQApplication
//@ pragma DefaultEnv QT_QPA_PLATFORMTHEME=gtk3
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import Quickshell
import Quickshell.Io
import QtQuick
import "bar"
import "app-launcher"
import "notifications"
import "theme-switcher"
import "wallpaper"
import "osd"
import "monitor-manager"
import "idle-inhibitor"
import "settings"
import "clipboard"
import "power-menu"
import "dock"
import "root:/settings"
import "root:/clipboard"

// Root scope: instantiates every UI module once and shares a single active
// theme object (`ts.theme`) from ThemeSwitcher. Modules are otherwise
// independent (services/panels/overlays each own their Wayland surfaces,
// IPC handlers, and state). Load order here defines what exists in the shell;
// disabling a feature is as simple as removing its component instance.
Scope {
  // Central theme provider: manages curated themes and matugen/wallpaper
  // palette generation. Exposes the active palette as `ts.theme`.
  ThemeSwitcher { id: ts }

  // Top status bar (plugins, tray, clock, workspaces, quick actions).
  Bar               { theme: ts.theme }
  // Application launcher overlay (SUPER+D / IPC "launcher").
  AppLauncher       { theme: ts.theme }
  // Notification daemon popup stack (freedesktop notifications via Quickshell).
  NotificationPopup { theme: ts.theme }
  // Wallpaper picker/manager and wallpaper application integration.
  WallpaperManager  { theme: ts.theme }
  // On-screen display for volume/brightness changes.
  OSD               { theme: ts.theme }
  // Visual monitor/layout manager (Hyprland monitor configuration).
  MonitorManager    { theme: ts.theme }
  // Idle inhibitor ("caffeine") toggle/badge and Wayland inhibitor.
  CaffeineToggle    { theme: ts.theme }
  // Unified settings panel (appearance, bar, Hyprland, dock, power, etc.).
  Settings          { theme: ts.theme }
  // Clipboard history panel/service integration.
  ClipboardPanel    { theme: ts.theme }
  // Power/session menu (lock/logout/reboot/shutdown).
  PowerMenu         { theme: ts.theme }
  // App dock (pinned + running apps), per-screen/position/autohide.
  Dock              { theme: ts.theme }
}
