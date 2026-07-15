#!/usr/bin/env bash
# PostToolUse advisory for image-producing skills/agents.
#
# WHY ADVISORY, NOT A BLOCK: PostToolUse fires AFTER the tool ran, so any image
# the skill/agent generated already exists. A hook here cannot pre-validate or
# strip it (that needs PreToolUse, which cannot see a tool's generated output).
# The realistic mitigation is a nudge: remind the model to keep image-heavy
# skill work in short sessions and to run cb-img on any image before re-reading
# it, so a rejected image cannot poison a large, expensive-to-resend context.
#
# Runs async with a 5s timeout; never blocks. Emits to stderr (surfaced as
# context) only for skills/agents known to capture screenshots.
set -euo pipefail

payload="$(cat)"

# Extract the skill name (.tool_input.skill) or subagent type
# (.tool_input.subagent_type) using an external python parser file, so this
# shell script carries no fragile inline-python quoting.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_name="$(printf '%s' "$payload" | python3 "$HERE/_extract_skill.py" 2>/dev/null || true)"

[ -z "${skill_name:-}" ] && exit 0

# Skills/agents that capture or return screenshots.
case "$skill_name" in
  dogfood|e2e|e2e-runner|run|verify|frontend-slides)
    msg="[image-guard] ${skill_name} captures screenshots. If an image fails "
    msg+="to process, run cb-img on it before re-reading, and consider a fresh "
    msg+="session: a rejected image forces a full-context retry that burns tokens."
    printf '%s\n' "$msg" >&2
    ;;
esac
exit 0
