#!/usr/bin/env bash
# Sync whitelisted files from ~/.claude/ into this repo, then redact.
# Idempotent. Safe to re-run.

set -euo pipefail

SRC="${CLAUDE_SRC:-$HOME/.claude}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/claude"

if [[ ! -d "$SRC" ]]; then
  echo "source not found: $SRC" >&2
  exit 1
fi

# Whitelist: directories and files to sync
WHITELIST_DIRS=(
  "rules"
  "agents"
  "commands"
  "skills"
  "hooks"
  "output-styles"
)

WHITELIST_FILES=(
  "CLAUDE.md"
  "settings.json"
)

# NOTE (audit 2026-07-15, R-3): memory/ is NO LONGER mirrored publicly.
# The former feedback_*/reference_* glob published engineering-diary content
# (e.g. feedback_branch_workflow.md leaked employer repo names trackmax/
# wms-frontend/wms-backend and the TMAX- Jira prefix, which redact.sh/scan.sh
# did not know). A prefix blocklist cannot keep up with new employers/projects.
# Only generic, reusable config (rules/agents/commands/skills) is public.

# Clear dest (tracked files removed; untracked preserved elsewhere)
rm -rf "$DEST"
mkdir -p "$DEST"

# Copy whitelisted dirs
for d in "${WHITELIST_DIRS[@]}"; do
  if [[ -d "$SRC/$d" ]]; then
    cp -r "$SRC/$d" "$DEST/$d"
  fi
done

# Copy whitelisted files
for f in "${WHITELIST_FILES[@]}"; do
  if [[ -f "$SRC/$f" ]]; then
    cp "$SRC/$f" "$DEST/$f"
  fi
done

# Employer/client-specific skills that hardcode private repo names — never
# public (audit 2026-07-15). Extend as new client-tooling skills are added.
EXCLUDE_SKILLS=(
  "pr-review"   # references tyremax/trackmax repos throughout
)
for s in "${EXCLUDE_SKILLS[@]}"; do
  rm -rf "$DEST/skills/$s" 2>/dev/null || true
done

# memory/ intentionally NOT mirrored — see R-3 note above.
# Belt-and-suspenders: if a stale memory/ dir survives in DEST from a prior
# sync, remove it so it can never be committed.
rm -rf "$DEST/memory"

# Prune runtime artifacts that hooks/ drags in (audit 2026-07-15, I-3 extended).
# The hooks whitelist is needed for the hook *code*, but peon-ping and other
# hooks write per-session logs/state that leak live FB cookies and a minute
# activity trail of employer work (trackmax/tyremax/TMAX-*, /home/johnn paths).
# None of it is reusable config; strip it before redact/scan.
if [[ -d "$DEST/hooks" ]]; then
  # Log files and log dirs
  find "$DEST/hooks" -type f \( -name '*.log' -o -name '*.jsonl' \) -delete 2>/dev/null || true
  find "$DEST/hooks" -type d -name 'logs' -prune -exec rm -rf {} + 2>/dev/null || true
  # Per-machine state / caches / update-checker markers
  find "$DEST/hooks" -type f \( \
        -name 'config.json' -o -name '*.pid' -o -name '.state.json' \
        -o -name '.last_update_check' -o -name '.update_available' \
     \) -delete 2>/dev/null || true
  find "$DEST/hooks" -type d \( -name '__pycache__' -o -name 'sidecar' \) \
     -prune -exec rm -rf {} + 2>/dev/null || true
  # dotclaude-sync logs dir specifically
  rm -rf "$DEST/hooks/dotclaude-sync/logs" "$DEST/hooks/peon-ping/logs" 2>/dev/null || true
fi

# Run redaction (still runs over the generic dirs as a second line of defence)
"$REPO_ROOT/scripts/redact.sh" "$DEST"

echo "sync complete: $DEST"
