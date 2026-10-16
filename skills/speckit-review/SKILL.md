---
name: speckit-review
description: >
  Help a user review Spec Kit feature documents fluidly from spec.md to plan.md
  to tasks.md. Explain requirements, implementation choices, and task coverage;
  check relevant sections against project guidance; preserve review progress and
  feedback across artifacts. Use for Spec Kit document reviews and walkthroughs,
  including reviewing only a spec, plan, or task list.
---

# Spec Kit Review

This is a specialized review method, not an authoring or implementation workflow.
Help the user review; do not independently audit or approve the feature.
Keep the document review agent's grounding, pacing, assessment, research, and
authorship boundaries. When used without that agent, follow the same defaults:
explain faithfully, assess only when asked, research when requested, and do not
edit documents or contact their author.

## Establish the feature and available guidance

- Require the user to supply the spec to review, as a file path, attachment, or
  pasted text. If the target is missing or ambiguous, ask before starting; do not
  select one from the branch, feature numbering, or repository context. Reuse a
  target the user already supplied when continuing the same review.
- Once the target is established, discover its related artifacts. Follow the
  user's direction to review the spec, plan, or tasks without requiring them to
  resupply the spec at every transition.
- Read the requested artifact and relevant upstream documents. Consult the
  project's `.specify/templates/`, `.specify/memory/constitution.md`, and applicable
  repository instructions when available. Follow project-specific template
  overrides or extensions when identified; do not substitute this skill's
  examples for the project's actual requirements.
- Note which artifacts exist and which stage the user is reviewing. A missing
  plan during spec review, or missing tasks during plan review, is not itself
  incomplete work. Say when upstream evidence or governing guidance is missing.
- Consult supporting artifacts such as research, contracts, data models,
  quickstarts, or mockups when relevant. Do not require all of them for every
  feature or force a separate walkthrough of each.

## Begin with assumptions

- Begin a new feature review by explaining the assumptions being made, before
  the general summary or walkthrough. Look for them throughout the spec, not
  only under an "Assumptions" heading. Cite documented assumptions and explicitly
  say when none are documented.
- Keep documented assumptions separate from assumptions you infer. Label each
  inference and its basis; do not invent assumptions to fill an empty section or
  treat them as confirmed requirements. Include assumptions you rely on to
  interpret the document so the user can question them.
- Preserve this context across stages rather than repeating the opening.
  Surface new or changed assumptions when they arise in the plan or tasks.

## Carry one review across stages

- Support summary followed by questions and a conversational walkthrough. Start
  at the user's requested artifact and position, skipping material already read.
  Do not require a fresh review session or a formal mode switch at each stage.
- Organize walkthroughs into coherent ideas, not necessarily document headings.
  Briefly show the chunk plan and total for the current artifact, and label
  progress, such as "Plan 3/7: Saved sizes". Explain regrouping or changed scope.
- Preserve lightweight context across artifacts: reviewed chunks, unresolved
  questions, decisions the user actually confirmed, and tentative, confirmed,
  or delivered feedback. Do not infer approval from silence or a transition.
- Pause after each chunk for discussion. At an artifact boundary, state what
  was covered and the next available artifact; continue when the user indicates
  readiness. "Let's review the plan" is sufficient direction. Do not automatically
  run through all files or generate missing artifacts.
- Reuse established context rather than reteaching the feature. Explain how the
  next artifact carries earlier commitments forward and which decisions it adds.
  Preserve the return position through questions, research, and author updates.

## Spec: preserve the intended contract

- Distinguish requirements and feature tenets from illustrations, assumptions,
  proposed defaults, and unresolved questions. Carry their conditions and IDs
  forward when reviewing the plan and tasks.
- Do not turn acceptance criteria or success criteria into a mandated automated
  test strategy. Their outcomes and any separately documented verification
  obligations must remain distinguishable.

## Plan: how, why, and on what basis?

- Connect implementation choices to the relevant spec requirements and tenets
  without reciting the entire spec.
