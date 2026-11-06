---
name: copy-rich-text
description: >
  Copy human-facing text to the Windows clipboard as genuine rich-text HTML
  with native tables, bold labels, inline code, and a plain-text fallback. Use when asked to
  "format for Teams", "copy as rich text", "put formatted message on clipboard",
  "copy a table as rich text", "format a table for Teams", or when "Markdown
  doesn't paste well". Windows-only; does not send messages.
compatibility: Windows interactive desktop with Windows PowerShell 5.1 and System.Windows.Forms.
---

# Copy Rich Text

Put formatted text on the Windows clipboard for pasting into Teams or another
HTML-aware editor. This is inherently Windows-specific (CF_HTML and WinForms);
Linux/macOS clipboard writing is not supported. No packages are required.

## Workflow

1. Identify the exact source message in the conversation or a user-specified file.
   Ask if the source is ambiguous. Preserve wording, punctuation, paragraph
   boundaries, table cell contents/order, and code literally; do not summarize,
   polish, or send the message.
2. Apply only requested formatting. Represent bold labels and inline code with
   the structured runs below in paragraphs or table cells. Use ordered `blocks`
   for mixed paragraphs/tables. **A requested table must be a native table block,
   never flattened into aligned spaces, a Markdown pipe table, or one monospaced
   code run.** Interpret Markdown delimiters as formatting only
   where intended; never strip literal backticks or asterisks from code.
3. Write UTF-8 JSON to a uniquely named file in the session workspace, not the
   repository. Treat message text as data, never as PowerShell or raw HTML.
4. If the user only requested a preview or formatting advice, stop before copying.
   A request to copy, put on the clipboard, or invoke this skill authorizes one
   clipboard replacement. Otherwise ask before replacing the clipboard.
5. Run the helper using its absolute installed skill path:

   ```powershell
   powershell.exe -NoProfile -STA -File "<skill-dir>\scripts\Copy-RichText.ps1" -InputPath "<session-dir>\message.json"
   ```

   PowerShell 7 can also invoke the helper; it relaunches Windows PowerShell in
   STA with an encoded command when necessary. Paths are passed as data.
   Append `-DryRun` to validate/render without any clipboard access; this reports
   only status and UTF-8 payload size, not message content.

6. On success say the rich-text message is copied. Use **Ctrl+V** in the target
   compose box, not **Ctrl+Shift+V / paste as plain text**, which discards
   formatting. The receiving editor may normalize fonts or styles. Do not claim
   a Teams paste was verified unless the user actually checked it.
7. Delete only the temporary input file you created after the command completes.
   On failure report it plainly; do not claim the clipboard is unchanged if a
   write was attempted. Do not retry a write automatically.

## Input

Choose exactly one root property: legacy `paragraphs` or ordered `blocks`.
Both are nonempty arrays; never provide both.

Each paragraph or table cell is a nonempty array of runs. Each run has required
string `text`, and optional Boolean `bold` and `code` (both default false).
An empty-text run can represent an empty paragraph or cell. Unknown properties are
rejected to catch misspellings rather than silently dropping formatting.

### Legacy paragraphs

Existing `paragraphs` input remains supported without changes:

```json
{
  "paragraphs": [
    [{ "text": "Status: ", "bold": true }, { "text": "Ready for review." }],
    [
      { "text": "Command: ", "bold": true },
      { "text": "example --check <file>", "code": true }
    ]
  ]
}
```

### Ordered paragraph and table blocks

A paragraph block has exactly `type: "paragraph"` and `runs`.
A table block has exactly `type: "table"`, `headers`, and `rows`.
`headers` is a nonempty array of cells. `rows` is an array of rows; each row
has exactly the same number of cells as `headers`. Header-only tables may use
`rows: []`. Cells use the same `text`/`bold`/`code` runs as paragraphs, not strings
or caller-supplied HTML. Supply one empty-text run for an empty cell.

```json
{
  "blocks": [
    {
      "type": "paragraph",
      "runs": [{ "text": "Review status", "bold": true }]
    },
    {
      "type": "table",
      "headers": [[{ "text": "Item" }], [{ "text": "Status" }]],
      "rows": [
        [[{ "text": "Validation" }], [{ "text": "Passed", "bold": true }]],
        [
          [{ "text": "example --check", "code": true }],
          [{ "text": "Awaiting review" }]
        ]
      ]
    },
    {
      "type": "paragraph",
      "runs": [{ "text": "Please review when ready." }]
    }
  ]
}
```

The renderer emits real `<table>`, `<thead>`, `<tbody>`, `<tr>`, `<th>`, and `<td>`
elements with visible borders, padded cells, and bold/shaded headers. Bold/code
runs stay within their individual cells. Every run is HTML-escaped; literal
`<table>` or `<script>` text cannot become markup. Whitespace and embedded
newlines are preserved using fixed styles and `<br>`.

The UnicodeText fallback joins unchanged cell text with tabs and table rows
with Windows line endings, including the header row. Blocks are separated by
blank lines, preserving their order; paragraph behavior is unchanged.
There is deliberately no Markdown parser, raw-HTML input, link rewriter, remote
service, arbitrary styling API, or aligned-code-table fallback.

## Clipboard safety

- Never read or log existing clipboard contents. Never overwrite the clipboard
  to test the skill; use `-DryRun` and the pure renderer instead.
- A real write sets HTML and UnicodeText together and requests persistence
  after the process exits. It then verifies those formats are available, without
  reading their content.
- CF_HTML offsets are UTF-8 **byte** offsets, including the fixed-width header.
  Keep the renderer and its non-ASCII offset tests together when modifying it.
- Clipboard access requires the same interactive Windows desktop as the user.
  Clipboard locks, remote/headless sessions, or target-editor restrictions may
  prevent copying or retaining formatting; report failures, do not install
  dependencies, change global settings, or automate Teams as a workaround.
