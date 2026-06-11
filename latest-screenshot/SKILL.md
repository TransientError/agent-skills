---
name: latest-screenshot
description: >
  Find and attach screenshots from ~/Screenshots (swappy output).
  Trigger: "latest screenshot", "last screenshot", "show screenshot",
  "open screenshot", "attach screenshot", or referencing a recent screenshot.
---

# Screenshot Finder

Resolve screenshot references to files in `~/Screenshots/` (swappy save dir).

## When to Activate

User says any of: "latest screenshot", "last screenshot", "recent screenshot",
"show screenshot", "open screenshot", "attach screenshot", or asks to view/use
a screenshot they recently took.

## How It Works

1. List screenshots sorted by modification time: `ls -t ~/Screenshots/`
2. Resolve the user's request to one or more files
3. Act on it: view (read the image), open in viewer, or reference via `@path`

## Commands

```bash
# Latest screenshot
ls -t ~/Screenshots/ | head -1

# Last N screenshots
ls -t ~/Screenshots/ | head -N

# Find screenshot by date (filenames are swappy-YYYYMMDD_HHMMSS.png)
ls ~/Screenshots/ | grep "20260503"
```

## Actions

- **"latest screenshot"** → resolve newest file, then `view` it (reads image into context)
- **"open screenshot"** → resolve file, open with `feh <path> &>/dev/null & disown`
- **"attach screenshot"** → resolve file, tell user to use `@<path>` or read it in directly
- **"show me my last 5 screenshots"** → list them with timestamps
- **"screenshot from today/yesterday"** → filter by date in filename

## Rules

- Screenshot dir: `~/Screenshots/`
- Filename format: `swappy-YYYYMMDD_HHMMSS.png`
- Always use `ls -t` for recency sorting (modification time)
- When viewing an image, use the `view` tool on the resolved path
- When opening, use `feh` and background it with `&>/dev/null & disown`
- If no screenshots found, tell the user the directory is empty
- Keep responses short

## Example Flows

User: "latest screenshot"
→ Run `ls -t ~/Screenshots/ | head -1` → `swappy-20260503_213804.png`
→ `view ~/Screenshots/swappy-20260503_213804.png`
→ Describe or act on the image

User: "open my last screenshot"
→ Resolve newest file
→ `feh ~/Screenshots/swappy-20260503_213804.png &>/dev/null & disown`
→ "Opened in feh."

User: "screenshot from march 22"
→ `ls ~/Screenshots/ | grep "20260322"` → `swappy-20260322_213936.png`
→ View or open as requested
