#!/usr/bin/env bash
# archiso runs this in the airootfs chroot after /etc/skel has been copied to
# user homes. mkarchiso's `cp -af --no-preserve=ownership,mode` strips exec bits
# from custom airootfs files, so restore them here (file_permissions in
# profiledef.sh cannot cover every generated file).
set -e

# Live user helpers (muze-session-start is exec'd by Hyprland on tty1).
chmod 755 /etc/skel/.local/bin/* 2>/dev/null || true
if [[ -d /home/live/.local/bin ]]; then
    chmod 755 /home/live/.local/bin/* 2>/dev/null || true
fi

# Installer source tree in /opt/muze (wrappers use `bash`, but keep these sane).
if [[ -d /opt/muze/bin ]]; then
    chmod 755 /opt/muze/bin/* 2>/dev/null || true
fi
if [[ -d /opt/muze/installer ]]; then
    chmod 755 /opt/muze/installer/muze-* /opt/muze/installer/lib/*.sh 2>/dev/null || true
fi
chmod 755 /opt/muze/install.sh /usr/local/bin/muze-* 2>/dev/null || true

# Universal clipboard: wl-paste --watch runs this capture helper.
chmod 755 /etc/skel/.config/quickshell/clipboard/capture.sh 2>/dev/null || true
if [[ -d /home/live/.config/quickshell/clipboard ]]; then
    chmod 755 /home/live/.config/quickshell/clipboard/capture.sh 2>/dev/null || true
fi

# The live user may install without a password.
chmod 440 /etc/sudoers.d/live 2>/dev/null || true

exit 0
