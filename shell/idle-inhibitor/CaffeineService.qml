pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Shared caffeine (idle inhibitor) state/service.
// Owns the active/inhibited state, persists it across restarts, and exposes
// toggle methods and IPC (target "idle"). The actual Wayland IdleInhibitor is
// held by CaffeineToggle's always-mapped window, which binds to this state.
Singleton {
  id: root

  property bool active: false
  property bool restoring: true
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/muze/caffeine"

  Component.onCompleted: loadProc.running = true

  function toggle() { active = !active }
  function enable() { active = true }
  function disable() { active = false }

  onActiveChanged: {
    if (restoring) return
    saveProc.command = ["sh", "-c",
      'mkdir -p "$HOME/.local/state/muze" && printf %s "$1" > "$HOME/.local/state/muze/caffeine"',
      "sh", root.active ? "1" : "0"]
    saveProc.running = true
  }

  Process {
    id: loadProc
    running: false
    command: ["sh", "-c", 'cat "$HOME/.local/state/muze/caffeine" 2>/dev/null || true']
    stdout: StdioCollector {
      onStreamFinished: {
        root.restoring = true
        root.active = text.trim() === "1"
        root.restoring = false
      }
    }
  }

  Process { id: saveProc; running: false }

  IpcHandler {
    target: "idle"
    function toggle(): void { root.toggle() }
    function enable(): void { root.enable() }
    function disable(): void { root.disable() }
  }
}
