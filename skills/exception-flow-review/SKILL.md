---
name: exception-flow-review
description: >
  Automated, read-only review of exception behavior introduced or made reachable
  by a change. Trace throws through callers, catches, async boundaries, middleware,
  retries, and fallback to assess systemic failure and unintended blast radius.
  Use when asked for "exception review", "exception flow review", "review throws",
  "check exception handling", or "where are these exceptions caught".
---

# Exception Flow Review

Determine where affected exceptions are handled and whether the resulting failure
matches the operation's contract. Review the complete failure path, not just the
new throw statement or nearest catch.

## Scope and execution

- Resolve the requested PR, branch diff, staged/unstaged changes, or supplied code.
  Pin the base and reviewed revision when available. Ask if the target is ambiguous.
- Read applicable repository guidance and the affected operation's contract.
  Distinguish required failure behavior from optional fallback or partial success.
- Inventory added or changed throws, catch filters, rethrows, error conversions,
  retries, and fallback. Include existing exceptions newly reachable through the
  change, such as constructor fallback or validation on a newly activated branch.
- Perform an automated, read-only pass, not an unrelated repository-wide audit.
  Follow unchanged callers and handlers only as needed to establish the outcome.
- Do not edit, install, start hosts, execute tests, commit, or post review
  comments/votes unless separately requested. Read-only inspection is permitted
  when the host's permissions allow it.
- If delegated to a reviewer agent, supply the exact target, this checklist, and
  relevant context. Do not nest another review. Respect host model selection and
  distinguish independent review from builder self-review.

## Trace each affected failure

1. **Establish the trigger.** Identify the input/state that causes the exception,
   its type, and whether it is deliberate contract enforcement, an expected
   operational failure, cancellation, or an unexpected programming error.
2. **Follow propagation.** Walk callers to the terminal handling point or an
   unhandled boundary. Read catch types, filters, nesting, rethrows, wrapping, and
   conversions into result objects or status codes. "There is a catch upstream"
   is not evidence that this exception matches it or gets a safe outcome.
3. **Follow async and framework boundaries.** Check awaited versus detached tasks,
   aggregate failures, concurrent fan-out, callbacks, streams, and message/job
   dispatch. Determine how exceptions are observed and whether construction
   happens outside the operation's normal catch/retry boundary.
4. **Determine the outcome and blast radius.** Does one item, optional dependency,
   or branch fail the entire request/batch/process? Are sibling results discarded
   or work left running? Does a disabled branch still fail during construction?
   Compare that behavior with the intended all-or-nothing or partial-success
   contract rather than assuming failures should always be swallowed.
5. **Check recovery and consistency.** Assess fallback, retry eligibility, bounded
   attempts, cancellation, cleanup, rollback, and idempotency after partial side
   effects. Flag retries that repeat completed non-idempotent work or convert
   caller cancellation into an unrelated failure/retry.
6. **Check observability and exposure.** Find where the outcome is logged or
   otherwise signaled according to repository conventions. Flag silent terminal
   failure, misleading success, duplicate reporting of the same error, lost
   exception context, or sensitive details exposed to callers.

Record a compact chain for each materially different outcome:

```text
trigger/throw -> caller or async boundary -> matching handler (or none)
             -> retry/fallback/cleanup -> caller-visible or systemic outcome
```

Cite the code for the trigger and terminal decision. If framework behavior is
material, verify it using available implementation or authoritative documentation,
or mark that edge unresolved.

## Compare against the base and existing tests

- Explain what changed in exception reachability or handling compared with the
  base. An unchanged throw can become a new regression when a PR activates it.
- Check whether tests inject an error at the real failing boundary and assert the
  resulting outcome. Mocking below construction can miss constructor exceptions.
- A test asserting only "throws" does not prove the right exception is handled,
  unrelated work survives, side effects are safe, or the caller sees the contract.
- Do not label deliberate fail-fast behavior or rejecting invalid input a defect
  without evidence it violates the intended contract.
- Suggest a focused regression at the failure boundary, including partial-success
  or cancellation behavior when relevant. Do not run or author tests in this pass.

## Output

State the target/revision and inventoried failure paths. Give stable numbered
findings, each with:

- **Severity:** HIGH, MEDIUM, or LOW, based on reachable impact.
- **Evidence:** file:line citations for the trigger and relevant handlers/boundaries.
- **Failure chain:** trigger, propagation, terminal outcome, and affected work.
- **Contract mismatch:** why the failure, recovery, or apparent success is wrong.
- **Correction:** the smallest handling change and useful regression scenario.
- **Confidence:** separate verified behavior from unresolved framework assumptions.

Finish with **PASS**, **FAIL**, or **BLOCKED**:

- **PASS:** no actionable exception-flow defect found in scope; disclose limits
  and distinguish inspected code from runtime evidence.
- **FAIL:** a reachable exception path violates the contract with evidence.
- **BLOCKED:** missing contract, source, or framework behavior prevents a material
  failure path from being assessed.

Do not recommend blanket catches, success-shaped fallbacks, or suppressing every
exception. A general review mentioning exceptions does not complete this dedicated
propagation and systemic-impact pass.
