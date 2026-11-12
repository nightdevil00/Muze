// Power/session action menu overlay.
// Shows a centered modal panel with session actions (lock, log out, reboot,
// shutdown), supports keyboard navigation/activation, and exposes IPC
// (target "power": toggle/open/close). Actions invoke system/session commands.

// Muze power menu -- Lock, Log out, Reboot, Shutdown.
// Open with `qs ipc call power toggle`.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "root:/settings"

Scope {
    id: root
    property var theme: MuzeDefaultTheme {}
    property string font: "JetBrainsMono Nerd Font"
    property bool panelVisible: false
    property int selectedIndex: 0

    readonly property var actions: [
        { label: "Lock screen", icon: "󰌾", cmd: ["loginctl", "lock-session"] },
        { label: "Log out",     icon: "󰍃", cmd: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
        { label: "Reboot",      icon: "󰜉", cmd: ["systemctl", "reboot"] },
        { label: "Shutdown",    icon: "󰐥", cmd: ["systemctl", "poweroff"] }
    ]

    IpcHandler {
        target: "power"
        function toggle(): void {
            root.panelVisible = !root.panelVisible
            if (root.panelVisible) root.selectedIndex = 0
        }
        function open(): void { root.panelVisible = true; root.selectedIndex = 0 }
        function close(): void { root.panelVisible = false }
    }

    function run(index) {
        if (index < 0 || index >= actions.length) return
        const cmd = actions[index].cmd
        root.panelVisible = false
        actionProc.command = cmd
        actionProc.running = true
    }

    Process {
        id: actionProc
        running: false
    }

    PanelWindow {
        id: win
        visible: root.panelVisible
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "muze-power-menu"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        Item {
            anchors.fill: parent
            focus: win.visible
            Keys.onEscapePressed: root.panelVisible = false
            Keys.onUpPressed: root.selectedIndex = (root.selectedIndex - 1 + root.actions.length) % root.actions.length
            Keys.onDownPressed: root.selectedIndex = (root.selectedIndex + 1) % root.actions.length
            Keys.onReturnPressed: root.run(root.selectedIndex)
            Keys.onEnterPressed: root.run(root.selectedIndex)

            MouseArea {
                anchors.fill: parent
                onClicked: root.panelVisible = false
                Rectangle { anchors.fill: parent; color: root.theme.bgOverlay }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 360
                height: col.implicitHeight + 36
                radius: 16
                color: root.theme.bgBase
                border.color: root.theme.bgBorder
                border.width: 1
                MouseArea { anchors.fill: parent; onClicked: {} }

                ColumnLayout {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 8

                    Text {
                        text: "󰐥  Power"
                        color: root.theme.accentPrimary
                        font.pixelSize: 15
                        font.bold: true
                        font.family: root.font
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: root.actions
                        Rectangle {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 10
                            color: root.selectedIndex === index ? root.theme.bgSelected : root.theme.bgSurface
                            border.color: root.selectedIndex === index ? root.theme.accentPrimary : root.theme.bgBorder
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12
                                Text {
                                    text: modelData.icon
                                    color: root.selectedIndex === index ? root.theme.accentPrimary : root.theme.textPrimary
                                    font.pixelSize: 16
                                    font.family: root.font
                                }
                                Text {
                                    text: modelData.label
                                    color: root.theme.textPrimary
                                    font.pixelSize: 13
                                    font.family: root.font
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = index
                                onClicked: root.run(index)
                            }
                        }
                    }

                    Text {
                        text: "↑↓ navigate · ⏎ select · esc close"
                        color: root.theme.textMuted
                        font.pixelSize: 10
                        font.family: root.font
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
