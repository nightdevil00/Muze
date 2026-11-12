#!/usr/bin/env bash
# muze-install :: apply (rewritten) - deterministic executor for install.toml
set -euo pipefail

CONFIG=$1
PASSWORD=$2
LOGFILE=${3:-/root/muze-install.log}
MUZE_ROOT=${MUZE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
export MUZE_ROOT

info() { printf '\033[0;34m  INFO\033[0m    %s\n' "$*"; }
ok()   { printf '\033[0;32m  OK\033[0m      %s\n' "$*"; }
warn() { printf '\033[1;33m  WARN\033[0m    %s\n' "$*"; }
abort(){ printf '\033[0;31m  ABORT\033[0m   %s\n' "$*"; exit 1; }

# Load config
ENV_FILE=$(mktemp)
python3 - "$CONFIG" > "$ENV_FILE" <<'PY'
import sys, tomllib, shlex
with open(sys.argv[1], 'rb') as f:
    d = tomllib.load(f)
def emit(p, o):
    for k, v in o.items():
        key = p + k.upper()
        if isinstance(v, dict):
            emit(key + '_', v)
        elif isinstance(v, bool):
            print(f"{key}={'true' if v else 'false'}")
        elif isinstance(v, list):
            print(f"{key}={shlex.quote(' '.join(map(str,v)))}")
        elif v is None:
            print(f"{key}=")
        else:
            print(f"{key}={shlex.quote(str(v))}")
emit('', d)
PY
set -a; . "$ENV_FILE"; set +a
rm -f "$ENV_FILE"

HOSTNAME=${SYSTEM_HOSTNAME:-muze}
USERNAME=${SYSTEM_USERNAME:-user}
LOCALE=${SYSTEM_LOCALE:-en_US.UTF-8}
KEYMAP=${SYSTEM_KEYMAP:-us}
TIMEZONE=${SYSTEM_TIMEZONE:-UTC}
DISK=${DISK_DEVICE:-}
MODE=${DISK_MODE:-fullwipe}
FS=${DISK_FILESYSTEM:-btrfs}
ENCRYPT=${DISK_ENCRYPT:-false}
EFI_MB=${DISK_EFI_SIZE_MB:-512}
EFI_DEV_MANUAL=${DISK_EFI_DEVICE:-}
ROOT_DEV_MANUAL=${DISK_ROOT_DEVICE:-}
BOOTLOADER=${BOOT_BOOTLOADER:-limine}
CHAINLOAD_WINDOWS=${BOOT_CHAINLOAD_WINDOWS:-true}
SNAPSHOTS=${BOOT_SNAPSHOTS:-${AGENT_SNAPSHOT_BEFORE:-true}}
SOURCE=${PACKAGES_SOURCE:-auto}
PROFILES=${PACKAGES_PROFILES:-minimal}
BROWSER=${PACKAGES_BROWSER:-chromium}
FLATPAK=${PACKAGES_FLATPAK:-false}
AUR=${PACKAGES_AUR:-false}
EXTRA=${PACKAGES_EXTRA:-}
SNAPSHOT_BEFORE=${AGENT_SNAPSHOT_BEFORE:-$SNAPSHOTS}
THEME_MODE=${MUZE_THEME_MODE:-wallpaper}
THEME_APPS=${MUZE_THEME_APPS:-true}
BAR_HEIGHT=${MUZE_BAR_HEIGHT:-32}
BAR_OPACITY=${MUZE_BAR_OPACITY:-100}

[[ $EUID -eq 0 ]] || abort "must run as root"
[[ -d /sys/firmware/efi ]] || abort "UEFI required (/sys/firmware/efi missing)"
[[ -n "$DISK" && -b "$DISK" ]] || abort "invalid or missing [disk].device: $DISK"

# Prevent touching live USB
BOOT_SRC=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
if [[ -n "$BOOT_SRC" ]]; then
    d="$BOOT_SRC"
    while :; do
        parent=$(lsblk -dno PKNAME "$d" 2>/dev/null | tail -1 || true)
        [[ -n "$parent" ]] || break
        d="/dev/$parent"
    done
    [[ "$DISK" == "$d" ]] && abort "refusing to install onto the live USB ($d)"
fi

# Package source
OFFLINE_REPO="/var/cache/offline-repo"
OFFLINE=0
if [[ "$SOURCE" == "offline" || "$SOURCE" == "auto" ]]; then
    [[ -f "$OFFLINE_REPO/offline.db" ]] && OFFLINE=1
fi
[[ "$SOURCE" == "offline" && $OFFLINE -eq 0 ]] && abort "offline install requested but no bundled repo at $OFFLINE_REPO"
if [[ $OFFLINE -eq 1 ]]; then
    PACMAN_CONF=$(mktemp /tmp/muze-pacman-XXXX.conf)
    cat > "$PACMAN_CONF" <<'EOF'
[options]
Architecture = auto
SigLevel = Never
LocalFileSigLevel = Optional
ParallelDownloads = 8
[offline]
SigLevel = Never
Server = file:///var/cache/offline-repo/
EOF
    ok "using bundled offline repository"
else
    PACMAN_CONF="/etc/pacman.conf"
    ping -c 1 -W 2 archlinux.org >/dev/null 2>&1 || abort "no internet and no offline repo"
    ok "using online Arch mirrors"
fi

# Package list
read_list() { [[ -f "$1" ]] || return 0; sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true; }
PKGS=()
PKGS+=($(read_list "$MUZE_ROOT/packages/base.packages"))
PKGS+=($(read_list "$MUZE_ROOT/packages/desktop.packages"))
DET=$(bash "$MUZE_ROOT/installer/muze-detect" --shell 2>/dev/null || true)
UCODE=$(sed -n 's/^UCODE=//p' <<<"$DET" | tr -d "'" | tr -d '"')
GPU_PKGS=$(sed -n 's/^GPU_PKGS=//p' <<<"$DET" | tr -d "'" | tr -d '"')
BATTERY=$(sed -n 's/^BATTERY=//p' <<<"$DET" | tr -d "'" | tr -d '"')
[[ -n "$UCODE" ]] && PKGS+=($UCODE)
[[ -n "$GPU_PKGS" ]] && PKGS+=($GPU_PKGS)
[[ "$BATTERY" == "yes" ]] && PKGS+=(tlp)
if [[ "$SNAPSHOTS" == "true" ]]; then
    PKGS+=(snapper snap-pac)
    if [[ "$BOOTLOADER" == "limine" ]]; then
        PKGS+=(limine-mkinitcpio-hook limine-snapper-sync)
    fi
fi

# profiles
PKGS+=($(read_list "$MUZE_ROOT/packages/profiles/minimal.packages"))
for p in $PROFILES; do
    [[ "$p" == "minimal" ]] && continue
    f="$MUZE_ROOT/packages/profiles/$p.packages"
    [[ -f "$f" ]] && PKGS+=($(read_list "$f")) || warn "unknown profile: $p"
done

case "$BROWSER" in
    firefox) PKGS+=(firefox) ;;
    zen)     PKGS+=(chromium); warn "Zen Browser is AUR; installed post-boot if enabled" ;;
    *)       PKGS+=(chromium) ;;
