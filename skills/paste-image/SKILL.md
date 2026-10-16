---
name: paste-image
description: >
  Paste an image from the clipboard directly into the conversation, like
  Ctrl+V on desktop. Slurps the Wayland clipboard with wl-paste into the
  current session's files/ directory (no clutter, no extra dir permission),
  then views it.
  Trigger: "paste", "paste image", "paste screenshot", "clip", "clipboard
  image", or when the user refers to an image they just copied.
---

# Paste Image

Grab an image from the clipboard and pull it into the conversation — the CLI's
answer to desktop-style Ctrl+V image paste.

Images are written into the **current session's `files/` directory**, not
`~/Screenshots`. This is deliberate:

- The session dir is already an allowed path → no extra directory-permission prompts.
- Session files are ephemeral (die with the session) → never clutter the user's real screenshot folder.

## When to Activate

User says any of: "paste", "paste image", "paste screenshot", "paste the image",
"clip", "clipboard image", or otherwise refers to an image they just copied and
want you to see (e.g. "look at what I copied", "here's a screenshot" with nothing
attached).

Do **not** activate for pasting text, code, or when the user has already attached
an image via `@path` or drag-and-drop.

## How It Works

1. Check the clipboard actually holds an image: `wl-paste --list-types`.
2. Pick the first `image/*` MIME type offered.
3. Dump it to the current session's `files/` dir with a timestamped name.
4. `view` the saved file to read it into context.
5. Act on the image per the user's request.

The session `files/` path is in your session context (the
`session-state/<session-id>/files` folder). Substitute it for `$SESSION_FILES`
below.

## Commands

```bash
# Session files dir — replace with the real path from your session context
SESSION_FILES="/home/kvwu/.copilot/session-state/<session-id>/files"

# 1. What's on the clipboard?
types=$(wl-paste --list-types 2>/dev/null)

# 2. First image MIME type (empty => no image copied)
mime=$(printf '%s\n' "$types" | grep -m1 '^image/')

# 3. Dump to session dir with the right extension
if [ -n "$mime" ]; then
    ext="${mime#image/}"
    case "$ext" in jpeg) ext=jpg ;; svg+xml) ext=svg ;; esac
    out="$SESSION_FILES/clip-$(date +%Y%m%d_%H%M%S).$ext"
    wl-paste --type "$mime" > "$out"
    echo "saved: $out"
else
    echo "no image on clipboard"
fi
```

Then `view "$out"`.

## Actions

- **"paste" / "paste image" / "clip"** → run the slurp, save to session `files/`, then `view` the result.
- **"paste screenshot"** → same flow (screenshot is just an image on the clipboard).
- clipboard has no image → tell the user "No image on the clipboard — copy one first (screenshot, image file, etc.), then say paste."
- After viewing, describe or act on the image as the user asked.

## Rules

- **Save location is the session `files/` dir — never `~/Screenshots`.** This is the whole point of the skill.
- No cleanup needed: session files are discarded when the session ends.
- Primary tool is `wl-paste` (Wayland). Granting it once ("always allow") is safe — it only reads the clipboard.
- X11 fallback (if `wl-paste` is unavailable or `WAYLAND_DISPLAY` is unset):
  `xclip -selection clipboard -t image/png -o > "$out"`.
- Always confirm an image is present (`--list-types`) before dumping; don't write empty/garbage files.
- Filename format: `clip-YYYYMMDD_HHMMSS.<ext>`.
- Keep responses short.

## Example Flows

User: *(copies a screenshot with swappy)* "paste"
→ `wl-paste --list-types` shows `image/png`
→ `wl-paste --type image/png > $SESSION_FILES/clip-20260801_014226.png`
→ `view` it → describe / act on it

User: "paste image" *(clipboard has plain text)*
→ `wl-paste --list-types` shows only `text/plain`
→ "No image on the clipboard — copy one first, then say paste."

User: "look at what I just copied"
→ Treat as paste → slurp clipboard image into session dir → view
