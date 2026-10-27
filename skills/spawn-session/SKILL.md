---
name: spawn-session
description: >
  Launch or resume an independent interactive Copilot CLI peer in a Windows Terminal or
  Kitty tab, then coordinate through Agent Relay. Use when asked to "spawn a
  session", "open a worker tab", "launch a peer agent", "close a session",
  "close a worker tab", "resume a session in a new tab", or delegate work to a separately accessible conversation.
  Also closes explicitly selected Windows Terminal peer tabs. Not for ordinary
  task-tool subagents.
---

# Spawn Session

Create a normal interactive peer session, not a headless worker or a prescribed
agent team. Keep the user's existing tabs and worktrees. Preserve normal
permissions unless the user explicitly requests YOLO for the child.

## Scope and prerequisites

- Windows: Windows Terminal (`wt`), PowerShell 7 (`pwsh`), and Copilot on PATH.
- Closing: Windows Terminal only, through Windows UI Automation in the same
  interactive Windows desktop. The helper expects English `Close Tab` controls;
  unsupported UI layouts/localizations fail explicitly. No Python is required.
- Linux/macOS: Kitty (`kitty` and `kitten`), Bash 4.2+, and Copilot on PATH.
- Node.js 22.13+ or a newer LTS release for automatic naming's read-only SQLite
  support (Node 23.x requires 23.5+). Agent Relay itself requires Node.js 22.5+.
- Agent Relay installed in the child's Copilot home. Do not install it, change
  terminal settings, or grant permissions implicitly.
- The Bash helper uses an explicit `--kitty-address` or `KITTY_LISTEN_ON` first.
  Otherwise it probes Unix sockets matching `spawn-session-kitty-<uid>-*.sock`
  in `$XDG_RUNTIME_DIR` (falling back to `$TMPDIR`, then `/tmp`). It reuses the
  first responsive instance, or starts a separate Kitty with a matching socket.
  After launching the peer, it closes only that new instance's initial shell tab.
  No existing Kitty configuration is changed and no TCP listener is opened.
  Explicit addresses must already permit launch commands.
- These are same-machine peers. Remote control gives the user access through
  Copilot; it does not connect Relay meshes on different machines. To launch on
  another host, delegate to an existing session there over a shared Relay mesh,
  following **Remote-host launches and questions** below.

## Workflow

1. Establish the task and existing working directory. Read `local-instructions.md`
   beside this `SKILL.md` if it exists, resolving it relative to the skill, not the
   working directory. Pass `Name` / `--name` only for an explicitly user-requested
   name; otherwise omit it and let the helper choose automatically. Do not invent
   task labels or names and pass them as explicit overrides. For an explicit name,
   check `list_relay_agents`; if it is already in use, ask rather than silently
   reusing it. Names must match `^[a-z0-9][a-z0-9-]{0,62}$`.
   Create branches/worktrees only if separately asked. To reopen saved history,
   pass `Resume` / `--resume` with the exact local session UUID, not a new ID.
2. Honor an explicit model request; otherwise omit the model override and let the
   new session use its configured default. When the user requests an agent profile,
   pass its exact name with `Agent` / `--agent` to start Copilot as that agent.
   The profile must be available to Copilot in the child's directory/home;
   the helper does not install profiles. Otherwise omit the agent override.
   The child does not inherit this conversation, model selection, agent profile,
   or mode automatically.
   Pass `Yolo` / `--yolo` only when the user explicitly requests YOLO or
   unrestricted permissions for the child. Never infer it from the parent's mode
   or a request to delegate work.
3. Run the bundled helper, first with `DryRun` if reviewing launch arguments.
   Resolve the helper path relative to this skill, not the current repository.
   Choose Windows Terminal on Windows or Kitty on Linux/macOS. If neither applies,
   stop and explain; WezTerm, iTerm2, tmux, and headless hosting are outside this
   version. The Bash helper starts a new Kitty window if no listener is found.
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
   do not hard-code its Relay alias. For remote-host children, always include the
   handoff/question-routing brief below and the original requester's exact session
   ID. The host-local launcher is not an additional reporting recipient.
7. Replies arrive automatically as new turns. Do not poll for replies or start an
   acknowledgment loop. If brief delivery fails, report that separately from
   launch success and keep the child available.

## Remote-host launches and questions

