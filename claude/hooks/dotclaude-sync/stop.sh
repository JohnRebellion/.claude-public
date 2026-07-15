#!/usr/bin/env bash
# dotclaude-sync Stop hook
# Auto-commit + push changes when session ends.
# Single commit per session with auto-message.

set -u
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG_DIR="$CLAUDE_DIR/hooks/dotclaude-sync/logs"
LOG="$LOG_DIR/sync.log"
mkdir -p "$LOG_DIR"

log() {
  printf '%s [stop] %s\n' "$(date -Is)" "$*" >> "$LOG"
}

if [[ ! -d "$CLAUDE_DIR/.git" ]]; then
  log "Not a git repo — skip."
  exit 0
fi

cd "$CLAUDE_DIR" || { log "cd failed"; exit 0; }

HOST=$(hostname -s 2>/dev/null || echo "unknown")
if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
  ENV_TAG="wsl"
elif grep -qi "nobara" /etc/os-release 2>/dev/null; then
  ENV_TAG="nobara"
else
  ENV_TAG="linux"
fi

git add -A 2>>"$LOG"

# SECRET GUARD (audit 2026-07-15, R-2; scoped 2026-07-15 per user decision).
# dotclaude is a PRIVATE single-user repo, and the user intentionally tracks FB
# session cookies here (ph-scraper Marketplace workflow). So this guard does NOT
# block FB cookies — it only blocks the categories that are NEVER intentional and
# would be catastrophic if pushed even to a private repo shared across the fleet:
# live provider API keys / OAuth bearer tokens (ghp_/gho_/sk-/AKIA/*_token).
# Skip+warn beats leaking. To also block cookies again, add the FB patterns back.
#
# NOTE: the PUBLIC .claude-public mirror is protected separately (scan.sh +
# gitleaks + hooks-runtime pruning) — cookies never flow there regardless.
# Machine-token shapes only. Deliberately NOT matching "-----BEGIN PRIVATE
# KEY-----" — that string appears as discussion text in many transcripts
# (e.g. this audit's own), and a real key file would never be a .jsonl. Real
# key *files* are caught by the gitleaks pre-commit hook instead.
SECRET_RE='"(access|refresh)_token"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]{20}|\bgh[posr]_[A-Za-z0-9]{30}|\bglpat-[A-Za-z0-9_-]{20}|\bsk-[A-Za-z0-9_-]{20}|\bAKIA[0-9A-Z]{16}\b'
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if LC_ALL=C grep -EqI "$SECRET_RE" "$f" 2>/dev/null; then
    git rm --cached --quiet -- "$f" 2>>"$LOG"
    grep -qxF -- "$f" .gitignore 2>/dev/null || printf '%s\n' "$f" >> .gitignore
    log "SECRET GUARD: unstaged + gitignored file matching secret pattern: $f"
    printf '[dotclaude-sync] WARNING: %s matched a secret pattern and was NOT committed.\n' "$f" >&2
  fi
done < <(git diff --cached --name-only 2>/dev/null | grep -E '\.jsonl$|\.json$|\.log$|\.md$')
git add .gitignore 2>>"$LOG"

