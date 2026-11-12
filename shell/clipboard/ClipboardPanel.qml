// Clipboard history panel UI.
// Overlay panel that presents ClipboardService history, supports search/filter
// and item activation to restore content to the clipboard, and is toggled via
// shell keybind/IPC integration.

// Muze clipboard history overlay -- Omarchy-style, text + images, searchable.
// Open with `qs ipc call clipboard toggle` (bound to SUPER + CTRL + V).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "root:/settings"
import "root:/clipboard"

Scope {
    id: root
    property var theme: MuzeDefaultTheme {}
    property string font: "JetBrainsMono Nerd Font"

    IpcHandler {
        target: "clipboard"
        function toggle(): void { ClipboardService.toggle() }
        function open(): void { ClipboardService.open() }
        function close(): void { ClipboardService.close() }
        function pick(index: int): void { ClipboardService.paste(index) }
    }

    PanelWindow {
        id: win
        visible: ClipboardService.panelVisible
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "muze-clipboard"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        Item {
            anchors.fill: parent
            MouseArea {
                anchors.fill: parent
                onClicked: ClipboardService.close()
                Rectangle { anchors.fill: parent; color: root.theme.bgOverlay }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(760, parent.width * 0.9)
                height: Math.min(620, parent.height * 0.9)
                radius: 16
                color: root.theme.bgBase
                border.color: root.theme.bgBorder
                border.width: 1
                MouseArea { anchors.fill: parent; onClicked: {} }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "  Clipboard history"
                            color: root.theme.accentPrimary
                            font.pixelSize: 15
                            font.bold: true
                            font.family: root.font
                            Layout.fillWidth: true
                        }
                        Text {
                            text: ClipboardService.history.length + " entries"
                            color: root.theme.textMuted
                            font.pixelSize: 10
                            font.family: root.font
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 8
                        color: root.theme.bgSurface
                        border.color: searchInput.activeFocus ? root.theme.accentPrimary : root.theme.bgBorder
                        border.width: 1
                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.theme.textPrimary
                            font.pixelSize: 12
                            font.family: root.font
                            clip: true
                            selectByMouse: true
                            focus: win.visible
                            onTextChanged: {
                                ClipboardService.filterText = text
                                ClipboardService.selectedIndex = 0
                            }
                            Keys.onEscapePressed: ClipboardService.close()
                            Keys.onUpPressed: ClipboardService.move(-1)
                            Keys.onDownPressed: ClipboardService.move(1)
                            Keys.onReturnPressed: ClipboardService.confirm()
                            Keys.onEnterPressed: ClipboardService.confirm()
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text === "" && !searchInput.activeFocus
                            text: "Search history…"
                            color: root.theme.textMuted
                            font.pixelSize: 12
                            font.family: root.font
                        }
                    }

                    Flickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: listCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: listCol
                            width: flick.width - 12
                            spacing: 4
                            Repeater {
                                model: ClipboardService.displayRows
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 46
                                    radius: 8
                                    color: ClipboardService.selectedIndex === index
                                        ? root.theme.bgSelected : root.theme.bgSurface
                                    border.color: ClipboardService.selectedIndex === index
                                        ? root.theme.accentPrimary : "transparent"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12
                                        Image {
                                            visible: modelData.type === "image" && modelData.path !== ""
                                            Layout.preferredWidth: 34
                                            Layout.preferredHeight: 34
                                            source: modelData.path !== "" ? "file://" + modelData.path : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                        Text {
                                            visible: modelData.type !== "image"
                                            text: "󰆐"
                                            color: root.theme.accentCyan
                                            font.pixelSize: 15
                                            font.family: root.font
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.preview
                                                color: root.theme.textPrimary
                                                font.pixelSize: 11
                                                font.family: root.font
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: modelData.capturedAt !== ""
                                                text: modelData.capturedAt
                                                color: root.theme.textMuted
                                                font.pixelSize: 9
                                                font.family: root.font
                                            }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            ClipboardService.selectedIndex = index
                                            ClipboardService.paste(modelData.index)
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: ClipboardService.displayRows.length === 0
                                Layout.fillWidth: true
                                text: "No clipboard history yet. Copy something with SUPER+C."
                                color: root.theme.textMuted
                                font.pixelSize: 11
                                font.family: root.font
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.fillWidth: true
                            text: "↑↓ navigate · ⏎ paste · esc close"
                            color: root.theme.textMuted
                            font.pixelSize: 10
                            font.family: root.font
                        }
                        Rectangle {
                            implicitWidth: clearText.implicitWidth + 20
                            implicitHeight: 28
                            radius: 7
                            color: clearHover.containsMouse ? root.theme.accentRed : root.theme.bgSurface
                            border.color: root.theme.bgBorder
                            border.width: 1
                            Text {
                                id: clearText
                                anchors.centerIn: parent
                                text: "Clear history"
                                color: root.theme.textPrimary
                                font.pixelSize: 10
                                font.family: root.font
                            }
                            MouseArea {
                                id: clearHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ClipboardService.clear()
                            }
                        }
                    }
                }
            }
        }
    }
}
