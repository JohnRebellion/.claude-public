---
model: sonnet
allowed-tools: WebSearch WebFetch Bash Read Glob Grep
---

# /research — Deep Research (No Agents)

Portable, codebase-aware research command. Works in any directory.
Runs entirely in the main session — no sub-agents spawned.

**Input:** `$ARGUMENTS`

---

## Step 0: Parse Flags & Topic

Extract flags and topic from `$ARGUMENTS`:
- `--no-local` → set LOCAL_SCAN = false (skip codebase context)
- `--quick` → set DEPTH = quick (3 sub-questions max, top 3 sources deep-read)
- `--deep` → set DEPTH = deep (5-7 sub-questions, top 8 sources deep-read)
- No flag → set DEPTH = balanced (3-5 sub-questions, top 5 sources deep-read)
- Everything after flags = TOPIC

If TOPIC is empty, ask: "What would you like me to research?" and stop.

---

## Step 1: Codebase Context Scan

**Skip this step if LOCAL_SCAN = false.**

Quickly scan the current working directory for project context:

1. Use Glob to find: `README*`, `CLAUDE.md`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml`, `docs/**/*.md` (limit to first 3-5 doc files)
2. Read the most relevant files (max 3-5 files, prioritize README and manifest files)
3. Summarize in 2-3 sentences: what this project is, what stack it uses, what domain it's in
4. Store this as CODEBASE_CONTEXT for later use in framing research

If no project files found or the topic has zero relevance to the codebase, set CODEBASE_CONTEXT = "No relevant codebase context" and proceed.

**Do NOT spend more than 30 seconds on this step. It's context-gathering, not research.**

---

## Step 2: Decompose into Sub-Questions

Break TOPIC into research sub-questions:
- **quick:** 3 sub-questions max
- **balanced:** 3-5 sub-questions
- **deep:** 5-7 sub-questions

If the topic is ambiguous or very broad, ask ONE clarifying question:
> "What's your goal — learning, deciding, or building something?"

If the user says "just research it" or similar — proceed with reasonable defaults.

For each sub-question, generate 2 keyword variations for search diversity.

**Output to chat:** Show the user the sub-questions before proceeding:
```
Researching: [TOPIC]
Sub-questions:
1. [question] → keywords: [var1], [var2]
2. [question] → keywords: [var1], [var2]
...
```

---

## Step 3: Search (Sequential, Main Session)

For each sub-question, run searches directly — no agents:

1. Run WebSearch with 2 keyword variations per sub-question
2. For broad topics, add a news/recent-focused query (append "2025" or "2026" or "latest")
3. Collect results: title, URL, snippet, estimated relevance (high/medium/low)
4. Deduplicate URLs across all results
5. Prioritize: official docs > academic/research > reputable news > technical blogs > forums

**Target:** 10-20 unique sources total.

After all searches complete, select the **top sources** for deep reading:
- **quick:** top 3 sources
- **balanced:** top 5 sources
- **deep:** top 8 sources

---

## Step 4: Deep-Read Key Sources (Sequential, Main Session)

For each selected source:

1. Use WebFetch to read the full page content
2. Extract facts relevant to the research sub-questions
3. For EACH extracted claim, record:
   - The claim/finding
   - Source name + URL
   - Type: FACT (directly stated with evidence), INFERENCE (reasoned from data), or ESTIMATE (approximate/projected)
   - Date of publication or "date unknown"
   - Any contrarian viewpoints, caveats, or opposing data mentioned

If a source is inaccessible or returns garbage, note it and move on. Do not fabricate content.

---

## Step 5: Quality Gate + Synthesis (Main Session)

Before writing the report, verify findings against this checklist:
- [ ] Every claim has a named source + URL. Remove any unsourced claims.
- [ ] Single-source claims: flag as [unverified — single source]
- [ ] Data older than 12 months: label with [as of YYYY]
- [ ] Contrarian evidence is included where found (do not suppress inconvenient findings)
- [ ] Each finding is labeled: FACT, INFERENCE, or ESTIMATE
- [ ] If a sub-question has insufficient data: write "Insufficient data found" — do NOT guess
- [ ] Recommendation follows logically from evidence (not assumed or hoped)

If any claim fails the gate, either fix it (add source, add caveat) or remove it.

Then write the full research report using this exact structure:

---

# [TOPIC]: Research Report
*Date: [TODAY'S DATE] | Sources: [N] | Overall Confidence: High/Medium/Low*

## Executive Summary
[3-5 sentences. Decision-oriented. What did you find, what does it mean, what should the reader do?]

## Codebase Context
[IF CODEBASE_CONTEXT exists and is relevant: explain how this research connects to the current project. 2-3 sentences max.]
[IF not relevant or --no-local: OMIT this entire section]

## Findings

### [Sub-question 1 as heading]
[Sourced findings. Each claim attributed inline: "According to [Source](url), ..." Label type where not obvious.]

### [Sub-question 2 as heading]
...

[Continue for all sub-questions]

## Risks & Caveats
[Bullet list: contrarian evidence, gaps in data, unverified single-source claims, stale data warnings, known biases in sources]

## Recommendation
[1-3 clear, actionable statements that follow from the evidence. If evidence is mixed, say so.]

## Sources
[Numbered list. Format: N. **[Title]** — [URL] — [one-line relevance note] — [date]]

## Methodology
- Sub-questions investigated: [count]
- Total searches run: [count]
- Sources discovered: [count]
- Sources deep-read: [count]
- Mode: direct (no agents — cost-efficient for Pro plan)
- Flags: [any quality gate failures, gaps, contradictions]

---

## Step 6: Output

After the report is written:

1. **Print the full report in chat** — the user sees it immediately
2. **Save to file:**
   - Directory: `./research-reports/` (create if it doesn't exist)
   - Filename: `<slugified-topic>-<YYYY-MM-DD>.md`
   - Slugify: lowercase, replace spaces/special chars with hyphens, max 60 chars
3. **Print confirmation:**
   ```
   Research complete.
   Report saved: ./research-reports/<filename>.md
   Sources: N | Confidence: High/Medium/Low
   Flags: [any gaps, unverified claims, or contradictions — or "None"]
   ```

---

## Rules (Non-Negotiable)

- **No agents.** All work runs in the main session to preserve Pro plan token budget.
- **Every claim needs a source.** No unsourced assertions in the final report.
- **Single-source claims** flagged as `[unverified — single source]`.
- **Prefer recent sources** (< 12 months). Older data labeled `[as of YYYY]`.
- **If data is not found:** write "Insufficient data found" — never fabricate.
- **Separate:** FACT (sourced), INFERENCE (reasoned), ESTIMATE (approximate).
- **Contrarian evidence** must be included, not suppressed. The user needs the full picture.
- **Do NOT over-research.** Hit the target source count and stop. Diminishing returns are real.

## MCP Tool Preferences

If available (configured in `~/.claude.json` or project MCP), prefer these tools in order:
1. `firecrawl_search` / `web_search_exa` → over `WebSearch`
2. `firecrawl_scrape` / `crawling_exa` → over `WebFetch`

If none are configured, `WebSearch` and `WebFetch` (built-in) work fine as defaults. Do not error or warn about missing MCP tools.
