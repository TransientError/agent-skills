---
name: zoxide
description: >
  Smart directory navigation using zoxide inside Copilot CLI.
  Jump to frequently-used directories without typing full paths.
  Trigger: "z <query>", "jump to <dir>", "cd <partial>", or "/z <query>".
  Wraps zoxide query + /cwd for seamless navigation.
---

# Zoxide Navigation

Use `zoxide query` to resolve directory keywords. Optionally jump there with `/cwd`.

## When to Activate

User says any of: `z <query>`, `/z <query>`, `jump to <name>`, `go to <name>`, `cd <partial-name>`, asks to change/switch directory by keyword, or references a directory by partial name/keyword.

## How It Works

1. Run `zoxide query <keywords>` to get the best-match directory path
2. Report the resolved path to the user
3. If the user expressed intent to **navigate** (e.g. "jump to", "go to", "cd", "switch to"), copy `/cwd <path>` to clipboard so they can paste to jump
4. If the user just **referenced** a directory (e.g. "the project in z foo", "where is my X repo"), report the path without copying — they want the info, not the navigation
5. If ambiguous, run `zoxide query -l -s <keywords>` to list matches with scores, present top 5 to user, let them pick

## Commands

```bash
# Single best match
zoxide query <keywords>

# List matches with scores (when ambiguous or user wants options)
zoxide query -l -s <keywords>

# List all tracked directories (when user says "z" with no args or asks what dirs are tracked)
zoxide query -l -s
```

## Rules

- Always use `zoxide query` (not `z` or `zi` — those are shell aliases that don't work in subshells)
- The agent cannot invoke `/cwd` directly — it's a slash command only the user can run
- **Only copy to clipboard when the user wants to navigate** — look for navigation intent words like "jump", "go", "cd", "switch", "navigate", "/z"
- When copying, use clipboard commands by platform:
  - Linux (Wayland): `echo '/cwd <path>' | wl-copy`
  - Linux (X11): `echo '/cwd <path>' | xclip -selection clipboard`
  - macOS: `echo '/cwd <path>' | pbcopy`
  - Windows/PowerShell: `Set-Clipboard '/cwd <path>'`
- Auto-detect: try `wl-copy` first, fall back to `xclip`, `pbcopy`, or note if none available
- If zoxide returns nothing, say so and suggest `zoxide query -l -s` to browse
- Keep responses short

## Example Flows

**Navigation intent (copy to clipboard):**

User: `z work` / `jump to work` / `cd work`
→ Run `zoxide query work` → get `/home/kvwu/work`
→ Run `echo '/cwd /home/kvwu/work' | wl-copy`
→ "Resolved `/home/kvwu/work` — copied `/cwd` command to clipboard, paste to jump."

**Informational (no clipboard):**

User: "what's the path for my qmk project?" / "look at z qmk"
→ Run `zoxide query qmk` → get `/home/kvwu/qmk_firmware`
→ "That resolves to `/home/kvwu/qmk_firmware`."

**Ambiguous matches:**

User: `z org`
→ Run `zoxide query org` → multiple matches → show list → user picks → then copy or just report based on context