esac
[[ "$BROWSER" != "chromium" && "$BROWSER" != "zen" ]] && PKGS=("${PKGS[@]/chromium/}")
[[ "$BROWSER" != "firefox" ]] && PKGS=("${PKGS[@]/firefox/}")
[[ "$FLATPAK" == "true" ]] && PKGS+=(flatpak)
[[ -n "$EXTRA" ]] && PKGS+=($EXTRA)

if [[ $OFFLINE -eq 1 ]]; then
    FILTERED=()
    for p in $(printf '%s\n' "${PKGS[@]}" | grep -v '^$' | sort -u); do
        if compgen -G "$OFFLINE_REPO/${p}-*.pkg.tar.zst" >/dev/null; then FILTERED+=("$p"); else warn "dropping $p (not in offline repo)"; fi
    done
    PKGS=("${FILTERED[@]}")
else
    mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | grep -v '^$' | sort -u)
fi
ok "packages to install: ${#PKGS[@]}"

[[ "$SNAPSHOT_BEFORE" == "true" && -x "$MUZE_ROOT/bin/muze-snapshot" ]] && bash "$MUZE_ROOT/bin/muze-snapshot" "$DISK" || true

# Partitioning
part_num() { local dev=$1 n=$2; [[ "$dev" == *nvme* || "$dev" == *mmcblk* ]] && printf '%sp%s' "$dev" "$n" || printf '%s%s' "$dev" "$n"; }
WIN_EFI=""
for p in $(blkid -t TYPE=vfat -o device 2>/dev/null || true); do
    mp=$(mktemp -d); if mount -o ro "$p" "$mp" 2>/dev/null; then [[ -d "$mp/EFI/Microsoft" ]] && WIN_EFI="$p"; umount "$mp" 2>/dev/null || true; fi; rmdir "$mp" 2>/dev/null || true; [[ -n "$WIN_EFI" ]] && break