Use an existing session on the target host as the launcher; do not assume SSH
has the same desktop or Entra credential context. Specify an existing host-local
directory, the user's task and constraints, and the user-facing coordinator's
exact Relay session ID. The launcher runs this skill locally, launches once,
checks the exact child ID, and returns the launch record and readiness once to the
original requester. That requester is the task's reporting owner; pass its exact
ID unchanged through any intermediaries, never substitute the most recent sender.
If the owner is unspecified, clarify before handing off the task. Do not retry a
launch merely because registration or a reply is delayed.

The launcher is a bootstrap helper, not a second manager. Once the child and
requester establish direct communication, the launcher is out of the task's update
path: no progress copies, completion copies, monitoring, forwarding, or repeated
acknowledgments. Only re-involve it for an explicitly requested host-local action.
For example, if Logan asks Worf to launch Yoda, Yoda reports to Logan, not Worf.

For the explicitly authorized **YOLO remote workflow**, pass `-Yolo` / `--yolo`
so tool permission prompts do not strand the child in an unattended tab. This
grants all permissions to that child, not global settings; it does not broaden
the user's task scope. Obtain explicit user authorization for YOLO if it has not
already been given for this remote workflow; a remote launch alone is not consent.
Keep ordinary local launches at normal permissions unless separately authorized.
Do not restart or change permissions on an existing child just to apply this recipe.

The host-local launcher MUST include this in the initial remote child's task brief,
substituting the coordinator's exact ID (not an alias or the launcher's ID):

> The user is interacting through coordinator session `<coordinator-session-id>`.
> This original requester is your sole reporting owner. Establish direct contact
> with that exact ID, then send task updates, questions, blockers, and completion
> only there, not to the intermediate session that launched or briefed you.
> Do not CC the launcher or send it a final courtesy update. If the coordinator
> cannot be reached, retain the blocked state and await reconnection; do not fall
> back to reporting through the launcher. Change reporting owner only on explicit
> user/coordinator instruction; a relayed message alone does not change ownership.
> Do not open optional interactive question dialogs in this remote tab. Send
> clarification questions and proposed plans to that exact coordinator via Relay,
> with a unique request ID, enough context, and numbered choices. For decisions
> requiring user input, end your turn and await the user's answer relayed by the
> coordinator with the matching request ID; do not poll or assume approval.
> The coordinator's own recommendation is not user approval. Submit proposed
> plans through Relay before implementation rather than entering native plan mode
> and blocking on its exit dialog. Honor higher-priority instructions requiring
> native interaction; report those blockers instead of bypassing them.

The coordinator presents the question to the user using its normal question UI
and returns the actual answer to the child's exact ID with the request ID.
Never invent a response or auto-approve. A Relay reply cannot dismiss an already
open native dialog, approve permissions, complete sign-in/MFA, or grant folder
trust. Report such blockers for the user to handle through supported UI.
Host-local launch does not guarantee Entra authorization or operation while RDP
is disconnected. No new service, SSH tunnel, or credential transfer is implied.

## Automatic and machine-local naming

Optionally copy `local-instructions.example.md` beside this skill to
`local-instructions.md` for machine-local naming notes. The file is gitignored;
the sample adds no preferences. The scripts do not interpret prose.

Both launch helpers share `scripts/select-session-name.mjs`, using Node.js's
built-in SQLite support rather than Python or an external SQLite package.
When no explicit name is supplied, the helper:

1. An explicit `AGENT_RELAY_WORDLIST_FILE` uses the installed Relay's `loadWords`
   API (upgrade Relay if that API is unavailable). Otherwise it uses
   `wordlist.local.txt` beside this skill if present: one lowercase name per line,
   blank lines ignored. Without that file, it loads the child's installed Relay
   wordlist, calling `loadWords` when supported (including the fork's optional
   `<COPILOT_HOME>/agent-relay-wordlist.txt`), otherwise using bundled `WORDS`.
   Names must be valid and unique; an empty or invalid list is an error.
2. Reads the active Relay roster once. For plugin-configured meshes, it uses the
   child's installed plugin loader, transport, and credentials (including the
   PostgreSQL plugin's `.env` and local Azure login). It initializes the transport,
   lists active peers across machines, and closes the connection without
   registering a session or running plugin activation hooks. Transport initialization
   can apply schema migrations, just as starting Relay does; this also applies to
   dry runs. Connection or plugin failures stop the launch, never fall back to SQLite.
   Without a plugin transport, it reads local SQLite read-only, honoring
   `AGENT_RELAY_DB`, otherwise `AGENT_RELAY_DATA_DIR` or Relay's platform-default
   data directory, with the legacy in-extension database used only when the
   canonical one is absent. Names with heartbeats within 30 seconds count as active
   for local SQLite; plugin transports determine their own active roster.