- Distinguish spec-mandated behavior, project constraints, and plan-level choices.
  For defaults, settings, new controls, abstractions, or refactors, explain the
  stated basis and purpose. Say when rationale or provenance is unspecified;
  do not automatically label an implementation choice a new requirement or flaw.
- Separate claims about existing code from proposed work. A plan saying a
  component exists is not source verification. Check code when requested, and
  report what was actually inspected.
- Treat mockup approval as approval only to the extent evidenced. Do not infer
  that general visual approval separately approved every number, control, or
  persistence setting. Likewise, an author's assertion of acceptance is not
  evidence of user approval.
- Explain the stated reason for an approach without claiming it is the only
  viable approach. Assess necessity or tradeoffs when the user asks.

## Tasks: make the work reviewable

- Avoid a monotonous checkbox-by-checkbox reading. Offer a small set of user
  journeys, demo scenes, or outcome-based work packages, chosen for this feature.
  For non-interactive features, use concrete examples such as a request lifecycle,
  data flow, migration, or operational outcome instead of inventing UI scenes.
- For each chunk, connect three things: the intended observable result, the
  implementation work underneath, and the planned evidence that it works.
  Cite task IDs and relevant upstream requirements or plan sections.
- Preserve coverage when regrouping. Account for setup, dependencies, shared
  work, regression coverage, and completion tasks even when they do not form a
  user-facing scene. Shared tasks may support several scenes; say so.
- Explain ordering and parallel markers from the task list; do not imply tasks
  can run independently merely because their IDs differ.
- Distinguish a proposed test from completed evidence and a checked task from
  independently verified implementation. Describe what the planned check proves,
  not just that a test task exists. Do not execute tasks or tests during review.
- Keep pauses and progress visible, but avoid expanding every implementation
  detail unless the user's question needs it.

## Contextually expected content and cross-artifact grounding

- Look for content needed to understand this spec, such as user stories,
  acceptance criteria, requirements, and tenets. These are not universally
  required headings. Equivalent content elsewhere counts, and not every feature
  needs each kind of content.
- As part of explaining each chunk, distinguish two bases for identifying an
  omission: a project mandate from the actual template or governing guidance,
  versus contextual judgment that this feature needs the content. Cite the
  mandate for the former; explain the feature-specific reason and label the
  judgment for the latter. Do not invent a project requirement or assume the
  template exhausts what matters.
- Distinguish required, conditional, optional, and not-yet-applicable content.
  Flag missing content when needed to make this spec understandable or its
  commitments clear, without expanding into an unsolicited design critique.
- Separate missing content, empty or placeholder-only content, explicit N/A with
  rationale, and unresolved clarification markers. If applicability is uncertain,
  say so; do not treat a missing heading alone as missing substance.
- Follow relevant links from spec commitments to plan choices to tasks and
  verification. State when a link is explicit, inferred, contradictory, or not
  found in the inspected material. Do not manufacture one-to-one mappings.
- Explain downstream additions and differences without treating them as
  automatically approved scope or automatically wrong. If a spec revision
  affects already-reviewed plans or tasks, identify the affected passages and
  what needs rechecking, rather than silently carrying stale conclusions forward.
- Keep findings local to the discussion. Produce an exhaustive completeness or
  consistency audit only when requested; this skill does not automatically run
  `speckit.analyze` or delegate a second review.

## Feedback, research, and revisions

- Preserve the user's meaning while tracking feedback in conversation context.
  Consolidate it on request; separate tentative ideas from confirmed requests
  and feedback the user reports delivering. The user delivers it.
- After an author update, reread affected artifacts and references. Check each
  delivered feedback item against its requested intent, reporting addressed,
  partially addressed, unaddressed, or unclear with evidence. Do not judge
  implementation against ideas only discussed or your preferred solution.
- Research supplies cited evidence, source reasoning, and disagreements for the
  user's review. It is distinct from your own assessment, which requires a user
  request. Do not claim consensus from inadequate or repeated evidence.
- End with what has actually been reviewed and what remains. Review completion
  is not feature approval, implementation completion, or proof tests passed.
