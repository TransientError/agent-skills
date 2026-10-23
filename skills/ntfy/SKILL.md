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
2. Use a short, generic message such as "Task finished." or "Input is needed."
   ntfy.sh is an external service: do not send source code, logs, credentials,
   internal URLs, customer data, repository paths, or confidential work details.
   Leave those details in the session. A notification is not an approval request
   or proof that the phone received it.
3. Resolve the helper relative to this skill and run it with `DryRun` / `--dry-run`
   first when checking setup. Dry runs read and validate the topic but do not
   contact any server or print its value.
4. For an authorized event, invoke the helper once without the dry-run switch.
   Default priority is 3; use 4 or 5 only when explicitly requested.
5. Report `published` only when the server confirms the expected message.
   Publishing is not confirmation of phone delivery. On timeout, malformed
   response, or HTTP failure, report delivery as unconfirmed; do not retry
   automatically because the first request may already have published.

## Helpers

Windows: PowerShell 7. Linux/macOS: Python 3.9+ (standard library only).
Both helpers work on Windows too; Bash and the ntfy CLI are not required.

Resolve `<skill-dir>` from this skill's installation location:

```powershell
pwsh -NoProfile -File "<skill-dir>\scripts\Send-Ntfy.ps1" `
    -Message 'Task finished.' -Title 'Agent notification' -DryRun
```

```text
python "<skill-dir>/scripts/send_ntfy.py" --message "Task finished." --title "Agent notification" --dry-run
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