done

if [[ "$MODE" == "manual" ]]; then
    [[ -n "$EFI_DEV_MANUAL" && -b "$EFI_DEV_MANUAL" ]] || abort "manual mode needs [disk].efi_device"
    [[ -n "$ROOT_DEV_MANUAL" && -b "$ROOT_DEV_MANUAL" ]] || abort "manual mode needs [disk].root_device"
    EFI_DEV="$EFI_DEV_MANUAL"; ROOT_DEV="$ROOT_DEV_MANUAL"; EFI_NUM=$(lsblk -no PARTN "$EFI_DEV" | head -1)
    ok "manual layout: EFI=$EFI_DEV root=$ROOT_DEV"
elif [[ "$MODE" == "fullwipe" ]]; then
    warn "ERASING ALL DATA ON $DISK"
    parted --script "$DISK" mklabel gpt
    parted --script "$DISK" mkpart primary fat32 1MiB "${EFI_MB}MiB"; parted --script "$DISK" set 1 esp on; parted --script "$DISK" name 1 "MUZE_EFI"
    parted --script "$DISK" mkpart primary btrfs "${EFI_MB}MiB" 100%; parted --script "$DISK" name 2 "MUZE_ROOT"
    EFI_NUM=1; ROOT_NUM=2; EFI_DEV=$(part_num "$DISK" 1); ROOT_DEV=$(part_num "$DISK" 2)
else # dualboot
    FREE=$(parted -m "$DISK" unit B print free 2>/dev/null | awk -F: '$NF ~ /free/ {gsub(/B/,"",$2);gsub(/B/,"",$3);gsub(/B/,"",$4); if($4+0>m+0){m=$4+0;s=$2;e=$3}} END{if(m>0) printf "%s %s %s",s,e,m}' || true)
    START_B=$(awk '{print $1}' <<<"$FREE"); END_B=$(awk '{print $2}' <<<"$FREE"); SIZE_B=$(awk '{print $3}' <<<"$FREE")
    [[ -n "$FREE" && "$SIZE_B" -ge $((12*1073741824)) ]] || abort "no free region >= 12 GiB on $DISK (shrink a partition first)"
    LAST=$(lsblk -n -o PARTN "$DISK" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -1)
    EFI_NUM=$(( ${LAST:-0} + 1 )); ROOT_NUM=$(( EFI_NUM + 1 ))
    ALIGN=$((1048576)); EFI_START=$(( (START_B + ALIGN - 1) / ALIGN * ALIGN )); EFI_END=$(( EFI_START + EFI_MB*1048576 ))
    ROOT_START=$(( (EFI_END + 1 + ALIGN - 1) / ALIGN * ALIGN )); ROOT_END=$(( END_B / ALIGN * ALIGN - ALIGN ))
    (( ROOT_END > ROOT_START )) || abort "not enough aligned free space"
    parted --script "$DISK" mkpart primary fat32 "${EFI_START}B" "${EFI_END}B"; parted --script "$DISK" set "$EFI_NUM" esp on; parted --script "$DISK" name "$EFI_NUM" "MUZE_EFI"
    parted --script "$DISK" mkpart primary btrfs "${ROOT_START}B" "${ROOT_END}B"; parted --script "$DISK" name "$ROOT_NUM" "MUZE_ROOT"
    EFI_DEV=$(part_num "$DISK" "$EFI_NUM"); ROOT_DEV=$(part_num "$DISK" "$ROOT_NUM")
    ok "dualboot: $(( SIZE_B/1073741824 )) GiB free region reused"
