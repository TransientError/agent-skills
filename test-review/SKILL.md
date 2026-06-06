---
name: test-review
description: >
  Adversarial review of AI-generated tests. Checks for adequate coverage,
  trivial/tautological assertions, logic bypass, and other ways tests can
  "cheat" instead of genuinely exercising the code under test.
  Trigger: "review tests", "test review", "check my tests", "are these tests good",
  or when reviewing test files written by an AI agent.
---

# AI-Generated Test Review

Perform an adversarial review of test code, especially tests written by AI agents. The goal is to catch tests that *look* correct but fail to provide real safety.

## When to Activate

- User asks to review tests or test quality
- User mentions tests were AI-generated and wants a sanity check
- During code review when test files are in the diff

## Scope

Unless the user explicitly asks to review all tests, **only review new or changed tests** — i.e., tests that appear in the current diff or were just created. Do not re-review the entire test suite every time.

**Before starting the review, list the test files/functions you plan to review and confirm with the user.** This gives them a chance to expand or narrow the scope.

## Review Checklist

### 1. Coverage Gaps

- Are all public functions/methods exercised?
- Are edge cases covered (empty inputs, nulls, boundary values, error paths)?
- Are both happy path and failure modes tested?
- If there are conditional branches, does at least one test hit each branch?

### 2. Trivial / Tautological Tests

Flag tests that prove nothing:

- Asserting a hardcoded value equals itself
- Testing only the default/zero state without exercising behavior
- Assertions that are always true regardless of implementation (e.g., `assert len(result) >= 0`)
- "Smoke tests" that only check the function doesn't throw, when the function's contract is to *return a value*
- Tests where the expected value is computed by copy-pasting the same logic being tested

### 3. Logic Bypass / Cheating

Flag tests that sidestep the system under test:

- Mocking the very thing being tested (mock returns what the assertion expects)
- Stubbing internal methods so deeply that no real code path runs
- Constructing the "expected" output by calling the function under test itself
- Snapshot/golden tests where the snapshot was auto-accepted without human review
- Tests that depend on implementation details instead of observable behavior (brittle)

### 4. Misleading Structure

- Test names that don't match what they actually verify
- Shared mutable state between tests (order-dependent passes)
- Setup/teardown that silently masks bugs (e.g., catching all exceptions)
- `@skip`, `@ignore`, or commented-out assertions hiding failures

### 5. Assertion Quality

- Are assertions specific? (`assertEqual(x, 42)` vs. `assertTrue(x)`)
- Do tests assert on the *right thing*? (return value vs. side effect)
- Is there at least one assertion per test? (no assertion = no test)
- Are error messages / assertion messages helpful for debugging?

## Output Format

For each issue found, report:

```
[SEVERITY] file:line — short description
  → Why it matters
  → Suggested fix
```

Severities:
- **CRITICAL** — Test provides false confidence; passes even if code is broken
- **WARNING** — Test is weak or fragile; may not catch regressions
- **INFO** — Minor improvement opportunity

## Invocation

Use the **rubber-duck** agent with model override `gpt-5.5`. Include the review checklist (sections 1–5 above) in the prompt along with the test code to review.

```
task(
  agent_type: "rubber-duck",
  model: "gpt-5.5",
  prompt: "<review checklist from this skill> + <test code under review>"
)
```

Cross-model review reduces correlated blind spots — a different model family is less likely to share the same assumptions that produced the tests.

## Principles

- Be adversarial: assume the test is wrong until proven otherwise
- A test's job is to *fail when the code is broken* — evaluate every test by asking "what bug could slip past this?"
- Prefer fewer, stronger assertions over many trivial ones
- Tests should break when behavior changes, not when implementation details change
- If you can delete the implementation body (replace with `pass`/`return null`/`throw`) and the test still passes, it's a bad test
