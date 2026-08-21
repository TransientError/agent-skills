#!/usr/bin/env python3
"""Align GitHub-flavored Markdown table columns so the raw source is readable.

Pads every table cell with spaces so the pipes line up vertically. Preserves
leading indentation, alignment colons in the separator row (:---, :--:, --:),
and escaped pipes (\\|). Operates in place on the given file(s).

Usage:
    python3 format_markdown_tables.py FILE [FILE ...]

Limitation: any line whose first non-space character is '|' is treated as a
table row, including such lines inside fenced code blocks.
"""
import re
import sys


def is_table_line(line):
    return line.lstrip().startswith("|")


def split_row(content):
    tmp = content.replace(r"\|", "\x00")
    if tmp.startswith("|"):
        tmp = tmp[1:]
    if tmp.endswith("|"):
        tmp = tmp[:-1]
    return [c.strip().replace("\x00", r"\|") for c in tmp.split("|")]


def is_sep_cells(cells):
    return len(cells) > 0 and all(re.fullmatch(r":?-{1,}:?", c) for c in cells)


def sep_cell(orig, width):
    left = orig.startswith(":")
    right = orig.endswith(":")
    inner = max(1, width - (1 if left else 0) - (1 if right else 0))
    return (":" if left else "") + ("-" * inner) + (":" if right else "")


def format_file(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")

    out = []
    i, n = 0, len(lines)
    while i < n:
        if is_table_line(lines[i]):
            j = i
            indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
            block = []
            while j < n and is_table_line(lines[j]):
                block.append(lines[j].strip())
                j += 1
            rows = [split_row(b) for b in block]
            ncols = max(len(r) for r in rows)
            for r in rows:
                r += [""] * (ncols - len(r))
            sep_idx = next((k for k, r in enumerate(rows) if is_sep_cells(r)), None)
            widths = [3] * ncols
            for k, r in enumerate(rows):
                if k == sep_idx:
                    continue
                for c in range(ncols):
                    widths[c] = max(widths[c], len(r[c]))
            for k, r in enumerate(rows):
                if k == sep_idx:
                    cells = [sep_cell(r[c], widths[c]).ljust(widths[c], "-") for c in range(ncols)]
                else:
                    cells = [r[c].ljust(widths[c]) for c in range(ncols)]
                out.append(indent + "| " + " | ".join(cells) + " |")
            i = j
        else:
            out.append(lines[i])
            i += 1

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("formatted:", path)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    for path in argv[1:]:
        format_file(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
