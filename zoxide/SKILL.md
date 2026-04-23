---
name: zoxide
description: >
  Smart directory navigation using zoxide inside Copilot CLI.
  Jump to frequently-used directories without typing full paths.
  Trigger: "z <query>", "jump to <dir>", "cd <partial>", or "/z <query>".
  Wraps zoxide query + /cwd for seamless navigation.
---

# Zoxide Navigation

Use `zoxide query` to resolve directory keywords, then `/cwd` to jump there.

## When to Activate

User says any of: `z <query>`, `/z <query>`, `jump to <name>`, `go to <name>`, `cd <partial-name>`, or asks to change/switch directory by keyword.

## How It Works

1. Run `zoxide query <keywords>` to get the best-match directory path
2. Output the `/cwd <path>` command for the user to run (slash commands cannot be invoked programmatically)
3. If ambiguous, run `zoxide query -l -s <keywords>` to list matches with scores, present top 5 to user, let them pick
4. Format: just output `/cwd <resolved-path>` on its own line so user can copy-paste or run it

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
- After resolving the path, copy `/cwd <path>` to the system clipboard so the user can just paste
- Clipboard commands by platform:
  - Linux (Wayland): `echo '/cwd <path>' | wl-copy`
  - Linux (X11): `echo '/cwd <path>' | xclip -selection clipboard`
  - macOS: `echo '/cwd <path>' | pbcopy`
  - Windows/PowerShell: `Set-Clipboard '/cwd <path>'`
- Auto-detect: try `wl-copy` first, fall back to `xclip`, `pbcopy`, or note if none available
- If zoxide returns nothing, say so and suggest `zoxide query -l -s` to browse
- Keep responses short: confirm what was copied, tell user to paste

## Example Flows

User: `z work`
→ Run `zoxide query work` → get `/home/kvwu/work`
→ Run `echo '/cwd /home/kvwu/work' | wl-copy`
→ "Copied to clipboard — paste to jump."

User: `z qmk`
→ Run `zoxide query qmk` → get `/home/kvwu/qmk_firmware`
→ Copy `/cwd /home/kvwu/qmk_firmware` to clipboard
→ "Copied to clipboard — paste to jump."

User: `z org`
→ Run `zoxide query org` → multiple matches → show list → user picks → copy `/cwd <chosen>` to clipboard
