---
name: neovide
description: >
  Launch and manage a per-session Neovide instance from Copilot CLI.
  Open files and jump to lines in the GUI editor during conversation.
  Trigger: "show me", "open in neovide", "open this file", "show this in editor",
  "neovide", or when user asks to visually display a file being discussed.
---

# Neovide Session Manager

Use the bundled helper in **one tool invocation per request**. Do not separately
probe, launch, poll, or send editor commands: the helper handles those steps.
Never open the file through the OS default application.

## When to activate

Activate when the user explicitly asks to see a file in the editor, including
"show me src/main.rs", "open that file in neovide", "show me that function",
or "open it" when discussing a file. Do not auto-trigger on `view` or `edit`.
Choose the file and optional line from the user's request or conversation.

## Open a file

Resolve the script path relative to this skill's directory, not the current
working directory. Replace the example paths and line number with actual values.
Quote paths as single arguments. Relative file paths resolve against the caller's
working directory; absolute paths are preferred.

**Linux / macOS (POSIX shell):**

```sh
sh "/ABSOLUTE/SKILL/DIR/scripts/neovide-session.sh" open "/absolute/path/to/file" 42
```

In Copilot CLI's `bash` tool, use `mode: "async", detach: true` for the whole
open invocation, since it may launch a GUI that must outlive the tool call.
Read its completion output to confirm success; do not launch a separate probe.
The helper backgrounds `neovide --fork` with all standard streams redirected so
the GUI cannot block readiness polling or hold the tool's output pipe open.

**Windows (PowerShell Core):**

```powershell
pwsh -NoProfile -File "C:\ABSOLUTE\SKILL\DIR\scripts\Neovide-Session.ps1" open "C:\absolute\path\to\file" 42
```

Omit the final line argument to open without jumping. Lines must be positive
integers. Filenames are passed as arguments to `nvim --remote`, never interpolated
into editor commands. The helper moves the cursor separately when requested.

## Session lifecycle

Both helpers require `COPILOT_AGENT_SESSION_ID` and use one deterministic server:
`/tmp/nvim-copilot-<SESSION_ID>` on Unix, or
`\\.\pipe\nvim-copilot-<SESSION_ID>` on Windows.

The helper actively probes the server, reuses it if available, otherwise launches
Neovide and polls for readiness for up to 10 seconds before opening the file.
Do not substitute socket-existence checks or launch a second instance yourself.
Subsequent opens reuse the same editor and its buffers.

## Close

When the user requests closing Neovide or ends the editing session, invoke the
same helper once:

```sh
sh "/ABSOLUTE/SKILL/DIR/scripts/neovide-session.sh" close
```

```powershell
pwsh -NoProfile -File "C:\ABSOLUTE\SKILL\DIR\scripts\Neovide-Session.ps1" close
```

**Closing uses `:qa!` and discards unsaved changes. Warn before invoking it.**
Closing an already stopped server is a no-op; it never launches Neovide.

## Prerequisites and errors

- Linux / macOS: POSIX shell; Windows: PowerShell Core (`pwsh`).
- Neovim (`nvim`) on PATH, plus Neovide on PATH when launching.
- A graphical desktop session for launching Neovide.
- Report a nonzero helper exit as failure, using its error message. Do not claim
  the file opened or manually retry individual workflow steps.

One helper call reduces approval opportunities but does not bypass host permission
checks or guarantee a single prompt; path and sandbox approvals may still apply.
