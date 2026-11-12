#!/usr/bin/env bash
# Muze clipboard capture -- adapted from Omarchy's universal clipboard.
#
# Emits ONE compact JSON entry on stdout for the current clipboard selection.
# In watch mode `wl-paste --watch` invokes this with the payload on stdin and
# the MIME type as $1; without arguments it snapshots the selection itself.
#
# Skips password-manager hints, deduplicates images by sha256, and bounds every
# read so a stalled clipboard owner cannot hang the watcher.
set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/muze"
IMAGE_DIR="$STATE_DIR/clipboard-images"
mkdir -p "$IMAGE_DIR"

types=$(timeout 2s wl-paste --list-types 2>/dev/null || true)

if [[ ${CLIPBOARD_STATE:-} == "sensitive" ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
    exit 0
fi

emit_text() {
    local tmp
    tmp=$(mktemp --tmpdir="$STATE_DIR" clipboard.XXXXXX) || return 0
    if ! timeout 2s "$@" >"$tmp" 2>/dev/null || [[ ! -s "$tmp" ]]; then
        rm -f -- "$tmp"
        return 0
    fi
    # -c is essential: wl-paste --watch feeds the QML SplitParser line by line.
    jq -Rsc --arg captured_at "$(date +'%a %H:%M')" \
        '{type:"text", text:., capturedAt:$captured_at}' <"$tmp"
    rm -f -- "$tmp"
}

emit_image() {
    local mime=$1 ext hash file tmp
    shift
    ext=${mime#image/}
    [[ $ext == jpeg ]] && ext=jpg
    tmp=$(mktemp --tmpdir="$IMAGE_DIR" clipboard.XXXXXX) || return 0
    if ! timeout 2s "$@" >"$tmp" 2>/dev/null || [[ ! -s "$tmp" ]]; then
        rm -f -- "$tmp"
        return 0
    fi
    hash=$(sha256sum "$tmp" | awk '{print $1}')
    file="$IMAGE_DIR/$hash.$ext"
    if [[ -e $file ]]; then
        rm -f -- "$tmp"
    else
        mv -- "$tmp" "$file"
    fi
    jq -cn --arg mime "$mime" --arg path "$file" \
        --arg captured_at "$(date +'%a %H:%M')" \
        '{type:"image", mime:$mime, path:$path, capturedAt:$captured_at}'
}

case "${1:-}" in
    text)     emit_text cat; exit 0 ;;
    image/*)  emit_image "$1" cat; exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
    if grep -qx "$mime" <<<"$types"; then
        emit_image "$mime" wl-paste --type "$mime"
        exit 0
    fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
    emit_text wl-paste --type text --no-newline
fi
