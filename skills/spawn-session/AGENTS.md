# AGENTS.md - spawn-session development notes

These notes govern changes to this skill package. Runtime launch, reporting,
permission, and lifecycle behavior remains in `SKILL.md`.

## Cross-platform validation

- Keep PowerShell and Bash launch helpers behaviorally equivalent, including
  arguments, validation, reporting-mode metadata, and JSON output fields.
- Run PowerShell dry-run tests natively on Windows.
- Run Bash tests using native Git Bash on Windows or native Bash on Linux/macOS;
  never use WSL for this skill's Bash tests.
- Never run Windows UI Automation close tests through WSL. Use the same
  interactive Windows desktop and exact non-caller test tabs.
- Dry runs must not open terminals, launch Copilot, alter permissions, or reserve
  Relay names. Closing tests must never target an existing user tab.
