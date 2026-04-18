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

# Blacklist patterns removed during redaction pass
BLACKLIST_MEMORY_PREFIXES=(
  "user_"
  "project_"
)

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

# Memory: copy only feedback_* and reference_* plus MEMORY.md
if [[ -d "$SRC/memory" ]]; then
  mkdir -p "$DEST/memory"
  shopt -s nullglob
  for f in "$SRC/memory"/feedback_*.md "$SRC/memory"/reference_*.md; do
    cp "$f" "$DEST/memory/"
  done
  if [[ -f "$SRC/memory/MEMORY.md" ]]; then
    cp "$SRC/memory/MEMORY.md" "$DEST/memory/MEMORY.md"
  fi
  shopt -u nullglob
fi

# Drop blacklisted memory files if any snuck in
for prefix in "${BLACKLIST_MEMORY_PREFIXES[@]}"; do
  find "$DEST/memory" -maxdepth 1 -type f -name "${prefix}*.md" -delete 2>/dev/null || true
done

# Filter MEMORY.md index to remove lines pointing at dropped files
if [[ -f "$DEST/memory/MEMORY.md" ]]; then
  tmp="$(mktemp)"
  grep -Ev '\((user|project)_[^)]*\.md\)' "$DEST/memory/MEMORY.md" > "$tmp" || true
  mv "$tmp" "$DEST/memory/MEMORY.md"
fi

# Run redaction
"$REPO_ROOT/scripts/redact.sh" "$DEST"

echo "sync complete: $DEST"
