#!/usr/bin/env bash
# build_iso.sh -- build the Muze live/install ISO with archiso.
#
#   1. Copy the releng profile as a base.
#   2. Overlay iso/overlay/ (live user, autologin, pacman configs, skel).
#   3. Populate /etc/skel with the Muze shell + configs via install.sh --skel,
#      so mkarchiso copies them into /home/live/.config at boot.
#   4. Copy the whole Muze source tree into /opt/muze (installer reads it).
#   5. Download base + desktop + default packages into a bundled offline repo.
#   6. Add the desktop packages to the ISO's packages.x86_64.
#   7. Run mkarchiso and copy the finished ISO to the project root.
#
# Run as root:  sudo ./iso/build_iso.sh
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
info() { echo -e "${B}INFO:${N} $*"; }
ok()   { echo -e "${G}OK:${N} $*"; }
abort(){ echo -e "${R}ABORT:${N} $*"; exit 1; }

[[ $EUID -eq 0 ]] || abort "run as root (sudo $0)"

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT/iso"
WORK="$PROJECT/iso/work"
PROFILE="$WORK/profile"
OUT="$WORK/out"
CACHE="$WORK/pkg-cache"
SKEL="$PROFILE/airootfs/etc/skel"
OFFLINE="$PROFILE/airootfs/var/cache/offline-repo"
LOGFILE="$PROJECT/iso/build_iso.log"
mkdir -p "$PROJECT/iso"
exec > >(tee -a "$LOGFILE") 2>&1
info "build log: $LOGFILE"

# ---------------------------------------------------------------- prereqs ---
command -v mkarchiso >/dev/null || { info "installing archiso"; pacman -S --noconfirm archiso; }
command -v repo-add  >/dev/null || { info "installing pacman-contrib"; pacman -S --noconfirm pacman-contrib; }
RELENG=/usr/share/archiso/configs/releng
[[ -d "$RELENG" ]] || abort "releng profile missing ($RELENG)"

# ---------------------------------------------------------------- work dir ---
if [[ -d "$WORK" && "${KEEP_WORK:-0}" != "1" ]]; then
    info "cleaning $WORK"
    rm -rf "$WORK"
fi
mkdir -p "$PROFILE" "$OUT" "$CACHE" "$SKEL" "$OFFLINE"
cp -a "$RELENG/." "$PROFILE/"

# ---------------------------------------------------------------- overlay ----
info "overlaying Muze airootfs files"
cp -a "$SCRIPT_DIR/overlay/airootfs/." "$PROFILE/airootfs/"

# /etc/skel -> /home/live/.config (mkarchiso copies skel for UID >= 1000 users)
info "populating /etc/skel with the Muze desktop"
"$PROJECT/install.sh" --target "$SKEL" --skel
# skel must be root-owned; mkarchiso chowns it to the live user
chown -R 0:0 "$SKEL"

# Whole source tree for the installer. Copy an explicit whitelist: the profile
# lives inside $PROJECT/iso/work, so a blind `cp -a "$PROJECT/."` would recurse.
info "copying Muze source into /opt/muze"
mkdir -p "$PROFILE/airootfs/opt/muze"
for item in shell config bin assets packages installer docs install.sh VERSION README.md; do
    [[ -e "$PROJECT/$item" ]] && cp -a "$PROJECT/$item" "$PROFILE/airootfs/opt/muze/"
done
cp /home/mihai/Projects/Muze.md "$PROFILE/airootfs/opt/muze/Muze.md" 2>/dev/null || true
chmod 755 "$PROFILE/airootfs/usr/local/bin/"* "$PROFILE/airootfs/opt/muze/install.sh" \
          "$PROFILE/airootfs/opt/muze/bin/"* 2>/dev/null || true

