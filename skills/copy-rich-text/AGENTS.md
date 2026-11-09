# AGENTS.md - copy-rich-text development notes

These notes govern changes to this skill package. Clipboard consent and runtime
safety remain in `SKILL.md`.

## Renderer and test coupling

- CF_HTML offsets are UTF-8 byte offsets, including the fixed-width header.
  Keep renderer changes and non-ASCII offset regressions in the same commit.
- Automated tests must not read or overwrite the user's clipboard. Use the pure
  renderer, `-DryRun`, and the isolated fixture namespace for clipboard-writer
  behavior.
- Cover legacy paragraphs, mixed paragraph/table blocks, escaped cell content,
  rectangular validation, UnicodeText fallback, and both Windows PowerShell 5.1
  and PowerShell 7 when available.
- Do not replace native table rendering with Markdown/aligned-code fallbacks or
  allow caller-supplied raw HTML.
