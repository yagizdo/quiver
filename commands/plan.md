---
name: plan
description: Create a structured implementation plan with parallel agent research before coding.
argument-hint: "<task description>"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

```
!`git log --oneline -5 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --sort=-committerdate 2>/dev/null || echo "NO_GIT"`
```

---

# Instructions

You are a planning orchestrator. Your job is to clarify the task, dispatch research agents in parallel, synthesize their findings, and draft a step-by-step implementation plan. You do NOT write code -- you research, design, and document.

## Step 0 -- Git Availability

If any gather-context block above returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch/commit context.`
Proceed to Step 1. Treat all git-sourced fields (branch, log, diff, status) as empty.

## Step 1 -- Scope the Task

If `$ARGUMENTS` is empty and the conversation has no obvious pending task:
> No task to plan. Usage: `/plan <describe the task you want to plan>`
**Stop here.**

Otherwise:

1. **Restate** the task goal in one sentence.
2. **List boundaries** -- what is in scope, what is out.
3. **Identify the focus area.** If the task description is broad or ambiguous (e.g., "refactor the map page", "improve the dashboard"), use `AskUserQuestion` to clarify scope. Build action buttons from the relevant categories detected during initial context gathering. Always include a free-text option as the last button.

   Example -- for a broad "refactor X page" request:
   > What aspect of {area} should the plan focus on?
   Buttons: `["UI/Design -- layout, styling, animations", "Architecture -- state management, code structure", "Performance -- loading, caching, optimization", "All of the above -- full overhaul", "Other (I'll describe)"]`

   Example -- for an ambiguous "add auth" request:
   > Which authentication approach should the plan target?
   Buttons: `["OAuth2 (Google, GitHub)", "Email/password", "Magic links", "SSO/SAML", "Other (I'll describe)"]`

   **Rules for clarifying questions:**
   - Use `AskUserQuestion` with action buttons -- never ask clarifying questions as plain text.
   - Derive button options from the codebase context and task domain -- do not use generic placeholders.
   - Always include an "Other" free-text option as the last button.
   - Ask at most ONE clarifying question. If the task is clear enough to proceed, skip this step.
   - If the user picks "Other", accept their free-text response and continue.

4. **Assess complexity:**

| Complexity | Signals | Agents to Dispatch |
|------------|---------|-------------------|
| **Light** | 1-3 files, single layer, well-understood | Explore |
| **Standard** | 3-10 files, 2+ layers, moderate unknowns | Explore + best-practices-researcher |
| **Deep** | 10+ files, architectural impact, security/auth/payments, unfamiliar domain | Explore + best-practices-researcher + architecture-strategist |

If the task is trivial (single file, obvious change), use `AskUserQuestion`:
> This task is straightforward enough to implement directly.
Buttons: `["Skip plan -- implement directly", "Create a plan anyway"]`

5. **Detect review-fix context.** Check if the task references a review report:
   - If `$ARGUMENTS` contains a path matching `.claude/reports/review-*.md` or `review-*_*-*-*.md`, this is a **review-fix plan**.
   - If a review report path is detected, read it and extract the findings.
   - Check `.claude/plans/` for existing plans with the same `review_source` frontmatter. Count them to determine the `review_iteration` number (first fix plan = 1, second = 2).
   - If `review_iteration` would be 3 or higher, warn the user:
     > This would be iteration {N} of the review-fix cycle. The maximum is 2 iterations. Consider addressing remaining findings manually or accepting them as-is.
     Buttons: `["Create the plan anyway", "Stop -- I'll handle it manually"]`
   - Carry the review report path and iteration number forward to Step 5 for frontmatter generation.

If the user picks "Skip plan", **stop here** and implement. Otherwise continue.

## Step 2 -- Agent Discovery

Discover available agents before dispatch:

**Tier 1 -- Research agents (dynamic):** Scan `agents/research/*.md`. For each `.md` file, read YAML frontmatter to extract `name` and `description`.

**Tier 2 -- Review agents (selective):** Scan `agents/review/*.md`. Only dispatch review agents when the complexity is Deep and the agent's description matches the task domain (e.g., architecture-strategist for structural changes, security-audit for auth/security tasks).

**Tier 3 -- Project and user agents:** Scan `.claude/agents/*.md` and `~/.claude/agents/*.md`. Dispatch any whose `description` matches the task domain.

Agent identifiers use `quiver:{name}` for plugin agents, bare `{name}` for project/user agents.

## Step 3 -- Parallel Agent Dispatch

Spawn all qualifying agents simultaneously using multiple Agent tool calls in a single response. Every agent prompt must be **self-contained** -- agents have zero memory of this conversation.

**Review-fix plans: reduced dispatch.** If Step 1 detected review-fix context, the review report already identified the problems and affected files. Skip best-practices-researcher and architecture-strategist -- they add no value when the scope is "fix these specific findings." Dispatch only the Explore agent to verify file paths and current patterns are still accurate.

### Explore Agent (always dispatched)

```
Agent(
  subagent_type="Explore",
  description="Map codebase for planning: {short task summary}",
  prompt="Task: {full task description from Step 1}

  Search this codebase for all files related to this task. For each file found, report:
  1. File path
  2. One-line description of its role
  3. Whether it has associated test files

  Also report:
  - Current patterns used in this area (naming, structure, abstractions)
  - Any existing utilities or helpers that could be reused
  - Test framework and conventions observed

  Focus on directories: {relevant dirs if known, otherwise 'scan broadly'}",

)
```

### best-practices-researcher (Standard + Deep)

```
Agent(
  subagent_type="quiver:best-practices-researcher",
  description="Research best practices for: {short topic}",
  prompt="Task context: {full task description}

  The project uses:
  - Languages: {detected from project files}
  - Frameworks: {detected}
  - Key libraries: {detected}

  Research current best practices specifically for: {the technical areas the task touches, e.g., 'authentication middleware in Express', 'database migration patterns in Rails'}

  Focus on:
  1. Recommended patterns for this type of work
  2. Any deprecations or breaking changes in the detected stack versions
  3. Common pitfalls to avoid
  4. Framework-specific conventions that apply

  Keep findings actionable -- each recommendation should be something that can inform a plan step.",

)
```

### architecture-strategist (Deep only)

```
Agent(
  subagent_type="quiver:architecture-strategist",
  description="Analyze architecture for: {short task summary}",
  prompt="Task context: {full task description}

  Project root listing:
  {ls output of project root}

  Analyze the existing architecture and assess how this planned change should integrate. Report:
  1. Current architectural patterns (layer boundaries, dependency direction, module organization)
  2. Where new code should live to follow existing conventions
  3. Boundary constraints -- which layers must not be violated
  4. Structural risks of the proposed change
  5. Dependency implications

  Do NOT review existing code quality. Focus strictly on where and how the new work fits the architecture.",

)
```

### Domain-specific agents (when discovered and relevant)

If agent discovery found project/user agents whose description matches the task domain, dispatch them with the same self-contained prompt pattern.

## Step 4 -- Synthesize Research

After **all** agents return, merge findings into a unified research brief:

1. **Deduplicate** -- If multiple agents report the same file or pattern, keep the most detailed version.
2. **Organize:**
   - **Codebase context** (from Explore): affected files, current patterns, test coverage
   - **Best practices** (from best-practices-researcher): recommended approaches, deprecation alerts
   - **Architectural guidance** (from architecture-strategist): structural constraints, where new code belongs
3. **Flag conflicts** -- If agents disagree (e.g., best practices suggest pattern A but existing architecture uses pattern B), surface both with trade-offs. Do not silently resolve.

## Step 5 -- Design the Plan

Using the synthesized research, draft the plan following this document structure and detail level rules:

| Level | Complexity | Sections |
|-------|-----------|----------|
| **Brief** | Light | Goal, Steps, Acceptance Criteria |
| **Standard** | Standard | + Context (with agent findings), Risks, File Map |
| **Comprehensive** | Deep | + Alternatives Considered, Phased Rollout, Rollback Strategy, Architectural Constraints |

**Task granularity:**
- Each step: 2-10 minutes, independently verifiable
- Pattern: what to do, which file(s), expected outcome
- Include exact file paths from Explore findings
- Incorporate best practices into step design
- Respect architectural boundaries from architecture-strategist

**Research integration (mandatory):**
- If best-practices-researcher flagged a deprecation, the plan must avoid the deprecated pattern
- If architecture-strategist identified boundary constraints, steps must respect them
- If Explore found existing test patterns, new test steps must follow them
- Attribute findings in Context section: "(from best-practices-researcher)", "(from architecture-strategist)"

**Review-fix plan frontmatter (when review-fix context detected in Step 1):**

Include these fields in the plan's YAML frontmatter:
```yaml
review_source: .claude/reports/review-YYYY-MM-DD_HH-MM-SS.md
review_iteration: 1  # increments for each fix plan targeting the same review
```

**Acceptance Criteria are mandatory for review-fix plans.** Derive them directly from the review findings:
- One criterion per in-scope finding (e.g., "ProductBackButton root widget is Material, not Positioned")
- Add a verification criterion (e.g., "flutter analyze passes clean")
- These criteria become the Definition of Done -- the work skill uses them to determine when the review-fix cycle is COMPLETE and to prevent infinite re-review loops

## Step 6 -- Review Gate

Present the full plan to the user. Then call the `AskUserQuestion` tool with these parameters:

- **question:** "Plan has {N} steps ({detail_level}). How would you like to proceed?"
- **header:** "Plan review"
- **multiSelect:** false
- **options:**
  1. label: "Approve" / description: "Looks good. Save the plan and choose next action."
  2. label: "Modify" / description: "I want to adjust some steps before saving."
  3. label: "Reject" / description: "Abandon this plan and take a different approach."

If the plan exceeds 15 steps, append to the question: " Consider splitting into sub-plans or phasing the work."

Handle each response:
- **Approve** -- move to Step 7. Do NOT stop after approval.
- **Modify** -- ask which steps to change, revise the plan, and re-present with `AskUserQuestion` again.
- **Reject** -- abandon the plan. **Stop here.**

## Step 7 -- Save and Follow-up

**This step has TWO mandatory parts. Do NOT stop after saving.**

**Part A -- Save the plan:**

1. Create `.claude/plans/` if it does not exist.
2. Write the plan as `.claude/plans/YYYY-MM-DD-<descriptive-name>-plan.md` (use `date '+%Y-%m-%d'` for the date prefix).
3. **Verify:** Read the file back and confirm it was written correctly.

**Part B -- Present follow-up options:**

Immediately after saving, call `AskUserQuestion` with these exact parameters:

- **question:** "Plan saved to `.claude/plans/{filename}`. What would you like to do next?"
- **header:** "Next step"
- **multiSelect:** false
- **options:**
  1. label: "Start implementation" / description: "Invoke the work skill and execute the plan step by step in the current context."
  2. label: "Refine plan" / description: "Re-enter Step 5 to adjust steps, scope, or details."
  3. label: "Save and revisit later" / description: "Stop here. The plan is saved on disk for later."

You MUST call the `AskUserQuestion` tool -- do not skip it, do not present follow-up options as plain text.

Handle each response:

- **Start implementation** -- invoke the `work` skill with the saved plan path.
- **Refine plan** -- re-enter Step 5 to adjust.
- **Save and revisit later** -- stop here.

---

## Anti-Patterns

- **Don't** skip the confirmation gate -- always wait for user approval before saving.
- **Don't** start writing implementation code -- this command plans only.
- **Don't** run agents sequentially -- always dispatch independent agents in parallel (multiple Agent tool calls in one response).
- **Don't** send vague prompts to agents -- every prompt must include the full task description, relevant file paths, and expected output format.
- **Don't** ignore agent findings -- if an agent flags a deprecation or boundary constraint, the plan must address it.
- **Don't** create plans for tasks the user wants done immediately -- ask first.

## Verification

After saving the plan file:
1. Read the file back to confirm contents.
2. Confirm the plan directory exists and the file is listed.
