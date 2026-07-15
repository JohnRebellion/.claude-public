#!/usr/bin/env bash
# SessionStart hook — one-line hygiene nudge for image-heavy work.
# Printed to stdout; Claude Code shows SessionStart stdout as context.
# Intentionally tiny so it costs near-zero tokens.
echo "[image-guard] For screenshots/PDFs: run 'cb-img <file>' first, and keep image-heavy work in short sessions — a rejected image forces a full-context retry that burns tokens."
