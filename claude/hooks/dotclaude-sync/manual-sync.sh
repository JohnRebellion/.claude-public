#!/usr/bin/env bash
# Manual recovery sync for ~/.claude when SessionStart/Stop hooks drift.
# Safe to run any time. Stashes dirty tree, ff-pulls or rebases, pushes.
# Flags:
#   --quiet   suppress stdout (still logs to sync.log); for boot trigger
set -u
QUIET=0
for arg in "$@"; do
  [[ "$arg" == "--quiet" ]] && QUIET=1
done

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG_DIR="$CLAUDE_DIR/hooks/dotclaude-sync/logs"
LOG="$LOG_DIR/sync.log"
mkdir -p "$LOG_DIR"

log() {
  printf '%s [manual-sync] %s\n' "$(date -Is)" "$*" >> "$LOG"
  [[ $QUIET -eq 0 ]] && echo "$*"
}

cd "$CLAUDE_DIR" 2>/dev/null || { log "cd $CLAUDE_DIR failed"; exit 1; }

# Match stop.sh signing policy: sign on nobara, --no-gpg-sign elsewhere
# (WSL/other hosts lack the signing key).
if grep -qi "nobara" /etc/os-release 2>/dev/null; then
  SIGN_FLAG=""
else
  SIGN_FLAG="--no-gpg-sign"
fi

log "start (remote=$(git remote get-url origin 2>/dev/null))"

# CREDENTIAL GUARD: back up live auth files before any merge/rebase touches the
# tree. A remote that untracked .credentials.json (or stashing a dirty tree)
# can drop the on-disk token and kill the running session's connection. We snap
# copies now and restore them after the sync, no matter how the merge resolves.
CRED_FILES=(".credentials.json" ".claude.json")
# Backups live OUTSIDE the repo ($CLAUDE_DIR) so they can never be staged/pushed.
CRED_BAK_DIR="${TMPDIR:-/tmp}/dotclaude-cred-guard"
mkdir -p "$CRED_BAK_DIR"
chmod 700 "$CRED_BAK_DIR" 2>/dev/null || true
for cf in "${CRED_FILES[@]}"; do
  if [[ -f "$CLAUDE_DIR/$cf" ]]; then
    cp -p "$CLAUDE_DIR/$cf" "$CRED_BAK_DIR/$(echo "$cf" | tr '/' '_').bak" 2>>"$LOG" \
      && log "cred-guard: backed up $cf"
    # Belt-and-suspenders: keep git from ever staging changes to these.
    git update-index --skip-worktree -- "$cf" 2>/dev/null || true
  fi
done

restore_creds() {
  for cf in "${CRED_FILES[@]}"; do
    bak="$CRED_BAK_DIR/$(echo "$cf" | tr '/' '_').bak"
    if [[ -f "$bak" ]]; then
      # Restore only if the live file went missing or changed during sync.
      if [[ ! -f "$CLAUDE_DIR/$cf" ]] || ! cmp -s "$bak" "$CLAUDE_DIR/$cf"; then
        cp -p "$bak" "$CLAUDE_DIR/$cf" 2>>"$LOG" && log "cred-guard: RESTORED $cf"
      fi
    fi
  done
}
trap restore_creds EXIT

if ! timeout 60 git fetch origin --quiet 2>>"$LOG"; then
  log "fetch failed — check network/SSH"
  exit 1
fi

# Prefetch LFS objects for the remote branch. A rebase/merge across LFS-tracked
# files smudges pointers back to content on checkout; if the objects aren't in
# .git/lfs/objects (e.g. after a prune or fresh clone), git aborts with
# "should have been a pointer, but wasn't". Best-effort — push still works
# without it, this just prevents the merge from choking.
if git lfs ls-files >/dev/null 2>&1; then
  timeout 120 git lfs fetch origin main 2>>"$LOG" || log "lfs prefetch failed (continuing)"
fi