fi

partprobe "$DISK" 2>/dev/null || true; sync; sleep 2
[[ -b "$EFI_DEV" && -b "$ROOT_DEV" ]] || abort "partitions not found: $EFI_DEV / $ROOT_DEV"

# Filesystems
LUKS_UUID=""
wipefs -a "$ROOT_DEV" 2>/dev/null || true
if [[ "$ENCRYPT" == "true" ]]; then
    info "LUKS2 on $ROOT_DEV"
    printf '%s' "$PASSWORD" | cryptsetup luksFormat --type luks2 --batch-mode --force-password "$ROOT_DEV" -
    printf '%s' "$PASSWORD" | cryptsetup open "$ROOT_DEV" muze_root
    ROOT_MAP="/dev/mapper/muze_root"
    LUKS_UUID=$(cryptsetup luksUUID "$ROOT_DEV")
else
    ROOT_MAP="$ROOT_DEV"
fi

mkfs.btrfs -f "$ROOT_MAP" >/dev/null; udevadm settle
mount "$ROOT_MAP" /mnt
SUBVOLS=(@ @home @log @pkg @.snapshots @var @root)
for s in "${SUBVOLS[@]}"; do btrfs subvolume create "/mnt/$s" >/dev/null; done
umount /mnt
MOPTS="noatime,compress=zstd"
mount -o "$MOPTS,subvol=@" "$ROOT_MAP" /mnt
mkdir -p /mnt/{home,.snapshots,var,root,boot,efi}
mount -o "$MOPTS,subvol=@home" "$ROOT_MAP" /mnt/home
mount -o "$MOPTS,subvol=@var"  "$ROOT_MAP" /mnt/var
mount -o "$MOPTS,subvol=@root" "$ROOT_MAP" /mnt/root
mkdir -p /mnt/var/log /mnt/var/cache/pacman/pkg
mount -o "$MOPTS,subvol=@log" "$ROOT_MAP" /mnt/var/log
mount -o "$MOPTS,subvol=@pkg" "$ROOT_MAP" /mnt/var/cache/pacman/pkg
mount -o "$MOPTS,subvol=@.snapshots" "$ROOT_MAP" /mnt/.snapshots

mkfs.fat -F32 -n MUZE_EFI "$EFI_DEV" >/dev/null; udevadm settle
mount "$EFI_DEV" /mnt/boot
ok "filesystems ready"

# Windows chainload copy
if [[ "$MODE" == "dualboot" && -n "$WIN_EFI" && "$WIN_EFI" != "$EFI_DEV" ]]; then
    WIN_MP=$(mktemp -d)
    if mount -o ro "$WIN_EFI" "$WIN_MP" 2>/dev/null; then
        mkdir -p /mnt/boot/EFI
        cp -r "$WIN_MP/EFI/Microsoft" /mnt/boot/EFI/ 2>/dev/null && ok "Windows bootloader copied" || warn "could not copy Windows bootloader"
        umount "$WIN_MP"
    fi
    rmdir "$WIN_MP" 2>/dev/null || true
