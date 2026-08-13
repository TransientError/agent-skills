# agent-skills

A collection of skills for GitHub Copilot CLI and other AI coding agents.

## Install

```bash
npx skills add TransientError/agent-skills
```

## Skills

### afk

Set ground rules for running Copilot on autopilot while the user is away. Constrains the agent to safe operations within an explicit scope before entering autonomous mode.

**Trigger:** "afk", "/afk", "afk mode", or when indicating you're stepping away.

### latest-screenshot

Find and attach screenshots from ~/Screenshots (swappy output).

**Trigger:** "latest screenshot", "last screenshot", "show screenshot", "attach screenshot", or referencing a recent screenshot.

### neovide

Launch and manage a per-session Neovide instance from Copilot CLI. Open files and jump to lines in the GUI editor during conversation.

**Trigger:** "show me", "open in neovide", "open this file", "neovide", or asking to visually display a file.

**Prerequisites:** [Neovide](https://neovide.dev/) must be installed.

### presenterm

Generate terminal-based presentation slides in [presenterm](https://github.com/mfontanini/presenterm) markdown format. Covers slide syntax, comment commands, code blocks, layouts, diagrams, and themes.

**Trigger:** "make slides", "create presentation", "presenterm", "slide deck".

**Prerequisites:** [presenterm](https://github.com/mfontanini/presenterm) must be installed.

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
