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
- Pass result to `/cwd` slash command — do NOT use `cd` in bash (that only affects the subshell)
- If zoxide returns nothing, say so and suggest `zoxide query -l -s` to browse
- Keep responses short: just the jump confirmation or the pick-list

## Example Flows

User: `z work`
→ Run `zoxide query work` → get `/home/kvwu/work` → output:
```
/cwd /home/kvwu/work
```

User: `z qmk`
→ Run `zoxide query qmk` → get `/home/kvwu/qmk_firmware` → output:
```
/cwd /home/kvwu/qmk_firmware
```

User: `z org`
→ Run `zoxide query org` → multiple matches → show list → user picks → output `/cwd <chosen>`