fi

# Cmdline
if [[ "$ENCRYPT" == "true" ]]; then
    CMDLINE="quiet splash cryptdevice=UUID=${LUKS_UUID}:muze_root root=/dev/mapper/muze_root rw rootflags=subvol=@ rootfstype=btrfs"
else
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_MAP")
    CMDLINE="quiet splash root=UUID=${ROOT_UUID} rw rootflags=subvol=@ rootfstype=btrfs"
fi
CMDLINE_FB=${CMDLINE/quiet splash /quiet }

# Pacstrap
info "installing base system (${#PKGS[@]} packages) ..."
pacstrap -C "$PACMAN_CONF" /mnt "${PKGS[@]}"
genfstab -U /mnt >> /mnt/etc/fstab
ok "base system installed"

[[ "$ENCRYPT" == "true" ]] && printf 'muze_root UUID=%s none luks,discard\n' "$LUKS_UUID" >> /mnt/etc/crypttab
[[ $OFFLINE -eq 1 ]] && cp "$PACMAN_CONF" /mnt/etc/pacman-offline.conf

# Stage AUR snapshot pkgs if available
mkdir -p /mnt/var/cache/muze-aur
if [[ $OFFLINE -eq 1 ]]; then
    for p in limine-mkinitcpio-hook limine-snapper-sync; do
        for f in "$OFFLINE_REPO/$p"-*.pkg.tar.zst; do [[ -f "$f" ]] && cp -f "$f" /mnt/var/cache/muze-aur/ || true; done
    done
fi

# Chroot setup
cat > /mnt/setup.sh <<'CHROOT'
#!/usr/bin/bash
set -euo pipefail
source /pwhash.env
rm -f /pwhash.env

TIMEZONE="__TIMEZONE__"
HOSTNAME="__HOSTNAME__"
KEYMAP="__KEYMAP__"
USERNAME="__USERNAME__"
LOCALE="__LOCALE__"
ENCRYPT="__ENCRYPT__"
EFINUM="__EFINUM__"
DISK="__DISK__"
CHAINLOAD="__CHAINLOAD__"
CMDLINE="__CMDLINE__"
CMDLINE_FB="__CMDLINE_FB__"
FLATPAK="__FLATPAK__"
BOOTLOADER="__BOOTLOADER__"
SNAPSHOTS="__SNAPSHOTS__"

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc || true
printf '%s UTF-8\n' "en_US" > /etc/locale.gen
grep -q "^$LOCALE UTF-8" /etc/locale.gen || printf '%s UTF-8\n' "$LOCALE" >> /etc/locale.gen
locale-gen
printf 'LANG=%s\n' "$LOCALE" > /etc/locale.conf
printf '%s\n' "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<H
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
H
printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf

cat > /etc/os-release <<'OSR'
NAME="Muze"
PRETTY_NAME="Muze Linux"
ID=muze
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/muze"
DOCUMENTATION_URL="https://wiki.archlinux.org"
SUPPORT_URL="https://github.com/muze/issues"
BUG_REPORT_URL="https://github.com/muze/issues"
LOGO=archlinux-logo
OSR
ln -sf /etc/os-release /usr/lib/os-release

echo "root:$PWHASH" | chpasswd -e
useradd -m -G wheel -s /bin/bash "$USERNAME" 2>/dev/null || true
echo "$USERNAME:$PWHASH" | chpasswd -e
sed -i '/^# %wheel ALL=(ALL:ALL) ALL$/s/^# //' /etc/sudoers

cat > /etc/pacman.conf <<'PAC'
[options]
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
PAC

sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
sed -i 's|^BINARIES=.*|BINARIES=(/usr/bin/btrfs)|' /etc/mkinitcpio.conf
if [[ "$ENCRYPT" == "true" ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
else
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap block filesystems fsck)/' /etc/mkinitcpio.conf
fi
grep -q '^COMPRESSION=' /etc/mkinitcpio.conf || printf 'COMPRESSION="zstd"\n' >> /etc/mkinitcpio.conf
mkinitcpio -P

cat > /etc/systemd/zram-generator.conf <<'Z'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
Z

# Snapper
if [[ "$SNAPSHOTS" == "true" ]]; then
  mkdir -p /etc/snapper/configs /etc/conf.d
  cat > /etc/snapper/configs/root <<'SNAPCONF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="10"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="no"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
SNAPCONF
  printf 'SNAPPER_CONFIGS="root"\n' > /etc/conf.d/snapper
  chmod 750 /.snapshots 2>/dev/null || true
  chown root:root /.snapshots 2>/dev/null || true
fi

# Bootloader
if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
  bootctl install || true
  mkdir -p /boot/loader/entries
  printf 'default  muze.conf\n' > /boot/loader/loader.conf
  printf 'timeout 3\n' >> /boot/loader/loader.conf
  printf 'console-mode max\n' >> /boot/loader/loader.conf
  if [[ "$ENCRYPT" == "true" ]]; then
    printf 'title   Muze Linux\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions %s\n' "$CMDLINE" > /boot/loader/entries/muze.conf
  else
    ROOT_UUID=$(blkid -s UUID -o value "$(findmnt -no SOURCE /)" 2>/dev/null || blkid -s UUID -o value /dev/mapper/muze_root 2>/dev/null || true)
    if [[ -z "$ROOT_UUID" ]]; then ROOT_UUID=$(grep -oP 'root=UUID=\K[^ ]+' <<<"$CMDLINE" | head -1 || true); fi
    printf 'title   Muze Linux\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions root=UUID=%s rw rootflags=subvol=@ rootfstype=btrfs\n' "$ROOT_UUID" > /boot/loader/entries/muze.conf
  fi
  cp /boot/loader/entries/muze.conf /boot/loader/entries/muze-fallback.conf 2>/dev/null || true
  sed -i 's/initramfs-linux.img/initramfs-linux-fallback.img/' /boot/loader/entries/muze-fallback.conf 2>/dev/null || true
  sed -i "s|options .*|options $CMDLINE_FB|" /boot/loader/entries/muze-fallback.conf 2>/dev/null || true
else
  # limine
  mkdir -p /boot/EFI/limine /boot/EFI/BOOT
  if [[ -f /usr/share/limine/BOOTX64.EFI ]]; then
    cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
    cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
  fi
  efibootmgr --create --disk "$DISK" --part "$EFINUM" --label "Muze (Limine)" --loader '\EFI\limine\BOOTX64.EFI' --unicode || true
  if compgen -G '/var/cache/muze-aur/*.pkg.tar.zst' >/dev/null 2>&1; then
    pacman -U --noconfirm /var/cache/muze-aur/*.pkg.tar.zst >/dev/null 2>&1 || true
  fi
  printf 'TARGET_OS_NAME="Muze Linux"\nESP_PATH="/boot"\n' > /etc/default/limine
  if [[ -f /etc/limine-snapper-sync.conf ]]; then
    sed -i 's|^#\?TARGET_OS_NAME=.*|TARGET_OS_NAME="Muze Linux"|' /etc/limine-snapper-sync.conf
    sed -i 's|^#\?ESP_PATH=.*|ESP_PATH="/boot"|' /etc/limine-snapper-sync.conf
  else
    printf 'TARGET_OS_NAME="Muze Linux"\nESP_PATH="/boot"\n' > /etc/limine-snapper-sync.conf
  fi
  if [[ ! -s /boot/limine.conf ]]; then
    cat > /boot/limine.conf <<LIMEOF
timeout: 3

/Muze Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: $CMDLINE
    module_path: boot():/initramfs-linux.img

/Muze Linux (fallback)
    protocol: linux
    path: boot():/vmlinuz-linux
    cmdline: $CMDLINE_FB
    module_path: boot():/initramfs-linux-fallback.img
LIMEOF
  fi
  if [[ -d /boot/EFI/Microsoft && "$CHAINLOAD" == "true" ]] && ! grep -qi 'Microsoft' /boot/limine.conf; then
    cat >> /boot/limine.conf <<'WEOF'

/Windows Boot Manager
    protocol: chainload
    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
WEOF
  fi
  cp -f /boot/limine.conf /boot/EFI/limine/limine.conf 2>/dev/null || true
  cp -f /boot/limine.conf /boot/EFI/BOOT/limine.conf 2>/dev/null || true
fi

systemctl enable NetworkManager.service
systemctl enable bluetooth.service
systemctl enable systemd-timesyncd.service
systemctl enable fstrim.timer
[[ "$FLATPAK" == "true" ]] && systemctl enable --now flatpak.service 2>/dev/null || true
[[ "$SNAPSHOTS" == "true" ]] && systemctl enable snapper-cleanup.timer 2>/dev/null || true
if [[ "$BOOTLOADER" == "limine" && -f /usr/lib/systemd/system/limine-snapper-sync.service ]]; then
  systemctl enable limine-snapper-sync.service 2>/dev/null || true
fi
mkdir -p /etc/muze
CHROOT

LOCALE_BASE=${LOCALE%%.*}
PWHASH=$(printf '%s' "$PASSWORD" | openssl passwd -6 -stdin)
printf "PWHASH='%s'\nLOCALE='%s'\nLANG_BASE='%s'\n" "$PWHASH" "$LOCALE" "$LOCALE_BASE" > /mnt/pwhash.env
for kv in "TIMEZONE:$TIMEZONE" "HOSTNAME:$HOSTNAME" "KEYMAP:$KEYMAP" "USERNAME:$USERNAME" "LOCALE:$LOCALE" \
          "ENCRYPT:$ENCRYPT" "EFINUM:$EFI_NUM" "DISK:$DISK" "CHAINLOAD:$CHAINLOAD_WINDOWS" \
          "CMDLINE:$CMDLINE" "CMDLINE_FB:$CMDLINE_FB" "FLATPAK:$FLATPAK" "BOOTLOADER:$BOOTLOADER" "SNAPSHOTS:$SNAPSHOTS"; do
    k=${kv%%:*}; v=${kv#*:}
    sed -i "s|__${k}__|${v}|g" /mnt/setup.sh
done
chmod +x /mnt/setup.sh
arch-chroot /mnt /setup.sh
rm -f /mnt/setup.sh
ok "system configured"

# Muze files
info "installing the Muze desktop ..."
UID_T=$(id -u "$USERNAME" 2>/dev/null || echo 1000)
GID_T=$(id -g "$USERNAME" 2>/dev/null || echo 1000)
mkdir -p "/mnt/home/$USERNAME"
bash "$MUZE_ROOT/install.sh" --target "/mnt/home/$USERNAME" --owner "$UID_T:$GID_T" 2>/dev/null || bash "$MUZE_ROOT/install.sh" || true
printf '/home/%s/Pictures/Wallpapers/beach.jpg' "$USERNAME" > "/mnt/home/$USERNAME/.config/quickshell/wallpaper.conf" 2>/dev/null || true
chown "$UID_T:$GID_T" "/mnt/home/$USERNAME/.config/quickshell/wallpaper.conf" 2>/dev/null || true
mkdir -p /mnt/usr/share/muze /mnt/etc/muze
cp -r "$MUZE_ROOT/." /mnt/usr/share/muze/ 2>/dev/null || true
cp "$CONFIG" /mnt/etc/muze/install.toml 2>/dev/null || true
printf 'Muze %s\n' "$(cat "$MUZE_ROOT/VERSION" 2>/dev/null || echo 0.1.0)" > /mnt/etc/muze/release
python3 - "/mnt/home/$USERNAME/.config/muze/settings.json" "$THEME_MODE" "$THEME_APPS" "$BAR_HEIGHT" "$BAR_OPACITY" <<'PY' 2>/dev/null || true
import json, sys
p = sys.argv[1]
try: d = json.load(open(p))
except Exception: d = {"version":1,"appearance":{},"hyprland":{}}
d.setdefault("appearance", {})
d["appearance"].update(themeMode=sys.argv[2], themeApps=(sys.argv[3]=="true"), barHeight=int(sys.argv[4]), barOpacity=int(sys.argv[5]))
open(p,"w").write(json.dumps(d, indent=2) + "\n")
PY
chown -R "$UID_T:$GID_T" "/mnt/home/$USERNAME" 2>/dev/null || true

cat > /mnt/usr/local/bin/muze-first-boot <<'EOF'
#!/usr/bin/env bash
set -u
C=/etc/muze/install.toml
[[ -f "$C" ]] || exit 0
shopt -s nullglob
for p in limine-mkinitcpio-hook limine-snapper-sync; do
  pacman -Q "$p" >/dev/null 2>&1 && continue
  for f in /var/cache/muze-aur/$p-*.pkg.tar.zst; do pacman -U --noconfirm "$f" >/dev/null 2>&1 && break; done
done
AUR=$(python3 -c 'import tomllib;print(str(tomllib.load(open("/etc/muze/install.toml","rb")).get("packages",{}).get("aur",False)))' 2>/dev/null || echo False)
if [[ "$AUR" == "True" ]] && ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
  command -v yay >/dev/null 2>&1 || { pacman -S --needed --noconfirm base-devel git >/dev/null 2>&1 || true; su -c 'cd /tmp && git clone --depth 1 https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm' -s /bin/bash "$(id -un 1000)" >/dev/null 2>&1 || true; }
  for p in limine-mkinitcpio-hook limine-snapper-sync; do yay -S --needed --noconfirm "$p" >/dev/null 2>&1 || true; done
  if [[ -f /usr/share/muze/packages/aur.packages ]]; then
    mapfile -t AUR_PKGS < <(sed -e 's/#.*//' /usr/share/muze/packages/aur.packages | grep -v '^$' | grep -vxE 'limine-mkinitcpio-hook|limine-snapper-sync')
    (( ${#AUR_PKGS[@]} )) && yay -S --needed --noconfirm "${AUR_PKGS[@]}" >/dev/null 2>&1 || true
  fi
fi
if [[ -f /usr/lib/systemd/system/limine-snapper-sync.service ]]; then
  systemctl enable limine-snapper-sync.service >/dev/null 2>&1 || true
  systemctl enable snapper-cleanup.timer >/dev/null 2>&1 || true
fi
u=$(id -un 1000 2>/dev/null || true)
[[ -n "$u" ]] && su - "$u" -c 'command -v muze-theme >/dev/null && muze-theme "$HOME/Pictures/Wallpapers/beach.jpg"' >/dev/null 2>&1 || true
systemctl disable muze-first-boot.service >/dev/null 2>&1 || true
EOF
chmod 755 /mnt/usr/local/bin/muze-first-boot
cat > /mnt/etc/systemd/system/muze-first-boot.service <<'EOF'
[Unit]
Description=Muze first-boot setup
After=network-online.target graphical.target
Wants=network-online.target
ConditionPathExists=/etc/muze/install.toml
[Service]
Type=oneshot
ExecStart=/usr/local/bin/muze-first-boot
[Install]
WantedBy=multi-user.target
EOF
arch-chroot /mnt systemctl enable muze-first-boot.service >/dev/null 2>&1 || true
ok "Muze desktop installed"

cp "$LOGFILE" /mnt/var/log/muze-install.log 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
if [[ "$ENCRYPT" == "true" ]]; then cryptsetup close muze_root 2>/dev/null || true; fi
ok "filesystems unmounted"