# SELF-HEAL: untrack any file that matches .gitignore but is still tracked.
# Merges (-X theirs/ours) and rebases can resurrect host-local runtime files
# (peon-ping state, costs.jsonl, backups/) that another host still tracks — the
# root cause of recurring merge conflicts across the fleet. `git check-ignore`
# is the authoritative ignore test: it sees skip-worktree entries that
# `git ls-files -ci` silently skips. Removes from the index only, never disk.
mapfile -t SELFHEAL < <(git ls-files 2>/dev/null | git check-ignore --no-index --stdin 2>/dev/null)
if (( ${#SELFHEAL[@]} > 0 )); then
  git rm --cached --sparse --ignore-unmatch -q -- "${SELFHEAL[@]}" 2>>"$LOG"
  log "self-heal: untracked ${#SELFHEAL[@]} gitignored file(s): ${SELFHEAL[*]}"
fi

# Guard: GitHub rejects any single non-LFS file >100MB. Session logs are
# append-only and can cross that line mid-session. Unstage anything >50MB so
# the push never gets rejected; the file stays on disk, just not synced.
# Size-based (not path) so it catches every session's new-UUID log.
MAX_BYTES=$((50*1024*1024))
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
  # LFS-tracked files are exempt: LFS stores them out-of-band, so the 100MB
  # push limit doesn't apply. Only plain-git blobs need the guard.
  if [[ "$(git check-attr filter -- "$f" 2>/dev/null)" == *": filter: lfs"* ]]; then
    continue
  fi
  if (( sz > MAX_BYTES )); then
    git rm --cached --quiet -- "$f" 2>>"$LOG"
    grep -qxF -- "$f" .gitignore 2>/dev/null || printf '%s\n' "$f" >> .gitignore
    log "Skipped oversized file ($((sz/1024/1024))MB > 50MB), added to .gitignore: $f"
  fi
done < <(git diff --cached --name-only 2>/dev/null)
git add .gitignore 2>>"$LOG"

# LFS integrity guard: an LFS-tracked file can get staged as a RAW blob instead
# of a pointer when `git add` races a still-growing log (the clean filter reads
# a partial/locked file). A raw >100MB blob then gets rejected by GitHub, and a
# raw blob under an lfs attr corrupts the pointer contract (breaks future
# rebase/merge with "should have been a pointer, but wasn't"). Re-add any such
# file to force it back through the LFS clean filter into a proper pointer.
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  [[ "$(git check-attr filter -- "$f" 2>/dev/null)" == *": filter: lfs"* ]] || continue
  blob=$(git ls-files -s -- "$f" 2>/dev/null | awk '{print $2}')
  [[ -n "$blob" ]] || continue
  bsz=$(git cat-file -s "$blob" 2>/dev/null || echo 0)
  # A real LFS pointer is ~130 bytes; anything large means a raw blob slipped in.
  if (( bsz > 1024 )); then
    # Re-stage through the LFS clean filter. `git add` alone re-runs the filter
    # on the working file; no need to rm --cached first (which errors when
    # staged/HEAD/worktree all differ).
    git add -- "$f" 2>>"$LOG"
    nblob=$(git ls-files -s -- "$f" 2>/dev/null | awk '{print $2}')
    nsz=$(git cat-file -s "$nblob" 2>/dev/null || echo 0)
    if (( nsz > 1024 )); then
      # Still raw after re-add (file locked/growing) — unstage rather than push
      # a raw blob. Next sync catches it once the file settles.
      git rm --cached --quiet -- "$f" 2>>"$LOG"
      log "LFS file still raw after re-add ($((nsz/1024/1024))MB), unstaged for now: $f"
    else
      log "Re-cleaned raw LFS blob -> pointer: $f"
    fi
  fi
done < <(git diff --cached --name-only 2>/dev/null)

if git diff --cached --quiet 2>/dev/null; then
  log "No changes to commit."
  exit 0
fi

COUNT=$(git diff --cached --name-only | wc -l)
SUMMARY=$(git diff --cached --shortstat 2>/dev/null | sed 's/^[[:space:]]*//')

MSG="session sync from $ENV_TAG@$HOST ($COUNT files)

$SUMMARY
$(date -Is)"

if [[ "$ENV_TAG" == "nobara" ]]; then
  SIGN_FLAG=""
else
  SIGN_FLAG="--no-gpg-sign"
fi

if git commit -m "$MSG" $SIGN_FLAG --quiet 2>>"$LOG"; then
  log "Committed $COUNT file changes (sign=${SIGN_FLAG:-on})."
else
  log "Commit failed."
  exit 0
fi

if timeout 25 git push origin main --quiet 2>>"$LOG"; then
  log "Pushed to origin/main."
else
  # Most common failure: remote advanced (another host pushed) while this
  # session's fetch was skipped, so push is rejected non-fast-forward. Rebase
  # our single session commit onto the remote tip and retry once. Conflicts in
  # ephemeral session logs resolve to the remote copy (theirs).
  log "Push rejected — fetch+rebase and retry."
  if timeout 25 git fetch origin --quiet 2>>"$LOG"; then
    if git rebase origin/main --quiet 2>>"$LOG"; then
      log "Rebased onto origin/main."
    else
      git diff --name-only --diff-filter=U 2>/dev/null | while read -r f; do
        git checkout --theirs -- "$f" 2>>"$LOG" && git add -- "$f" 2>>"$LOG"
      done
      if GIT_EDITOR=true git rebase --continue --quiet 2>>"$LOG"; then
        log "Rebased after resolving session-log conflicts (theirs)."
      else
        git rebase --abort 2>>"$LOG"
        log "Rebase failed — aborted, commit kept locally for manual sync."
        exit 0
      fi
    fi
    if timeout 25 git push origin main --quiet 2>>"$LOG"; then
      log "Pushed to origin/main after rebase."
    else
      log "Push still failing after rebase — commit kept locally."
    fi
  else
    log "Fetch failed during push recovery — commit kept locally."
  fi
fi

exit 0
