---
name: speckit-mode
description: >
  Apply the repository's installed Spec Kit implementation workflow without
  switching agents. Use when the user requests "Spec Kit mode", "speckit mode",
  or implementation using the project's speckit.implement instructions.
---

# Spec Kit Mode

Use the current agent to execute the user's implementation request using the
project's installed Spec Kit workflow. This skill adapts instructions; it does
not select or invoke another agent.

1. Locate the repository's installed `speckit.implement` profile, typically
   `.github/agents/speckit.implement.agent.md`. If absent, look for an equivalent
   implementation instruction file in the repository's agent, prompt, or skill
   directories. If missing or ambiguous, ask for the intended file before
   implementation; do not install Spec Kit or substitute upstream instructions.
2. Read the selected file and relevant referenced resources. Follow its workflow
   for the requested scope, including its prerequisites, gates, task tracking,
   validation, and hooks. Use the project's instructions rather than a copied
   workflow. Reading the profile does not select its model, tools, or role.
3. Retain the current agent's routing, delegation, integration, and verification
   responsibilities where compatible. Pass relevant workflow constraints to
   delegates; keep responsibility for gates and shared task tracking with the
   lead agent. Parallel eligibility does not require parallel execution.
4. Respect instruction priority and existing permissions. Surface genuine
   conflicts between the installed workflow and current agent's instructions;
   ask before proceeding when resolution would change scope or behavior. Do not
   silently drop workflow requirements, rewrite the installed profile, or treat
   this mode as authorization to bypass a gate or grant new permissions.
