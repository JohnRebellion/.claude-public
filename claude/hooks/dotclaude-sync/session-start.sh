#!/usr/bin/env bash
# dotclaude-sync SessionStart hook
# Silent fetch + pull if working tree clean and origin has new commits.
# Never blocks. Never overwrites local changes. Logs everything.

set -u
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG_DIR="$CLAUDE_DIR/hooks/dotclaude-sync/logs"
LOG="$LOG_DIR/sync.log"
mkdir -p "$LOG_DIR"

log() {
  printf '%s [session-start] %s\n' "$(date -Is)" "$*" >> "$LOG"
}

if [[ ! -d "$CLAUDE_DIR/.git" ]]; then
  log "Not a git repo at $CLAUDE_DIR — skip."
  exit 0
fi

cd "$CLAUDE_DIR" || { log "cd failed"; exit 0; }

# WSL2 NAT adds latency to the cold SSH handshake; 8s was too tight (real
# fetch measured ~12s). Retry once before giving up.
if ! timeout 25 git fetch origin --quiet 2>>"$LOG"; then
  log "git fetch slow/failed — retrying once."
  if ! timeout 25 git fetch origin --quiet 2>>"$LOG"; then
    log "git fetch failed or timed out — skip."
    exit 0
  fi
fi

LOCAL=$(git rev-parse @ 2>/dev/null)
REMOTE=$(git rev-parse '@{u}' 2>/dev/null) || { log "No upstream — skip."; exit 0; }
BASE=$(git merge-base @ '@{u}' 2>/dev/null)

if [[ "$LOCAL" == "$REMOTE" ]]; then
  log "Up to date."
  exit 0
fi

if [[ "$LOCAL" == "$BASE" ]]; then
  DIRTY=$(git status --porcelain 2>/dev/null)
  STASHED=0
  if [[ -n "$DIRTY" ]]; then
    STASH_MSG="dotclaude-sync auto-stash $(date -Is)"
    if git stash push -u --quiet -m "$STASH_MSG" 2>>"$LOG"; then
      STASHED=1
      log "Auto-stashed dirty tree before pull."
    else
      log "Auto-stash failed — skip pull."
      exit 0
    fi
  fi

  if git pull --ff-only --quiet origin main 2>>"$LOG"; then
    COMMITS=$(git rev-list --count "$LOCAL..$REMOTE" 2>/dev/null)
    log "Pulled $COMMITS commit(s) from origin."
  else
    log "Fast-forward pull failed."
  fi

  if [[ "$STASHED" -eq 1 ]]; then
    if git stash pop --quiet 2>>"$LOG"; then
      log "Restored auto-stash."
    else
      log "Stash pop conflict — left in stash list for manual resolution."
    fi
  fi
elif [[ "$REMOTE" == "$BASE" ]]; then
  log "Ahead of origin — Stop hook will push."
else
  log "Diverged — manual merge needed."
fi

# Throttled weekly gc (audit 2026-07-15): the repo accumulated 477MB of
# tmp_pack_* garbage from timeout-killed fetch/lfs transfers because nothing
# ever ran gc. Run at most once every 7 days, in the background, non-blocking.
GC_STAMP="$CLAUDE_DIR/hooks/dotclaude-sync/.last-gc"
NOW=$(date +%s)
LAST_GC=0
[[ -f "$GC_STAMP" ]] && LAST_GC=$(cat "$GC_STAMP" 2>/dev/null || echo 0)
if (( NOW - LAST_GC > 604800 )); then
  printf '%s' "$NOW" > "$GC_STAMP"
  log "Weekly gc: launching background git gc."
  ( git gc --auto --quiet 2>>"$LOG"; git prune --expire=2.weeks.ago 2>>"$LOG"; \
    log "Weekly gc: done." ) >/dev/null 2>&1 &
fi

exit 0
