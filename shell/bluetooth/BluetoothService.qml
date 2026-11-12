// Bluetooth state/service integration for the shell.
// Wraps Quickshell Bluetooth APIs to expose adapter/device state, scanning,
// connect/disconnect/pair/trust actions, and audio profile helpers for UI
// components (bar, settings). Centralizes device management logic in one place.

pragma Singleton

// Muze Bluetooth service -- thin, reactive wrapper over Quickshell's native
// Quickshell.Bluetooth (BlueZ over D-Bus). No external commands needed.
import Quickshell
import Quickshell.Bluetooth
import QtQuick

QtObject {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null && adapter !== undefined
    readonly property bool powered: available ? adapter.enabled : false
    readonly property bool discovering: available ? adapter.discovering : false
    readonly property var devices: Bluetooth.devices

    readonly property string connectedName: {
        let devs = []
        try { devs = Bluetooth.devices.values || [] } catch (e) { return "" }
        for (const d of devs) {
            if (d.connected) return d.deviceName || d.name || "Connected"
        }
        return ""
    }

    readonly property int connectedCount: {
        let n = 0
        let devs = []
        try { devs = Bluetooth.devices.values || [] } catch (e) { return 0 }
        for (const d of devs) if (d.connected) n++
        return n
    }

    readonly property int deviceCount: {
        let devs = []
        try { devs = Bluetooth.devices.values || [] } catch (e) { return 0 }
        return devs.length
    }

    function setPowered(on) {
        if (root.available) root.adapter.enabled = on
    }
    function togglePower() { root.setPowered(!root.powered) }
    function setDiscovering(on) {
        if (root.available) root.adapter.discovering = on
    }
    function toggleDiscovering() { root.setDiscovering(!root.discovering) }
}
