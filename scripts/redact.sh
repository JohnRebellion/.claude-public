#!/usr/bin/env bash
# Redact personal data from a directory tree in place.
# - /home/<user>/ → {{ .chezmoi.homeDir }}/
# - emails → REDACTED_EMAIL
# - known personal strings → REDACTED
# - strip common secret-shaped tokens

set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" || ! -d "$TARGET" ]]; then
  echo "usage: $0 <dir>" >&2
  exit 1
fi

# Personal strings to redact (add more as needed)
PERSONAL_STRINGS=(
  "John Necir Rebellion"
  "John Rebellion"
  "John.Rebellion@mtusa.com"
  "john.rebellion@mtusa.com"
  "Rebellion"
  "mtusa.com"
  "johnn"
)

# Files to process: text-like only
mapfile -d '' FILES < <(find "$TARGET" -type f \( \
  -name "*.md" -o -name "*.json" -o -name "*.jsonc" -o -name "*.yaml" -o -name "*.yml" \
  -o -name "*.toml" -o -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \
  -o -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.txt" \
  -o -name "*.conf" -o -name "*.cfg" -o -name "*.ini" \) -print0)

redact_file() {
  local f="$1"

  # Skip binary
  if ! grep -Iq . "$f" 2>/dev/null; then
    return
  fi

  # /home/<anyuser>/ → {{ .chezmoi.homeDir }}/
  sed -i -E 's#/home/[a-zA-Z0-9_-]+#{{ .chezmoi.homeDir }}#g' "$f"

  # /Users/<anyuser>/ (macOS) → {{ .chezmoi.homeDir }}
  sed -i -E 's#/Users/[a-zA-Z0-9_.-]+#{{ .chezmoi.homeDir }}#g' "$f"

  # Emails → REDACTED_EMAIL (skip anthropic noreply + example domains)
  sed -i -E 's#\b[A-Za-z0-9._%+-]+@(?!(example\.com|noreply\.anthropic\.com|anthropic\.com)\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b#REDACTED_EMAIL#g' "$f" 2>/dev/null || \
  perl -i -pe 's/\b[A-Za-z0-9._%+-]+\@(?!(?:example\.com|noreply\.anthropic\.com|anthropic\.com)\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/REDACTED_EMAIL/g' "$f"

  # Personal strings
  for s in "${PERSONAL_STRINGS[@]}"; do
    # escape for sed
    esc=$(printf '%s' "$s" | sed -e 's/[\/&.*^$[]/\\&/g')
    sed -i "s/${esc}/REDACTED/gI" "$f"
  done

  # Secret-shaped: API keys (sk-..., ghp_..., AKIA..., Bearer tokens)
  perl -i -pe 's/\b(sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|Bearer\s+[A-Za-z0-9._-]{20,})\b/REDACTED_SECRET/g' "$f"
}

for f in "${FILES[@]}"; do
  redact_file "$f"
done

echo "redaction complete: ${#FILES[@]} files processed"
