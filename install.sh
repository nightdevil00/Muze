#!/usr/bin/env bash
# install.sh -- install the Muze desktop into a home directory.
#
# Used three ways:
#   ./install.sh                         install into the current $HOME
#   ./install.sh --target /home/alice    install into another user's home
#   ./install.sh --target /etc/skel --skel   populate the ISO skeleton
#                                            (paths stay HOME-relative)
#
# Safe to re-run: user-owned files are never deleted, only overwritten with
# the shipped defaults. Use --force to also refresh generated colour files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}"
SKEL=0
FORCE=0
OWNER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET=$2; shift 2 ;;
        --skel)   SKEL=1; shift ;;
        --force)  FORCE=1; shift ;;
        --owner)  OWNER=$2; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

info() { printf '\033[0;34m[muze-install]\033[0m %s\n' "$*"; }

[[ -d "$ROOT/shell" && -d "$ROOT/config" ]] || { echo "Muze source tree not found at $ROOT" >&2; exit 1; }
mkdir -p "$TARGET"

# 1. QuickShell config (real copy, not a symlink: /etc/skel must be portable)
rm -rf "$TARGET/.config/quickshell"
mkdir -p "$TARGET/.config/quickshell"
cp -r "$ROOT/shell/." "$TARGET/.config/quickshell/"
# Clipboard capture helper is invoked by wl-paste; keep it executable here and
# in the skel copy (archiso strips modes, so customize_airootfs.sh repeats it).
chmod 755 "$TARGET/.config/quickshell/clipboard/capture.sh" 2>/dev/null || true
info "shell -> $TARGET/.config/quickshell"

# 2. Desktop config tree. Generated colour files are only installed on a
#    fresh home or with --force, so a user's current palette survives updates.
for dir in hypr kitty foot fuzzel qt6ct gtk-3.0 gtk-4.0 btop matugen muze quickshell mimeapps.list; do
    src="$ROOT/config/$dir"
    [[ -e "$src" ]] || continue
    dst="$TARGET/.config/$dir"
    if [[ -d "$src" ]]; then
        mkdir -p "$dst"
        for f in "$src"/* "$src"/.[!.]*; do
            [[ -e "$f" ]] || continue
            base=$(basename "$f")
            case "$base" in
                muze-colors.conf|muze-colors.ini|muze.conf|muze.theme|gtk.css|colors.lua|look.lua|wallpaper-theme.json|hyprlock.conf)
                    if [[ $FORCE -eq 1 || ! -e "$dst/$base" ]]; then cp -r "$f" "$dst/$base"; fi
                    ;;
                *) cp -r "$f" "$dst/" ;;
            esac
        done
    else
        cp "$src" "$dst"
    fi
done
info "config -> $TARGET/.config"

# 3. CLI helpers
mkdir -p "$TARGET/.local/bin"
cp "$ROOT/bin/"* "$TARGET/.local/bin/"
chmod 755 "$TARGET/.local/bin/"*
info "bin -> $TARGET/.local/bin"

# 4. Wallpaper + first-run state
mkdir -p "$TARGET/Pictures/Wallpapers"
cp "$ROOT/assets/beach.jpg" "$TARGET/Pictures/Wallpapers/"
if [[ $SKEL -eq 0 ]]; then
    printf '%s' "$TARGET/Pictures/Wallpapers/beach.jpg" > "$TARGET/.config/quickshell/wallpaper.conf"
else
    # /etc/skel has no absolute path yet; muze-session-start falls back to
    # $HOME/Pictures/Wallpapers/beach.jpg.
    rm -f "$TARGET/.config/quickshell/wallpaper.conf"
fi
printf 'wallpaper' > "$TARGET/.config/quickshell/theme.conf"

# 5. A default settings.json if none exists
if [[ ! -f "$TARGET/.config/muze/settings.json" ]]; then
    mkdir -p "$TARGET/.config/muze"
    cp "$ROOT/config/muze/settings.json" "$TARGET/.config/muze/settings.json"
fi

# 6. Desktop entry for the installer (live session convenience)
mkdir -p "$TARGET/.local/share/applications"
cat > "$TARGET/.local/share/applications/muze-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install Muze
Comment=Install Muze to this machine
Exec=kitty -e sudo muze-install
Icon=system-software-install
Terminal=false
Categories=System;
EOF

# 7. Ownership (installing into a target home from the live ISO)
if [[ -n "$OWNER" ]]; then
    chown -R "$OWNER" "$TARGET/.config" "$TARGET/.local" "$TARGET/Pictures" 2>/dev/null || true
    info "chowned to $OWNER"
elif [[ $SKEL -eq 0 && $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    u=$(id -u "$SUDO_USER" 2>/dev/null || true); g=$(id -g "$SUDO_USER" 2>/dev/null || true)
    [[ -n "$u" && -n "$g" ]] && chown -R "$u:$g" "$TARGET/.config" "$TARGET/.local" "$TARGET/Pictures" 2>/dev/null || true
fi

info "done. Start with: qs -n -d   (or log into the Muze Hyprland session)"
