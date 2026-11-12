// Clipboard history backend/service.
// Maintains clipboard entries (text/image metadata as provided by the capture
// pipeline), exposes the model and actions (select/copy/remove/clear) to the
// panel, and coordinates with external helpers/watchers used by the shell.

pragma Singleton

// Muze universal clipboard history service -- Omarchy-style.
// Watches the Wayland clipboard for text and images, keeps a deduplicated
// JSON history, and restores an entry with wl-copy.
import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: root

    property var history: []
    property bool panelVisible: false
    property string filterText: ""
    property int selectedIndex: 0
    property int historyLimit: 100

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/muze"
    readonly property string historyPath: stateDir + "/clipboard-history.json"
    readonly property string captureScript: Quickshell.env("HOME") + "/.config/quickshell/clipboard/capture.sh"

    // Display rows: newest first, filtered by the search text.
    readonly property var displayRows: {
        const q = root.filterText.toLowerCase()
        const rows = []
        for (let i = 0; i < root.history.length; i++) {
            const e = root.history[i]
            if (!e) continue
            const preview = e.type === "image"
                ? "Image · " + (e.mime || "image/png")
                : String(e.text || "").replace(/[\r\n]+/g, " ↵ ")
            if (q !== "" && preview.toLowerCase().indexOf(q) < 0
                    && (e.type !== "text" || String(e.text || "").toLowerCase().indexOf(q) < 0))
                continue
            rows.push({ index: i, type: e.type, preview: preview,
                        path: e.type === "image" ? (e.path || "") : "",
                        capturedAt: e.capturedAt || "" })
        }
        return rows
    }

    function entryKey(e) {
        if (!e) return ""
        return e.type === "image" ? "image:" + (e.path || "")
                                  : "text:" + String(e.text || "")
    }

    function addEntry(raw) {
        const line = String(raw || "").trim()
        if (line === "") return
        let e
        try { e = JSON.parse(line) } catch (err) { return }
        if (!e || (e.type !== "text" && e.type !== "image")) return
        if (e.type === "text" && String(e.text || "").trim() === "") return

        const key = root.entryKey(e)
        const next = [e]
        for (let i = 0; i < root.history.length && next.length < root.historyLimit; i++) {
            if (root.entryKey(root.history[i]) !== key) next.push(root.history[i])
        }
        root.history = next
        root.save()
    }

    function save() {
        writeProc.command = [
            "sh", "-c",
            'mkdir -p "$HOME/.local/state/muze" && printf \'%s\' "$1" > "$HOME/.local/state/muze/clipboard-history.json"',
            "sh", JSON.stringify(root.history, null, 2)
        ]
        writeProc.running = true
    }

    function load(raw) {
        try {
            const d = JSON.parse(String(raw || "[]"))
            if (Array.isArray(d)) root.history = d
        } catch (err) { console.warn("Muze clipboard: bad history file") }
    }

    function paste(index) {
        const e = root.history[index]
        if (!e) return
        if (e.type === "image") {
            pasteProc.command = ["sh", "-c", 'wl-copy --type "$1" < "$2"',
                                 "sh", e.mime || "image/png", e.path || ""]
        } else {
            pasteProc.command = ["sh", "-c", 'printf \'%s\' "$1" | wl-copy',
                                 "sh", String(e.text || "")]
        }
        pasteProc.running = true
        root.close()
    }

    function clear() {
        root.history = []
        root.save()
        root.close()
    }

    function open() {
        root.filterText = ""
        root.selectedIndex = 0
        root.panelVisible = true
    }
    function close() {
        root.panelVisible = false
        root.filterText = ""
    }
    function toggle() {
        if (root.panelVisible) root.close()
        else root.open()
    }
    function move(delta) {
        const n = root.displayRows.length
        if (n === 0) return
        root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + delta))
    }
    function confirm() {
        const row = root.displayRows[root.selectedIndex]
        if (row) root.paste(row.index)
    }

    // Load persisted history once at startup.
    property Process loadProc: Process {
        running: true
        command: ["sh", "-c", 'cat "$HOME/.local/state/muze/clipboard-history.json" 2>/dev/null || true']
        stdout: StdioCollector { onStreamFinished: root.load(text) }
    }

    // Two watchers: text and images. Each capture.sh invocation prints one
    // JSON line; SplitParser hands it to addEntry.
    // `sh <script>` rather than executing the script directly: archiso copies
    // airootfs with --no-preserve=mode, so the exec bit is not guaranteed.
    property Process textWatcher: Process {
        running: true
        command: ["wl-paste", "--type", "text", "--watch", "sh", root.captureScript, "text"]
        stdout: SplitParser { onRead: data => root.addEntry(data) }
    }

    property Process imageWatcher: Process {
        running: true
        command: ["wl-paste", "--type", "image/png", "--watch", "sh", root.captureScript, "image/png"]
        stdout: SplitParser { onRead: data => root.addEntry(data) }
    }

    property Process writeProc: Process { running: false }
    property Process pasteProc: Process { running: false }
}
