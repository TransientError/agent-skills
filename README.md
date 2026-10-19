# agent-skills

A collection of skills for GitHub Copilot CLI and other AI coding agents,
plus custom agents for GitHub Copilot CLI.

## Install

```bash
npx skills add TransientError/agent-skills
```

This installs skills. Custom agents are installed separately; see [Agents](#agents).

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

A read-only partner that helps you review any document. Supports a short summary
followed by your questions, or a conversational walkthrough organized into
coherent chunks with visible progress. Explains faithfully, provides assessment
when asked, surfaces key decisions and their stated rationale, and keeps
requested research distinct from its own judgment.
Preserves your place through detours, tracks feedback lightly, consolidates it
on request, and checks author revisions against feedback you actually delivered.
Does not edit documents or contact authors.

**Use:** Select `doc-review` and ask to review a document, or ask Copilot to use the
`doc-review` agent.

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
