# agent-skills

A collection of skills for GitHub Copilot CLI and other AI coding agents,
plus custom agents for GitHub Copilot CLI.

## Install

```bash
npx skills add TransientError/agent-skills
```

This installs skills. Custom agents are installed separately; see [Agents](#agents).

## Copilot statusline preset

The portable preset in `config/copilot-statusline/settings.json` uses
[copilot-statusline](https://github.com/EncodeTS/copilot-statusline) with Nord
Powerline colors. Shows Agent Relay alias, Git branch, worktree, line changes,
Git status, ahead/behind, and context usage. Git widgets hide outside repositories;
AI credits are omitted to avoid duplicating the built-in footer.

**Prerequisites:** Copilot CLI with custom statusline support and experimental
mode enabled, Node.js 22.5+, Bun (`bunx`, preferred) or npm (`npx`), and
[Agent Relay](https://github.com/joniba/agent-relay) already installed.
Your terminal font must support Powerline separators and the widget icons.

Install Agent Relay first using its upstream installer (same command in Bash
and PowerShell; Bun preferred):

```sh
bunx --yes github:joniba/agent-relay --no-statusline
```

With npm instead, use `npx --yes github:joniba/agent-relay --no-statusline`.

`--no-statusline` preserves your existing statusline configuration; this repo's
installer wires Relay's alias into the Powerline preset instead. Use that option
when upgrading Relay with the same command, too. If using `COPILOT_HOME`, set it
consistently for Relay installation, preset installation, and Copilot launches.
Relay is not bundled or installed automatically by this repo.

Enable experimental mode persistently inside Copilot with
`/settings experimental on`, or launch with `copilot --experimental`. Restart
Copilot after installing Relay so its extension loads.

From a clone or worktree on Linux/macOS:

```bash
bash ./install-statusline.sh
```

On Windows (PowerShell 7; also works on Linux/macOS):

```powershell
pwsh -NoProfile -File ./install-statusline.ps1
```

Preview file changes with Bash `--dry-run` or PowerShell `-DryRun`. Both entry
points link `~/.config/copilot-statusline`
to this repo's `config/copilot-statusline` directory: a directory symlink on
Linux/macOS or an NTFS junction on Windows (no administrator privileges needed).
Existing destinations are refused unless Bash `--force` or PowerShell `-Force`
is supplied; these move the entire old destination to a unique sibling `.bak`
path first. The installer also merges
`statusLine` plus `footer.showCustom` into `~/.copilot/settings.json`, respecting
`COPILOT_HOME` for the latter. Other Copilot settings are preserved; changed
existing Copilot settings get unique `.bak` copies beside them. Reinstalling an
existing link is safe; preset edits through the linked path change the repo file.

The renderer is pinned to `copilot-statusline@0.1.24` and fetched on first use.
Bash uses Node only to safely merge JSON; PowerShell uses its native JSON tools.
No Relay installation, permissions, or experimental-mode settings are changed.
Restart Copilot if the row does not appear. Keep the clone/worktree available
for the link to remain valid. To undo, remove only the symlink/junction (not its
contents) and restore the printed backup paths; for a fresh setup, also remove
the added `statusLine` and `footer.showCustom` keys.

## Agents

Agent profiles live in `agents/`. To install `doc-review` for all projects on
Linux/macOS, run from your local clone or worktree:

```bash
mkdir -p ~/.copilot/agents
ln -s "$PWD/agents/doc-review.agent.md" ~/.copilot/agents/doc-review.agent.md
```

If the destination already exists, review it before replacing it. The symlink
keeps the repository file as the source of truth while drafting. Keep this
clone or worktree available for the link to remain valid.

On Windows, run from your local clone or worktree (PowerShell required):

```powershell
.\link-agents.ps1
```

This creates an NTFS directory junction from `%USERPROFILE%\.copilot\agents`
to this repo's entire `agents` directory; edits and new agent profiles are
available without recopying. No administrator privileges are required. Keep
this clone or worktree available for the junction to remain valid.

Existing content is not replaced by default. Use `.\link-agents.ps1 -Force`
to move it to `%USERPROFILE%\.copilot\agents.bak` before linking (an existing
backup is never overwritten). This replaces the entire agents directory, so
agents in the backup are not loaded. Use `.\link-agents.ps1 -Remove` to remove
only this repo's junction, leaving the source files and any backup untouched.

Restart Copilot CLI after installation, then select an agent through `/agent`.

### lead

A delegation-first lead for a whole feature or initiative. Owns planning,
decomposition, sequencing, integration, and review while handing implementation,
exploration, and validation to subagents. Supports Spec Kit when the project
uses it, but does not require it.

**Use:** Select `lead` explicitly through `/agent` for feature-level or multi-step
work, not quick one-off edits.

**Prerequisites:** A client with subagent support and the tools needed for the
delegated work.

### doc-review

A document-reading partner that helps you review any document. Supports a short
summary followed by your questions, or a conversational walkthrough organized into
coherent chunks with visible progress. Explains faithfully, provides assessment
when asked, surfaces key decisions and their stated rationale, and keeps
requested research distinct from its own judgment.
Preserves your place through detours, tracks feedback lightly, consolidates it
on request, and checks author revisions against feedback you actually delivered.
When reviewing a document in an ADO PR, drafts comment wording from collected
feedback for your approval and can post the approved comments, tracking pending
and posted items. Does not edit documents or contact authors outside those
requested PR comments.

**Use:** Select `doc-review` and ask to review a document, or ask Copilot to use the
`doc-review` agent.

**Prerequisites:** Read access to the document. Optional ADO posting requires
an authenticated MCP server named `ado` exposing PR metadata, document revision,
and thread read/write operations, plus comment permissions. Adjust the profile's
`ado/*` tool allowlist if your server has a different name. Commenting authority
is limited by behavioral instructions, not a read-only MCP permission boundary.

### code-walkthrough

A reading partner for large or generated code changes, distinct from Copilot's
built-in autonomous `code-review` agent. Turns a diff into a numbered,
dependency-aware reading route, points to files and symbols in your existing
viewer, and explains one code-range **chunk** at a time within numbered
**sections**. Announces section completion after all its chunks are reviewed and
for ADO PRs announces file completion when all changed hunks in that file are
covered, even across sections, so you can check it off in ADO. Provides a
conversation checkpoint when pausing and reconciles progress against the PR
snapshot on resume. Preserves your place through questions,
proactively calls out subtle error-handling and exception-flow issues with
code-grounded failure traces, offers broader assessment when asked, and tracks
coverage through to the end.

Accepts pasted diffs, `.patch` files, local Git comparisons, and Azure DevOps PRs.
For ADO, retrieves PR metadata and paginated diffs through configured MCP read
tools, keeping the comparison and surrounding code tied to the reviewed snapshot.
Collects feedback during the walkthrough, drafts ADO PR comment wording for your
approval, and can post the approved comments, tracking posted and pending items
across pauses.
Does not edit code, run tests, approve PRs, resolve threads, or control the diff
display. Neovide integration is not part of this version.

**Use:** Select `code-walkthrough` through `/agent`, then ask "Walk me through this
patch" or "Guide me through this ADO PR" with the patch path or PR URL.

**Prerequisites:** Read access to the diff. Local Git comparisons require Git;
ADO retrieval requires an authenticated ADO MCP connection exposing PR metadata
and diff read operations; posting also requires PR thread read/write tools and
comment permissions. An exported patch works without ADO access. The profile
inherits available tools to support different MCP installations; its repository
read-only and user-authorized commenting boundaries are behavioral instructions,
not a tool-level permission sandbox.

## Skills

Skills live in `skills/<name>/`, with a `SKILL.md` file in each directory.
The install command above discovers skills in this layout.

### afk

Set ground rules for running Copilot on autopilot while the user is away. Constrains the agent to safe operations within an explicit scope before entering autonomous mode.

**Trigger:** "afk", "/afk", "afk mode", or when indicating you're stepping away.

### agent-review

Help review a custom agent definition conversationally. Explains its role,
authority, instruction context, tools, and delegation without adopting the role
or invoking the target. Tracks author feedback and verifies revisions while
distinguishing written instructions, declared capabilities, and runtime evidence.
Complements `doc-review`; assessment, research, and behavioral trials follow the
user's requests rather than becoming an automatic audit.

**Trigger:** Reviewing a custom agent profile, prompt, or its authoring choices.

**Prerequisites:** Access to the agent definition and relevant referenced resources.
No agent invocation or additional tooling is required for a textual review.

### latest-screenshot

Find and attach screenshots from ~/Screenshots (swappy output).

**Trigger:** "latest screenshot", "last screenshot", "show screenshot", "attach screenshot", or referencing a recent screenshot.

### neovide

Launch and manage a per-session Neovide instance from Copilot CLI. Open files and jump to lines in the GUI editor during conversation.

**Trigger:** "show me", "open in neovide", "open this file", "neovide", or asking to visually display a file.

**Prerequisites:** [Neovide](https://neovide.dev/) must be installed.

### ntfy

Send an explicitly requested phone/push notification through ntfy. Reads the
private topic from the gitignored `skills/ntfy/topic.local.txt`, never from tracked
instructions or command-line arguments. The tracked `topic.example.txt` contains
only a placeholder. Includes equivalent PowerShell and Python helpers with dry
runs, bounded requests, and redacted results; no automatic retries or live test
notifications. Copy the private file separately to each host that should use it.
Notifications identify the actual sending Relay session and recognizable task,
summarize the outcome and next action, and distinguish repeated scheduled runs.
Useful non-sensitive context replaces ambiguous bare "Task finished" alerts.

**Trigger:** "send an ntfy notification", "notify my phone", "ping me when done",
or an explicitly requested completion/blocker alert.

**Prerequisites:** PowerShell 7 on Windows or Python 3.9+ on Linux/macOS, network
access to ntfy, and an existing private topic subscription in the phone app.
No ntfy CLI, Python packages, Bash, or OAuth login is required.

### open-in-emacs-wsl

Open a Windows file in GNU Emacs running inside WSL, displayed on the Windows desktop via VcXsrv (not WSLg). Starts VcXsrv itself if it isn't running; if VcXsrv is running but misconfigured, it only warns and leaves restarting it to an explicit, user-confirmed step. **Windows-only.**

**Trigger:** "open in emacs", "open this in emacs", "open the todo in emacs".

**Prerequisites:** WSL with a distro that has Emacs installed, and [VcXsrv](https://sourceforge.net/projects/vcxsrv/).

### paste-image

Paste an image from the clipboard directly into the conversation, like Ctrl+V on desktop. Slurps the Wayland clipboard with `wl-paste` into the current session's `files/` directory (no clutter, no extra directory-permission prompts), then views it.

**Trigger:** "paste", "paste image", "paste screenshot", "clip", "clipboard image", or referring to an image you just copied.

**Prerequisites:** [wl-clipboard](https://github.com/bugaevc/wl-clipboard) (`wl-paste`) on Wayland; `xclip` fallback on X11.

### presenterm

Generate terminal-based presentation slides in [presenterm](https://github.com/mfontanini/presenterm) markdown format. Covers slide syntax, comment commands, code blocks, layouts, diagrams, and themes.

**Trigger:** "make slides", "create presentation", "presenterm", "slide deck".

**Prerequisites:** [presenterm](https://github.com/mfontanini/presenterm) must be installed.

### prettify-markdown

Prettify Markdown meant for human consumption so the raw source is readable — starting with aligning table columns (padding cells so the pipes line up). Applies only to human-facing Markdown (READMEs, docs, reports, PR descriptions), not agent-to-agent output.

**Trigger:** "prettify markdown", "clean up this markdown", "align the table", "make the raw markdown readable", "format markdown tables".

**Prerequisites:** PowerShell Core (`pwsh`) on Windows, or Python 3 on Linux/macOS.

### copy-rich-text

Copy a message to the Windows clipboard as genuine rich-text HTML, with bold
labels, inline code, and a Unicode plain-text fallback. Preserves wording, escapes
text safely, and handles non-ASCII CF_HTML byte offsets. Paste with Ctrl+V into
Teams or another HTML-aware editor; paste-as-plain-text discards formatting.
Does not send messages or automate Teams. Includes a clipboard-free dry run.

**Trigger:** "format for Teams", "copy as rich text", "Markdown doesn't paste well",
or "put formatted message on clipboard".

**Prerequisites:** Windows interactive desktop, Windows PowerShell 5.1, and
built-in `System.Windows.Forms`. Windows-only by design; no additional packages
or Python implementation are needed for this WinForms clipboard helper.
PowerShell 7 invocation automatically relaunches Windows PowerShell STA when needed.

### reveal-in-explorer

Open Windows File Explorer to the folder **containing** a file we've been working on — handy for dragging it elsewhere. Opens the folder plainly by default; highlights/selects the file only when you say "select". **Windows-only.**

**Trigger:** "reveal", "reveal in Explorer", "show in Explorer", "open the containing folder", "open the folder for this file". Add "select" to highlight the file.

**Prerequisites:** Windows with PowerShell and `explorer.exe`.

### skill-review

Help review a skill's instructions and supporting resources conversationally.
Explains intended behavior without activating the skill, distinguishes written
instructions from runtime evidence, tracks author feedback, and verifies revisions.
Adds an explicit scriptability lens: call out repeatable mechanical work that
could use scripts while keeping interpretation and conversation with the agent.
Complements `doc-review`; does not rewrite skills or run their scripts by default.

**Trigger:** Reviewing a `SKILL.md`, a skill package, or its authoring choices.

**Prerequisites:** Access to the target skill and relevant supporting resources.
No skill execution or additional tooling is required for a textual review.

### speckit-review

Help review a Spec Kit feature fluidly from specification to implementation plan
to tasks, preserving questions, decisions, feedback, and progress across stages.
Starts from a user-supplied spec and explains documented and inferred assumptions
first. Distinguishes project-mandated content from contextually expected content,
requirements from implementation choices, and turns task lists into reviewable
scenarios or outcome-based chunks rather than checkbox recitation.
Complements `doc-review`;
does not author documents, execute tasks, or automatically run an adversarial audit.

**Trigger:** "review Spec Kit docs", a walkthrough of a Spec Kit spec, plan, or
task list, or continuing a feature review from one artifact to the next.

**Prerequisites:** Access to the feature documents. Project templates and
constitution are used when available; no Spec Kit CLI installation is required.

### test-review

Adversarial review of AI-generated tests. Checks for adequate coverage, trivial/tautological assertions, logic bypass, and other ways tests can "cheat" instead of genuinely exercising the code under test.

**Trigger:** "review tests", "test review", "check my tests", "are these tests good", or when reviewing test files written by an AI agent.

### spawn-session

Launch independent interactive Copilot CLI peers in Windows Terminal or Kitty
tabs and hand off self-contained tasks through Agent Relay. Keeps normal
permission prompts by default and existing worktrees; no fixed team roles or
headless pool. Explicitly requested YOLO launches are supported with `-Yolo`
(PowerShell) or `--yolo` (Bash), granting all permissions to that child only.
Start the child as a requested Copilot agent profile with `-Agent 'doc-review'`
(PowerShell) or `--agent doc-review` (Bash), including when resuming history.
The profile must already be available to Copilot in the child's directory/home;
omitting this option leaves agent selection to Copilot, not the parent's profile.
Launchers do not enable Copilot remote control or pass the removed `--remote`
flag; Agent Relay works independently. Enable remote control separately in the
child if requested and supported by its CLI version.
Kitty reuses a listening instance or starts one automatically on Linux/macOS.
Existing Kitty tabs preserve focus; a new Kitty window or Windows Terminal tab
may take focus.
Also closes explicitly selected Windows Terminal peer tabs through UI Automation,
with exact-title/unique-match checks, optional inspected runtime-ID guard, a dry
run, and verified tab removal. Closing is Windows-only and does not kill processes
first or accept confirmation dialogs automatically.

**Resume saved history:** `-Resume <session-uuid>` (PowerShell) or
`--resume <session-uuid>` (Bash) reopens a stopped local session in a new tab,
reusing its UUID and recorded Relay alias without generating a new session.
An explicit name on resume overrides only the Relay alias and terminal title;
it does not pass Copilot's incompatible `--name` flag or rename saved history.
Missing local history, known live sessions, and name collisions stop the launch.
Supply its existing working directory; this is not attachment to a running peer.

**Remote-host launches:** An existing session on the target host can run the
helper locally over a shared Relay mesh and return the child's exact ID.
The explicitly user-authorized remote workflow uses `-Yolo` / `--yolo` for that
child only. Its initial brief must route questions and proposed plans through
Relay to the user-facing coordinator's exact ID, rather than strand optional
dialogs in a remote tab. The coordinator asks the user and relays the actual
answer; this cannot answer native dialogs, sign-in/MFA, or folder-trust prompts.
The original requester is the sole reporting owner. After direct handoff, the
child sends updates and completion only to that session, not the intermediate
host-local launcher; the launcher does not monitor or forward task updates.
Local launches retain normal permissions unless separately authorized.

**Machine-local naming:** Optionally copy
`skills/spawn-session/local-instructions.example.md` to `local-instructions.md`
in the same directory for local naming notes. Both launch helpers automatically
choose names from a gitignored `wordlist.local.txt` beside the skill (one name per
line), or Relay's installed wordlist when no local list exists. They hash the actual
launch session ID into the list and probe forward with wraparound, skipping active
names from Relay's active roster, including other machines on a PostgreSQL mesh.
Plugin meshes use the installed Relay transport and credentials; local SQLite
remains read-only. No AI name selection or Python is needed. Only explicit
user-requested names should use `-Name` / `--name`. Selection is best-effort, not an
atomic reservation. Shared-transport initialization can apply schema migrations,
including during dry runs; connection failures stop the launch rather than fall
back to SQLite. Local files are not synced by Git, and these preferences do not
affect ordinary Relay sessions unless the same file is configured there.
`AGENT_RELAY_WORDLIST_FILE` takes precedence over the skill-local list when the
installed Relay supports it. Without a skill-local list, the
[Relay fork](https://github.com/TransientError/agent-relay)'s effective per-user
wordlist is used when available, with bundled names on older Relay builds.

**Trigger:** "spawn a session", "open a worker tab", "launch a peer agent",
"close a session", "close a worker tab", or delegate to a separately accessible
conversation.

**Prerequisites:** Copilot CLI with experimental extensions and
[Agent Relay](https://github.com/joniba/agent-relay) installed on the same machine.
Windows requires Windows Terminal and PowerShell 7; Linux/macOS requires Kitty
and Bash 4.2+. The Bash helper discovers sockets matching
`spawn-session-kitty-<uid>-*.sock` or starts a listener; no manual socket setup
is needed. PowerShell 7 can also target Kitty with an explicit socket.
Automatic naming requires Node.js 22.13+ or a newer LTS release for built-in
read-only SQLite support (Node 23.x requires 23.5+); Relay itself requires 22.5+.
Remote session access additionally depends on Copilot account policy.
Automatic naming on plugin meshes also requires Relay's installed plugin-loader
API and the configured transport's dependencies and authentication (for PostgreSQL,
the plugin's `.env` and a local Azure login).
Closing requires the same interactive Windows desktop and English Windows Terminal
`Close Tab` controls; it needs no Python or additional packages.
WezTerm, iTerm2, tmux, and headless hosting are not supported by this skill.

### worktree-cleanup

Clean up stale git worktrees and branches whose PRs already merged or closed. Detects squash-merged branches (Azure DevOps + GitHub) via `merge-tree`, confirms PR status through `az`/`gh`, and removes worktrees with a dry-run-first, recovery-SHA workflow. Understands the `pr-<id>` review-checkout convention and skips Copilot-managed worktrees.

**Trigger:** "clean up worktrees", "clean workspace", "delete merged worktrees", "prune worktrees", "which worktrees can I delete", or "clean up pr-* review branches".

**Prerequisites:** PowerShell + git. PR-status lookups need the [Azure CLI](https://learn.microsoft.com/cli/azure/) (`az`, with the `azure-devops` extension) or the [GitHub CLI](https://cli.github.com/) (`gh`), authenticated for your repo.

### zoxide

Smart directory navigation using [zoxide](https://github.com/ajeetdsouza/zoxide) inside Copilot CLI. Jump to frequently-used directories without typing full paths, or reference directories by keyword without navigating.

**Trigger:** "z \<query\>", "jump to \<dir\>", "cd \<partial\>", or "/z \<query\>".

**Prerequisites:** [zoxide](https://github.com/ajeetdsouza/zoxide) must be installed.

## Development

Use `link-skills.sh` to symlink skills into `~/.copilot/skills/` for local development:

```bash
./link-skills.sh          # create symlinks
./link-skills.sh --remove # remove symlinks
./link-skills.sh --force  # replace real directories with symlinks
```

## License

MIT
