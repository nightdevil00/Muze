// Idle inhibitor ("caffeine") window/badge.
// Holds the actual Wayland IdleInhibitor on an always-mapped overlay window
// (required for inhibition to remain active) and shows a transient badge on
// state changes. State/persistence/IPC live in CaffeineService.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
  id: root
  property var theme: null
  property string font: "JetBrainsMono Nerd Font"
  property bool showBadge: false

  readonly property color cBg: (theme && theme.bgBase) ? theme.bgBase : "#1e1e2e"
  readonly property color cBorder: (theme && theme.bgBorder) ? theme.bgBorder : "#45475a"
  readonly property color cOrange: (theme && theme.accentOrange) ? theme.accentOrange : "#fab387"
  readonly property color cMuted: (theme && theme.textMuted) ? theme.textMuted : "#6c7086"

  Connections {
    target: CaffeineService
    function onActiveChanged() {
      if (!CaffeineService.restoring) {
        root.showBadge = true
        hideTimer.restart()
      }
    }
  }

  Timer {
    id: hideTimer
    interval: 2000
    onTriggered: root.showBadge = false
  }

  PanelWindow {
    id: host
    // Always mapped — the Wayland idle inhibitor only holds while this
    // window stays mapped, so this must never be tied to active state.
    visible: true
    focusable: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-idle-inhibitor"

    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: badge }

    anchors {
      bottom: true
      right: true
    }
    margins {
      bottom: 8
      right: 8
    }
    implicitWidth: 40
    implicitHeight: 40

    IdleInhibitor {
      enabled: CaffeineService.active
      window: host
    }

    Rectangle {
      id: badge
      anchors.centerIn: parent
      width: 32
      height: 32
      radius: 16
      color: root.cBg
      border.color: CaffeineService.active ? root.cOrange : root.cBorder
      border.width: 1
      opacity: root.showBadge ? 1 : 0

      Behavior on border.color { ColorAnimation { duration: 150 } }
      Behavior on opacity { NumberAnimation { duration: 150 } }

      Accessible.role: Accessible.Indicator
      Accessible.name: CaffeineService.active ? "Idle inhibitor active — screen will not sleep" : "Idle inhibitor inactive — normal sleep behavior"

      Text {
        anchors.centerIn: parent
        text: CaffeineService.active ? "" : ""
        color: CaffeineService.active ? root.cOrange : root.cMuted
        font.pixelSize: 16
        font.family: root.font
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: CaffeineService.toggle()
      }
    }
  }
}
