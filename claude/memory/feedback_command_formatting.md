---
name: Clipboard copy offer for copyable output
description: After any copyable output (commands, code, markdown, prompts), write to /tmp and offer cb copy — like the copy button on Claude web app
type: feedback
---

After producing any substantial copyable output (commands, code blocks, markdown, prompts, configs, handoff prompts, etc.), **always ask** if the user wants it copied to clipboard.

This is the terminal equivalent of the copy tooltip on the Claude web/desktop app. It does NOT replace normal output — output renders normally first, then offer the copy.

**Flow:**
1. Render output normally in the conversation (code blocks, markdown, etc.)
2. Write the copyable content to `/tmp/<descriptive-name>.<ext>` (`.sh` for commands, `.md` for markdown, etc.)
3. Ask: "Want me to copy to clipboard? Run: `cat /tmp/<file> | cb copy`"

**Command formatting rules (when output is shell commands):**
- Max ~80 characters per command line
- Use backslash continuation for long commands
- Never chain 3+ commands with `&&` on one line
- Numbered steps with `# Step N — Description:` comments

**Why:** User works via SSH where selecting/copying from terminal output is unreliable with long or wrapped text. `cb copy` uses OSC 52 to reach the local clipboard through SSH.

**Note:** `cb copy` works from the user's terminal (SSH + OSC 52) but NOT from Claude's subprocess. Never run `cb copy` directly in a Bash tool call — always write to file and let the user pipe it.
