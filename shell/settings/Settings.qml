// Settings panel UI (Muze settings window/overlay).
// Tabbed interface for configuring appearance, top bar/plugins, Hyprland,
// bluetooth, displays, dock, power, and about/keybind info. Edits flow through
// MuzeSettings (which persists and triggers apply scripts where needed), and
// the panel is controlled via IPC (target "muze"/settings actions).

// Muze Settings -- one page for the shell and for Hyprland customisations.
// Open with `qs ipc call muze settings` (bound to SUPER + comma by default).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "root:/settings"
import "root:/bluetooth"

Scope {
    id: root
    property var theme: MuzeDefaultTheme {}
    property bool panelVisible: false
    property string tab: "appearance"
    property string font: "JetBrainsMono Nerd Font"
    readonly property string version: "0.1.0"
    property string exportStatus: ""
    property bool hasExportFiles: false
    property string detectedExportFile: ""

    function refreshExportFiles() {
        if (!detectExportProc.running) detectExportProc.running = true
    }

    Component.onCompleted: refreshExportFiles()
    onPanelVisibleChanged: if (panelVisible) refreshExportFiles()

    property var tabs: [
        { key: "appearance", label: "Appearance" },
        { key: "bar",        label: "Top bar" },
        { key: "hyprland",   label: "Hyprland" },
        { key: "bluetooth",  label: "Bluetooth" },
        { key: "displays",   label: "Displays" },
        { key: "dock",       label: "Dock" },
        { key: "power",      label: "Power" },
        { key: "about",      label: "About" }
    ]

    IpcHandler {
        target: "muze"
        function settings(): void { root.panelVisible = !root.panelVisible }
        function openSettings(): void { root.panelVisible = true }
        function closeSettings(): void { root.panelVisible = false }
        function appearance(): void { root.tab = "appearance"; root.panelVisible = true }
        function bar(): void { root.tab = "bar"; root.panelVisible = true }
        function displays(): void { root.tab = "displays"; root.panelVisible = true }
        function bluetooth(): void { root.tab = "bluetooth"; root.panelVisible = true }
        function hyprland(): void { root.tab = "hyprland"; root.panelVisible = true }
        function dock(): void { root.tab = "dock"; root.panelVisible = true }
        function power(): void { root.tab = "power"; root.panelVisible = true }
    }

    // ------------------------------------------------------- Bluetooth audio --
    // PipeWire-Pulse card profiles for connected headsets (A2DP / HSP-HFP).
    property var audioCards: []
    property string audioMessage: ""

    function refreshAudio() {
        if (!audioListProc.running) audioListProc.running = true
    }

    function setAudioProfile(card, profile) {
        audioSetProc.command = ["muze-bluetooth-audio", "set", card, profile]
        audioSetProc.running = true
        root.audioMessage = "Switching to " + profile + "…"
        audioRefreshTimer.restart()
    }

    onTabChanged: if (root.tab === "bluetooth") root.refreshAudio()

    Process {
        id: audioListProc
        running: false
        command: ["muze-bluetooth-audio", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.audioCards = d.cards || []
                } catch (e) {
                    root.audioCards = []
                }
            }
        }
    }

    Process {
        id: audioSetProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.audioMessage = text.trim() === "ok" ? "Profile applied." : "Could not apply profile."
                root.refreshAudio()
            }
        }
    }

    Timer {
        id: audioRefreshTimer
        interval: 1200
        repeat: false
        onTriggered: root.refreshAudio()
    }

    Timer {
        interval: 6000
        repeat: true
        running: root.tab === "bluetooth" && root.panelVisible
        onTriggered: root.refreshAudio()
    }

    // ---------------------------------------------------------------- shared UI
    component ToggleSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()
        implicitWidth: 38
        implicitHeight: 21
        radius: 11
        color: sw.checked ? root.theme.accentPrimary : root.theme.bgSelected
        border.color: root.theme.bgBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 15; height: 15; radius: 8
            color: sw.checked ? root.theme.bgBase : root.theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    component ToggleRow: RowLayout {
        id: tr
        property string label: ""
        property string sublabel: ""
        property bool checked: false
        property string settingKey: ""
        Layout.fillWidth: true
        spacing: 8
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: tr.label
                color: root.theme.textPrimary
                font.pixelSize: 12
                font.family: root.font
                Layout.fillWidth: true
            }
            Text {
                visible: tr.sublabel !== ""
                text: tr.sublabel
                color: root.theme.textMuted
                font.pixelSize: 10
                font.family: root.font
                Layout.fillWidth: true
            }
        }
        ToggleSwitch {
            checked: tr.checked
            onToggled: MuzeSettings.apply(tr.settingKey, !tr.checked)
        }
    }

    component StepperRow: ColumnLayout {
        id: sr
        property string label: ""
        property string settingKey: ""
        property real minValue: 0
        property real maxValue: 100
        property real stepValue: 1
        property bool decimals: false
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: sr.label
                color: root.theme.textPrimary
                font.pixelSize: 12
                font.family: root.font
                Layout.fillWidth: true
            }
            Text {
                text: sr.decimals ? Number(MuzeSettings[sr.settingKey]).toFixed(2)
                                  : MuzeSettings[sr.settingKey]
                color: root.theme.accentPrimary
                font.pixelSize: 12
                font.family: root.font
                font.bold: true
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                implicitWidth: 26; implicitHeight: 24; radius: 6
                color: root.theme.bgSurface
                Text { anchors.centerIn: parent; text: "−"; color: root.theme.textPrimary; font.pixelSize: 14; font.family: root.font }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: MuzeSettings.apply(sr.settingKey,
                        Math.max(sr.minValue, MuzeSettings[sr.settingKey] - sr.stepValue))
                }
            }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 6; radius: 3
                color: root.theme.bgSurface
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1,
                        (MuzeSettings[sr.settingKey] - sr.minValue) / (sr.maxValue - sr.minValue)))
                    height: parent.height; radius: 3
                    color: root.theme.accentPrimary
                }
            }
            Rectangle {
                implicitWidth: 26; implicitHeight: 24; radius: 6
                color: root.theme.bgSurface
                Text { anchors.centerIn: parent; text: "+"; color: root.theme.textPrimary; font.pixelSize: 14; font.family: root.font }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: MuzeSettings.apply(sr.settingKey,
                        Math.min(sr.maxValue, MuzeSettings[sr.settingKey] + sr.stepValue))
                }
            }
        }
    }

    component ChoiceRow: Flow {
        id: cr
        property var options: []
        property string current: ""
        property string settingKey: ""
        signal chosen(string key)
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: cr.options
            Rectangle {
                required property var modelData
                implicitWidth: choiceText.implicitWidth + 20
                implicitHeight: 28
                radius: 7
                color: cr.current === modelData.key ? root.theme.accentPrimary : root.theme.bgSurface
                border.color: root.theme.bgBorder
                border.width: 1
                Text {
                    id: choiceText
                    anchors.centerIn: parent
                    text: modelData.label
                    color: cr.current === modelData.key ? root.theme.bgBase : root.theme.textSecondary
                    font.pixelSize: 11
                    font.family: root.font
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: MuzeSettings.apply(cr.settingKey, modelData.key)
                }
            }
        }
    }

    component ActionButton: Rectangle {
        id: ab
        property string label: ""
        property string hint: ""
        signal clicked()
        implicitWidth: Math.max(150, abRow.implicitWidth + 28)
        implicitHeight: 34
        radius: 8
        color: abHover.containsMouse ? root.theme.accentPrimary : root.theme.bgSelected
        border.color: root.theme.bgBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Row {
            id: abRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                text: ab.label
                color: abHover.containsMouse ? root.theme.bgBase : root.theme.textPrimary
                font.pixelSize: 11
                font.family: root.font
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: ab.hint !== ""
                text: ab.hint
                color: abHover.containsMouse ? root.theme.bgBase : root.theme.textMuted
                font.pixelSize: 10
                font.family: root.font
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: abHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ab.clicked()
        }
    }

    component SectionTitle: Text {
        color: root.theme.accentPrimary
        font.pixelSize: 13
        font.bold: true
        font.family: root.font
    }
    component SubLabel: Text {
        color: root.theme.textMuted
        font.pixelSize: 10
        font.family: root.font
        Layout.fillWidth: true
        Layout.rightMargin: 16
        rightPadding: 12
        wrapMode: Text.WordWrap
    }
    component Divider: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.theme.bgBorder
    }

    // ---------------------------------------------------------------- window
    PanelWindow {
        id: win
        visible: root.panelVisible
        // Never leave the page non-scrollable if the panel closes mid-drag.
        onVisibleChanged: if (!visible) flick.interactive = true
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "muze-settings"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        Item {
            anchors.fill: parent
            focus: win.visible
            Keys.onEscapePressed: root.panelVisible = false

            MouseArea {
                anchors.fill: parent
                onClicked: root.panelVisible = false
                Rectangle { anchors.fill: parent; color: root.theme.bgOverlay }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(980, parent.width * 0.94)
                height: Math.min(680, parent.height * 0.92)
                radius: 16
                color: root.theme.bgBase
                border.color: root.theme.bgBorder
                border.width: 1
                MouseArea { anchors.fill: parent; onClicked: {} }

                Row {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 18

                    // ---- sidebar ----
                    ColumnLayout {
                        width: 168
                        height: parent.height
                        spacing: 6
                        Text {
                            text: "  MUZE"
                            color: root.theme.accentPrimary
                            font.pixelSize: 20
                            font.bold: true
                            font.family: root.font
                            Layout.bottomMargin: 4
                        }
                        Text {
                            text: "settings"
                            color: root.theme.textMuted
                            font.pixelSize: 11
                            font.family: root.font
                            Layout.bottomMargin: 12
                        }
                        Repeater {
                            model: root.tabs
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 8
                                color: root.tab === modelData.key ? root.theme.accentPrimary
                                     : (tabHover.containsMouse ? root.theme.bgHover : "transparent")
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: root.tab === modelData.key ? root.theme.bgBase : root.theme.textSecondary
                                    font.pixelSize: 12
                                    font.family: root.font
                                    font.bold: root.tab === modelData.key
                                }
                                MouseArea {
                                    id: tabHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.tab = modelData.key
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Text {
                            text: "v" + root.version + "\nesc to close"
                            color: root.theme.textMuted
                            font.pixelSize: 9
                            font.family: root.font
                        }
                    }

                    Rectangle { width: 1; height: parent.height; color: root.theme.bgBorder }

                    // ---- content ----
                    Flickable {
                        id: flick
                        // 24 px of right padding: the Row leaves the leftover
                        // space at the right edge so long text is never cut off.
                        width: parent.width - 168 - 1 - 18 - 24
                        height: parent.height
                        contentWidth: width
                        contentHeight: col.implicitHeight + 24
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: col
                            width: flick.width - 20
                            spacing: 16

                            // ============ APPEARANCE ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "appearance"
                                spacing: 12
                                SectionTitle { text: "Theme" }
                                SubLabel { text: "Muze extracts a Material 3 palette from your wallpaper with matugen and applies it systemwide: shell, Hyprland, GTK, Qt, terminals and btop." }

                                ChoiceRow {
                                    options: [
                                        { key: "wallpaper", label: "Wallpaper" },
                                        { key: "theme",     label: "Curated theme" },
                                        { key: "light",     label: "Light palette" }
                                    ]
                                    current: MuzeSettings.themeMode
                                    settingKey: "themeMode"
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ActionButton {
                                        label: "Pick wallpaper"
                                        hint: "SUPER+W"
                                        onClicked: { root.panelVisible = false; qsIpc.command = ["qs", "ipc", "call", "wallpaper", "toggle"]; qsIpc.running = true }
                                    }
                                    ActionButton {
                                        label: "Theme switcher"
                                        hint: "SUPER+T"
                                        onClicked: { root.panelVisible = false; qsIpc.command = ["qs", "ipc", "call", "theme", "toggle"]; qsIpc.running = true }
                                    }
                                    ActionButton {
                                        label: "Regenerate colours"
                                        onClicked: MuzeSettings.retheme()
                                    }
                                }

                                Divider {}
                                SectionTitle { text: "Application theming" }
                                ToggleRow {
                                    label: "Theme third-party apps"
                                    sublabel: "GTK 3 / GTK 4 CSS generated by matugen. Turn off to leave GTK apps stock."
                                    checked: MuzeSettings.themeApps
                                    settingKey: "themeApps"
                                }

                                Divider {}
                                SectionTitle { text: "Clock" }
                                ToggleRow {
                                    label: "24-hour clock"
                                    checked: MuzeSettings.use24h
                                    settingKey: "use24h"
                                }
                                ToggleRow {
                                    label: "Show seconds"
                                    checked: MuzeSettings.clockSeconds
                                    settingKey: "clockSeconds"
                                }

                                // Live swatches from the last generated palette
                                Divider {}
                                SectionTitle { text: "Current palette" }
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: [root.theme.bgBase, root.theme.bgSurface, root.theme.bgSelected,
                                                root.theme.textPrimary, root.theme.textSecondary,
                                                root.theme.accentPrimary, root.theme.accentCyan,
                                                root.theme.accentGreen, root.theme.accentOrange, root.theme.accentRed]
                                        Rectangle {
                                            required property var modelData
                                            width: 32; height: 32; radius: 8
                                            color: modelData
                                            border.color: root.theme.bgBorder
                                            border.width: 1
                                        }
                                    }
                                }
                            }

                            // ============ BAR ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "bar"
                                spacing: 12
                                SectionTitle { text: "Top bar" }
                                StepperRow {
                                    label: "Bar height"; settingKey: "barHeight"
                                    minValue: 24; maxValue: 48; stepValue: 2
                                }
                                StepperRow {
                                    label: "Bar opacity"; settingKey: "barOpacity"
                                    minValue: 40; maxValue: 100; stepValue: 5
                                }
                                Divider {}
                                SectionTitle { text: "Arrange plugins" }
                                SubLabel { text: "Drag plugins to reorder them or move them between Left, Center, and Right bar regions. The Arch apps-menu stays at the far left and the settings gear at the far right." }

                                Item {
                                    id: barArrange
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 420
                                    property int rowH: 34
                                    property string dragRegion: ""
                                    property int dragIndex: -1
                                    property string dragLabel: ""
                                    property string hoverRegion: ""
                                    property int hoverIndex: -1
                                    property bool dragging: dragRegion !== ""
                                    property var regions: ["left", "center", "right"]
                                    property var regionLabels: ({ left: "Left", center: "Center", right: "Right" })

                                    function regionModel(name) {
                                        if (name === "left") return MuzeSettings.barLeft
                                        if (name === "center") return MuzeSettings.barCenter
                                        return MuzeSettings.barRight
                                    }

                                    function endDrag(commit) {
                                        if (commit && dragging && hoverRegion !== "") {
                                            MuzeSettings.moveBarPlugin(dragRegion, dragIndex, hoverRegion, hoverIndex)
                                        }
                                        dragRegion = ""; dragIndex = -1; dragLabel = ""
                                        hoverRegion = ""; hoverIndex = -1
                                        dragGhost.visible = false
                                        flick.interactive = true
                                    }

                                    Row {
                                        id: regionRow
                                        anchors.fill: parent
                                        spacing: 10

                                        Repeater {
                                            id: regionRepeater
                                            model: barArrange.regions
                                            delegate: Rectangle {
                                                id: regionBox
                                                required property string modelData
                                                required property int index
                                                property string regionName: modelData
                                                width: (regionRow.width - 20) / 3
                                                height: regionRow.height
                                                radius: 10
                                                color: root.theme.bgSurface
                                                border.color: (barArrange.dragging && barArrange.hoverRegion === regionName) ? root.theme.accentPrimary : root.theme.bgBorder
                                                border.width: 1

                                                Column {
                                                    id: regionCol
                                                    anchors.fill: parent
                                                    anchors.margins: 8
                                                    spacing: 6

                                                    Text {
                                                        text: barArrange.regionLabels[regionName]
                                                        color: root.theme.textSecondary
                                                        font.pixelSize: 11
                                                        font.family: root.font
                                                        font.bold: true
                                                    }

                                                    Rectangle { width: parent.width; height: 1; color: root.theme.bgBorder }

                                                    Item {
                                                        id: listArea
                                                        width: parent.width
                                                        height: regionBox.height - 50

                                                        Column {
                                                            id: itemCol
                                                            width: parent.width
                                                            spacing: 4
                                                            Repeater {
                                                                id: itemRepeater
                                                                model: barArrange.regionModel(regionName)
                                                                delegate: Rectangle {
                                                                    id: pluginItem
                                                                    required property string modelData
                                                                    required property int index
                                                                    width: itemCol.width
                                                                    height: 30
                                                                    radius: 7
                                                                    color: (barArrange.dragging && barArrange.dragRegion === regionName && barArrange.dragIndex === index)
                                                                        ? root.theme.bgSelected : root.theme.bgBase
                                                                    border.color: root.theme.bgBorder
                                                                    border.width: 1
                                                                    opacity: (barArrange.dragging && barArrange.dragRegion === regionName && barArrange.dragIndex === index) ? 0.5 : 1.0

                                                                    RowLayout {
                                                                        anchors.fill: parent
                                                                        anchors.leftMargin: 8
                                                                        anchors.rightMargin: 8
                                                                        spacing: 6
                                                                        Text {
                                                                            text: "≡"
                                                                            color: root.theme.textMuted
                                                                            font.pixelSize: 13
                                                                            font.family: root.font
                                                                        }
                                                                        Text {
                                                                            Layout.fillWidth: true
                                                                            text: MuzeSettings.pluginLabels[modelData] || modelData
                                                                            color: root.theme.textPrimary
                                                                            font.pixelSize: 11
                                                                            font.family: root.font
                                                                            elide: Text.ElideRight
                                                                        }
                                                                        Text {
                                                                            visible: !MuzeSettings.pluginVisible(modelData)
                                                                            text: "hidden"
                                                                            color: root.theme.textMuted
                                                                            font.pixelSize: 9
                                                                            font.family: root.font
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            // empty-region drop hint
                                                            Text {
                                                                visible: barArrange.regionModel(regionName).length === 0
                                                                width: parent.width
                                                                height: 28
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                                text: "Drop plugins here"
                                                                color: root.theme.textMuted
                                                                font.pixelSize: 10
                                                                font.family: root.font
                                                            }
                                                        }

                                                        // Drop indicator line
                                                        Rectangle {
                                                            id: dropLine
                                                            visible: barArrange.dragging && barArrange.hoverRegion === regionName
                                                            width: parent.width
                                                            height: 2
                                                            color: root.theme.accentPrimary
                                                            y: Math.max(0, Math.min(listArea.height - 2, barArrange.hoverIndex * 34))
                                                            z: 5
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            preventStealing: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onPressed: (mouse) => {
                                                                flick.interactive = false
                                                                const model = barArrange.regionModel(regionName)
                                                                const idx = Math.floor(mouse.y / 34)
                                                                if (idx < 0 || idx >= model.length) { flick.interactive = true; return }
                                                                barArrange.dragRegion = regionName
                                                                barArrange.dragIndex = idx
                                                                barArrange.dragLabel = MuzeSettings.pluginLabels[model[idx]] || model[idx]
                                                                barArrange.hoverRegion = regionName
                                                                barArrange.hoverIndex = idx
                                                                dragGhost.textLabel = "≡  " + barArrange.dragLabel
                                                                dragGhost.visible = true
                                                                const p = mapToItem(barArrange, mouse.x, mouse.y)
                                                                dragGhost.x = p.x + 10
                                                                dragGhost.y = p.y - 12
                                                            }
                                                            onPositionChanged: (mouse) => {
                                                                if (!barArrange.dragging) return
                                                                const p = mapToItem(barArrange, mouse.x, mouse.y)
                                                                dragGhost.x = p.x + 10
                                                                dragGhost.y = p.y - 12
                                                                // find target region
                                                                let targetRegion = regionName
                                                                let targetIndex = 0
                                                                for (let r = 0; r < regionRepeater.count; r++) {
                                                                    const box = regionRepeater.itemAt(r)
                                                                    if (!box) continue
                                                                    const bp = mapToItem(box, mouse.x, mouse.y)
                                                                    if (bp.x >= 0 && bp.x <= box.width && p.y >= 0 && p.y <= barArrange.height) {
                                                                        targetRegion = box.regionName
                                                                        const lp = mapToItem(box.children[0].children[2], mouse.x, mouse.y) // listArea
                                                                        const m = barArrange.regionModel(targetRegion)
                                                                        targetIndex = Math.max(0, Math.min(m.length, Math.floor(lp.y / 34 + 0.5)))
                                                                        break
                                                                    }
                                                                }
                                                                // fallback by x across arrange area
                                                                const ax = p.x
                                                                const third = barArrange.width / 3
                                                                if (ax < third) targetRegion = "left"
                                                                else if (ax < third * 2) targetRegion = "center"
                                                                else targetRegion = "right"
                                                                const m2 = barArrange.regionModel(targetRegion)
                                                                // approximate y in target list
                                                                const targetBox = regionRepeater.itemAt(barArrange.regions.indexOf(targetRegion))
                                                                if (targetBox) {
                                                                    const lp2 = targetBox.mapFromItem(barArrange, p.x, p.y)
                                                                    targetIndex = Math.max(0, Math.min(m2.length, Math.floor((lp2.y - 60) / 34 + 0.5)))
                                                                }
                                                                barArrange.hoverRegion = targetRegion
                                                                barArrange.hoverIndex = targetIndex
                                                            }
                                                            onReleased: { barArrange.endDrag(true) }
                                                            onCanceled: { barArrange.endDrag(false) }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Floating drag ghost
                                    Rectangle {
                                        id: dragGhost
                                        property string textLabel: ""
                                        visible: false
                                        z: 100
                                        width: 180
                                        height: 28
                                        radius: 7
                                        color: root.theme.bgSelected
                                        border.color: root.theme.accentPrimary
                                        border.width: 1
                                        Text {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            verticalAlignment: Text.AlignVCenter
                                            text: dragGhost.textLabel
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Divider {}
                                SectionTitle { text: "Show plugins" }
                                SubLabel { text: "Toggle individual widgets. Hidden plugins keep their position in the order above." }
                                Repeater {
                                    model: [
                                        { label: "Clock & date",        key: "showClock" },
                                        { label: "Workspaces",          key: "showWorkspaces" },
                                        { label: "Now playing",         key: "showMedia" },
                                        { label: "Window title",        key: "showTitle" },
                                        { label: "Audio / volume",      key: "showVolume" },
                                        { label: "Brightness",          key: "showBrightness" },
                                        { label: "CPU usage",           key: "showCpu" },
                                        { label: "Network",             key: "showNetwork" },
                                        { label: "Bluetooth",           key: "showBluetooth" },
                                        { label: "Battery",             key: "showBattery" },
                                        { label: "Temperature",         key: "showTemperature" },
                                        { label: "System tray",         key: "showTray" },
                                        { label: "Power menu",          key: "showPower" },
                                        { label: "Screen recorder",     key: "showScreenRecorder" },
                                        { label: "Screenshot",          key: "showScreenshot" },
                                        { label: "Caffeine (idle inhibit)", key: "showCaffeine" },
                                        { label: "Arch apps-menu button", key: "showAppsMenu" },
                                        { label: "Settings gear button",  key: "showSettingsButton" }
                                    ]
                                    ToggleRow {
                                        required property var modelData
                                        label: modelData.label
                                        checked: MuzeSettings[modelData.key]
                                        settingKey: modelData.key
                                    }
                                }
                            }

                            // ============ HYPRLAND ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "hyprland"
                                spacing: 12
                                SectionTitle { text: "Hyprland customisations" }
                                SubLabel { text: "Written to ~/.config/hypr/muze/look.lua and reloaded with hyprctl. Hand overrides go in muze/user.lua." }
                                StepperRow { label: "Gaps in";       settingKey: "gapsIn";       minValue: 0;  maxValue: 20; stepValue: 1 }
                                StepperRow { label: "Gaps out";      settingKey: "gapsOut";      minValue: 0;  maxValue: 30; stepValue: 1 }
                                StepperRow { label: "Border size";   settingKey: "borderSize";   minValue: 0;  maxValue: 8;  stepValue: 1 }
                                StepperRow { label: "Rounding";      settingKey: "rounding";     minValue: 0;  maxValue: 24; stepValue: 1 }
                                Divider {}
                                SectionTitle { text: "Effects" }
                                ToggleRow {
                                    label: "Blur"
                                    checked: MuzeSettings.blurEnabled
                                    settingKey: "blurEnabled"
                                }
                                StepperRow { label: "Blur size";     settingKey: "blurSize";     minValue: 1;  maxValue: 20; stepValue: 1 }
                                ToggleRow {
                                    label: "Animations"
                                    checked: MuzeSettings.animationsEnabled
                                    settingKey: "animationsEnabled"
                                }
                                StepperRow { label: "Active opacity";   settingKey: "activeOpacity";   minValue: 0.6; maxValue: 1.0; stepValue: 0.05; decimals: true }
                                StepperRow { label: "Inactive opacity"; settingKey: "inactiveOpacity"; minValue: 0.6; maxValue: 1.0; stepValue: 0.05; decimals: true }
                                Divider {}
                                SectionTitle { text: "Layout & input" }
                                ChoiceRow {
                                    options: [
                                        { key: "dwindle",   label: "Dwindle" },
                                        { key: "master",    label: "Master" },
                                        { key: "scrolling", label: "Scrolling" }
                                    ]
                                    current: MuzeSettings.layout
                                    settingKey: "layout"
                                }
                                ToggleRow {
                                    label: "Natural scroll (touchpad)"
                                    checked: MuzeSettings.naturalScroll
                                    settingKey: "naturalScroll"
                                }
                                ChoiceRow {
                                    options: [
                                        { key: "us", label: "US" }, { key: "ro", label: "RO" },
                                        { key: "de", label: "DE" }, { key: "fr", label: "FR" },
                                        { key: "gb", label: "GB" }
                                    ]
                                    current: MuzeSettings.kbLayout
                                    settingKey: "kbLayout"
                                }
                            }

                            // ============ POWER ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "power"
                                spacing: 12
                                SectionTitle { text: "Screen lock & idle" }
                                SubLabel { text: "These options drive hypridle. Timers only run while the session is idle; SUPER+SHIFT+C toggles the Caffeine idle inhibitor for a temporary override." }

                                ToggleRow {
                                    label: "Lock the screen when idle"
                                    sublabel: "Runs hyprlock after the timeout below. Off means the screen is never locked automatically, including before suspend."
                                    checked: MuzeSettings.lockEnabled
                                    settingKey: "lockEnabled"
                                }
                                StepperRow {
                                    visible: MuzeSettings.lockEnabled
                                    label: "Lock after (minutes)"
                                    settingKey: "lockMinutes"
                                    minValue: 1; maxValue: 60; stepValue: 1
                                }
                                Divider {}
                                ToggleRow {
                                    label: "Turn the display off when idle"
                                    sublabel: "Blanks the panel with DPMS without locking or suspending."
                                    checked: MuzeSettings.screenOffEnabled
                                    settingKey: "screenOffEnabled"
                                }
                                StepperRow {
                                    visible: MuzeSettings.screenOffEnabled
                                    label: "Display off after (minutes)"
                                    settingKey: "screenOffMinutes"
                                    minValue: 1; maxValue: 120; stepValue: 1
                                }
                                Divider {}
                                ToggleRow {
                                    label: "Suspend when idle"
                                    sublabel: "Suspends the machine after the timeout. Turn this off if only the display should sleep."
                                    checked: MuzeSettings.suspendEnabled
                                    settingKey: "suspendEnabled"
                                }
                                StepperRow {
                                    visible: MuzeSettings.suspendEnabled
                                    label: "Suspend after (minutes)"
                                    settingKey: "suspendMinutes"
                                    minValue: 1; maxValue: 240; stepValue: 1
                                }
                                Divider {}
                                SubLabel { text: "Changes are written to ~/.config/muze/settings.json and applied immediately by restarting hypridle. With lock and suspend both off, an idle session stays awake with only the display turning off." }
                            }

                            // ============ BLUETOOTH ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "bluetooth"
                                spacing: 12
                                SectionTitle { text: "Bluetooth" }
                                SubLabel { text: "Power, scan and manage devices through BlueZ. The bar plugin shows the connection state; right-click it to open this page." }

                                Divider {}
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        Layout.fillWidth: true
                                        text: BluetoothService.available
                                            ? (BluetoothService.powered ? "Adapter on" : "Adapter off")
                                            : "No Bluetooth adapter found"
                                        color: root.theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: root.font
                                    }
                                    ToggleSwitch {
                                        checked: BluetoothService.powered
                                        enabled: BluetoothService.available
                                        onToggled: BluetoothService.togglePower()
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    ActionButton {
                                        label: BluetoothService.discovering ? "Stop scan" : "Scan for devices"
                                        enabled: BluetoothService.available && BluetoothService.powered
                                        onClicked: BluetoothService.toggleDiscovering()
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: BluetoothService.connectedCount + " connected · " +
                                              BluetoothService.deviceCount + " known"
                                        color: root.theme.textMuted
                                        font.pixelSize: 10
                                        font.family: root.font
                                    }
                                }

                                Divider {}
                                SectionTitle { text: "Devices" }
                                SubLabel {
                                    visible: BluetoothService.deviceCount === 0
                                    text: "No devices yet. Turn the adapter on and scan to discover nearby devices, or pair them with your system's Bluetooth tools."
                                }

                                Repeater {
                                    model: BluetoothService.devices
                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 46
                                        radius: 8
                                        color: root.theme.bgSurface
                                        border.color: modelData.connected ? root.theme.accentPrimary : root.theme.bgBorder
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.deviceName || modelData.name || modelData.address
                                                    color: root.theme.textPrimary
                                                    font.pixelSize: 12
                                                    font.family: root.font
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: (modelData.connected ? "Connected" :
                                                           modelData.paired ? "Paired" : "Available") +
                                                          (modelData.batteryAvailable
                                                              ? " · " + Math.round(modelData.battery * 100) + "%"
                                                              : "") +
                                                          " · " + modelData.address
                                                    color: root.theme.textMuted
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Rectangle {
                                                implicitWidth: connectLabel.implicitWidth + 20
                                                implicitHeight: 28
                                                radius: 7
                                                color: connectHover.containsMouse ? root.theme.accentPrimary : root.theme.bgSelected
                                                border.color: root.theme.bgBorder
                                                border.width: 1
                                                Text {
                                                    id: connectLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.connected ? "Disconnect" : "Connect"
                                                    color: connectHover.containsMouse ? root.theme.bgBase : root.theme.textPrimary
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                }
                                                MouseArea {
                                                    id: connectHover
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.connected) modelData.disconnect()
                                                        else modelData.connect()
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                visible: modelData.paired
                                                implicitWidth: forgetLabel.implicitWidth + 16
                                                implicitHeight: 28
                                                radius: 7
                                                color: "transparent"
                                                border.color: root.theme.bgBorder
                                                border.width: 1
                                                Text {
                                                    id: forgetLabel
                                                    anchors.centerIn: parent
                                                    text: "Forget"
                                                    color: root.theme.textMuted
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: modelData.forget()
                                                }
                                            }
                                        }
                                    }
                                }

                                Divider {}
                                SectionTitle { text: "Audio profile" }
                                SubLabel { text: "Choose the Bluetooth audio codec for a connected headset. A2DP is high-fidelity playback; HSP/HFP also enables the microphone." }

                                SubLabel {
                                    visible: root.audioCards.length === 0
                                    text: "No Bluetooth audio card is active yet. Connect a headset and wait a moment, then it will appear here with its available profiles."
                                }

                                Text {
                                    visible: root.audioMessage !== ""
                                    Layout.fillWidth: true
                                    text: root.audioMessage
                                    color: root.theme.accentGreen
                                    font.pixelSize: 10
                                    font.family: root.font
                                }

                                Repeater {
                                    model: root.audioCards
                                    ColumnLayout {
                                        id: cardRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: cardRow.modelData.description + "  ·  " + cardRow.modelData.address
                                            color: root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            elide: Text.ElideRight
                                        }
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Repeater {
                                                model: cardRow.modelData.profiles || []
                                                Rectangle {
                                                    required property var modelData
                                                    readonly property bool active:
                                                        modelData.name === cardRow.modelData.activeProfile
                                                    implicitWidth: profileLabel.implicitWidth + 20
                                                    implicitHeight: 30
                                                    radius: 7
                                                    color: active ? root.theme.accentPrimary
                                                                  : (profileHover.containsMouse ? root.theme.bgHover : root.theme.bgSurface)
                                                    border.color: root.theme.bgBorder
                                                    border.width: 1
                                                    Text {
                                                        id: profileLabel
                                                        anchors.centerIn: parent
                                                        text: modelData.description || modelData.name
                                                        color: active ? root.theme.bgBase : root.theme.textSecondary
                                                        font.pixelSize: 10
                                                        font.family: root.font
                                                    }
                                                    MouseArea {
                                                        id: profileHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.setAudioProfile(
                                                            cardRow.modelData.name, modelData.name)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ============ DISPLAYS ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "displays"
                                spacing: 12
                                SectionTitle { text: "Displays" }
                                SubLabel { text: "Arrange, scale, rotate or mirror monitors with the visual editor. Layouts are saved to ~/.config/hypr/monitors.lua and restored at login." }
                                ActionButton {
                                    label: "Open display manager"
                                    hint: "SUPER+O"
                                    onClicked: { root.panelVisible = false; qsIpc.command = ["qs", "ipc", "call", "monitors", "toggle"]; qsIpc.running = true }
                                }
                                Divider {}
                                SubLabel { text: "Tip: the display manager writes monitors.lua (Lua config). Everything else about monitors (resolution, refresh rate) is handled there too." }
                            }


                            // ============ DOCK ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "dock"
                                spacing: 12
                                SectionTitle { text: "Dock" }
                                SubLabel { text: "App dock with pinned and running applications (Omarchy-style). Right-click a dock icon to pin/unpin, middle-click to launch a new window." }

                                ToggleRow {
                                    label: "Enable dock"
                                    sublabel: "Show the dock on screen edges."
                                    checked: MuzeSettings.dockEnabled
                                    settingKey: "dockEnabled"
                                }
                                ToggleRow {
                                    label: "Auto-hide"
                                    sublabel: "Hide the dock until the pointer reaches its edge."
                                    checked: MuzeSettings.dockAutohide
                                    settingKey: "dockAutohide"
                                }

                                StepperRow {
                                    label: "Icon size"
                                    settingKey: "dockIconSize"
                                    minValue: 24; maxValue: 64; stepValue: 2
                                }


                                Divider {}
                                SectionTitle { text: "Screens" }
                                SubLabel { text: "Choose whether the dock appears on all monitors or a single screen." }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        id: allScreenBtn
                                        readonly property bool active: MuzeSettings.dockScreen === "all"
                                        implicitWidth: allLbl.implicitWidth + 20
                                        implicitHeight: 30
                                        radius: 7
                                        color: allScreenBtn.active ? root.theme.accentPrimary : (allHover.containsMouse ? root.theme.bgHover : root.theme.bgSurface)
                                        border.color: root.theme.bgBorder
                                        border.width: 1
                                        Text {
                                            id: allLbl
                                            anchors.centerIn: parent
                                            text: "All screens"
                                            color: allScreenBtn.active ? root.theme.bgBase : root.theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }
                                        MouseArea {
                                            id: allHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: MuzeSettings.apply("dockScreen", "all")
                                        }
                                    }
                                    Repeater {
                                        model: Quickshell.screens
                                        Rectangle {
                                            id: scBtn
                                            required property var modelData
                                            readonly property bool active: MuzeSettings.dockScreen === modelData.name
                                            implicitWidth: scLbl.implicitWidth + 20
                                            implicitHeight: 30
                                            radius: 7
                                            color: scBtn.active ? root.theme.accentPrimary : (scHover.containsMouse ? root.theme.bgHover : root.theme.bgSurface)
                                            border.color: root.theme.bgBorder
                                            border.width: 1
                                            Text {
                                                id: scLbl
                                                anchors.centerIn: parent
                                                text: modelData.name
                                                color: scBtn.active ? root.theme.bgBase : root.theme.textSecondary
                                                font.pixelSize: 11
                                                font.family: root.font
                                            }
                                            MouseArea {
                                                id: scHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: MuzeSettings.apply("dockScreen", modelData.name)
                                            }
                                        }
                                    }
                                }

                                Divider {}
                                SectionTitle { text: "Position" }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Repeater {
                                        model: ["bottom", "left", "right", "top"]
                                        Rectangle {
                                            required property var modelData
                                            readonly property bool active: MuzeSettings.dockPosition === modelData
                                            implicitWidth: posLabel.implicitWidth + 20
                                            implicitHeight: 30
                                            radius: 7
                                            color: active ? root.theme.accentPrimary : (posHover.containsMouse ? root.theme.bgHover : root.theme.bgSurface)
                                            border.color: root.theme.bgBorder
                                            border.width: 1
                                            Text {
                                                id: posLabel
                                                anchors.centerIn: parent
                                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                color: active ? root.theme.bgBase : root.theme.textSecondary
                                                font.pixelSize: 11
                                                font.family: root.font
                                            }
                                            MouseArea {
                                                id: posHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: MuzeSettings.apply("dockPosition", modelData)
                                            }
                                        }
                                    }
                                }

                                Divider {}
                                SectionTitle { text: "Pinned apps" }
                                SubLabel { text: "Desktop entry IDs pinned to the dock (in order). You can also right-click icons on the dock to pin/unpin running apps." }
                                Repeater {
                                    model: MuzeSettings.dockPinned || []
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        implicitHeight: 34
                                        radius: 7
                                        color: root.theme.bgSurface
                                        border.color: root.theme.bgBorder
                                        border.width: 1
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData
                                                color: root.theme.textPrimary
                                                font.pixelSize: 11
                                                font.family: root.font
                                                elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                implicitWidth: unpinT.implicitWidth + 16
                                                implicitHeight: 24
                                                radius: 6
                                                color: unpinH.containsMouse ? root.theme.accentRed : root.theme.bgSelected
                                                Text {
                                                    id: unpinT
                                                    anchors.centerIn: parent
                                                    text: "Unpin"
                                                    color: unpinH.containsMouse ? root.theme.bgBase : root.theme.textPrimary
                                                    font.pixelSize: 10
                                                    font.family: root.font
                                                }
                                                MouseArea {
                                                    id: unpinH
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var p = (MuzeSettings.dockPinned || []).slice()
                                                        p.splice(index, 1)
                                                        MuzeSettings.apply("dockPinned", p)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ============ ABOUT ============
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.tab === "about"
                                spacing: 12
                                SectionTitle { text: "Muze" }
                                SubLabel { text: "A QuickShell desktop for Hyprland, built on Arch Linux. v" + root.version }
                                Divider {}
                                SectionTitle { text: "Keybinds" }
                                Repeater {
                                    model: [
                                        { k: "SUPER + Return",  v: "Terminal (kitty)" },
                                        { k: "SUPER + E",       v: "File manager (thunar)" },
                                        { k: "SUPER + Space",   v: "Fuzzel launcher" },
                                        { k: "SUPER + D",       v: "Muze app launcher" },
                                        { k: "apps-menu (bar)", v: "Open the app launcher" },
                                        { k: "gear (bar)",      v: "Open Muze settings" },
                                        { k: "BT pill (right-click)", v: "Bluetooth settings" },
                                        { k: "SUPER + ,",       v: "Muze settings" },
                                        { k: "SUPER + C/V/X/A", v: "Universal copy / paste / cut / select-all" },
                                        { k: "SUPER + Ctrl + V", v: "Clipboard history (text + images)" },
                                        { k: "SUPER + T",       v: "Theme switcher" },
                                        { k: "SUPER + W",       v: "Wallpaper picker" },
                                        { k: "SUPER + O",       v: "Display manager" },
                                        { k: "SUPER + SHIFT + O", v: "Refresh display layout" },
                                        { k: "SUPER + SHIFT + C", v: "Caffeine (idle inhibit)" },
                                        { k: "SUPER + SHIFT + V", v: "Toggle floating" },
                                        { k: "SUPER + I",       v: "Installer (live ISO)" },
                                        { k: "SUPER + N",       v: "Dismiss notifications" },
                                        { k: "SUPER + SHIFT + N", v: "Toggle do-not-disturb" },
                                        { k: "SUPER + Q",       v: "Close window" },
                                        { k: "SUPER + F",       v: "Fullscreen" },
                                        { k: "SUPER + P",       v: "Pseudo-tile" },
                                        { k: "SUPER + J",       v: "Toggle split" },
                                        { k: "SUPER + 1..0",    v: "Switch workspace" },
                                        { k: "SUPER + SHIFT + 1..0", v: "Move window to workspace" },
                                        { k: "SUPER + S",       v: "Special workspace (scratchpad)" },
                                        { k: "SUPER + arrows",  v: "Focus window" },
                                        { k: "SUPER + SHIFT + arrows", v: "Move window" },
                                        { k: "SUPER + Print",   v: "Screenshot to clipboard" },
                                        { k: "Print",           v: "Region screenshot to clipboard" },
                                        { k: "SUPER + SHIFT + Print", v: "Region screenshot to file (~/Pictures/Screenshots)" },
                                        { k: "SUPER + SHIFT + M", v: "Power menu" },
                                        { k: "SUPER + SHIFT + R", v: "Toggle screen recording" }
                                    ]
                                    RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 12
                                        Text {
                                            text: modelData.k
                                            color: root.theme.accentPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.preferredWidth: 170
                                        }
                                        Text {
                                            text: modelData.v
                                            color: root.theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: root.font
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                                Divider {}
                                SectionTitle { text: "Settings backup" }
                                SubLabel { text: "Export or import settings.json, pinned apps, Hyprland settings, and installed packages (Arch + AUR) as a portable JSON file." }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle {
                                        id: exportBtn
                                        visible: root.hasExportFiles
                                        implicitWidth: exportBtnLabel.implicitWidth + 24
                                        implicitHeight: 32
                                        radius: 8
                                        color: exportBtnHover.containsMouse ? root.theme.accentPrimary : root.theme.bgSelected
                                        border.color: root.theme.bgBorder
                                        border.width: 1
                                        opacity: exportProc.running ? 0.7 : 1.0
                                        Text {
                                            id: exportBtnLabel
                                            anchors.centerIn: parent
                                            text: exportProc.running ? "Exporting…" : "Export settings"
                                            color: exportBtnHover.containsMouse ? root.theme.bgBase : root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }
                                        MouseArea {
                                            id: exportBtnHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: exportProc.running ? Qt.BusyCursor : Qt.PointingHandCursor
                                            enabled: !exportProc.running
                                            onClicked: {
                                                root.exportStatus = ""
                                                exportProc.running = true
                                            }
                                        }
                                    }
                                    Rectangle {
                                        id: importBtn
                                        implicitWidth: importBtnLabel.implicitWidth + 24
                                        implicitHeight: 32
                                        radius: 8
                                        color: importBtnHover.containsMouse ? root.theme.accentPrimary : root.theme.bgSelected
                                        border.color: root.theme.bgBorder
                                        border.width: 1
                                        opacity: importProc.running ? 0.7 : 1.0
                                        Text {
                                            id: importBtnLabel
                                            anchors.centerIn: parent
                                            text: importProc.running ? "Importing…" : "Import settings"
                                            color: importBtnHover.containsMouse ? root.theme.bgBase : root.theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: root.font
                                        }
                                        MouseArea {
                                            id: importBtnHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: importProc.running ? Qt.BusyCursor : Qt.PointingHandCursor
                                            enabled: !importProc.running
                                            onClicked: {
                                                root.exportStatus = ""
                                                importProc.running = true
                                            }
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: root.exportStatus !== ""
                                        text: root.exportStatus
                                        color: root.theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: root.font
                                        wrapMode: Text.WrapAnywhere
                                    }
                                }
                                SubLabel {
                                    visible: !root.hasExportFiles
                                    text: "No Muze export files detected in your home folder. Use Import settings to select an export file."
                                }
                                SubLabel {
                                    visible: root.hasExportFiles && root.detectedExportFile !== ""
                                    text: "Detected export: " + root.detectedExportFile
                                }
                                Divider {}
                                SubLabel { text: "Colours: matugen. Shell: Quickshell. Compositor: Hyprland. Config lives in ~/.config/muze/settings.json -- edit it, import it, or let the installer generate it." }
                            }
                        }
                    }
                }
            }
        }
    }

    Process { id: qsIpc; running: false }
    Process {
        id: detectExportProc
        running: false
        command: ["bash", "-lc", "ls -1t \"$HOME\"/Muze-export-*.json 2>/dev/null | head -n1 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                root.detectedExportFile = p
                root.hasExportFiles = p.length > 0
            }
        }
    }
    Process {
        id: exportProc
        running: false
        command: ["muze-export-settings"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                if (p.length > 0)
                    root.exportStatus = "Exported to " + p
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const e = text.trim()
                if (e.length > 0 && root.exportStatus === "")
                    root.exportStatus = "Export failed: " + e
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.exportStatus === "")
                root.exportStatus = "Export failed (exit " + code + ")"
            if (code === 0) root.refreshExportFiles()
        }
    }
    Process {
        id: importProc
        running: false
        command: ["bash", "-lc", "file=$(zenity --file-selection --title='Import Muze Settings' --file-filter='JSON files (*.json) | *.json' --file-filter='All files | *' 2>/dev/null || kdialog --getopenfilename \"$HOME\" '*.json' 2>/dev/null || true); if [ -n \"$file\" ]; then muze-import-settings \"$file\"; else echo '__CANCELLED__'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (out === "__CANCELLED__" || out.length === 0) {
                    root.exportStatus = "Import cancelled."
                } else {
                    root.exportStatus = out
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const e = text.trim()
                if (e.length > 0 && root.exportStatus.indexOf("Import failed") !== 0)
                    root.exportStatus = "Import failed: " + e
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && root.exportStatus === "")
                root.exportStatus = "Import failed (exit " + code + ")"
            if (code === 0) root.refreshExportFiles()
        }
    }
}
