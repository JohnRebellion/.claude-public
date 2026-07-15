---
description: Manage Claude session titles, slugs, and aliases — heuristic auto-titling with on-demand LLM upgrade
---

# Session Titles

Manage descriptive titles and slug-keys for Claude session files in
`~/.claude/sessions/`. Titles auto-generate (heuristic) on every Stop via the
`session-titler` hook and auto-update when a session's content drifts. This
command is the manual surface: list, backfill, retitle, and upgrade to
LLM-quality titles.

Backed by `~/.claude/hooks/session-titler/titler.js` (self-contained Node;
independent of the everything-claude-code plugin). Slug aliases are written to
`~/.claude/session-aliases.json` in the same schema ECC's `/sessions load`
reads, so `/sessions load <slug>` resolves them.

## Usage

```
/session-titles [list|backfill|retitle|llm|set] [target] [flags]
```

`target` = a slug, short-id, filename fragment, `all`, or omitted (= latest).

## Actions

### List (default) — also backfills untitled sessions on access

```bash
node ~/.claude/hooks/session-titler/titler.js backfill all >/dev/null 2>&1
node ~/.claude/hooks/session-titler/titler.js list --limit=40
```

### Backfill — title only sessions that are still bare-date defaults

```bash
node ~/.claude/hooks/session-titler/titler.js backfill all
```

### Retitle (heuristic) — recompute now; `--force` ignores drift state

```bash
node ~/.claude/hooks/session-titler/titler.js retitle <target> [--force] [--no-alias]
```

### LLM upgrade — produce a high-quality title for weak heuristic ones

Run this to get the target file paths, then **read each session and apply a
polished title yourself**:

```bash
node ~/.claude/hooks/session-titler/titler.js retitle <target> --llm
```

For each `SESSION_FILE:` printed, read it, then apply:

```bash
node ~/.claude/hooks/session-titler/titler.js set <filename> \
  --title "<project>: <what was actually done>" --slug "<kebab-slug>"
```

Manually-set titles are flagged `manual` and the auto-hook will NOT downgrade
them to heuristic unless the session content later drifts.

### Set — apply an explicit title/slug to one session

```bash
node ~/.claude/hooks/session-titler/titler.js set <target> --title "..." [--slug "..."]
```

## How auto-update works

- The Stop hook (`~/.claude/hooks/session-titler/stop.sh`) runs after ECC's
  session-end writes the `.tmp` file.
- It fingerprints the session's topical content (project + tasks + files).
  If the fingerprint changed since last titling, it regenerates the title and
  refreshes the slug alias. Unchanged → no-op.
- Drift/manual state lives in `~/.claude/session-titler-state.json` (kept out of
  the session file because ECC rebuilds the header and would strip in-file
  fields; the visible heading + `**Title:**` still survive ECC).

## Examples

```bash
/session-titles                              # list (backfills untitled first)
/session-titles retitle all --force          # recompute every title now
/session-titles llm research                 # get the research session's path to hand-title
/session-titles set chezmoi-migrate --title "chezmoi: new-machine bootstrap analysis"
```

## Notes

- Heuristic titles are good when a session has a clear actionable first task.
  Sessions that open with a vague question get weaker titles — use `llm` to
  upgrade those.
- Slug collisions across different sessions are auto-suffixed (`-2`, `-3`).
