---
name: ntfy
description: >
  Send a short phone/push notification through ntfy using a private machine-local
  topic file. Use when asked to "send an ntfy notification", "notify my phone",
  "ping me when done", or send an explicitly requested completion/blocker alert.
---

# ntfy

Send one notification for the user's requested event, not an automatic stream of
progress updates. This skill does not create subscriptions, run a listener, or
schedule future work.

## Private topic setup

Read the topic from `topic.local.txt` beside this `SKILL.md`, independent of the
working directory. The file contains exactly one topic name, optionally followed
by a newline. It is gitignored and must never be committed or copied into this
skill, examples, logs, chat, or command-line arguments.

`topic.example.txt` contains only the placeholder `ntfy-topic-name`. Never publish
to that placeholder. If the local file is absent, stop and ask the user to set up
a private topic; do not invent or silently use another one. When the user asks
for a new topic, generate an unguessable cryptographically random value, save it
only in the ignored file, and have the user subscribe privately in their ntfy app.
Keep the same private file available on each host that should use that topic;
installing or updating the skill does not distribute it.

ntfy topics can contain letters, digits, underscores, and hyphens, up to 64
characters. On an unprotected public server, the topic is effectively a password:
anyone who knows it may be able to read and publish messages. A random topic is
not encryption or an account access-control policy.

## Workflow

1. Confirm that the user requested this notification or explicitly authorized the
   completion/blocker event. Creating or testing the skill is not permission to
   publish a live notification.
2. Identify the sending session and requested task, then summarize what happened
   using **Notification content** below. Bare "Task finished." or "Input is needed."
   messages are insufficient when several sessions or scheduled tasks are running.
3. Resolve the helper relative to this skill and run it with `DryRun` / `--dry-run`
   first when checking setup. Dry runs read and validate the topic but do not
   contact any server or print its value.
4. For an authorized event, invoke the helper once without the dry-run switch.
   Default priority is 3; use 4 or 5 only when explicitly requested.
5. Report `published` only when the server confirms the expected message.
   Publishing is not confirmation of phone delivery. On timeout, malformed
   response, or HTTP failure, report delivery as unconfirmed; do not retry
   automatically because the first request may already have published.

## Notification content

Always supply a descriptive title and message, not just the helpers' default title.

- **Title:** `[<relay-name>] <task label> - <status>`, for example
  `[din] Session launcher fix - done`. Use the actual sending session's registered
  Relay name, not a guessed alias or the target/launcher's name. Read the session's
  `files/agent-relay-name.txt` or identify its exact ID in `list_relay_agents`.
  If Relay identity is unavailable, use a short session-ID prefix and say the alias
  is unavailable; do not omit identification or invent a name.
- **Message:** one to three short sentences describing what you did, the concrete
  outcome, and any remaining blocker or next action. Distinguish implemented from
  committed/pushed, and queued/running from completed. Mention meaningful
  verification when relevant; never claim success for failed or partial work.
- **Scheduled tasks:** use the user's recognizable task label; add the run time
  with timezone or a non-sensitive run label when repeated runs could be confused.
  Do not expose internal scheduler identifiers.

Example: title `[din] Session launcher fix - done`, message
`Removed the obsolete launch flag. Regression checks passed; committed and pushed.`
For a blocker: title `[cara] Editor setup - blocked`, message
`Installed the editor. Compiler setup is waiting for your input; details are in the session.`
Examples are illustrative: replace the sender, task, and outcome with actual facts.

ntfy.sh is an external service and notifications may appear on a lock screen.
Include useful **non-sensitive** context, not source code, logs, credentials,
internal URLs, customer data, repository paths, or confidential work details.
Use a safe task label and leave restricted details in the session; privacy is not
a reason to omit the sender and all task context. A notification is not an
approval request or proof that the phone received it.

## Helpers

Windows: PowerShell 7. Linux/macOS: Python 3.9+ (standard library only).
Both helpers work on Windows too; Bash and the ntfy CLI are not required.

Resolve `<skill-dir>` from this skill's installation location:

```powershell
pwsh -NoProfile -File "<skill-dir>\scripts\Send-Ntfy.ps1" `
    -Message 'Removed the obsolete launch flag. Regression checks passed; changes are not yet committed.' `
    -Title '[din] Session launcher fix - done' -DryRun
```

```text
python "<skill-dir>/scripts/send_ntfy.py" --message "Removed the obsolete launch flag. Regression checks passed; changes are not yet committed." --title "[din] Session launcher fix - done" --dry-run
```

Omit the dry-run switch only to publish an authorized notification. Both accept:

- `Message` / `--message`: required nonblank text.
- `Title` / `--title`: defaults to `Agent notification`.
- `Priority` / `--priority`: integer 1-5, default 3.
- `TopicFile` / `--topic-file`: optional private file path, never the topic value.
- `Server` / `--server`: defaults to `https://ntfy.sh`; use a different trusted
  server only when the user requests it. HTTPS is required except for HTTP
  loopback addresses used in local tests.

Helpers POST UTF-8 JSON to the server root, not a topic-bearing URL. They do not
follow redirects, retry, print the topic, or echo server response bodies. Payloads
over 4096 UTF-8 bytes are rejected; attachments and interactive actions are outside
this skill. No login or OAuth flow is needed for this unprotected-topic workflow.

## Reference

- [ntfy publishing API](https://docs.ntfy.sh/publish/#publish-as-json)
