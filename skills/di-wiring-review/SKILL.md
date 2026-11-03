---
name: di-wiring-review
description: >
  Automated, read-only review of dependency-injection wiring affected by a change.
  Trace actual resolving containers, registrations, factories, lifetimes, and
  runtime activation paths rather than assuming registration means resolution.
  Use when asked for "DI review", "DI wiring review", "dependency injection review",
  "check dependency wiring", or "startup review".
---

# DI Wiring Review

Review whether changed code can be constructed and used through its actual runtime
dependency-injection path. This is a dedicated wiring pass, not a general code
review or proof that the application starts.

## Scope and execution

- Resolve the requested PR, branch diff, staged/unstaged changes, or supplied code.
  Pin the base and reviewed revision when available. Ask if the target is ambiguous.
- Read applicable repository guidance. Start with changed constructors,
  registrations, factories, consumers, and composition roots; follow unchanged
  code only as needed to close the affected dependency graph.
- Perform the review automatically and report findings, rather than walking the
  user through every file. Do not broaden into an unrelated dependency audit.
- Remain read-only: no edits, installs, host startup, test execution, commits, or
  review comments/votes unless separately requested. Read-only code and git
  inspection are permitted when the host's permissions allow them.
- If the host delegates this pass to a reviewer agent, give it the exact target,
  this checklist, and relevant context. Do not nest another review. Respect host
  model selection; distinguish an independent review from a builder self-review.

## Trace the actual resolution path

1. **Identify activation points.** Find the request, job, message handler, plugin,
   pipeline, or startup action that constructs the affected consumer. Check both
   startup-time and first-use activation, including lazy factories and reflection.
2. **Identify the resolving container.** Follow the provider/container instance
   passed to each factory or resolver. Distinguish root containers, child scopes,
   separately built containers, module registries, and test-only collections.
   Verify inheritance/forwarding semantics; do not assume all containers share
   registrations.
3. **Close the dependency graph.** For each affected constructor/factory dependency,
   find its registration in that exact container and environment. Match service
   identity, including interfaces, concrete types, generic arguments, names,
   qualifiers, and keys. Follow transitive dependencies to their registrations.
4. **Check selection and fallback.** Inspect constructor selection, optional
   dependencies, default constructors, fallback instances, duplicate registration
   precedence, decorators, and collection resolution. Determine what missing or
   failed resolution actually does: throws, returns null, chooses another
   constructor, or silently substitutes behavior.
5. **Check lifetime and ownership.** Look for scoped dependencies captured by
   singletons or long-lived factories, resolution outside a valid scope, premature
   disposal, and ownership of disposable instances forwarded between containers.
   Apply the framework's actual lifetime rules, not assumed universal rules.
6. **Check conditional activation.** Walk affected environment, configuration, and
   feature branches. Determine whether construction happens before filtering or
   feature checks: a disabled component can still break unrelated work if it is
   eagerly instantiated.

Record a compact evidence chain for each affected activation path:

```text
entry point -> consumer/factory -> resolving container -> registration
            -> dependency activation -> lifetime/owner
```

Cite the code establishing each important edge. A symbol search hit or a root
registration by itself does not close the chain.

## Evaluate existing validation evidence

- Check whether tests use the production composition path or build their own
  container. Explicit mock registrations can conceal missing runtime wiring.
- Distinguish resolving a service from invoking a factory or lazy path inside it.
  Container build validation cannot prove behavior of arbitrary runtime factories.
- Distinguish host startup and health checks from exercising the affected request,
  job, or message path. Do not claim runtime success from reading code or reports.
- When a constructor failure was repaired only in a fixture, check the equivalent
  production resolution path before accepting a fixture-only explanation.
- Suggest the smallest regression that exercises the real composition boundary
  with controlled downstream dependencies. Do not run or author it in this pass.

## Output

State the target/revision, affected activation paths, and inspected container
boundaries. Then give stable numbered findings, each with:

- **Severity:** HIGH, MEDIUM, or LOW, based on reachable impact.
- **Evidence:** file:line citations for the consumer, resolver, and registration
  mismatch or lifetime violation.
- **Failure path:** conditions, resolution behavior, and caller/job impact.
- **Correction:** the smallest wiring fix and useful regression boundary.
- **Confidence:** distinguish demonstrated code paths from uncertain assumptions.

Finish with **PASS**, **FAIL**, or **BLOCKED**:

- **PASS:** no actionable wiring defect found within the stated scope; disclose
  unexecuted runtime validation and any non-material coverage limits.
- **FAIL:** an actionable wiring defect is supported by a complete failure chain.
- **BLOCKED:** missing source, configuration, or framework semantics prevent a
  material part of the resolution path from being assessed.

Do not invent defects for intentionally optional dependencies or unrelated
pre-existing issues. Do not count a general review that merely mentions DI as
completion of this dedicated trace.
