#!/bin/bash
set -uo pipefail

case "$NTFY_TITLE" in
  *error*|*Error*|*ERROR*|*fail*|*Fail*)
    EVT="PostToolUseFailure"
    EXTRA='{"tool_name":"Bash","error":"ntfy remote error"}'
    ;;
  *complete*|*done*|*Done*)
    EVT="Stop"
    EXTRA='{}'
    ;;
  *permission*|*Permission*|*approval*|*needs*)
    EVT="PermissionRequest"
    EXTRA='{}'
    ;;
  *idle*|*question*)
    EVT="Notification"
    EXTRA='{"notification_type":"elicitation_dialog"}'
    ;;
  *)
    # default — skip (silent). Avoids noise on every ntfy push.
    exit 0
    ;;
esac

jq -n \
  --arg e "$EVT" \
  --arg s "ntfy-bridge" \
  --argjson x "$EXTRA" \
  '{hook_event_name: $e, cwd: "", session_id: $s, permission_mode: ""} * $x' \
  | bash "$HOME/.claude/hooks/peon-ping/peon.sh"
