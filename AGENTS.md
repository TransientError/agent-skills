# AGENTS.md

Guidance for AI agents working in this repository.

## What this repo is

A collection of Agent Skills for GitHub Copilot CLI and other AI coding agents.
Each skill lives in `skills/<name>/`, containing a `SKILL.md` (YAML frontmatter +
body) and optional `scripts/`, `references/`, `assets/`, or `templates/` folders.
`link-skills.ps1` / `link-skills.sh` link skill directories into
`~/.copilot/skills/` for local development, and `link-agents.ps1` /
`link-agents.sh` link `agents/` into `~/.copilot/agents/`.

## Skills must be cross-platform by default

Any skill that ships executable helpers must work on **Windows, Linux, and
macOS** unless the skill is inherently platform-specific (and says so explicitly
in its `SKILL.md` and README `Prerequisites`).

- Provide **both a PowerShell (`.ps1`) and a Python (`.py`) implementation** for
  non-trivial logic. PowerShell Core (`pwsh`) covers Windows; Python covers
  Linux/macOS (and Windows too). Ship both and let `SKILL.md` pick per platform.
- **Bash is acceptable only for simple, portable shell glue.** Do not implement
  parsing- or algorithm-heavy logic in bash — port it to Python instead.
- Keep the implementations behaviorally equivalent. If you change one, change the
  other in the same commit.
- In `SKILL.md`, document which runtime to invoke on which platform, and list any
  runtime prerequisites in the repo `README.md`.
- Avoid hard-coded platform assumptions: path separators, line endings (`\r\n`
  vs `\n`), `$HOME`/`%USERPROFILE%`, and shell built-ins. Prefer writing UTF-8
  without a BOM and preserving a file's existing line endings.

## Authoring conventions

- Skill directory name: lowercase with hyphens; the `name` in frontmatter must
  match the folder name exactly.
- `description` must state WHAT the skill does and WHEN to use it (trigger
  phrases/keywords) — it is the primary discovery mechanism.
- Keep `SKILL.md` bodies lean (aim < 300 lines); move long reference material to
  `references/`.
- After adding a skill, add a short entry to `README.md` (summary + triggers +
  any prerequisites).

## Markdown formatting

Use Prettier instead of the retired `prettify-markdown` skill and its custom
table formatters. For human-facing Markdown you create or edit, run
`bunx prettier --write <file.md>`, respecting the project's existing configuration.
Without Bun, use `npx prettier --write <file.md>`.
Prettier aligns tables and formats the rest of the document, so review the diff.
Do not format agent/tool-only intermediate artifacts merely to align tables.
