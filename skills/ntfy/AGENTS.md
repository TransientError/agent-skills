# AGENTS.md - ntfy development notes

These notes govern changes to this skill package. Runtime publication consent,
topic privacy, and notification content requirements remain in `SKILL.md`.

## Test isolation

- Creating, modifying, or testing this skill never authorizes a live ntfy
  publication.
- Automated tests must use dry-run rendering or a local loopback test server.
  Never publish to `ntfy.sh`, a configured private server, or the user's topic.
- Do not read, print, copy, or commit `topic.local.txt`; tests use generated
  temporary topic files containing non-sensitive fixture values.
- Verify payload encoding, redirect refusal, timeout/uncertain-delivery behavior,
  response validation, size limits, and PowerShell/Python parity without retries.
- Tests must not read or overwrite the user's clipboard or change notification,
  network, credential, or subscription configuration.
