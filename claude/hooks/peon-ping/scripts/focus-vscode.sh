#!/bin/bash
# peon-ping: focus an existing VS Code window for a given workspace CWD.
#
# Usage: focus-vscode.sh <cwd>
#
# Strategy:
#   1. Enumerate VS Code (Insiders) windows via kdotool / wmctrl.
#   2. Match by workspace name in the window title: VS Code titles look like
#        "<file> - <workspace-folder> - Visual Studio Code [- Insiders]"
#      so we match on the basename of <cwd>.
#   3. Activate the matching window via the window manager — never invoke
#      `code -r`, which would replace the workspace in the foreground window
#      (the original bug: clicking the notif closed the current workspace and
#      reopened a new one).
#   4. If no matching window exists, activate any VS Code window as a fallback.
#      Do NOT spawn a new instance — the user can open it manually.
set -u

cwd="${1:-}"
log_dir="${PEON_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/logs"
mkdir -p "$log_dir" 2>/dev/null
log_file="$log_dir/focus-vscode-$(date +%F).log"
ts() { date '+%F %T'; }
log() { printf '[%s] %s\n' "$(ts)" "$*" >>"$log_file" 2>/dev/null; }

log "click cwd=${cwd:-<empty>}"

base=""
[ -n "$cwd" ] && base="$(basename "$cwd")"

# Common VS Code window classes / wmclass identifiers.
VSCODE_CLASSES=(
  'Code - Insiders'
  'code-insiders'
  'Code'
  'code-oss'
  'code'
  'VSCodium'
  'Cursor'
)

# --- kdotool path (Wayland-safe via KWin scripting) ---------------------------
if command -v kdotool &>/dev/null; then
  match_wid=""
  first_wid=""
  for cls in "${VSCODE_CLASSES[@]}"; do
    while IFS= read -r wid; do
      [ -z "$wid" ] && continue
      [ -z "$first_wid" ] && first_wid="$wid"
      name="$(kdotool getwindowname "$wid" 2>/dev/null || true)"
      log "candidate wid=$wid name=$name"
      if [ -n "$base" ] && printf '%s' "$name" | grep -qF -- "- $base -"; then
        match_wid="$wid"
        break 2
      fi
    done < <(kdotool search --class "$cls" 2>/dev/null)
  done

  target="${match_wid:-$first_wid}"
  if [ -n "$target" ]; then
    if [ -n "$match_wid" ]; then
      log "kdotool: activate workspace-matched $target"
    else
      log "kdotool: no workspace match for '$base'; activating first VS Code window $target"
    fi
    kdotool windowactivate "$target" >/dev/null 2>&1
    exit 0
  fi
fi

# --- wmctrl fallback (X11 / XWayland) -----------------------------------------
if command -v wmctrl &>/dev/null; then
  if [ -n "$base" ]; then
    # Match window by title substring " - <base> -"
    wmctrl_match=$(wmctrl -l 2>/dev/null | awk -v b=" - $base -" 'index($0, b) {print $1; exit}')
    if [ -n "$wmctrl_match" ]; then
      log "wmctrl: activate workspace-matched id=$wmctrl_match"
      wmctrl -i -a "$wmctrl_match" >/dev/null 2>&1
      exit 0
    fi
  fi
  for cls in 'code-insiders.Code - Insiders' 'code.Code' 'code-oss.Code'; do
    if wmctrl -lx 2>/dev/null | awk '{print $3}' | grep -q "^${cls}$"; then
      log "wmctrl: activate first match for class $cls"
      wmctrl -x -a "$cls" >/dev/null 2>&1
      exit 0
    fi
  done
fi

log "no VS Code window found to activate (no instance running?)"
exit 1