# Upstream tracking can get dropped when the remote is re-added (filter-repo,
# manual remote surgery). Re-bind it so @{u} resolves below.
git rev-parse --abbrev-ref 'main@{u}' >/dev/null 2>&1 || \
  git branch --set-upstream-to=origin/main main 2>>"$LOG"

LOCAL=$(git rev-parse @ 2>/dev/null)
REMOTE=$(git rev-parse '@{u}' 2>/dev/null) || { log "no upstream"; exit 1; }
BASE=$(git merge-base @ '@{u}' 2>/dev/null)

if [[ "$LOCAL" == "$REMOTE" ]]; then
  log "up to date ($LOCAL)"
  exit 0
fi

STASHED=0
if [[ -n "$(git status --porcelain)" ]]; then
  if git stash push -u --quiet -m "manual-sync $(date -Is)" 2>>"$LOG"; then
    STASHED=1
    log "stashed dirty tree"
  else
    log "stash failed"
    exit 1
  fi
fi

PUSH_NEEDED=0
if [[ "$LOCAL" == "$BASE" ]]; then
  COUNT=$(git rev-list --count "$LOCAL..$REMOTE")
  if git pull --ff-only --quiet origin main 2>>"$LOG"; then
    log "fast-forwarded $COUNT commit(s)"
  else
    log "ff-pull failed"
    [[ $STASHED -eq 1 ]] && git stash pop --quiet 2>>"$LOG"
    exit 1
  fi
elif [[ "$REMOTE" == "$BASE" ]]; then
  log "ahead of origin — pushing"
  PUSH_NEEDED=1
else
  log "diverged — rebasing onto origin/main (-X theirs for session logs)"
  # -X theirs auto-resolves jsonl/log conflicts in favor of remote;
  # safe because session-log files are append-only ephemeral state.
  if git rebase -X theirs origin/main --quiet 2>>"$LOG"; then
    log "rebased"
  else
    # Handle empty-commit case: -X theirs may make commits redundant
    while [[ -d .git/rebase-merge || -d .git/rebase-apply ]]; do
      if ! GIT_EDITOR=true git rebase --skip --quiet 2>>"$LOG"; then
        git rebase --abort 2>>"$LOG"
        log "rebase failed — manual resolve needed"
        [[ $STASHED -eq 1 ]] && log "stash still in list"
        exit 1
      fi
    done
    log "rebase resolved (skipped empty commits)"
  fi
  PUSH_NEEDED=1
fi

# SELF-HEAL: untrack any file that matches .gitignore but is still tracked.
# The merge above uses -X theirs, which resurrects host-local runtime files
# (peon-ping state, costs.jsonl, backups/) that another host still tracks — the
# root cause of recurring merge conflicts. `git check-ignore` is authoritative:
# it sees skip-worktree entries that `git ls-files -ci` silently skips. The
# merge already auto-committed, so commit the removal separately and push it.
# Index-only removal, never touches disk.
mapfile -t SELFHEAL < <(git ls-files 2>/dev/null | git check-ignore --no-index --stdin 2>/dev/null)
if (( ${#SELFHEAL[@]} > 0 )); then
  git rm --cached --sparse --ignore-unmatch -q -- "${SELFHEAL[@]}" 2>>"$LOG"
  if ! git diff --cached --quiet 2>/dev/null; then
    if git commit --no-edit $SIGN_FLAG -m "chore(sync): self-heal — untrack ${#SELFHEAL[@]} gitignored file(s)" 2>>"$LOG"; then
      log "self-heal: untracked ${#SELFHEAL[@]} gitignored file(s): ${SELFHEAL[*]}"
      PUSH_NEEDED=1
    fi
  fi
fi

if [[ $PUSH_NEEDED -eq 1 ]]; then
  if timeout 30 git push origin main --quiet 2>>"$LOG"; then
    log "pushed to origin/main"
  else
    log "push failed — commits kept locally"
  fi
fi

if [[ $STASHED -eq 1 ]]; then
  if git stash pop --quiet 2>>"$LOG"; then
    log "stash restored"
  else
    log "stash pop conflict — kept in list"
  fi
fi

log "done ($(git rev-parse @))"
