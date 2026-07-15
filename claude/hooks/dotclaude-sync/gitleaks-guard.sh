#!/usr/bin/env bash
# Shared gitleaks guard for git pre-commit / pre-push hooks.
# Added 2026-07-15 (audit R-2: no secret scanning anywhere).
#
# Scans staged changes (pre-commit) or the whole tree (pre-push) for secrets.
# Degrades gracefully: if gitleaks is not installed, it warns once and allows
# the operation (so fresh machines that haven't `go install`ed it aren't
# bricked) — the dotclaude stop.sh content guard is the always-on backstop.
#
# Install gitleaks:  GOBIN=$HOME/go/bin go install github.com/zricethezav/gitleaks/v8@latest
set -uo pipefail

MODE="${1:-staged}"   # "staged" (pre-commit) | "full" (pre-push)

# Find gitleaks on PATH or in the usual go bin.
GITLEAKS="$(command -v gitleaks 2>/dev/null || true)"
[[ -z "$GITLEAKS" && -x "$HOME/go/bin/gitleaks" ]] && GITLEAKS="$HOME/go/bin/gitleaks"

if [[ -z "$GITLEAKS" ]]; then
  echo "[gitleaks-guard] gitleaks not installed — skipping scan (install: GOBIN=\$HOME/go/bin go install github.com/zricethezav/gitleaks/v8@latest)" >&2
  exit 0
fi

if [[ "$MODE" == "staged" ]]; then
  # Only the staged diff — fast, blocks the commit that introduces a secret.
  if ! "$GITLEAKS" protect --staged --redact --no-banner 2>/dev/null; then
    echo "" >&2
    echo "[gitleaks-guard] SECRET DETECTED in staged changes — commit blocked." >&2
    echo "  Review above (values redacted). Unstage the offending file or add a" >&2
    echo "  false-positive allow rule to .gitleaks.toml, then retry." >&2
    exit 1
  fi
else
  # Pre-push: scan only the commits being pushed (not full history — this repo
  # carries LFS + a large pack, so a full `detect` can take minutes and stall
  # every sync). We diff-scan the range HEAD is ahead of origin/main; if that
  # ref is missing (fresh clone) fall back to the last 20 commits. The one-time
  # full-history guarantee is Phase 2's filter-repo + verification, not here.
  BASE="origin/main"
  git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || BASE="HEAD~20"
  git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || BASE=""   # shallow/first push
  if [[ -n "$BASE" ]]; then
    LOGOPT="--log-opts=${BASE}..HEAD"
  else
    LOGOPT=""
  fi
  if ! timeout 60 "$GITLEAKS" detect --redact --no-banner $LOGOPT 2>/dev/null; then
    echo "" >&2
    echo "[gitleaks-guard] SECRET DETECTED in commits being pushed — push blocked." >&2
    echo "  (scanned range: ${BASE:-recent}..HEAD)" >&2
    exit 1
  fi
fi
exit 0
