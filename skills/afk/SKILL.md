---
name: afk
description: >
  Set ground rules for running Copilot on autopilot while the user is away.
  Constrains the agent to safe operations within an explicit scope before
  entering autonomous mode.
  Trigger: "afk", "/afk", "afk mode", or when the user indicates they are
  stepping away and want work to continue.
---

# AFK Mode

Lightweight alternative to full plan mode — for when the user doesn't have time to spec things out in detail but wants the agent to keep working safely while they're away. A quick conversation to establish scope and guardrails, then hand off to autopilot.

## When to Activate

User says: `afk`, `/afk`, `afk mode`, or indicates they're stepping away and want the agent to keep working.

## Setup Flow

When triggered, have a **quick conversation** to clarify anything unclear. Don't make it a formal checklist — just ask what you need to know. Typical things to sort out:

- **What's the task?** If it's not obvious from context, ask.
- **What can I touch?** Which files/dirs are in scope? Can I create new ones?
- **Anything destructive?** If the task might involve deleting files, force-pushing, etc. — confirm it's safe now.
- **Any blockers?** Missing creds, ambiguous requirements, external deps? Resolve or agree on a fallback.

If the user already provided all this context, don't ask redundant questions — just confirm you're ready.

### The Handoff

Once everything is clear, give a brief summary:

- What you'll do
- What you won't do
- When you'll stop

Then say **"Ready — turn on autopilot and say go."**

The user enables autopilot, says "go" (or similar), and walks away.

## Ground Rules (Always Active in AFK Mode)

These constraints apply for the entire autonomous session:

1. **File scope**: Only edit files the user approved. Stay within the working directory tree unless explicitly told otherwise.
2. **No destructive commands** unless pre-approved or inside a session-created throwaway worktree.
3. **Stop on ambiguity**: If a decision could reasonably go two or more ways and the user hasn't specified a preference, stop and wait rather than guessing.
4. **Stop on blockers**: If you hit a permission error, missing dependency, or anything that requires human intervention, stop.
5. **No external side effects** without prior approval: no git push, no deployments, no API calls that mutate external state, no spending money.
6. **Commit early, commit often** (locally): If the task involves code changes, make atomic commits as you go so progress isn't lost.

## Use Cases

### Research Loop

User is exploring a topic; findings lead to further questions.

- Agent reads, summarizes, and follows leads autonomously
- Creates notes/documents in an approved location
- Stops when the topic is exhausted or hits a dead end

### TDD Development Loop

User has a failing test (or a set of tests to write + implement).

- Agent cycles: run tests → implement/fix → run tests → refactor
- Stays within the approved source and test directories
- Commits after each green cycle
- Stops when all tests pass or when stuck on a failure it can't resolve

### Refactoring / Migration

User wants a mechanical change applied across many files.

- Agent applies the pattern, runs lint/tests after each batch
- Stops if tests break in an unexpected way
- Commits after each successful batch

## Example Interaction

```
User: afk — finish implementing the auth middleware, tests are in tests/auth/

Agent: Before you go, let me confirm:

 Task: Implement auth middleware to pass the existing tests in tests/auth/
 Scope: src/middleware/ and tests/auth/ (edit only)
 Destructive actions: None expected
 Blockers: None identified — tests and deps are in place

I'll cycle TDD-style: run tests → implement → run tests → commit on green.
I'll stop if I hit a test I can't resolve or need a design decision.

Ready — enable autopilot whenever you like.
```

## Rules

- This skill is a **pre-flight conversation**, not an executor. It sets up constraints; autopilot does the work.
- Keep it brief — the user wants to leave, not have a meeting.
- If the user provides all context upfront (task + scope + permissions), just confirm and say ready.
- Only ask about things that are genuinely unclear. Don't interrogate.
- Default to conservative: when in doubt, ask before they leave rather than guess while they're gone.
