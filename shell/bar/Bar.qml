// Top bar shell component.
// Renders a per-screen Wayland bar split into left/center/right sections
// so plugins don't spread; apps-menu/settings are draggable bar items.
// Plugin placement/order/visibility are driven by MuzeSettings regions. Integrates system services
// (workspaces, media/MPRIS, audio, brightness, network, battery, tray,
// bluetooth, recording, power, etc.) and exposes IPC (target "bar").

// Muze top bar. Plugins are placed in left/center/right regions
// (MuzeSettings.barLeft/barCenter/barRight) and can be reordered/moved
// between regions in Settings. Arch apps-menu and settings stay at the ends.
import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "root:/settings"
import "root:/bluetooth"
import "root:/idle-inhibitor"

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "JetBrainsMono Nerd Font"
  property bool barVisible: true

  property var activePlayer: {
    const players = Mpris.players.values;
    if (!players || players.length === 0) return null;
    for (const p of players) {
      if (p.playbackState === MprisPlaybackState.Playing) return p;
    }
    return players[0];
  }

  IpcHandler {
    target: "bar"
    function toggle(): void { root.barVisible = !root.barVisible; }
  }

  // Track default audio sink for volume state in bar audio widgets.
  PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

  // ---- brightness state --------------------------------------------------
  property real brightnessValue: 0
  property real brightnessMax: 1

  FileView {
    id: brightnessFile
    path: ""
    watchChanges: true
    onFileChanged: brightnessReadProc.running = true
  }

  Process {
    id: brightnessReadProc
    command: ["brightnessctl", "get"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const val = parseInt(text.trim());
        if (!isNaN(val) && root.brightnessMax > 0)
          root.brightnessValue = val / root.brightnessMax;
      }
    }
  }

  Process { id: brightnessSetProc; running: false }

  Process {
    id: backlightDiscovery
    command: ["sh", "-c", "p=$(ls -d /sys/class/backlight/*/brightness 2>/dev/null | head -1); [ -n \"$p\" ] && echo \"$p\" && cat \"${p%brightness}max_brightness\""]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        if (lines.length >= 2) {
          const max = parseInt(lines[1]);
          if (!isNaN(max) && max > 0) root.brightnessMax = max;
          brightnessFile.path = lines[0];
          brightnessReadProc.running = true;
        }
      }
    }
  }

  // ---- IPC helpers (other targets in this same shell) -------------------
  // Bar buttons trigger other shell modules by calling their IPC targets via
  // `qs ipc call ...` processes (launcher, settings, power, recorder, etc.).
  Process { id: launcherProc; running: false }
  Process { id: settingsProc; running: false }
  Process { id: powerProc; running: false }
  Process { id: recorderProc; running: false }
  Process { id: screenshotProc; running: false }
  property bool recordingActive: false
  function toggleRecording() {
    recorderToggleProc.command = ["muze-record", "toggle"];
    recorderToggleProc.running = true;
  }
  function takeScreenshot() {
    screenshotProc.command = ["muze-screenshot", "region-clip"];
    screenshotProc.running = true;
  }
  Process {
    id: recorderToggleProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: recorderStatusProc.running = true
    }
    onExited: recorderStatusProc.running = true
  }
  Process {
    id: recorderStatusProc
    running: true
    command: ["muze-record", "status"]
    stdout: StdioCollector {
      onStreamFinished: root.recordingActive = text.trim() === "recording"
    }
  }
  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: if (!recorderStatusProc.running) recorderStatusProc.running = true
  }
  function openLauncher() {
    launcherProc.command = ["qs", "ipc", "call", "launcher", "toggle"];
    launcherProc.running = true;
  }
  function openSettings() {
    settingsProc.command = ["qs", "ipc", "call", "muze", "settings"];
    settingsProc.running = true;
  }
  function openPowerMenu() {
    powerProc.command = ["qs", "ipc", "call", "power", "toggle"];
    powerProc.running = true;
  }

  // ---- plugin component lookup ------------------------------------------
  // Maps plugin IDs from MuzeSettings.pluginOrder to their visual components.
  // The bar renders plugins by iterating the configured order and loading
  // the matching component for each visible plugin slot.
  function componentFor(id) {
    switch (id) {
      case "appsmenu":    return cAppsMenu;
      case "settingsbutton": return cSettingsButton;
      case "clock":       return cClock;
      case "workspaces":  return cWorkspaces;
      case "media":       return cMedia;
      case "title":       return cTitle;
      case "volume":      return cVolume;
      case "brightness":  return cBrightness;
      case "cpu":         return cCpu;
      case "network":     return cNetwork;
      case "bluetooth":   return cBluetooth;
      case "battery":     return cBattery;
      case "temperature": return cTemperature;
      case "tray":        return cTray;
      case "power":       return cPower;
      case "screenrecorder": return cScreenRecorder;
      case "screenshot":  return cScreenshot;
      case "caffeine":    return cCaffeine;
      default:            return cEmpty;
    }
  }

  // Fixed left button: Arch logo that opens the app launcher (SUPER+D).
  // Kept outside the reorderable plugin list so it always anchors the left side.
  Component {
    id: cAppsMenu
    Rectangle {
      id: appsMenu
      objectName: "apps-menu"
      Accessible.role: Accessible.Button
      Accessible.name: "apps-menu"
      width: 28; height: 24
      radius: 8
      color: appsMenuHover.containsMouse ? root.theme.bgSelected : "transparent"
      Image {
        anchors.centerIn: parent
        source: "root:/assets/apps-menu.svg"
        sourceSize.width: 16; sourceSize.height: 16
        width: 16; height: 16
        fillMode: Image.PreserveAspectFit
        smooth: true
      }
      MouseArea {
        id: appsMenuHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openLauncher()
      }
    }
  }

  // Fixed right button: opens Muze settings (SUPER+,).
  Component {
    id: cSettingsButton
    Rectangle {
      id: settingsButton
      objectName: "muze-settings-button"
      Accessible.role: Accessible.Button
      Accessible.name: "Muze settings"
      width: 28; height: 24
      radius: 8
      color: settingsHover.containsMouse ? root.theme.bgSelected : root.theme.bgSurface
      Text {
        anchors.centerIn: parent
        text: "⚙"
        color: root.theme.accentPrimary
        font.pixelSize: 14
        font.family: root.font
      }
      MouseArea {
        id: settingsHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openSettings()
      }
    }
  }

  Component {
    id: cScreenRecorder
    Rectangle {
      id: recButton
      objectName: "muze-screenrecorder-button"
      Accessible.role: Accessible.Button
      Accessible.name: root.recordingActive ? "Stop recording" : "Start recording"
      height: 24
      width: 26
      radius: 12
      color: root.recordingActive ? root.theme.accentRed
           : (recHover.containsMouse ? root.theme.bgSelected : root.theme.bgSurface)
      Text {
        anchors.centerIn: parent
        text: root.recordingActive ? "󰑊" : "󰻂"
        color: root.recordingActive ? root.theme.bgBase : root.theme.textPrimary
        font.pixelSize: 14
        font.family: root.font
      }
      Rectangle {
        visible: root.recordingActive
        anchors.centerIn: parent
        width: 20; height: 20; radius: 10
        color: "transparent"
        border.color: root.theme.bgBase
        border.width: 0
      }
      MouseArea {
        id: recHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleRecording()
      }
    }
  }

  Component {
    id: cScreenshot
    Rectangle {
      id: shotButton
      objectName: "muze-screenshot-button"
      Accessible.role: Accessible.Button
      Accessible.name: "Take region screenshot"
      height: 24
      width: 26
      radius: 12
      color: shotHover.containsMouse ? root.theme.bgSelected : root.theme.bgSurface
      Text {
        anchors.centerIn: parent
        text: "󰹑"
        color: root.theme.textPrimary
        font.pixelSize: 14
        font.family: root.font
      }
      MouseArea {
        id: shotHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.takeScreenshot()
      }
    }
  }

  Component {
    id: cPower
    Rectangle {
      id: powerButton
      objectName: "muze-power-button"
      Accessible.role: Accessible.Button
      Accessible.name: "Power menu"
      height: 24
      width: 26
      radius: 12
      color: powerHover.containsMouse ? root.theme.bgSelected : root.theme.bgSurface
      Text {
        anchors.centerIn: parent
        text: "󰐥"
        color: powerHover.containsMouse ? root.theme.accentRed : root.theme.textPrimary
        font.pixelSize: 14
        font.family: root.font
      }
      MouseArea {
        id: powerHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openPowerMenu()
      }
    }
  }


  Component {
    id: cCaffeine
    Rectangle {
      id: caffeineButton
      objectName: "muze-caffeine-button"
      Accessible.role: Accessible.Button
      Accessible.name: CaffeineService.active ? "Caffeine on (idle inhibited)" : "Caffeine off"
      height: 24
      width: 26
      radius: 12
      color: caffeineHover.containsMouse ? root.theme.bgSelected : root.theme.bgSurface
      Text {
        anchors.centerIn: parent
        text: CaffeineService.active ? "" : "󰾪"
        color: CaffeineService.active ? root.theme.accentOrange : root.theme.textMuted
        font.pixelSize: 14
        font.family: root.font
      }
      MouseArea {
        id: caffeineHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: CaffeineService.toggle()
      }
    }
  }

  Component { id: cEmpty; Item { width: 0; height: 24 } }

  // ---- plugin widgets ---------------------------------------------------
  Component {
    id: cClock
    Rectangle {
      height: 24
      width: timeDate.width + 16
      radius: 12
      color: root.theme.bgSurface
      Row {
        id: timeDate
        anchors.centerIn: parent
        spacing: 8
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Time.timeString
          color: root.theme.textPrimary
          font.pixelSize: 12
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Time.dateString
          color: root.theme.textSecondary
          font.pixelSize: 12
          font.family: root.font
        }
      }
    }
  }

  Component {
    id: cWorkspaces
    Item {
      implicitWidth: wsRow.implicitWidth
      implicitHeight: 24
      Process { id: wsScrollProc; running: false }
      Row {
        id: wsRow
        anchors.fill: parent
        spacing: 4
        Repeater {
          model: Hyprland.workspaces
          Rectangle {
            id: wsPill
            required property var modelData
            property bool urgentBlink: false
            width: modelData.focused ? 32 : 24
            height: 24
            radius: 12
            color: modelData.focused ? root.theme.accentPrimary :
                   modelData.urgent && urgentBlink ? root.theme.accentRed : root.theme.bgSurface
            Behavior on color { ColorAnimation { duration: 150 } }
            SequentialAnimation {
              loops: Animation.Infinite
              running: wsPill.modelData.urgent && !wsPill.modelData.focused
              PropertyAction { target: wsPill; property: "urgentBlink"; value: true }
              PauseAnimation { duration: 500 }
              PropertyAction { target: wsPill; property: "urgentBlink"; value: false }
              PauseAnimation { duration: 500 }
              onStopped: wsPill.urgentBlink = false
            }
            Text {
              anchors.centerIn: parent
              text: wsPill.modelData.id
              color: wsPill.modelData.focused ? root.theme.bgBase : root.theme.textPrimary
              font.pixelSize: 11
              font.family: root.font
              font.bold: wsPill.modelData.focused
            }
            MouseArea {
              anchors.fill: parent
              onClicked: wsPill.modelData.activate()
              onWheel: (wheel) => {
                const dir = wheel.angleDelta.y > 0 ? "e-1" : "e+1";
                wsScrollProc.command = ["hyprctl", "dispatch",
                  "hl.dsp.focus({ workspace = \"" + dir + "\" })"];
                wsScrollProc.running = true;
              }
            }
            Behavior on width { NumberAnimation { duration: 150 } }
          }
        }
      }
    }
  }

  Component {
    id: cMedia
    Rectangle {
      height: 24
      width: nowPlayingContent.width + 16
      radius: 12
      color: root.theme.bgSurface
      visible: root.activePlayer !== null
      Row {
        id: nowPlayingContent
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 8
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.activePlayer && root.activePlayer.isPlaying ? "󰐊" : "󰏤"
          color: root.theme.accentPrimary
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (!root.activePlayer) return "";
            const artist = root.activePlayer.trackArtist || "";
            const title = root.activePlayer.trackTitle || "";
            return artist ? artist + " - " + title : title;
          }
          color: root.theme.textPrimary
          font.pixelSize: 11
          font.family: root.font
          elide: Text.ElideRight
          width: Math.min(implicitWidth, 200)
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activePlayer.togglePlaying()
      }
    }
  }

  Component {
    id: cTitle
    Item {
      implicitWidth: Math.min(titleText.implicitWidth, 360)
      implicitHeight: 24
      width: implicitWidth
      Text {
        id: titleText
        anchors.fill: parent
        text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
        color: root.theme.textPrimary
        font.pixelSize: 12
        font.family: root.font
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  Component {
    id: cVolume
    Rectangle {
      height: 24
      width: volContent.width + 12
      radius: 12
      color: root.theme.bgSurface
      Row {
        id: volContent
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            const sink = Pipewire.defaultAudioSink;
            if (!sink || !sink.audio || sink.audio.muted || sink.audio.volume <= 0) return "󰖁";
            if (sink.audio.volume < 0.33) return "󰕿";
            if (sink.audio.volume < 0.66) return "󰖀";
            return "󰕾";
          }
          color: {
            const sink = Pipewire.defaultAudioSink;
            if (!sink || !sink.audio || sink.audio.muted) return root.theme.textMuted;
            return root.theme.accentPrimary;
          }
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            const sink = Pipewire.defaultAudioSink;
            if (!sink || !sink.audio) return "–";
            if (sink.audio.muted) return "Mute";
            return Math.round(sink.audio.volume * 100) + "%";
          }
          color: root.theme.textPrimary
          font.pixelSize: 11
          font.family: root.font
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: {
          const sink = Pipewire.defaultAudioSink;
          if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
        }
        onWheel: (wheel) => {
          const sink = Pipewire.defaultAudioSink;
          if (!sink || !sink.audio) return;
          const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
          sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + delta));
        }
      }
    }
  }

  Component {
    id: cBrightness
    Rectangle {
      height: 24
      width: brightContent.width + 12
      radius: 12
      color: root.theme.bgSurface
      visible: brightnessFile.path !== ""
      Row {
        id: brightContent
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰃠"
          color: root.theme.accentOrange
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Math.round(root.brightnessValue * 100) + "%"
          color: root.theme.textPrimary
          font.pixelSize: 11
          font.family: root.font
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onWheel: (wheel) => {
          brightnessSetProc.command = wheel.angleDelta.y > 0
            ? ["brightnessctl", "set", "5%+"]
            : ["brightnessctl", "set", "5%-"];
          brightnessSetProc.running = true;
        }
      }
    }
  }

  Component {
    id: cCpu
    Rectangle {
      height: 24
      width: cpuContent.width + 12
      radius: 12
      color: root.theme.bgSurface
      Row {
        id: cpuContent
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰻠"
          color: root.theme.accentOrange
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: SystemInfo.cpuUsage
          color: root.theme.textPrimary
          font.pixelSize: 11
          font.family: root.font
        }
      }
    }
  }

  Component {
    id: cNetwork
    Rectangle {
      height: 24
      width: netContent.width + 12
      radius: 12
      color: root.theme.bgSurface
      Row {
        id: netContent
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (SystemInfo.networkType === "ethernet") return "󰈀"
            if (SystemInfo.networkType === "wifi") return "󰖩"
            return "󰖪"
          }
          color: SystemInfo.networkType === "disconnected" ? root.theme.textMuted : root.theme.accentGreen
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: SystemInfo.networkInfo
          color: root.theme.textPrimary
          font.pixelSize: 11
          font.family: root.font
        }
      }
    }
  }

  // Compact Bluetooth pill: icon only (plus a dot when a device is
  // connected). Full status is in the tooltip / Settings -> Bluetooth.
  Component {
    id: cBluetooth
    Rectangle {
      id: btPill
      height: 24
      width: 26
      radius: 12
      color: btHover.containsMouse ? root.theme.bgSelected : root.theme.bgSurface
      Accessible.role: Accessible.Button
      Accessible.name: BluetoothService.connectedName !== ""
          ? "Bluetooth: connected to " + BluetoothService.connectedName
          : (BluetoothService.powered ? "Bluetooth on" : "Bluetooth off")

      Text {
        anchors.centerIn: parent
        text: "󰂯"
        color: BluetoothService.powered ? root.theme.accentCyan : root.theme.textMuted
        font.pixelSize: 14
        font.family: root.font
      }
      Rectangle {
        visible: BluetoothService.connectedName !== ""
        width: 6; height: 6; radius: 3
        color: root.theme.accentGreen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 3
      }

      // Hover tooltip with the full state / connected device name.
      Rectangle {
        visible: btHover.containsMouse
        anchors.top: parent.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: btTip.implicitWidth + 16
        height: 24
        radius: 6
        color: root.theme.bgBase
        border.color: root.theme.bgBorder
        border.width: 1
        z: 50
        Text {
          id: btTip
          anchors.centerIn: parent
          text: !BluetoothService.available ? "No Bluetooth adapter"
              : BluetoothService.connectedName !== "" ? BluetoothService.connectedName
              : BluetoothService.powered ? "Bluetooth on" : "Bluetooth off"
          color: root.theme.textPrimary
          font.pixelSize: 10
          font.family: root.font
        }
      }

      MouseArea {
        id: btHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
          if (mouse.button === Qt.RightButton) {
            settingsProc.command = ["qs", "ipc", "call", "muze", "bluetooth"]
            settingsProc.running = true
          } else {
            BluetoothService.togglePower()
          }
        }
      }
    }
  }

  Component {
    id: cBattery
    Rectangle {
      height: 24
      width: battContent.width + 12
      radius: 12
      color: root.theme.bgSurface
      readonly property color batteryColor: {
        if (SystemInfo.batteryCharging) return root.theme.accentGreen;
        if (SystemInfo.batteryLevelRaw > 20) return root.theme.batteryGood;
        if (SystemInfo.batteryLevelRaw > 10) return root.theme.batteryWarning;
        return root.theme.batteryCritical;
      }
      Row {
        id: battContent
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: SystemInfo.batteryIcon
          color: parent.parent.batteryColor
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: SystemInfo.batteryLevel
          color: root.theme.textPrimary
          font.pixelSize: 11
          font.family: root.font
        }
      }
    }
  }

  Component {
    id: cTemperature
    Rectangle {
      height: 24
      width: tempContent.width + 12
      radius: 12
      color: root.theme.bgSurface
      Row {
        id: tempContent
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰔏"
          color: root.theme.accentRed
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: SystemInfo.temperature
          color: root.theme.textPrimary
          font.pixelSize: 11
          font.family: root.font
        }
      }
    }
  }

  Component {
    id: cTray
    Rectangle {
      implicitHeight: 24
      implicitWidth: trayIcons.implicitWidth + 8
      radius: 12
      color: root.theme.bgSurface
      RowLayout {
        id: trayIcons
        anchors.centerIn: parent
        spacing: 2
        Repeater {
          model: SystemTray.items
          MouseArea {
            id: trayDelegate
            required property SystemTrayItem modelData
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: (mouse) => {
              if (mouse.button === Qt.LeftButton) modelData.activate()
              else if (mouse.button === Qt.RightButton && modelData.hasMenu) menuAnchor.open()
              else if (mouse.button === Qt.MiddleButton) modelData.secondaryActivate()
            }
            IconImage {
              anchors.centerIn: parent
              source: trayDelegate.modelData.icon
              implicitSize: 16
            }
            QsMenuAnchor {
              id: menuAnchor
              menu: trayDelegate.modelData.menu
              anchor.window: trayDelegate.QsWindow.window
              anchor.adjustment: PopupAdjustment.Flip
              anchor.onAnchoring: {
                const window = trayDelegate.QsWindow.window;
                const widgetRect = window.contentItem.mapFromItem(
                  trayDelegate, 0, trayDelegate.height,
                  trayDelegate.width, trayDelegate.height);
                menuAnchor.anchor.rect = widgetRect;
              }
            }
          }
        }
      }
    }
  }

  // ---- windows (one bar per screen) --------------------------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: barWindow
      required property var modelData
      screen: modelData
      visible: root.barVisible

      anchors { top: true; left: true; right: true }
      implicitHeight: MuzeSettings.barHeight
      color: Qt.rgba(root.theme.bgBase.r, root.theme.bgBase.g,
                     root.theme.bgBase.b, MuzeSettings.barOpacity / 100)

      // Three-section layout (left / center / right) to prevent plugins from
      // spreading across the full bar width. Fixed controls (apps menu, settings)
      // stay at the outer edges; plugin regions come from MuzeSettings.
      Item {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8

        // Left section: left-region plugins (e.g. apps menu, workspaces), packed to the left.
        Row {
          id: leftSection
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          Repeater {
            model: MuzeSettings.barLeft
            Loader {
              required property string modelData
              sourceComponent: root.componentFor(modelData)
              visible: MuzeSettings.pluginVisible(modelData)
              anchors.verticalCenter: leftSection.verticalCenter
            }
          }
        }

        // Center section: centered plugins (e.g. workspaces/clock/media/title).
        Row {
          id: centerSection
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          Repeater {
            model: MuzeSettings.barCenter
            Loader {
              required property string modelData
              sourceComponent: root.componentFor(modelData)
              visible: MuzeSettings.pluginVisible(modelData)
              anchors.verticalCenter: centerSection.verticalCenter
            }
          }
        }

        // Right section: right-region plugins (e.g. status items, settings), packed to the right.
        Row {
          id: rightSection
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          Repeater {
            model: MuzeSettings.barRight
            Loader {
              required property string modelData
              sourceComponent: root.componentFor(modelData)
              visible: MuzeSettings.pluginVisible(modelData)
              anchors.verticalCenter: rightSection.verticalCenter
            }
          }
        }
      }
    }
  }
}
