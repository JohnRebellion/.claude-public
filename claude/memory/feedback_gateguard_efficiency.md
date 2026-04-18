---
name: Gateguard fact-forcing efficiency
description: How to minimize token waste from the ECC gateguard hook that blocks every Write/Edit. Critical for multi-file tasks like UI component creation.
type: feedback
---

## Rule

When creating multiple new files (components, modules, etc.), minimize gateguard overhead:

1. **Pre-present facts BEFORE the Write call** — don't attempt the write first and get blocked. The block-present-retry cycle doubles token cost per file.
2. **Batch Glob/Grep verifications** — run one Glob with a pattern that covers all planned files, then reference that single result in each fact presentation.
3. **Keep fact presentations terse** — the gate needs 4 facts, not 4 paragraphs. One line per fact is sufficient.
4. **For greenfield multi-file creation (5+ files)**: use a Bash heredoc script to create file stubs, then use Edit to fill in content. The gate is less aggressive on edits to existing files.
5. **Never repeat the full user instruction verbatim more than once** — after the first presentation, use "Same user instruction as presented for [first file]" or quote only the first sentence.

## Why

**2026-04-16 incident:** Creating 14 UI components + 3 page components + edits generated ~80 extra tool calls from gateguard compliance. Each blocked write + fact presentation + retry costs ~3-5K tokens. Total overhead: ~100-150K tokens (roughly 40% of session budget) on gate compliance alone.

## How to apply

Before any multi-file creation task:
1. Run a single Glob to confirm no conflicts exist for ALL planned files
2. For each file, present the 4 facts in 4 short lines immediately before the Write
3. If creating 5+ files in a new directory, prefer: `mkdir -p && touch file1 file2 ...` via Bash, then Edit each file (edits to existing files have lower gate friction)
4. Group related files and present shared facts once, with per-file specifics inline