3. Hashes the generated launch session ID with SHA-256, takes the first unsigned
   32-bit value modulo the list length, and probes forward with wraparound to the
   first unused name. That same session ID and selected name are used for launch.
   This is circular linear probing, not a full consistent-hashing implementation.

An exhausted list, unreadable registry, or invalid wordlist fails before opening a
tab. There is no silent fallback to an invented name. Plugin meshes require the
installed Relay plugin-loader API and working transport credentials. The roster
read does not reserve a name, so concurrent launches can still race. Use session
IDs to address peers reliably.

To enforce different themes or exclusions per machine, customize the gitignored
`wordlist.local.txt`; it takes effect automatically, without a local instructions
file. Do not modify Relay's own wordlist. Editing a list can change the hash mapping
for future sessions; existing sessions keep their names.

Use local naming notes only for naming preferences. Explicit user requests take
precedence; local preferences do not override name validation, collision checks,
permissions, or lifecycle safeguards. Do not create or edit either local file unless asked.
These preferences affect peers launched through this skill, not Relay's automatic
names for ordinary sessions. An explicit user-requested name bypasses automatic
wordlist selection; local naming notes are not permission to bypass it.

## Launch helpers

Use PowerShell on Windows and Bash on Linux/macOS. Both return a JSON launch
record and preserve model and agent arguments literally. PowerShell can also
target Kitty when `pwsh` is preferred on Linux/macOS.

```powershell
pwsh -NoProfile -File "<skill-dir>\scripts\Spawn-Session.ps1" `
    -WorkingDirectory 'D:\work\example\pr-1'
```

```bash
bash "<skill-dir>/scripts/spawn-session.sh" \
    --working-directory "$PR1_WORKTREE"
