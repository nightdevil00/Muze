// Persistent settings singleton (shared shell state/config).
// Central source of truth for Muze shell and Hyprland-related UI settings.
// Loads/saves ~/.config/muze/settings.json, exposes typed properties for all
// modules (appearance/bar/plugins, dock, power, hyprland options, etc.),
// handles migrations/defaults, and provides helpers like apply/save/retheme
// so UI and external tools share one consistent configuration contract.

// MuzeSettings.qml -- persistent shell + Hyprland configuration.
//
// Everything the Settings UI changes lives in one JSON file:
//   ~/.config/muze/settings.json
// That file is the contract between the UI, the `muze-hypr-apply` script and
// (later) the agentic installer: edit it by hand, import a profile, or let the
// agent propose a diff -- the result is always applied the same way.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // ---- Appearance -------------------------------------------------------
    property string themeMode: "wallpaper"   // "wallpaper" | "theme" | "light"
    property bool themeApps: true
    property int barHeight: 32
    property int barOpacity: 100
    property bool showClock: true
    property bool showWorkspaces: true
    property bool showMedia: true
    property bool showVolume: true
    property bool showBrightness: true
    property bool showCpu: true
    property bool showNetwork: true
    property bool showBattery: true
    property bool showTemperature: false
    property bool showTray: true
    property bool showBluetooth: true
    property bool showSettingsButton: true
    property bool showAppsMenu: true
    property bool showPower: true
    property bool showScreenRecorder: true
    property bool showScreenshot: true
    property bool showTitle: true
    property bool showCaffeine: true
    property bool clockSeconds: false
    property bool use24h: true
    property string wallpaperPath: ""

    // ---- Dock -------------------------------------------------------------
    property bool dockEnabled: true
    property string dockPosition: "bottom"   // top|bottom|left|right
    property bool dockAutohide: false
    property int dockIconSize: 40
    property string dockScreen: "all"
    property var dockPinned: [
        "org.gnome.Nautilus", "firefox", "chromium", "kitty", "thunar"
    ]

    // Bar plugins split into three regions (left / center / right) so the
    // layout doesn't spread icons across the full width. Drag plugins between
    // regions and reorder them in Settings -> Top bar.
    property var barLeft: ["appsmenu", "workspaces"]
    property var barCenter: ["clock", "media", "title"]
    property var barRight: ["volume", "brightness", "cpu", "network", "bluetooth", "battery", "temperature", "caffeine", "tray", "power", "screenrecorder", "screenshot", "settingsbutton"]

    // Back-compat derived order (all regions concatenated).
    readonly property var pluginOrder: (barLeft || []).concat(barCenter || [], barRight || [])

    // Friendly names for the settings list.
    readonly property var pluginLabels: ({
        clock: "Clock & date", workspaces: "Workspaces", media: "Now playing",
        title: "Window title", volume: "Audio / volume", brightness: "Brightness",
        cpu: "CPU usage", network: "Network", bluetooth: "Bluetooth",
        battery: "Battery", temperature: "Temperature", tray: "System tray",
        power: "Power menu",
        screenrecorder: "Screen recorder",
        screenshot: "Screenshot",
        appsmenu: "Apps menu (Arch)",
        settingsbutton: "Settings button",
        caffeine: "Caffeine (idle inhibit)"
    })

    // Maps a plugin id to its visibility toggle (kept for backwards compat
    // with the showX toggles in Settings).
    readonly property var pluginToggleKey: ({
        clock: "showClock", workspaces: "showWorkspaces", media: "showMedia",
        volume: "showVolume", brightness: "showBrightness", cpu: "showCpu",
        network: "showNetwork", bluetooth: "showBluetooth",
        battery: "showBattery", temperature: "showTemperature",
        tray: "showTray", power: "showPower", screenrecorder: "showScreenRecorder", screenshot: "showScreenshot", title: "showTitle",
        appsmenu: "showAppsMenu", settingsbutton: "showSettingsButton",
        caffeine: "showCaffeine"
    })

    function pluginVisible(id) {
        const key = root.pluginToggleKey[id]
        return key ? root[key] !== false : true
    }

    function _cloneRegion(arr) { return Array.isArray(arr) ? arr.slice() : [] }

    function _regionArray(name) {
        if (name === "left") return root._cloneRegion(root.barLeft)
        if (name === "center") return root._cloneRegion(root.barCenter)
        return root._cloneRegion(root.barRight)
    }

    function _setRegion(name, arr) {
        if (name === "left") root.barLeft = arr
        else if (name === "center") root.barCenter = arr
        else root.barRight = arr
    }

    function normalizeBarRegions() {
        const defaults = ["appsmenu", "clock", "workspaces", "media", "title", "volume",
            "brightness", "cpu", "network", "bluetooth", "battery",
            "temperature", "caffeine", "tray", "power", "screenrecorder", "screenshot", "settingsbutton"]
        let left = root._cloneRegion(root.barLeft)
        let center = root._cloneRegion(root.barCenter)
        let right = root._cloneRegion(root.barRight)
        const seen = {}
        function uniq(list) {
            const out = []
            for (let i = 0; i < list.length; i++) {
                const id = list[i]
                if (!id || seen[id]) continue
                seen[id] = true
                out.push(id)
            }
            return out
        }
        left = uniq(left); center = uniq(center); right = uniq(right)
        for (let i = 0; i < defaults.length; i++) {
            const id = defaults[i]
            if (!seen[id]) { right.push(id); seen[id] = true }
        }
        root.barLeft = left; root.barCenter = center; root.barRight = right
    }

    function moveBarPlugin(fromRegion, fromIndex, toRegion, toIndex) {
        const src = root._regionArray(fromRegion)
        const dst = fromRegion === toRegion ? src : root._regionArray(toRegion)
        if (fromIndex < 0 || fromIndex >= src.length) return
        const item = src.splice(fromIndex, 1)[0]
        let insertAt = Math.max(0, Math.min(dst.length, toIndex))
        if (fromRegion === toRegion && fromIndex < toIndex) insertAt = Math.max(0, insertAt - 1)
        dst.splice(insertAt, 0, item)
        root._setRegion(fromRegion, src)
        root._setRegion(toRegion, dst)
        root.save()
    }

    // Legacy single-list move kept for compatibility; operates on concatenated order.
    function movePlugin(from, to) {
        if (from === to || from < 0 || to < 0) return
        const order = root.pluginOrder.slice()
        if (from >= order.length) return
        const id = order[from]
        // locate region
        function find(id) {
            let i = root.barLeft.indexOf(id); if (i >= 0) return ["left", i]
            i = root.barCenter.indexOf(id); if (i >= 0) return ["center", i]
            i = root.barRight.indexOf(id); if (i >= 0) return ["right", i]
            return null
        }
        // simple fallback: rebuild in right region
        order.splice(from, 1); order.splice(Math.max(0, Math.min(order.length, to)), 0, id)
        root.barLeft = []; root.barCenter = []; root.barRight = order
        root.normalizeBarRegions(); root.save()
    }

    // ---- Hyprland ---------------------------------------------------------
    property int gapsIn: 5
    property int gapsOut: 10
    property int borderSize: 2
    property int rounding: 12
    property real activeOpacity: 1.0
    property real inactiveOpacity: 0.95
    property bool blurEnabled: true
    property int blurSize: 6
    property bool animationsEnabled: true
    property string layout: "dwindle"
    property bool naturalScroll: true
    property string kbLayout: "us"
    property int followMouse: 1
    property int sensitivity: 0

    // ---- Power / idle -----------------------------------------------------
    // Applied by bin/muze-idle, which writes ~/.config/muze/hypridle.conf and
    // restarts hypridle. Each action can be turned off independently; a
    // timeout of 0 is treated as "never" too.
    property bool lockEnabled: true
    property int lockMinutes: 5
    property bool screenOffEnabled: true
    property int screenOffMinutes: 6
    property bool suspendEnabled: true
    property int suspendMinutes: 15

    readonly property var powerKeys: [
        "lockEnabled", "lockMinutes",
        "screenOffEnabled", "screenOffMinutes",
        "suspendEnabled", "suspendMinutes"
    ]

    readonly property var dockKeys: [
        "dockEnabled", "dockPosition", "dockAutohide", "dockIconSize", "dockScreen", "dockPinned"
    ]

    property bool ready: false
    readonly property string configPath: Quickshell.env("HOME") + "/.config/muze/settings.json"

    function _data() {
        return {
            version: 1,
            appearance: {
                themeMode: root.themeMode,
                themeApps: root.themeApps,
                pluginOrder: root.pluginOrder,
                barLeft: root.barLeft,
                barCenter: root.barCenter,
                barRight: root.barRight,
                barHeight: root.barHeight,
                barOpacity: root.barOpacity,
                showClock: root.showClock,
                showWorkspaces: root.showWorkspaces,
                showMedia: root.showMedia,
                showVolume: root.showVolume,
                showBrightness: root.showBrightness,
                showCpu: root.showCpu,
                showNetwork: root.showNetwork,
                showBattery: root.showBattery,
                showTemperature: root.showTemperature,
                showTray: root.showTray,
                showBluetooth: root.showBluetooth,
                showSettingsButton: root.showSettingsButton,
                showAppsMenu: root.showAppsMenu,
                showPower: root.showPower,
                showScreenRecorder: root.showScreenRecorder,
                showScreenshot: root.showScreenshot,
                showTitle: root.showTitle,
                showCaffeine: root.showCaffeine,
                clockSeconds: root.clockSeconds,
                use24h: root.use24h,
                wallpaperPath: root.wallpaperPath
            },
            dock: {
                enabled: root.dockEnabled,
                position: root.dockPosition,
                autohide: root.dockAutohide,
                iconSize: root.dockIconSize,
                screen: root.dockScreen,
                pinned: root.dockPinned
            },
            hyprland: {
                gapsIn: root.gapsIn,
                gapsOut: root.gapsOut,
                borderSize: root.borderSize,
                rounding: root.rounding,
                activeOpacity: root.activeOpacity,
                inactiveOpacity: root.inactiveOpacity,
                blurEnabled: root.blurEnabled,
                blurSize: root.blurSize,
                animationsEnabled: root.animationsEnabled,
                layout: root.layout,
                naturalScroll: root.naturalScroll,
                kbLayout: root.kbLayout,
                followMouse: root.followMouse,
                sensitivity: root.sensitivity
            },
            power: {
                lockEnabled: root.lockEnabled,
                lockMinutes: root.lockMinutes,
                screenOffEnabled: root.screenOffEnabled,
                screenOffMinutes: root.screenOffMinutes,
                suspendEnabled: root.suspendEnabled,
                suspendMinutes: root.suspendMinutes
            }
        }
    }

    // Write the JSON atomically-ish and re-apply the Hyprland half.
    function save() {
        const json = JSON.stringify(root._data(), null, 2)
        writeProc.command = [
            "sh", "-c",
            'mkdir -p "$HOME/.config/muze" && printf \'%s\' "$1" > "$HOME/.config/muze/settings.json"',
            "sh", json
        ]
        writeProc.running = true
        root.applyHyprland()
    }

    function applyHyprland() {
        hyprProc.command = ["muze-hypr-apply"]
        hyprProc.running = true
    }

    // Regenerate ~/.config/muze/hypridle.conf from the power settings and
    // restart hypridle (it has no live reload).
    function applyIdle() {
        // Absolute path: the Settings UI must keep working even when
        // ~/.local/bin is not on PATH (e.g. a shell started outside the
        // session's autostart environment).
        idleProc.command = [Quickshell.env("HOME") + "/.local/bin/muze-idle"]
        idleProc.running = true
    }

    // Re-render every matugen template from the CURRENT wallpaper. This never
    // changes the wallpaper itself (--colors-only --refresh).
    function retheme() {
        themeProc.command = ["muze-theme", "--colors-only", "--refresh"]
        themeProc.running = true
    }

    function setWallpaper(path) {
        root.wallpaperPath = path
        root.save()
        themeProc.command = ["muze-theme", path]
        themeProc.running = true
    }

    function apply(key, value) {
        root[key] = value
        root.save()
        if (key === "themeApps" || key === "themeMode")
            root.retheme()
        if (root.powerKeys.indexOf(key) >= 0)
            root.applyIdle()
    }

    function load(raw) {
        const wasReady = root.ready
        if (!raw || raw.trim() === "") {
            if (root.ready) return
            root.ready = true
            root.save()
            return
        }
        let d
        try { d = JSON.parse(raw) } catch (e) {
            console.error("Muze: could not parse settings.json:", e)
            return
        }
        const a = d.appearance || {}
        const h = d.hyprland || {}
        const p = d.power || {}
        const dk = d.dock || {}
        const pick = (v, fallback) => (v === undefined || v === null) ? fallback : v

        root.themeMode = pick(a.themeMode, root.themeMode)
        root.themeApps = pick(a.themeApps, root.themeApps)
        root.barHeight = pick(a.barHeight, root.barHeight)
        root.barOpacity = pick(a.barOpacity, root.barOpacity)
        root.showClock = pick(a.showClock, root.showClock)
        root.showWorkspaces = pick(a.showWorkspaces, root.showWorkspaces)
        root.showMedia = pick(a.showMedia, root.showMedia)
        root.showVolume = pick(a.showVolume, root.showVolume)
        root.showBrightness = pick(a.showBrightness, root.showBrightness)
        root.showCpu = pick(a.showCpu, root.showCpu)
        root.showNetwork = pick(a.showNetwork, root.showNetwork)
        root.showBattery = pick(a.showBattery, root.showBattery)
        root.showTemperature = pick(a.showTemperature, root.showTemperature)
        root.showTray = pick(a.showTray, root.showTray)
        root.showBluetooth = pick(a.showBluetooth, root.showBluetooth)
        root.showSettingsButton = pick(a.showSettingsButton, root.showSettingsButton)
        root.showAppsMenu = pick(a.showAppsMenu, root.showAppsMenu)
        root.showPower = pick(a.showPower, root.showPower)
        root.showScreenRecorder = pick(a.showScreenRecorder, root.showScreenRecorder)
        root.showScreenshot = pick(a.showScreenshot, root.showScreenshot)
        root.showTitle = pick(a.showTitle, root.showTitle)
        root.showCaffeine = pick(a.showCaffeine, root.showCaffeine)
        // Bar layout: prefer region arrays; migrate legacy single pluginOrder.
        if (Array.isArray(a.barLeft) || Array.isArray(a.barCenter) || Array.isArray(a.barRight)) {
            root.barLeft = pick(a.barLeft, root.barLeft)
            root.barCenter = pick(a.barCenter, root.barCenter)
            root.barRight = pick(a.barRight, root.barRight)
        } else if (Array.isArray(a.pluginOrder)) {
            const order = a.pluginOrder.slice()
            const leftSet = { workspaces: true, appsmenu: true }
            const centerSet = { clock: true, media: true, title: true }
            const left = [], center = [], right = []
            for (let i = 0; i < order.length; i++) {
                const id = order[i]
                if (leftSet[id]) left.push(id)
                else if (centerSet[id]) center.push(id)
                else right.push(id)
            }
            root.barLeft = left; root.barCenter = center; root.barRight = right
        }
        root.normalizeBarRegions()
        // Ensure fixed controls are present and placed reasonably if missing
        if (root.barLeft.indexOf("appsmenu") < 0 && root.barCenter.indexOf("appsmenu") < 0 && root.barRight.indexOf("appsmenu") < 0)
            root.barLeft = ["appsmenu"].concat(root.barLeft)
        if (root.barLeft.indexOf("settingsbutton") < 0 && root.barCenter.indexOf("settingsbutton") < 0 && root.barRight.indexOf("settingsbutton") < 0)
            root.barRight = root.barRight.concat(["settingsbutton"])
        root.clockSeconds = pick(a.clockSeconds, root.clockSeconds)
        root.use24h = pick(a.use24h, root.use24h)
        root.wallpaperPath = pick(a.wallpaperPath, root.wallpaperPath)

        root.dockEnabled = pick(dk.enabled, root.dockEnabled)
        root.dockPosition = pick(dk.position, root.dockPosition)
        root.dockAutohide = pick(dk.autohide, root.dockAutohide)
        root.dockIconSize = pick(dk.iconSize, root.dockIconSize)
        root.dockScreen = pick(dk.screen, root.dockScreen)
        root.dockPinned = pick(dk.pinned, root.dockPinned)

        root.gapsIn = pick(h.gapsIn, root.gapsIn)
        root.gapsOut = pick(h.gapsOut, root.gapsOut)
        root.borderSize = pick(h.borderSize, root.borderSize)
        root.rounding = pick(h.rounding, root.rounding)
        root.activeOpacity = pick(h.activeOpacity, root.activeOpacity)
        root.inactiveOpacity = pick(h.inactiveOpacity, root.inactiveOpacity)
        root.blurEnabled = pick(h.blurEnabled, root.blurEnabled)
        root.blurSize = pick(h.blurSize, root.blurSize)
        root.animationsEnabled = pick(h.animationsEnabled, root.animationsEnabled)
        root.layout = pick(h.layout, root.layout)
        root.naturalScroll = pick(h.naturalScroll, root.naturalScroll)
        root.kbLayout = pick(h.kbLayout, root.kbLayout)
        root.followMouse = pick(h.followMouse, root.followMouse)
        root.sensitivity = pick(h.sensitivity, root.sensitivity)

        root.lockEnabled = pick(p.lockEnabled, root.lockEnabled)
        root.lockMinutes = pick(p.lockMinutes, root.lockMinutes)
        root.screenOffEnabled = pick(p.screenOffEnabled, root.screenOffEnabled)
        root.screenOffMinutes = pick(p.screenOffMinutes, root.screenOffMinutes)
        root.suspendEnabled = pick(p.suspendEnabled, root.suspendEnabled)
        root.suspendMinutes = pick(p.suspendMinutes, root.suspendMinutes)

        // An external edit (agent / profile import / dotfiles restore) must
        // re-apply the Hyprland half as well. save() already does this for UI
        // changes, so only do it on a reload of a previously loaded config.
        if (wasReady) {
            root.applyHyprland()
            root.applyIdle()
        }
        root.ready = true
    }

    // QtObject has no default property, so helpers are declared as typed
    // properties rather than children (same pattern as Quickshell configs).
    property Process writeProc: Process { running: false }
    property Process hyprProc: Process { running: false }
    property Process themeProc: Process { running: false }
    property Process idleProc: Process { running: false }

    property Process loadProc: Process {
        running: true
        command: ["sh", "-c", 'cat "$HOME/.config/muze/settings.json" 2>/dev/null || true']
        stdout: StdioCollector {
            onStreamFinished: root.load(text)
        }
    }

    // Live-reload when settings.json is edited outside the UI (agent, profile
    // import, dotfiles restore). Our own save() only changes properties, so
    // this never loops.
    property FileView watcher: FileView {
        path: root.configPath
        watchChanges: true
        // watchChanges only emits fileChanged; re-read explicitly so textChanged
        // actually fires for edits made outside the UI (agent, profile import,
        // dotfiles restore).
        onFileChanged: root.watcher.reload()
        onTextChanged: root.load(root.watcher.text())
    }
}
