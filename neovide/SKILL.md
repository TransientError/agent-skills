---
name: neovide
description: >
  Launch and manage a per-session Neovide instance from Copilot CLI.
  Open files and jump to lines in the GUI editor during conversation.
  Trigger: "show me", "open in neovide", "open this file", "show this in editor",
  "neovide", or when user asks to visually display a file being discussed.
---

# Neovide Session Manager

## ⚠️ IMMEDIATE ACTION REQUIRED

When this skill is loaded, you MUST execute the workflow below to open the
requested file in Neovide. Do NOT use `Start-Process` on the file (that opens
the OS default app). Files are ONLY opened through `nvim --server ... --remote`.

**Workflow: Check → Launch → Wait → Open**

Run the appropriate script for the current OS using the `powershell` tool.
The file path and optional line number come from the user's request or
conversation context. Resolve relative paths to absolute before use.

### Windows (PowerShell)

```powershell
$sessionId = $env:COPILOT_AGENT_SESSION_ID
$server = "\\.\pipe\nvim-copilot-$sessionId"
$file = "<ABSOLUTE_FILE_PATH>"   # Replace with actual path
# $line = <LINE_NUMBER>          # Uncomment if jumping to a line

# 1. Check if Neovide is already running
$running = $false
try {
    nvim --server $server --remote-expr "1" 2>$null
    if ($LASTEXITCODE -eq 0) { $running = $true }
} catch { }

# 2. Launch Neovide if not running
if (-not $running) {
    Start-Process neovide -ArgumentList @('--', '--listen', $server)

    # 3. Wait for server to become ready (up to 10s)
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            nvim --server $server --remote-expr "1" 2>$null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        } catch { }
    }
    if (-not $ready) {
        Write-Error "Neovide server did not become ready within 10 seconds."
        return
    }
}

# 4. Open file (or file at line)
if ($line) {
    nvim --server $server --remote-send ":e +$line $file`n"
} else {
    nvim --server $server --remote $file
}

Write-Host "Opened in Neovide: $file"
```

### macOS / Linux (bash)

```bash
sessionId="$COPILOT_AGENT_SESSION_ID"
server="/tmp/nvim-copilot-$sessionId"
file="<ABSOLUTE_FILE_PATH>"   # Replace with actual path
# line=<LINE_NUMBER>           # Uncomment if jumping to a line

# 1. Check if Neovide is already running
if nvim --server "$server" --remote-expr "1" 2>/dev/null; then
    running=true
else
    running=false
fi

# 2. Launch Neovide if not running
if [ "$running" = false ]; then
    neovide --fork -- --listen "$server"

    # 3. Wait for server to become ready (up to 10s)
    ready=false
    for i in $(seq 1 20); do
        sleep 0.5
        if nvim --server "$server" --remote-expr "1" 2>/dev/null; then
            ready=true
            break
        fi
    done
    if [ "$ready" = false ]; then
        echo "ERROR: Neovide server did not become ready within 10 seconds." >&2
        exit 1
    fi
fi

# 4. Open file (or file at line)
if [ -n "$line" ]; then
    nvim --server "$server" --remote-send ":e +${line} ${file}\n"
else
    nvim --server "$server" --remote "$file"
fi

echo "Opened in Neovide: $file"
```

## When to Activate

User explicitly asks to see a file in the editor. Examples:
- "show me src/main.rs"
- "open that file in neovide"
- "can you show me the function we're talking about"
- "open this in the editor"
- "neovide this"
- "open it" (when a file is being discussed)

Do NOT auto-trigger on `view` or `edit` tool usage.

## Server Address

The server address is deterministic per session, derived from `$env:COPILOT_AGENT_SESSION_ID`:

| OS      | Address format                                           |
|---------|----------------------------------------------------------|
| Windows | `\\.\pipe\nvim-copilot-<SESSION_ID>`                     |
| Unix    | `/tmp/nvim-copilot-<SESSION_ID>`                         |

## Lifecycle Rules

1. **Before launching:** Always probe with `nvim --server $server --remote-expr "1"`. Do NOT use `Test-Path` or file-existence checks — use the active probe.
2. **One instance per session:** Never spawn a second Neovide for the same session.
3. **Launch method:** Windows: `Start-Process neovide`. Unix: `neovide --fork`.
4. **After launching:** Poll for readiness (up to 10s) before opening files.
5. **On session end:** Close with `nvim --server $server --remote-send ":qa!\n"`.

## Closing Neovide

When the user says "close neovide", "we're done", or the session is ending:

**Windows:**
```powershell
$server = "\\.\pipe\nvim-copilot-$env:COPILOT_AGENT_SESSION_ID"
nvim --server $server --remote-send ":qa!`n"
```

**Unix:**
```bash
nvim --server "/tmp/nvim-copilot-$COPILOT_AGENT_SESSION_ID" --remote-send ':qa!\n'
```

## Error Handling

- If `neovide` is not on PATH → tell the user Neovide is not installed.
- If `nvim` is not on PATH → tell the user Neovim is not installed.
- If the server doesn't become ready after 10s → tell the user the launch failed.
- If `--remote` exits nonzero → tell the user the file could not be opened.

## Tips

- Always use **absolute paths** when opening files.
- Resolve relative paths before sending to `nvim --server`.
- If the user says "show me that function", look up the file + line from context.
- Multiple files can be opened in sequence — they appear as buffers in the same instance.
