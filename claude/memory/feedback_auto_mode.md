---
name: Auto mode guardrails
description: Personal guardrails for Claude Code auto mode (Max plan). What to auto-execute vs what still needs confirmation.
type: feedback
---

## Rule

When auto mode is active:

**Safe to auto-execute without asking:**
- Single-file edits with clear scope
- Read-only operations (Grep, Glob, Read)
- Running tests, linters, type checkers
- Local builds, dev servers
- Git status, diff, log
- Research via WebSearch + WebFetch

**Still ask before:**
- Touching 3+ files in one turn
- Destructive git ops (reset --hard, force push, branch delete)
- Deleting data (rm, dropping tables, clearing state)
- Pushing to remote, creating/commenting on PRs, posting to Slack/email
- Modifying shared or production systems
- Installing/removing dependencies
- Sharing secrets anywhere

**Never — even in auto mode:**
- `--no-verify`, `--no-gpg-sign`, `--dangerously-skip-permissions`
- Force push to main/master
- `git add .` or `git add -A` (use specific file paths)
- Committing files that may contain secrets (.env, credentials.json)

## Why

Auto mode reduces friction on low-risk work. But the classifier model blocks "escalations beyond your request" — it does not guarantee every auto-executed action is what the user wanted. Explicit confirmation on risky ops prevents irreversible mistakes. The user's global CLAUDE.md reinforces this with the "executing actions with care" principle.

## How to apply

1. Check current mode on session start (Shift+Tab to view)
2. If auto mode: proceed on low-risk work immediately, with one-sentence status updates
3. If action falls in "still ask" list: stop and confirm before executing, even in auto mode
4. Never use auto mode as justification for destructive shortcuts
