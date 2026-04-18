# claude-public

Public, machine-agnostic Claude Code behavioural settings. Auto-stripped of personal data via pre-commit.

## Layout

- `claude/` — transformed, committable mirror of `~/.claude/` (whitelisted paths only).
- `scripts/sync.sh` — copy whitelist from `~/.claude/` → `claude/`, then redact.
- `scripts/redact.sh` — in-place redaction (paths → `{{ .chezmoi.homeDir }}`, emails/secrets/personal strings → `REDACTED*`).
- `scripts/scan.sh` — leak scanner. Blocks commit on match.
- `.githooks/pre-commit` — runs sync + scan + re-stage.

## Setup (per machine)

```
git config core.hooksPath .githooks
chmod +x scripts/*.sh .githooks/pre-commit
```

## Workflow

1. Edit `~/.claude/` normally.
2. `cd ~/.claude-public && git add -A && git commit -m "update"` — hook auto-syncs + redacts.
3. `git push`.
4. Other machines: `git pull` → apply via chezmoi.

## Whitelist

Dirs: `rules/`, `agents/`, `commands/`, `skills/`, `hooks/`, `output-styles/`
Files: `CLAUDE.md`, `settings.json`
Memory: `feedback_*.md`, `reference_*.md`, `MEMORY.md` (filtered)

## Blacklist

`memory/user_*.md`, `memory/project_*.md`, `projects/`, `todos/`, `sessions/`, `shell-snapshots/`, `ide/`, `*.jsonl`, `.credentials*`.

## Merge conflicts

Transforms idempotent. Resolve conflicts in `claude/` normally; re-run `scripts/sync.sh` if you want to reset to current local `~/.claude/`.

## Chezmoi apply (destination machine)

Point chezmoi source at `claude/` contents or template them into `~/.claude/`. Paths use `{{ .chezmoi.homeDir }}` so templating resolves per machine.
