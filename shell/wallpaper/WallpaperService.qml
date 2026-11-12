// Wallpaper state and application service.
// Tracks the current wallpaper selection, persists/restores it, and applies it
// (e.g. via awww/muze-wallpaper helpers) across monitors. Integrates with
// theme/matugen flows so wallpaper-driven colors can be regenerated.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  property list<string> wallpapers: []
  property string currentWallpaper: ""
  property string backend: "awww"

  // Scan wallpaper directories
  Process {
    id: scanner
    command: ["sh", "-c",
      "find ~/Pictures/Wallpapers ~/Pictures -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort -u | head -200"
    ]
    running: false
    stdout: SplitParser {
      onRead: data => {
        const path = data.trim();
        if (path !== "") {
          root.wallpapers = [...root.wallpapers, path];
        }
      }
    }
  }

  // Load saved wallpaper path
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/quickshell/wallpaper.conf"
    onTextChanged: {
      const saved = configFile.text().trim();
      if (saved !== "") root.currentWallpaper = saved;
    }
  }

  Component.onCompleted: {
    scanner.running = true;
  }

  function rescan() {
    wallpapers = [];
    scanner.running = true;
  }

  function setWallpaper(path) {
    currentWallpaper = path;

    // muze-wallpaper addresses EVERY output explicitly and uses a per-output
    // fade (awww's `grow` transition has one global centre and can leave a
    // secondary monitor on the old image). It also persists wallpaper.conf.
    setProcess.command = ["muze-wallpaper", path];
    setProcess.running = true;
  }

  Process {
    id: setProcess
    command: []
    running: false
  }

  Process {
    id: saveProcess
    command: []
    running: false
  }
}
