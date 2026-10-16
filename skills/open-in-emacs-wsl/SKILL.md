---
name: open-in-emacs-wsl
description: >
  Open a Windows file in GNU Emacs running inside WSL, displayed on Windows via
  VcXsrv. Windows-only. Trigger: "open in emacs", "open this in emacs", "open
  the todo in emacs", or any request to view/edit a file in Emacs.
compatibility: Windows only. Requires WSL (a distro with emacs installed) and VcXsrv.
---

# open-in-emacs-wsl

Opens a Windows file path in Emacs running inside WSL, with the GUI frame
displayed on the Windows desktop through VcXsrv (not WSLg) — because the user's
X server of choice is VcXsrv.

## When to use

Trigger phrases: "open in emacs", "open this in emacs", "open the todo in
emacs", or similar requests to view/edit a specific file in Emacs.

Windows-only. Do not use on Linux/macOS.

## How to run

```powershell
& "$HOME\.copilot\skills\open-in-emacs-wsl\scripts\Open-InEmacsWsl.ps1" -Path <windowsFilePath>
```

- `-Path` accepts an absolute or relative Windows path; relative paths resolve
  against the current directory.
- `-Distro <name>` overrides the WSL distro (defaults to `Ubuntu`).

The script:
1. Converts the Windows path to its WSL equivalent via `wslpath`.
2. Looks up the WSL default-route gateway IP live (the WSL2 host IP can change
   across reboots) and sets `DISPLAY=<hostIp>:0.0` — this is where VcXsrv is
   reachable, **not** WSLg's display.
3. Starts Emacs detached (`setsid`) inside WSL so it outlives the launching
   command. Repeated calls currently just launch another Emacs process (no
   single-instance/server reuse) — acceptable for now per the user.

## VcXsrv prerequisite and the misconfiguration gate

Emacs needs VcXsrv listening on TCP with access control disabled (`-ac`), since
no xauth cookie is set up.

- **VcXsrv not running at all:** the script starts it itself (via
  `Restart-VcXsrv.ps1`, flags `-multiwindow -clipboard -wgl -ac`). Nothing to
  lose, so no confirmation needed.
- **VcXsrv running but misconfigured** (missing `-ac` and/or not listening on
  TCP 6000): the script only **warns** — it never kills an existing VcXsrv
  itself, since that would silently drop all the user's other X11 windows.
  **The agent must not run `Restart-VcXsrv.ps1` in this case without asking
  the user first** (e.g. via `ask_user`) — the user can see the live client
  count/state in the VcXsrv UI and is better positioned to judge whether a
  restart is safe. Only after explicit confirmation should the agent run:

  ```powershell
  & "$HOME\.copilot\skills\open-in-emacs-wsl\scripts\Restart-VcXsrv.ps1"
  ```

## Troubleshooting

- If Emacs doesn't appear to launch, the script prints the tail of
  `/tmp/emacs-copilot.log` from inside WSL.
- A connection refused / blank window usually means VcXsrv isn't reachable at
  the computed `DISPLAY` — check the warnings above first.
