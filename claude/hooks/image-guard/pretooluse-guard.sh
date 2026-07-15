#!/usr/bin/env bash
# PreToolUse hook for the Read tool.
#
# Reads the hook JSON payload on stdin, extracts the target file_path, and if
# it is an oversized / unsupported / corrupt image, blocks the Read by exiting
# with code 2 and printing guidance to stderr. Claude Code surfaces a
# PreToolUse exit-2 as a denial with the stderr text fed back to the model,
# so the model learns to run `cb-img` on the file first instead of poisoning
# the conversation with an image the API will reject.
#
# Fail-open everywhere: any parsing/inspection problem allows the Read. The
# guard must never block legitimate work; its only job is to stop the known
# token-bleed case.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSPECT="$HERE/imgcheck.py"

payload="$(cat)"

# Extract file_path from the PreToolUse payload (.tool_input.file_path).
# Use python for robust JSON parsing; fall back to allowing on any error.
file_path="$(printf '%s' "$payload" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("file_path", "") or "")
except Exception:
    print("")
' 2>/dev/null || true)"

[ -z "$file_path" ] && exit 0
[ -f "$file_path" ] || exit 0

# Quick extension gate so we only pay inspection cost on image-ish files.
case "${file_path,,}" in
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.tif|*.tiff|*.avif|*.heic|*.heif|*.svg) ;;
  *) exit 0 ;;
esac

# Capture stdout and exit code together. Note: `set -e` is disabled for this
# assignment via `|| rc=$?` so a non-zero inspect exit does not abort the hook.
# We must read $? from the substitution itself, not from a wrapping `if`
# (a non-taken `if` resets $? to 0, masking the real code).
rc=0
reasons="$(python3 "$INSPECT" "$file_path" 2>/dev/null)" || rc=$?

# rc 0 => safe; rc 2 => unsafe (reasons on stdout); rc 3/other => allow.
if [ "$rc" -ne 2 ]; then
  exit 0
fi

cat >&2 <<EOF
BLOCKED: "$file_path" would likely be rejected by the API as an unprocessable
image, which triggers an expensive full-conversation retry loop.

Reasons:
$(printf '%s\n' "$reasons" | sed 's/^/  - /')

Fix it first, then re-read the SAFE copy:
  cb-img "$file_path"
This writes an API-safe PNG/JPEG (<5MB, <=8000px, <=3.75MP) and prints its
path. Read that path instead. Do NOT re-read the original.
EOF
exit 2
