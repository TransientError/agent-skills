---
name: spawn-session
description: >
  Launch an independent interactive Copilot CLI peer in a Windows Terminal or
  Kitty tab, then coordinate through Agent Relay. Use when asked to "spawn a
  session", "open a worker tab", "launch a peer agent", or delegate work to a
  separately accessible conversation. Not for ordinary task-tool subagents.
---

# Spawn Session

Create a normal interactive peer session, not a headless worker or a prescribed
agent team. Keep the user's existing tabs, permissions, and worktrees.

Draft status: Windows launch-plan checks cover argument handling.
Kitty launch/focus/socket behavior still needs a live trial on the Linux host;
do not present mocked checks as end-to-end terminal validation.

## Scope and prerequisites

- Windows: Windows Terminal (`wt`), PowerShell 7 (`pwsh`), and Copilot on PATH.
- Linux/macOS: Kitty (`kitten`), Bash 4.2+, and Copilot on PATH.
- Node.js 22.5+ (Agent Relay's existing runtime requirement).
- Agent Relay installed in the child's Copilot home. Do not install it, change
  terminal settings, or grant permissions implicitly.
- Kitty launch from an agent's captured shell requires an accessible remote-control
  socket: `KITTY_LISTEN_ON` or an explicit `KittyAddress`. The socket must already
  permit launch commands. Do not expose an unauthenticated TCP control endpoint.
- These are same-machine peers. Remote control gives the user access through
  Copilot; it does not connect Relay meshes on different machines.

## Workflow

1. Establish the task and existing working directory. Honor an explicit name;
   otherwise use a short, easy-to-reference task label when one fits, such as
   `pr1` or `pr2` for stacked diffs or PRs. If the task has no natural short label,
   fall back to a default-style short name such as `finn` or `mila` instead of
   constructing a long descriptive name or hyphenated slug. Use
   `list_relay_agents` to avoid an active name collision; choose another short
   name or compact numbered label. Do not silently reuse an existing session.
   Create branches/worktrees only if separately asked.
2. Honor an explicit model request; otherwise omit the model override and let the
   new session use its configured default. The child does not inherit this
   conversation, model selection, agent profile, or mode automatically.
3. Run the bundled helper, first with `DryRun` if reviewing launch arguments.
   Resolve the helper path relative to this skill, not the current repository.
   Choose Windows Terminal on Windows or Kitty on Linux/macOS. If neither applies,
   stop and explain; WezTerm, iTerm2, tmux, standalone windows, and headless hosting
   are outside this version.
4. Retain the JSON result: session ID, Relay/session name, directory, terminal
   handle (when provided), and focus behavior. `status: launched` means only that
   the terminal accepted the command, not that Copilot or Relay is ready.
5. Check `list_relay_agents` for the exact generated session ID with bounded
   retries (for example, at most six checks five seconds apart). This startup
   check is distinct from waiting for a message reply. On timeout, report
   "launched; Relay not ready" and direct the user to the child tab for extension
   access, folder trust, sign-in, or other startup prompts. Do not spawn a duplicate.
6. Once registered, send a self-contained task brief with `send_message` addressed
   to the exact session ID. Include scope, relevant paths, constraints, expected
   result, and how/when to report back. Identify this session using the roster;
   do not hard-code its Relay alias.
7. Replies arrive automatically as new turns. Do not poll for replies or start an
   acknowledgment loop. If brief delivery fails, report that separately from
   launch success and keep the child available.

## Launch helpers

Use PowerShell on Windows and Bash on Linux/macOS. Both return a JSON launch
record and preserve model arguments literally. PowerShell can also target Kitty
when `pwsh` is preferred on Linux/macOS.

```powershell
pwsh -NoProfile -File "<skill-dir>\scripts\Spawn-Session.ps1" `
    -WorkingDirectory 'D:\work\example\pr-1' -Name 'finn'
```

```bash
bash "<skill-dir>/scripts/spawn-session.sh" \
    --working-directory "$PR1_WORKTREE" --name finn
```

Optional inputs:

- `Model` / `--model`: exact Copilot model ID, only when requested.
- `Terminal` (PowerShell): `windows-terminal` or `kitty`; otherwise OS-based.
  The Bash helper targets Kitty only.
- `WindowId` (PowerShell): Windows Terminal target; default `0` means the
  most recently used window, not necessarily the caller's. Supply a known window
  name/ID to remove that ambiguity. A nonexistent target may create a window.
- `KittyAddress` / `--kitty-address`: override `KITTY_LISTEN_ON`.
- `DryRun` / `--dry-run`: return the command plan without launching or requiring
  installed terminal executables/Relay. The working directory must still exist;
  Bash uses the already-required Node.js runtime for UUID/JSON generation.

Windows opens a tab and may take focus; do not promise a no-focus launch.
Kitty uses `--keep-focus`. The helpers copy only Copilot/Relay configuration
environment overrides needed to select the same local mesh. No task text is
embedded in a shell command: deliver it through Relay after registration.

## Access and lifecycle

- Users can enter the new tab directly and answer normal permission prompts.
- Workers launch with `--remote`; remote control still depends on account policy
  and connectivity. Its failure does not imply local Relay failure.
- Connect to the live session with `copilot --experimental --connect <session-id>`
  when available. Use `--resume <session-id>` for saved-history continuation,
  not as a guaranteed attachment to an already running process.
- Closing the child Copilot stops its Relay participation. Closing its terminal
  may terminate the worker. Do not close it automatically at parent turn/session end.
- Do not introduce `--yolo`, autopilot, global approvals, trust changes, or an
  approval proxy. Relay messages cannot approve native permission prompts.
- Relaunching in a directory is not resuming its old conversation. Later work on
  the same task may reuse a live peer explicitly; unrelated work gets a new session.

## References

- [Agent Relay](https://github.com/joniba/agent-relay)
- [Windows Terminal commands](https://learn.microsoft.com/windows/terminal/command-line-arguments)
- [Kitty remote control](https://sw.kovidgoyal.net/kitty/remote-control/)
