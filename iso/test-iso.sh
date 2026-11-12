#!/usr/bin/env bash
# test-iso.sh -- boot a Muze ISO in QEMU (UEFI via OVMF) so you can try the
# live desktop and the installer without rebooting the host.
#
#   ./iso/test-iso.sh                       uses the newest Muze ISO
#   ./iso/test-iso.sh path/to/muze.iso
#   RAM=8192 CPUS=6 ./iso/test-iso.sh
#
# The VM window is a GTK window on the host desktop. Close it (or Ctrl+C in the
# terminal) to stop. The ISO is attached read-only, so nothing is written to it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO=${1:-$(ls -1t "$HERE"/../*.iso 2>/dev/null | head -1 || true)}
[[ -n "$ISO" && -f "$ISO" ]] || { echo "No Muze ISO found. Build one with: sudo ./iso/build_iso.sh" >&2; exit 1; }

OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd
[[ -f "$OVMF_CODE" && -f "$OVMF_VARS" ]] || {
    echo "OVMF firmware missing. Install with: sudo pacman -S edk2-ovmf" >&2
    exit 1
}

RAM=${RAM:-4096}
CPUS=${CPUS:-4}
VARS=$(mktemp /tmp/muze-ovmf-vars-XXXXXX.fd)
cp "$OVMF_VARS" "$VARS"
trap 'rm -f "$VARS"' EXIT

echo "Booting: $ISO"
echo "  RAM ${RAM} MiB, ${CPUS} CPUs, UEFI (OVMF), virtio-gpu"
echo "  Close the QEMU window or press Ctrl+C here to stop."

exec qemu-system-x86_64 \
    -name "Muze live" \
    -enable-kvm \
    -m "$RAM" -smp "$CPUS" \
    -cpu host \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$VARS" \
    -cdrom "$ISO" \
    -boot d \
    -device virtio-gpu-pci \
    -display gtk \
    -device virtio-net-pci,netdev=muze-net \
    -netdev user,id=muze-net \
    -usb -device usb-tablet
