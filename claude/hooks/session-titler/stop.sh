#!/usr/bin/env bash
# Stop-hook wrapper for the session-titler overlay.
#
# Runs AFTER the ECC plugin's session-end hook has written/updated the current
# session .tmp file, and re-derives a heuristic title + slug alias when the
# session's content has drifted. Reads the Stop-hook JSON on stdin (drained by
# titler.js) and never blocks the session — always exits 0.
#
# Independent of the ECC plugin: pure Node + this directory's lib.

set +e
input=$(cat)
printf '%s' "$input" | node "$HOME/.claude/hooks/session-titler/titler.js" hook >/dev/null 2>&1
exit 0
