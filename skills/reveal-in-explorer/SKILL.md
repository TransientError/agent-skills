---
name: reveal-in-explorer
description: >
  Open Windows File Explorer to the folder CONTAINING a file we've been working
  on — by default the containing folder is opened plainly; only highlight/select
  the file when the user explicitly says "select". Windows-only. Use when the user
  says "reveal", "reveal in Explorer", "show in Explorer", "open Explorer here",
  "open the containing folder", "open the folder for this file", "show me the
  folder", or wants to drag a file somewhere. The target is the CONTAINING
  DIRECTORY, not opening the file itself.
compatibility: Windows only. Requires PowerShell and explorer.exe.
---

# reveal-in-explorer

Open File Explorer to the **containing directory** of a file. By default the
folder opens with nothing selected; the file is highlighted (ready to drag) only
when the user explicitly asks to **select** it.

## When to use

- The user wants the **folder** that holds a file we've been working on.
- Triggers: "reveal", "reveal in Explorer", "show in Explorer", "open the
  containing folder", "open the folder for this file", "show me the folder".

Windows-only. Do not use on Linux/macOS.

## Choosing the mode (based on how the user asks)

| User phrasing                                             | Mode              | Flag        |
| -------------------------------------------------------- | ----------------- | ----------- |
| "reveal in explorer", "open the containing folder", etc. | Open folder plain | *(default)* |
| Phrasing that includes **"select"** (e.g. "reveal in explorer select", "…and select it", "highlight it") | Open folder with file highlighted | `-Select` |

Default = **no** selection. Add `-Select` **only** when the user's wording asks
to select/highlight the file.

## How to run

```powershell
# Default: open the containing folder, nothing selected
& "$HOME\.copilot\skills\reveal-in-explorer\scripts\Reveal-InExplorer.ps1" -Path <fileOrDir>

# When the user says "select": highlight the file, ready to drag
& "$HOME\.copilot\skills\reveal-in-explorer\scripts\Reveal-InExplorer.ps1" -Path <file> -Select
```

- **File path, default** → opens its containing folder plainly.
- **File path, `-Select`** → opens the containing folder with the file
  highlighted (`explorer /select,"<abs path>"`).
- **Directory path** → opens that directory directly (`-Select` ignored).
- Accepts relative paths (resolved against the current directory).

## Constraints

- Windows only (`explorer.exe`). No Linux/macOS equivalent is shipped.
- The target is always the **containing directory**, never launching/opening the
  file's associated application.
