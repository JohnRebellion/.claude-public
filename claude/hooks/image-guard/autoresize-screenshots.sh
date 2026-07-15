#!/usr/bin/env bash
# autoresize-screenshots.sh — shrink any oversized screenshot to API-safe
# limits, in place. Triggered by a systemd path unit watching the screenshot
# folder. Keeps pasted screenshots from ever tripping the Claude image-removal
# error.
#
# Safety:
#   - Only touches files under the watched dir with image extensions.
#   - Only rewrites when the file is actually over a limit (idempotent).
#   - Skips files already tagged safe (xattr marker) to avoid re-processing
#     and avoid a feedback loop with the path unit.
#   - Never deletes; rewrites in place via a temp file + atomic mv.
set -euo pipefail

WATCH_DIR="${1:-$HOME/Pictures/Screenshots}"
MAX_DIM=8000
MAX_BYTES=$((5 * 1024 * 1024))
MAX_MP=3.75
TARGET_DIM=4096
MARKER="user.cb_img_safe"

command -v magick >/dev/null 2>&1 || exit 0
[ -d "$WATCH_DIR" ] || exit 0

shopt -s nullglob nocaseglob
process_one() {
  local f="$1"
  [ -f "$f" ] || return 0
  # Skip if we've already marked it safe.
  getfattr -n "$MARKER" "$f" >/dev/null 2>&1 && return 0

  local W H FMT bytes mp need=0
  local probe
  probe="$(magick identify -limit area 0 -format '%w %h %m\n' "${f}[0]" 2>/dev/null)" || return 0
  read -r W H FMT <<<"$probe"
  [ -n "${W:-}" ] || return 0
  bytes=$(stat -c%s "$f")
  mp=$(awk "BEGIN{printf \"%.2f\", ($W*$H)/1000000}")

  [ "$bytes" -gt "$MAX_BYTES" ] && need=1
  { [ "$W" -gt "$MAX_DIM" ] || [ "$H" -gt "$MAX_DIM" ]; } && need=1
  awk "BEGIN{exit !($mp > $MAX_MP)}" && need=1

  if [ "$need" -eq 0 ]; then
    setfattr -n "$MARKER" -v 1 "$f" 2>/dev/null || true
    return 0
  fi

  local tmp="${f}.cbimg.tmp"
  # Read first frame only (`[0]`) so multi-frame PNG/APNG/animated sources
  # don't make magick emit numbered files; force the output codec with a
  # `PNG:` prefix so the .tmp extension can't confuse format detection.
  if magick "${f}[0]" -limit area 0 -auto-orient -strip \
       -resize "${TARGET_DIM}x${TARGET_DIM}>" "PNG:$tmp" 2>/dev/null \
     && [ -s "$tmp" ]; then
    # If still too big, hard-cap dimensions further.
    if [ "$(stat -c%s "$tmp")" -gt "$MAX_BYTES" ]; then
      magick "$tmp" -resize '3000x3000>' "PNG:$tmp" 2>/dev/null || true
    fi
    mv -f "$tmp" "$f"
    setfattr -n "$MARKER" -v 1 "$f" 2>/dev/null || true
    logger -t cb-img-autoresize "resized $f (${W}x${H}, ${mp}MP)" 2>/dev/null || true
  else
    rm -f "$tmp"
  fi
}

# Process all currently-eligible files in the dir (the path unit fires on any
# change; we sweep so we never miss one and stay idempotent via the marker).
for f in "$WATCH_DIR"/*.png "$WATCH_DIR"/*.jpg "$WATCH_DIR"/*.jpeg "$WATCH_DIR"/*.webp; do
  process_one "$f"
done
