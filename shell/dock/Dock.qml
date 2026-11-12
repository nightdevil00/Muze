// Omarchy-inspired application dock for the Muze shell.
// Displays pinned and running applications (matched from Hyprland toplevels
// to desktop entries), supports focus/launch, new window, and a context menu
// for pin/unpin/quit. Configured via MuzeSettings (enabled, position,
// autohide, icon size, per-screen/all, pinned list), persists pins, and
// exposes IPC (target "dock": toggle/show/hide). Rendered as per-screen
// Wayland layer surfaces with input masked to the dock, edge trigger, and menu.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "DockModel.js" as DockModel
import "root:/settings"

Scope {
  id: root
  property var theme: null
  property string font: "JetBrainsMono Nerd Font"

  readonly property color cBg: (theme && theme.bgBase) ? theme.bgBase : Qt.rgba(0.12,0.12,0.14,1)
  readonly property color cBorder: (theme && theme.bgBorder) ? theme.bgBorder : Qt.rgba(0.3,0.3,0.35,1)
  readonly property color cAccent: (theme && theme.accentPrimary) ? theme.accentPrimary : "#7aa2f7"
  readonly property color cText: (theme && theme.textPrimary) ? theme.textPrimary : "#cdd6f4"
  readonly property color cMuted: (theme && theme.textMuted) ? theme.textMuted : "#9aa5ce"

  readonly property var dockCfg: ({
    enabled: MuzeSettings.dockEnabled,
    position: DockModel.normalizePosition(MuzeSettings.dockPosition),
    autohide: MuzeSettings.dockAutohide,
    iconSize: MuzeSettings.dockIconSize,
    screen: MuzeSettings.dockScreen || "all",
    pinned: MuzeSettings.dockPinned || []
  })
  readonly property string position: dockCfg.position
  readonly property bool vertical: DockModel.isVertical(position)
  readonly property bool autohide: dockCfg.autohide === true
  readonly property bool enabled: dockCfg.enabled !== false

  function showOnScreen(screenName) {
    var sel = dockCfg.screen || "all"
    return sel === "all" || sel === screenName
  }

  property var order: []
  property var launches: ({})
  readonly property int launchTimeout: 10000

  function isLaunching(key) { return root.launches[key] !== undefined }

  function settleLaunches() {
    var next = {}, changed = false, now = Date.now()
    for (var key in root.launches) {
      var launch = root.launches[key]
      var item = root.itemsByKey[key]
      var windows = item ? item.windows.length : 0
      if (windows > launch.windows || now - launch.at > root.launchTimeout) changed = true
      else next[key] = launch
    }
    if (changed) root.launches = next
  }

  Timer {
    interval: 1000; repeat: true
    running: Object.keys(root.launches).length > 0
    onTriggered: root.settleLaunches()
  }

  function entryFor(item) { return item ? DesktopEntries.byId(item.key) : null }

  function iconFor(item) {
    var entry = entryFor(item)
    var icon = entry && entry.icon ? entry.icon : (item ? item.key : "")
    return Quickshell.iconPath(icon, true)
  }

  function labelFor(item) {
    var entry = entryFor(item)
    return entry ? (entry.name || item.key) : (item ? item.key : "")
  }

  readonly property var pinnedKeys: DockModel.pinnedIds(root.dockCfg)

  // Build the dock item model: pinned entries + running Hyprland toplevels,
  // matched to desktop entries where possible, then ordered by session order.
  readonly property var items: {
    var _rev = DesktopEntries.applications.values.length
    var pinned = root.pinnedKeys.filter(function(id) { return !!DesktopEntries.byId(id) })
    var windows = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var tl = toplevels[i]
      var wl = tl.wayland
      if (!wl || !wl.appId || wl.parent) continue
      var entry = DesktopEntries.heuristicLookup(wl.appId) || DesktopEntries.byId(wl.appId)
      var ws = tl.workspace
      windows.push({
        key: entry ? entry.id : wl.appId,
        hasEntry: !!entry && !entry.noDisplay,
        workspaceId: ws ? ws.id : -1,
        minimized: false,
        address: tl.address,
        toplevel: tl
      })
    }
    return DockModel.orderItems(DockModel.buildItems(pinned, windows), root.order)
  }

  readonly property var itemsByKey: {
    var byKey = {}
    for (var i = 0; i < root.items.length; i++) byKey[root.items[i].key] = root.items[i]
    return byKey
  }

  // Launch an app (desktop entry execute, with gtk-launch fallback) and mark
  // it as "launching" until a matching window appears or timeout elapses.
  function launch(item) {
    var entry = entryFor(item)
    if (!entry) return
    var next = Object.assign({}, root.launches)
    next[item.key] = { at: Date.now(), windows: item.windows.length }
    root.launches = next
    try { entry.execute() } catch (e) {
      launchProc.command = ["gtk-launch", item.key]
      launchProc.running = true
    }
  }

  Process { id: launchProc; running: false }

  // Focus/raise a specific Hyprland window (0.57 Lua dispatcher syntax).
  function bringForward(window) {
    var addr = String(window.address || "")
    if (!addr) { if (window.toplevel && window.toplevel.activate) window.toplevel.activate(); return }
    if (addr.indexOf("0x") !== 0) addr = "0x" + addr
    var target = 'window = "address:' + addr + '"'
    var cmd = "hyprctl dispatch " + JSON.stringify("hl.dsp.focus({ " + target + " })") +
      " && hyprctl dispatch " + JSON.stringify("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
    focusProc.command = ["sh", "-c", cmd]
    focusProc.running = true
  }

  Process { id: focusProc; running: false }

  // Click behavior: focus an existing window (cycling on active workspace)
  // or launch the app if no windows are running.
  function activate(item) {
    if (!item) return
    if (item.windows.length === 0) { root.launch(item); return }
    var mon = Hyprland.focusedMonitor
    var wsId = mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1
    var idx = DockModel.pickWindow(item.windows.map(function(w) {
      return { workspaceId: w.workspaceId, minimized: w.minimized, activated: w.toplevel.activated }
    }), wsId)
    if (idx >= 0) root.bringForward(item.windows[idx])
  }

  function quitApp(item) {
    if (!item) return
    var wins = item.windows.slice()
    for (var i = 0; i < wins.length; i++) {
      try { wins[i].toplevel.close() } catch (e) {}
    }
  }

  function isPinned(key) { return root.pinnedKeys.indexOf(key) >= 0 }
  function savePins(pins) { MuzeSettings.apply("dockPinned", pins) }
  function setPinned(key, pinned) {
    if (!key) return
    var pins = root.pinnedKeys.slice()
    var idx = pins.indexOf(key)
    if (pinned && idx < 0) pins.push(key)
    else if (!pinned && idx >= 0) pins.splice(idx, 1)
    savePins(pins)
  }

  // IPC interface: `qs ipc call dock toggle|show|hide`
  IpcHandler {
    target: "dock"
    function toggle(): void { MuzeSettings.apply("dockEnabled", !MuzeSettings.dockEnabled) }
    function show(): void { MuzeSettings.apply("dockEnabled", true) }
    function hide(): void { MuzeSettings.apply("dockEnabled", false) }
  }

  // One dock surface per screen (filtered by dock.screen setting).
  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        readonly property bool screenEnabled: root.showOnScreen(modelData.name)
        visible: root.enabled && screenEnabled
        color: "transparent"

        WlrLayershell.namespace: "muze-dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: menuOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        anchors.top: root.position === "top" || root.vertical
        anchors.bottom: root.position === "bottom" || root.vertical
        anchors.left: root.position === "left" || !root.vertical
        anchors.right: root.position === "right" || !root.vertical

        readonly property int iconSize: MuzeSettings.dockIconSize
        readonly property int slotSize: iconSize + Math.max(8, Math.round(iconSize * 0.25))
        readonly property int pad: Math.max(4, Math.round(iconSize * 0.15))
        readonly property int edge: 6
        readonly property int menuRoom: 190
        readonly property int dockThickness: slotSize + pad * 2 + 8

        property bool revealed: !root.autohide
        property var menuItem: null
        readonly property bool menuOpen: menuItem !== null
        readonly property bool contentShown: (root.enabled && screenEnabled) && (revealed || menuOpen)

        implicitWidth: root.vertical ? (dockThickness + menuRoom) : modelData.width
        implicitHeight: root.vertical ? modelData.height : (dockThickness + menuRoom)

        function openMenu(item) { menuItem = item; revealed = true }
        function closeMenu() { menuItem = null }

        Connections {
          target: root
          function onAutohideChanged() { win.revealed = !root.autohide }
          function onEnabledChanged() { if (root.enabled) win.revealed = !root.autohide }
          function onPositionChanged() { win.revealed = !root.autohide; win.closeMenu() }
        }

        // Input region: only dock body, edge trigger (autohide), or open menu
        // receive pointer events so transparent areas don't block windows.
        mask: Region {
          item: win.contentShown ? dockBg : (root.autohide ? edgeTrigger : null)
          Region { item: win.menuOpen ? ctxMenu : null }
        }

        Timer {
          id: hideTimer
          interval: 350
          onTriggered: {
            if (!root.autohide || win.menuOpen) return
            if (!dockHover.hovered && !edgeHover.hovered)
              win.revealed = false
          }
        }

        Item {
          id: edgeTrigger
          visible: root.autohide
          z: 10
          x: root.position === "right" ? (win.width - width) : 0
          y: root.position === "bottom" ? (win.height - height) : 0
          width: root.vertical ? win.edge : win.width
          height: root.vertical ? win.height : win.edge
          HoverHandler {
            id: edgeHover
            onHoveredChanged: {
              if (hovered) { win.revealed = true }
              else if (root.autohide) hideTimer.restart()
            }
          }
        }

        // Visual dock container (pill) sized to the icon layout and placed at
        // the configured screen edge/center.
        Rectangle {
          id: dockBg
          visible: win.contentShown
          z: 5
          radius: 16
          color: Qt.rgba(cBg.r, cBg.g, cBg.b, 0.95)
          border.color: cBorder
          border.width: 1

          // Position at the chosen edge, centered along it
          x: root.position === "left" ? 6
           : root.position === "right" ? (win.width - width - 6)
           : Math.round((win.width - width) / 2)
          y: root.position === "top" ? 6
           : root.position === "bottom" ? (win.height - height - 6)
           : Math.round((win.height - height) / 2)

          implicitWidth: iconsLayout.implicitWidth + pad * 2
          implicitHeight: iconsLayout.implicitHeight + pad * 2
          width: implicitWidth
          height: implicitHeight

          HoverHandler {
            id: dockHover
            onHoveredChanged: {
              if (hovered) win.revealed = true
              else if (root.autohide) hideTimer.restart()
            }
          }

          Item {
            id: iconsLayout
            anchors.centerIn: parent
            implicitWidth: root.vertical ? colLayout.implicitWidth : rowLayout.implicitWidth
            implicitHeight: root.vertical ? colLayout.implicitHeight : rowLayout.implicitHeight

            Row {
              id: rowLayout
              visible: !root.vertical
              spacing: 4
              Repeater { model: root.items; delegate: slotDelegate }
            }
            Column {
              id: colLayout
              visible: root.vertical
              spacing: 4
              Repeater { model: root.items; delegate: slotDelegate }
            }
          }
        }

        Component {
          id: slotDelegate
          Item {
            id: slot
            required property var modelData
            required property int index
            implicitWidth: win.slotSize
            implicitHeight: win.slotSize
            width: implicitWidth
            height: implicitHeight

            readonly property bool hovered: slotMouse.containsMouse
            readonly property bool running: modelData.windows.length > 0
            readonly property bool launching: root.isLaunching(modelData.key)
            readonly property bool pinned: root.isPinned(modelData.key)

            Rectangle {
              anchors.fill: parent
              anchors.margins: 2
              radius: 10
              color: slot.hovered ? Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.18) : "transparent"
            }

            Image {
              anchors.centerIn: parent
              width: win.iconSize; height: win.iconSize
              source: root.iconFor(modelData)
              sourceSize: Qt.size(win.iconSize * 2, win.iconSize * 2)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              mipmap: true
              opacity: slot.running || slot.launching ? 1.0 : 0.7
              scale: slot.hovered ? 1.1 : 1.0
              Behavior on scale { NumberAnimation { duration: 100 } }
            }

            Rectangle {
              visible: slot.running
              width: slot.pinned ? 14 : 6
              height: 4; radius: 2
              color: cAccent
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
            }

            Rectangle {
              visible: slot.pinned && !slot.running
              width: 5; height: 5; radius: 3
              color: cMuted
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
            }

            MouseArea {
              id: slotMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                  win.openMenu(modelData)
                  return
                }
                win.closeMenu()
                if (mouse.button === Qt.MiddleButton) root.launch(modelData)
                else root.activate(modelData)
              }
            }
          }
        }

        component MenuAction: Rectangle {
          id: ma
          property string label: ""
          property bool danger: false
          property bool visible_: true
          visible: visible_
          signal triggered()
          width: Math.max(190, maText.implicitWidth + 22)
          height: visible ? 30 : 0
          radius: 6
          color: maMouse.containsMouse ? (danger ? "#e06c75" : cAccent) : "transparent"
          Text {
            id: maText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: ma.label
            color: maMouse.containsMouse ? cBg : (danger ? "#e06c75" : cText)
            font.pixelSize: 11
            font.family: root.font
          }
          MouseArea {
            id: maMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ma.triggered()
          }
        }

        // Right-click context menu for the selected app (pin/unpin, focus/open,
        // new window, quit). Positioned adjacent to the dock inside the surface.
        Rectangle {
          id: ctxMenu
          visible: win.menuOpen && win.menuItem !== null
          z: 30
          radius: 10
          color: Qt.rgba(cBg.r, cBg.g, cBg.b, 0.98)
          border.color: cBorder
          border.width: 1
          width: menuCol.implicitWidth + 14
          height: menuCol.implicitHeight + 12

          x: {
            var px = root.vertical
              ? (root.position === "left" ? dockBg.x + dockBg.width + 8 : dockBg.x - width - 8)
              : Math.round((win.width - width) / 2)
            return Math.max(8, Math.min(win.width - width - 8, px))
          }
          y: {
            var py = root.vertical
              ? Math.round((win.height - height) / 2)
              : (root.position === "bottom" ? dockBg.y - height - 8 : dockBg.y + dockBg.height + 8)
            return Math.max(8, Math.min(win.height - height - 8, py))
          }

          Column {
            id: menuCol
            anchors.centerIn: parent
            spacing: 2

            property var dockItem: win.menuItem
            property bool pinned: dockItem ? root.isPinned(dockItem.key) : false
            property bool running: dockItem ? dockItem.windows.length > 0 : false

            Text {
              text: menuCol.dockItem ? root.labelFor(menuCol.dockItem) : ""
              color: cText
              font.pixelSize: 12
              font.bold: true
              font.family: root.font
              leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 4
              elide: Text.ElideRight
              width: Math.min(implicitWidth, 220)
            }

            Rectangle { width: parent.width; height: 1; color: cBorder; opacity: 0.6 }

            MenuAction {
              label: menuCol.running ? "Focus" : "Open"
              onTriggered: { root.activate(menuCol.dockItem); win.closeMenu() }
            }
            MenuAction {
              label: "New window"
              visible_: menuCol.running
              onTriggered: { root.launch(menuCol.dockItem); win.closeMenu() }
            }
            MenuAction {
              label: menuCol.pinned ? "Unpin from dock" : "Pin to dock"
              onTriggered: { root.setPinned(menuCol.dockItem.key, !menuCol.pinned); win.closeMenu() }
            }
            MenuAction {
              label: "Quit"
              visible_: menuCol.running
              danger: true
              onTriggered: { root.quitApp(menuCol.dockItem); win.closeMenu() }
            }
          }
        }
      }
    }
  }
}
