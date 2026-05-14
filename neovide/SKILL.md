---
name: neovide
description: >
  Launch and manage a per-session Neovide instance from Copilot CLI.
  Open files and jump to lines in the GUI editor during conversation.
  Trigger: "show me", "open in neovide", "open this file", "show this in editor",
  "neovide", or when user asks to visually display a file being discussed.
---

# Neovide Session Manager

Launch a Neovide GUI window tied to this Copilot CLI session. Open files and
jump to specific lines as things come up in conversation.

## When to Activate

User explicitly asks to see a file in the editor. Examples:
- "show me src/main.rs"
- "open that file in neovide"
- "can you show me the function we're talking about"
- "open this in the editor"
- "neovide this"

Do NOT auto-trigger on `view` or `edit` tool usage.

## Session Socket

The socket path is deterministic per session:

```
/tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID}
```

The env var `COPILOT_AGENT_SESSION_ID` is always available.

## Commands

### Check if session Neovide is already running

```bash
nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote-expr 'v:servername' 2>/dev/null
```

If this succeeds, the instance is alive. Skip launching.

### Launch Neovide (if not running)

```bash
neovide --fork -- --listen /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID}
```

Wait ~2 seconds after launch for the socket to be ready before sending commands.
Verify with the check command above.

### Open a file

```bash
nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote <filepath>
```

### Open a file at a specific line

```bash
nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote-send ':e +<line> <filepath><CR>'
```

Replace `<line>` with the line number and `<filepath>` with the absolute path.
Escape spaces in paths with `\ ` or wrap in single quotes inside the command string.

### Close the session Neovide

```bash
nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote-send ':qa!<CR>'
```

## Lifecycle Rules

1. **Before launching:** Always check if the socket is already alive.
2. **One instance per session:** Never spawn a second Neovide for the same session.
3. **Launch method:** Use `neovide --fork` so the bash call returns immediately. Use `detach: true` in async mode if running from the agent.
4. **After launching:** Wait 2 seconds, then verify the socket is responsive.
5. **On session end:** Close the Neovide instance with `:qa!` via remote-send. This is the agent's responsibility when the user says they're done or the session is ending.
6. **Stale sockets:** If the check command fails but the socket file exists, remove it (`rm /tmp/nvim-copilot-...`) before relaunching.

## Example Flows

### First time opening a file

User: "show me src/auth/login.rs"

1. Check socket: `nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote-expr 'v:servername' 2>/dev/null`
2. Not running → Launch: `neovide --fork -- --listen /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID}`
3. Wait 2s, verify socket
4. Open file: `nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote src/auth/login.rs`
5. "Opened `src/auth/login.rs` in Neovide."

### Opening at a specific line (instance already running)

User: "show me the handler at line 142"

1. Check socket → alive
2. Open at line: `nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote-send ':e +142 /absolute/path/to/file.rs<CR>'`
3. "Jumped to line 142 in `file.rs`."

### Closing

User: "close neovide" / "we're done" / session ending

1. `nvim --server /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID} --remote-send ':qa!<CR>'`
2. `rm -f /tmp/nvim-copilot-${COPILOT_AGENT_SESSION_ID}` (cleanup stale socket if needed)
3. "Neovide closed."

## Tips

- Always use absolute paths when opening files via remote-send
- The agent should resolve relative paths to absolute before sending
- If the user says "show me that function" after discussing code, look up the file + line from context and open it
- Multiple files can be opened in sequence — they'll appear as buffers in the same Neovide instance
