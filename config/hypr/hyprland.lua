-- Muze -- Hyprland configuration (Hyprland 0.57+ Lua config).
--
-- Generated files live under ~/.config/hypr/muze/:
--   look.lua    -- from ~/.config/muze/settings.json (muze-hypr-apply)
--   colors.lua  -- from the wallpaper (matugen) or the selected theme
--   user.lua    -- hand overrides, loaded last
-- The display manager writes monitors.lua; the `dofile` call below is what its
-- persistence check looks for.

local HOME = os.getenv("HOME") or ""

local function include(rel)
    local path = HOME .. "/.config/hypr/" .. rel
    local ok, err = pcall(dofile, path)
    if not ok then
        print("[muze] could not load " .. path .. ": " .. tostring(err))
    end
end

-- Fallback first, then the generated monitors.lua (written by the Muze
-- display manager). dofile (not require) so `hyprctl reload` re-reads it.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
pcall(dofile, (os.getenv("HOME") or "") .. "/.config/hypr/monitors.lua")

-- Generated + user config (dofile, not require, so `hyprctl reload` re-reads
-- them even though Lua caches modules).
include("muze/clipboard.lua")
include("muze/look.lua")
include("muze/colors.lua")
include("muze/user.lua")

------------------------------------------------------------------ environment
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("GTK_THEME", "adw-gtk3-dark")
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")

-------------------------------------------------------------------- autostart
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("muze-session-start")
    -- Ensure the Muze QuickShell UI is running (uses ~/.config/quickshell).
    hl.exec_cmd("sh -c 'pgrep -x qs >/dev/null 2>&1 || qs -n -d >/dev/null 2>&1 &'")
end)

------------------------------------------------------------------------ input
hl.config({
    input = {
        kb_layout    = "us",
        kb_variant   = "",
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = { natural_scroll = true },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

---------------------------------------------------------------------- keybinds
local M      = "SUPER"
local term   = "kitty"
local files  = "thunar"
local menu   = "fuzzel"

-- Apps & Muze shell
hl.bind(M .. " + RETURN",  hl.dsp.exec_cmd(term))
hl.bind(M .. " + E",       hl.dsp.exec_cmd(files))
hl.bind(M .. " + SPACE",   hl.dsp.exec_cmd(menu))
hl.bind(M .. " + D",       hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(M .. " + COMMA",   hl.dsp.exec_cmd("qs ipc call muze settings"))
hl.bind(M .. " + T",       hl.dsp.exec_cmd("qs ipc call theme toggle"))
hl.bind(M .. " + W",       hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))
hl.bind(M .. " + O",       hl.dsp.exec_cmd("qs ipc call monitors toggle"))
hl.bind(M .. " + SHIFT + O", hl.dsp.exec_cmd("qs ipc call monitors refresh"))
hl.bind(M .. " + SHIFT + C", hl.dsp.exec_cmd("qs ipc call idle toggle"))
hl.bind(M .. " + I",       hl.dsp.exec_cmd("kitty -e sudo muze-install"))
hl.bind(M .. " + N",       hl.dsp.exec_cmd("qs ipc call notifications dismiss_all"))
hl.bind(M .. " + SHIFT + N", hl.dsp.exec_cmd("qs ipc call notifications dnd_toggle"))
hl.bind(M .. " + SHIFT + R", hl.dsp.exec_cmd("muze-record toggle"))

-- Windows
hl.bind(M .. " + Q", hl.dsp.window.close())
hl.bind(M .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(M .. " + P", hl.dsp.window.pseudo())
hl.bind(M .. " + F", hl.dsp.window.fullscreen())
hl.bind(M .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(M .. " + SHIFT + M", hl.dsp.exec_cmd("qs ipc call power toggle"))

-- Focus / move
hl.bind(M .. " + left",        hl.dsp.focus({ direction = "left" }))
hl.bind(M .. " + right",       hl.dsp.focus({ direction = "right" }))
hl.bind(M .. " + up",          hl.dsp.focus({ direction = "up" }))
hl.bind(M .. " + down",        hl.dsp.focus({ direction = "down" }))
hl.bind(M .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(M .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(M .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(M .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Workspaces
for i = 1, 10 do
    local key = tostring(i % 10)
    hl.bind(M .. " + " .. key,        hl.dsp.focus({ workspace = i }))
    hl.bind(M .. " + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))
end
hl.bind(M .. " + S",        hl.dsp.workspace.toggle_special("magic"))
hl.bind(M .. " + SHIFT + S",  hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(M .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(M .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Mouse
hl.bind(M .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots
-- hl.bind(M .. " + PRINT",       hl.dsp.exec_cmd("muze-screenshot full-clip"))
-- hl.bind("PRINT",               hl.dsp.exec_cmd("muze-screenshot region-clip"))
-- hl.bind(M .. " + SHIFT + PRINT", hl.dsp.exec_cmd("muze-screenshot region-file"))
hl.bind("XF86SelectiveScreenshot", hl.dsp.exec_cmd("muze-screenshot region-clip"))

-- Media / brightness
local media = {
    { "XF86AudioRaiseVolume",   "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+" },
    { "XF86AudioLowerVolume",   "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" },
    { "XF86AudioMute",          "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" },
    { "XF86AudioMicMute",       "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle" },
    { "XF86MonBrightnessUp",    "brightnessctl -e4 -n2 set 5%+" },
    { "XF86MonBrightnessDown",  "brightnessctl -e4 -n2 set 5%-" },
    { "XF86AudioPlay",          "playerctl play-pause" },
    { "XF86AudioPause",         "playerctl play-pause" },
    { "XF86AudioNext",          "playerctl next" },
    { "XF86AudioPrev",          "playerctl previous" },
}
for _, b in ipairs(media) do
    hl.bind(b[1], hl.dsp.exec_cmd(b[2]), { locked = true, repeating = true })
end

------------------------------------------------------------------------- rules
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true,
              fullscreen = false, pin = false },
    no_focus = true,
})

hl.layer_rule({ name = "muze-blur-shell",  match = { namespace = "quickshell-.*" }, blur = true })
hl.layer_rule({ name = "muze-blur-muze",   match = { namespace = "muze-.*" },      blur = true })
hl.layer_rule({ name = "muze-noanim-osd",  match = { namespace = "quickshell-osd" }, no_anim = true })
hl.layer_rule({ name = "muze-ignorezero",  match = { namespace = "quickshell-.*" }, ignore_alpha = true })

-------------------------------------------------------------------------- misc
hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
    layers = {
        allow_new_top_layers_over_existing_fullscreen = true,
    },
    dwindle = { preserve_split = true },
    master  = { new_status = "master" },
})
