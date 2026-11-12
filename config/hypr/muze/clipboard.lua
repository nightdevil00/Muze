-- Muze universal clipboard (Omarchy-style).
--
-- Super+A / C / V / X work in every app; terminals get Ctrl+Shift+C / V so the
-- same shortcut copies and pastes there too. Super+Ctrl+V opens the Muze
-- clipboard history overlay (text + images, searchable).
--
-- The down/up split works around Hyprland's send_shortcut leaving synthetic
-- key state stuck. A virtual keyboard (wtype) cannot be used because the
-- physically held SUPER would merge into the injected chord.
local mod = "SUPER"

local function send_shortcut_once(mods, key)
    return function()
        hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
        hl.timer(function()
            hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
        end, { timeout = 50, type = "oneshot" })
    end
end

local terminal_classes = {
    "kitty", "foot", "org.codeberg.dnkl.foot", "alacritty",
    "com.mitchellh.ghostty", "ghostty", "wezterm", "contour", "rio",
}

local function active_is_terminal()
    local w = hl.get_active_window()
    if not w then return false end
    local c = string.lower(w.class or "")
    for _, name in ipairs(terminal_classes) do
        if c:find(name, 1, true) then return true end
    end
    return false
end

local function universal(default_mods, default_key, term_mods, term_key)
    return function()
        if active_is_terminal() then
            send_shortcut_once(term_mods, term_key)()
        else
            send_shortcut_once(default_mods, default_key)()
        end
    end
end

hl.bind(mod .. " + A",           send_shortcut_once("CTRL", "A"))
hl.bind(mod .. " + C",           universal("CTRL", "C", "CTRL SHIFT", "C"))
hl.bind(mod .. " + V",           universal("CTRL", "V", "CTRL SHIFT", "V"))
hl.bind(mod .. " + X",           send_shortcut_once("CTRL", "X"))
hl.bind(mod .. " + CTRL + V",    hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