# ---------------------------------------------------------------- packages ---
read_list() { # read_list <file>
    [[ -f "$1" ]] || return 0
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

ISO_PKGS=()
ISO_PKGS+=($(read_list "$PROJECT/packages/desktop.packages"))
ISO_PKGS+=($(read_list "$PROJECT/packages/offline-extra.packages"))
# Tools needed by the live environment / installer
ISO_PKGS+=(sddm arch-install-scripts limine efibootmgr parted gptfdisk openssl \
           gum dialog jq python dbus snapper snap-pac zram-generator mkinitcpio)
for p in "${ISO_PKGS[@]}"; do
    # A second kernel would need a second archiso initramfs; keep the live ISO
    # on one kernel. LTS still ships in the offline repo for target installs.
    [[ "$p" == linux-lts* ]] && continue
    grep -qx -- "$p" "$PROFILE/packages.x86_64" 2>/dev/null || echo "$p" >> "$PROFILE/packages.x86_64"
done
ok "ISO package list: $(wc -l < "$PROFILE/packages.x86_64") entries"

# Enable only the [multilib] section in the build config (optional profiles).
python3 - "$PROFILE/pacman.conf" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('#[multilib]\n#Include = /etc/pacman.d/mirrorlist',
              '[multilib]\nInclude = /etc/pacman.d/mirrorlist')
p.write_text(s)
PY

# ------------------------------------------------------- offline repository ---
OFFLINE_PKGS=()
OFFLINE_PKGS+=($(read_list "$PROJECT/packages/base.packages"))
OFFLINE_PKGS+=($(read_list "$PROJECT/packages/desktop.packages"))
OFFLINE_PKGS+=($(read_list "$PROJECT/packages/profiles/minimal.packages"))
OFFLINE_PKGS+=($(read_list "$PROJECT/packages/offline-extra.packages"))
mapfile -t OFFLINE_PKGS < <(printf '%s\n' "${OFFLINE_PKGS[@]}" | sort -u)
ok "offline repo: ${#OFFLINE_PKGS[@]} packages (+ dependencies)"

DL_CONF="$WORK/pacman-dl.conf"
cat > "$DL_CONF" <<'PACDL'
[options]
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
ParallelDownloads = 5
DownloadUser = root
DisableDownloadTimeout
SigLevel = Never
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
PACDL

if [[ "${SKIP_DOWNLOAD:-0}" == "1" && -f "$OFFLINE/offline.db" ]]; then
    ok "reusing existing offline repo (SKIP_DOWNLOAD=1)"
else
    TMP_DB="$WORK/tmp-db"
    mkdir -p "$TMP_DB"
    info "syncing package databases into a temporary db"
    pacman -Sy --config "$DL_CONF" --dbpath "$TMP_DB" --cachedir "$CACHE" --noconfirm
    info "downloading packages + all dependencies (this is the slow part)"
    # Provide defaults for provider prompts and confirmations in non-interactive runs.
    # With pipefail, `yes` exits 141 (SIGPIPE) when pacman closes stdin; ignore that
    # as long as pacman itself succeeds.
    set +o pipefail
    yes "" | pacman -Sw --config "$DL_CONF" --dbpath "$TMP_DB" --cachedir "$CACHE" --noconfirm \
           "${OFFLINE_PKGS[@]}"
    dl_rc=${PIPESTATUS[1]}
    set -o pipefail
    [[ $dl_rc -eq 0 ]] || abort "package download failed (pacman exit $dl_rc)"
    rm -rf "$TMP_DB"

    info "creating offline repository"
    find "$CACHE" -name '*.pkg.tar.zst' -exec cp -n {} "$OFFLINE/" \;
    COUNT=$(find "$OFFLINE" -name '*.pkg.tar.zst' | wc -l)
    [[ "$COUNT" -gt 0 ]] || abort "no packages downloaded"
    ( cd "$OFFLINE" && repo-add offline.db.tar.gz ./*.pkg.tar.zst )
    ok "offline repo: $COUNT packages"
fi

# -------------------------------------------------------- AUR package cache ---
# Boot-critical AUR packages (Limine snapshot stack) cannot be built inside
# pacstrap: they are built on the host once and cached here, then added to the
# offline repo so both the live ISO and installed systems have them.
AUR_CACHE="$PROJECT/packages/aur-cache"
if compgen -G "$AUR_CACHE/*.pkg.tar.zst" >/dev/null; then
    info "adding cached AUR packages to the offline repo"
    cp -n "$AUR_CACHE/"*.pkg.tar.zst "$OFFLINE/"
    ( cd "$OFFLINE" && repo-add offline.db.tar.gz ./*.pkg.tar.zst >/dev/null )
    ok "AUR cache baked: $(find "$AUR_CACHE" -name '*.pkg.tar.zst' | wc -l) packages"
else
    warn "no packages/aur-cache/*.pkg.tar.zst: snapshot support will be online-only"
fi

# ---------------------------------------------------------------- metadata ---
python3 - "$PROFILE/profiledef.sh" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('iso_name="archlinux"', 'iso_name="muze"')
s = s.replace('iso_label="ARCH_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"',
              'iso_label="MUZE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"')
s = s.replace('iso_publisher="Arch Linux <https://archlinux.org>"',
              'iso_publisher="Muze <https://github.com/muze>"')
s = s.replace('iso_application="Arch Linux Live/Rescue DVD"',
              'iso_application="Muze Live / Installer"')
extra = '''  ["/usr/local/bin/muze-live-login"]="0:0:755"
  ["/usr/local/bin/muze-install"]="0:0:755"
  ["/usr/local/bin/muze-detect"]="0:0:755"
  ["/usr/local/bin/muze-repair"]="0:0:755"
  ["/etc/sudoers.d/live"]="0:0:440"
  ["/etc/profile.d/muze.sh"]="0:0:644"
  ["/etc/skel/.local/bin/"]="0:0:755"
  ["/opt/muze/install.sh"]="0:0:755"
  ["/opt/muze/bin/"]="0:0:755"
  ["/opt/muze/installer/"]="0:0:755"
'''
s = s.replace('file_permissions=(\n', 'file_permissions=(\n' + extra)
p.write_text(s)
PY
# releng's shadow permission stays 400; ensure our new scripts are executable
ok "profile metadata updated"

# ---------------------------------------------------------------- build ------
info "running mkarchiso (this can take a while)"
[[ -d "$WORK/mkarchiso-work" ]] && rm -rf "$WORK/mkarchiso-work"
rm -f "$OUT"/*.iso 2>/dev/null || true
mkarchiso -v -w "$WORK/mkarchiso-work" -o "$OUT" "$PROFILE"

ISO=$(ls -1 "$OUT"/*.iso 2>/dev/null | head -1 || true)
[[ -n "$ISO" ]] || abort "no ISO produced in $OUT"
DEST="$PROJECT/$(basename "$ISO")"
cp "$ISO" "$DEST"
ok "ISO created: $DEST"
ls -lh "$DEST"
info "sha256: $(sha256sum "$DEST" | cut -d' ' -f1)"
