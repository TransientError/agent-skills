---
name: prettify-markdown
description: >
  Prettify Markdown that is meant for HUMAN consumption so the raw source is
  pleasant to read — starting with aligning table columns (padding cells with
  spaces so pipes line up). Use whenever you generate or edit a Markdown file a
  human will read (READMEs, docs, design notes, reports, PR descriptions, wiki
  pages) and it contains tables. Do NOT use for Markdown produced purely for
  another agent/tool to parse, where the padding just wastes tokens. Trigger
  phrases: "prettify markdown", "clean up this markdown", "align the table",
  "make the raw markdown readable", "format markdown tables".
---

# prettify-markdown

Make human-facing Markdown readable in its **raw** form, not just when rendered.
The first (and currently only) transform is **table column alignment**: pad every
cell with spaces so the `|` pipes line up vertically. More transforms may be added
to this skill over time.

## When to use

Apply when **both** are true:
- The Markdown is intended for a **human** to read (README, docs, design/spec
  notes, reports, changelogs, PR descriptions, wiki pages, committed `.md` files).
- It contains at least one Markdown table.

Do **not** apply when:
- The Markdown is an intermediate artifact meant only for another agent/tool to
  parse — alignment padding is pure token overhead there.
- The content is inside fenced code blocks that happen to contain `|`-leading
  lines (see Limitations).

## How to run

The bundled script aligns tables in place. Run it on the file(s) after you finish
writing them:

```powershell
& "$HOME\.copilot\skills\prettify-markdown\scripts\Format-MarkdownTables.ps1" -Path <file.md>
```

- Accepts multiple paths and pipeline input:
  `Get-ChildItem docs\*.md | & "...\Format-MarkdownTables.ps1"`
- Edits in place; preserves the file's existing line endings (LF/CRLF) and writes
  UTF-8 without a BOM.
- Prints `formatted: <path>` per file.

If PowerShell isn't available, the equivalent behavior can be reproduced by hand:
pad each cell to its column's max width, keep separator-row alignment colons
(`:---`, `:--:`, `--:`), and preserve escaped pipes (`\|`).

## What it does

| Aspect              | Behavior                                                        |
| ------------------- | --------------------------------------------------------------- |
| Column width        | Each column padded to the widest cell (minimum width 3)         |
| Separator row       | Rebuilt to column width, preserving `:` alignment markers       |
| Escaped pipes       | `\|` inside a cell is kept literal, not treated as a delimiter  |
| Indentation         | Leading whitespace on the table block is preserved              |
| Line endings / BOM  | Original EOL style preserved; written as UTF-8 (no BOM)         |

## Constraints

- Run only on human-facing Markdown (see When to use).
- The script treats any line whose first non-space character is `|` as a table
  row — **including such lines inside fenced code blocks**. If a file's code
  fences contain pipe-leading lines, don't run the script on it (or those blocks
  will be reformatted as tables).
- The transform is idempotent: running it again on already-aligned tables is a
  no-op.
