#!/usr/bin/env bash
# Leak scanner. Exits non-zero if personal data detected.
# Used by pre-commit after redaction, as defense-in-depth.

set -uo pipefail

TARGET="${1:-claude}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "$TARGET" ]]; then
  echo "target not found: $TARGET" >&2
  exit 0
fi

fail=0
report() {
  echo "LEAK: $1" >&2
  fail=1
}

# Patterns to block
declare -A PATTERNS=(
  ["home-path"]='/home/[a-zA-Z0-9_-]+'
  ["users-path"]='/Users/[a-zA-Z0-9_.-]+'
  ["email"]='[A-Za-z0-9._%+-]+@(?!example\.com|noreply\.anthropic\.com|anthropic\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
  ["johnn"]='\bjohnn\b'
  ["mtusa"]='mtusa\.com'
  ["rebellion"]='Rebellion'
  # Employer/client internals (audit 2026-07-15 I-3). Update as engagements change.
  ["tyremax"]='\btyremax\b'
  ["trackmax"]='\btrackmax\b'
  ["wms-repos"]='\bwms-(frontend|backend)\b'
  ["jira-tmax"]='\bTMAX-[0-9]+'
  ["sida4"]='\bsida4\b'
  ["4impact"]='\b4impact\b'
  ["necir"]='necir\.ph'
  ["api-key-sk"]='\bsk-[A-Za-z0-9_-]{20,}'
  ["api-key-ghp"]='\bghp_[A-Za-z0-9]{30,}'
  ["api-key-gho"]='\bgho_[A-Za-z0-9]{30,}'
  ["aws-key"]='\bAKIA[0-9A-Z]{16}\b'
  ["fb-cookie"]='\b(c_user|datr)=[A-Za-z0-9]'
)

# Employer/personal-name patterns are matched case-insensitively; everything
# else (paths, keys) stays case-sensitive so /Users/ != /users/ (API examples).
CI_PATTERNS=" johnn rebellion tyremax trackmax wms-repos jira-tmax sida4 4impact necir "

for name in "${!PATTERNS[@]}"; do
  pat="${PATTERNS[$name]}"
  if [[ "$CI_PATTERNS" == *" $name "* ]]; then
    flags="-rPniI"
  else
    flags="-rPnI"
  fi
  if hits=$(grep $flags --exclude-dir=.git "$pat" "$TARGET" 2>/dev/null); then
    if [[ -n "$hits" ]]; then
      report "pattern[$name]"
      echo "$hits" | head -20 >&2
    fi
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "" >&2
  echo "leak scan failed. commit blocked." >&2
  exit 1
fi

echo "leak scan clean"
exit 0