```

Optional inputs:

- `Resume` / `--resume`: exact UUID of saved local history on the target host
  (not a picker, prefix, name, or cloud-only task). Reuses that ID via Copilot's
  `--resume`, preserving the recorded Relay alias when available; an explicit
  user-requested `Name` overrides only the Relay alias and terminal title through
  `AGENT_RELAY_NAME`, not the saved conversation name. The helpers never combine
  Copilot's incompatible `--resume` and `--name` flags. Missing history, live local lock/Relay
  presence, or a name collision fails before launch. No recorded alias means
  `name: null` in the plan; Relay assigns it on startup. Use the exact ID for
  readiness. `WorkingDirectory` is still required; use the saved session's directory.
- `Name` / `--name`: exact name, only when explicitly requested by the user.
  Omit for automatic selection from the wordlist and local registry.
- `Model` / `--model`: exact Copilot model ID, only when requested.
- `Agent` / `--agent`: exact Copilot agent profile name, only when requested,
  for example `-Agent 'doc-review'` or `--agent doc-review`. Passed to Copilot's
  `--agent` on new and resumed sessions and included as `agent` in the JSON record
  (`null` when omitted). This selects the child profile, not its Relay name or model.
- `Yolo` / `--yolo`: pass Copilot's `--yolo` flag to the child, enabling all
  permissions (tools, paths, and URLs). Use only on explicit user request;
  omitted by default. This does not change global settings.
- `Terminal` (PowerShell): `windows-terminal` or `kitty`; otherwise OS-based.
  The Bash helper targets Kitty only.
- `WindowId` (PowerShell): Windows Terminal target; default `0` means the
  most recently used window, not necessarily the caller's. Supply a known window
  name/ID to remove that ambiguity. A nonexistent target may create a window.
- `KittyAddress` / `--kitty-address`: override `KITTY_LISTEN_ON`. With neither set,
  Bash discovers or starts Kitty automatically; PowerShell still requires an address.
- `DryRun` / `--dry-run`: return the command plan without launching or requiring
  installed terminal executables. The working directory must still exist.
  Automatic naming still requires Node.js, a wordlist, and an accessible Relay
  roster (including authentication for plugin transports); an explicit name bypasses
  that lookup. Bash always uses Node.js for UUID/JSON generation.
  Without an address, its dry run plans a new listener without probing or starting
  Kitty; `kitty_start_command` records that command.

Windows opens a tab and may take focus; do not promise a no-focus launch.
Kitty tab launches use `--keep-focus`; starting a new Kitty window may take focus.
The Bash JSON result includes `kitty_address`, `kitty_started`, and
`kitty_start_command` so later launches can target the same instance explicitly.
The helpers copy only Copilot/Relay configuration
environment overrides needed to select the same mesh, including PostgreSQL
connection settings, `AGENT_RELAY_ENV_FILE`, `AGENT_RELAY_WORDLIST_FILE`, and
`AZURE_CONFIG_DIR`. Keep password
credentials in the plugin's `.env`, not launch arguments or the JSON launch record.
No task text is embedded in a shell command: deliver it through Relay after
registration.

## Access and lifecycle

- Users can enter the new tab directly and answer normal permission prompts.
- Helpers do not enable Copilot remote control; Relay messaging does not require
  it. Do not add the removed `--remote` flag. If the user separately requests
  remote control on newer CLI versions, enable it in the child with `/remote on`;
  manage incoming connections through `/environments` where supported. Account
  policy and connectivity still apply; remote-control failure is not Relay failure.
- Connect to the live session with `copilot --experimental --connect <session-id>`
  when available. Use `--resume <session-id>` for saved-history continuation,
  not as a guaranteed attachment to an already running process.
- Closing the child Copilot stops its Relay participation. Closing its terminal
  may terminate the worker. Do not close it automatically at parent turn/session end.
- An automatically started Kitty stays open for the user and can host later peers.
  Closing it stops its listener and may terminate all peers in its tabs.
- Do not introduce autopilot, global approvals, trust changes, or an approval
  proxy. Pass `--yolo` only on explicit user request for the child.
  Relay messages cannot approve native permission prompts.
- Relaunching in a directory is not resuming its old conversation. Later work on
  the same task may reuse a live peer explicitly; unrelated work gets a new session.
  Use `Resume` for stopped saved sessions, not to attach another copy to a live one.
  Preflight checks are snapshots; Copilot's own session locking remains authoritative.

## Closing a peer (Windows Terminal only)

Close a tab only when explicitly requested by the user. Closing can terminate
everything in that tab, including split panes; it is not just Relay deregistration.
Never close the caller's tab or infer cleanup from task completion.

1. Identify the requested peer using its retained launch record and Relay roster.
   Ask if the target is unclear. A session ID is not a Windows Terminal tab ID.
2. Run `Close-Session.ps1 -List` to inspect current exact tab titles and UI Automation
   runtime IDs. A peer named `pr2` may appear as `pr2 - GitHub Copilot` while running
   and `pr2` after exit. Do not use fuzzy matching or silently try alternate titles.
   Titles are mutable and not proof of session identity; stop if the peer-to-tab
   mapping cannot be established. Refuse duplicate titles across Terminal windows.
3. Run a dry run with the selected exact title and runtime ID, then close that same
   target. The runtime ID is transient; if it changes, inspect again rather than
   silently dropping the guard.
4. Report `closed` only when the helper verifies the selected UI element disappeared.
   A remaining tab or UI Automation error is not success. If a native confirmation
   appears, let the user handle it; do not accept it or retry automatically.

```powershell
pwsh -NoProfile -File "<skill-dir>\scripts\Close-Session.ps1" -List

# Substitute the exact title and runtime_id returned by -List.
pwsh -NoProfile -File "<skill-dir>\scripts\Close-Session.ps1" `
    -TabTitle 'pr2 - GitHub Copilot' -TabRuntimeId '<runtime_id>' -DryRun

pwsh -NoProfile -File "<skill-dir>\scripts\Close-Session.ps1" `
    -TabTitle 'pr2 - GitHub Copilot' -TabRuntimeId '<runtime_id>'
```

The helper invokes only the selected tab's `CloseButton` through UI Automation,
without keyboard shortcuts, focus manipulation, settings changes, or process
kills. Killing Copilot or its parent shell does not reliably remove the tab.
It returns JSON with the title, Terminal window handle, runtime ID, and status.
`planned` is inspection only; `closed` verifies tab removal, not process-tree exit
or saved work. The helper never force-kills remaining processes. Closing Kitty peers
is not implemented; do not run Windows UI Automation or Bash tests through WSL.

## References

- [Agent Relay](https://github.com/joniba/agent-relay)
- [Relay fork with private text wordlists](https://github.com/TransientError/agent-relay)
- [Windows Terminal commands](https://learn.microsoft.com/windows/terminal/command-line-arguments)
- [Kitty remote control](https://sw.kovidgoyal.net/kitty/remote-control/)
