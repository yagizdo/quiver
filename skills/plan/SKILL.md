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

   **Rules:** Use `AskUserQuestion` with codebase-derived buttons (never plain text). Include "Other" as last option. At most ONE question -- skip if task is clear.

4. **Assess complexity:**

| Complexity | Signals | Agents to Dispatch |
|------------|---------|-------------------|
| **Light** | 1-3 files, single layer, well-understood | code-locator |
| **Standard** | 3-10 files, 2+ layers, moderate unknowns | code-navigator + best-practices-researcher |
| **Deep** | 10+ files, architectural impact, security/auth/payments, unfamiliar domain | code-navigator + best-practices-researcher + architecture-strategist |

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

## Step 2.5 -- Navigation Detection

Before dispatching agents, detect navigation capabilities once.

**CodeGraph:** Check if `.codegraph/` exists at project root. Set `codegraph_available` to `true` or `false`. No user prompt.

**LSP:** Follow the detection flow from the `code-navigation` skill:

1. Check project memory for a cached LSP preference (`lsp_preference.md`). If `lsp_declined` or `lsp_confirmed` is found, use the cached value and skip to step 4.
2. Attempt a lightweight LSP probe (e.g., `documentSymbol` on any source file from the project root).
3. If LSP is not available, detect the project language from manifest files and use `AskUserQuestion` to suggest installation:
   > LSP is not available for this project. Installing a language server (e.g., {recommended_server} for {language}) would enable better code navigation -- go-to-definition, find-references, and symbol search. Would you like to set it up? (You can always use /plan without it -- grep-based navigation works fine.)

   Buttons: `["Yes, help me set it up", "No, continue with grep"]`

   - If user accepts: provide installation instructions, re-probe, cache `lsp_confirmed` in project memory.
   - If user declines: cache `lsp_declined` in project memory.
4. Set `lsp_available` to `true` or `false`. Pass both `codegraph_available` and `lsp_available` to all agents dispatched in Step 3.

## Step 3 -- Parallel Agent Dispatch

Spawn all qualifying agents simultaneously using multiple Agent tool calls in a single response. Every agent prompt must be **self-contained** -- agents have zero memory of this conversation.

**Review-fix plans: reduced dispatch.** If Step 1 detected review-fix context, the review report already identified the problems and affected files. Skip best-practices-researcher and architecture-strategist -- they add no value when the scope is "fix these specific findings." Dispatch only the code-locator agent to verify file paths and that current locations are still accurate.

### code-locator Agent (Light + review-fix verify)

```
Agent(
  subagent_type="quiver:code-locator",
  description="Locate files for planning: {short task summary}",
  prompt="Task: {full task description from Step 1}

  codegraph_available: {true|false from Step 2.5}
  lsp_available: {true|false from Step 2.5}

  Locate all files related to this task. For each file found, report:
  1. File path and line (if a specific symbol is the entry point)
  2. One-line description of its role
  3. Whether it has an associated test file

  Surface the locator's table verbatim; do not re-summarize it.",

)
```

### code-navigator Agent (Standard + Deep)

```
Agent(
  subagent_type="quiver:code-navigator",
  description="Map codebase for planning: {short task summary}",
  prompt="Task: {full task description from Step 1}

  codegraph_available: {true|false from Step 2.5}
  lsp_available: {true|false from Step 2.5}

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
   - **Codebase context** (from code-navigator): affected files, current patterns, test coverage
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

**File structure mapping (before defining tasks):**
Map out which files will be created, modified, or deleted. This locks in decomposition decisions before task writing begins.
- Create: `exact/path/to/new-file.ext` -- one-line purpose
- Modify: `exact/path/to/existing.ext` -- what changes and why
- Test: `tests/path/to/test-file.ext` -- which test files are new or updated
- Delete: `exact/path/to/removed.ext` -- only if applicable

**Task granularity:**
- Each step: 2-10 minutes, independently verifiable
- Pattern: what to do, which file(s), expected outcome
- Include exact file paths from code-navigator findings
- Incorporate best practices into step design
- Respect architectural boundaries from architecture-strategist

**TDD task structure (when the project has tests):**
If the code-navigator agent found an existing test framework, structure each task following the TDD cycle:
1. Write the failing test (show exact test code)
2. Run the test -- confirm it fails with the expected error
3. Write the minimal implementation to make it pass
4. Run the test -- confirm it passes
5. Commit

Not every task requires TDD (e.g., config changes, docs, migrations). Apply it to tasks that produce testable behavior.

**No placeholders rule:** Every step must have actionable content. Never write: "TBD"/"TODO"/"implement later", "add appropriate handling"/"handle edge cases", "similar to Task N" (repeat details), "write tests" without scenarios, steps without file paths or expected outcomes, references to undefined symbols.

**Language rule:** Always write plan documents in English, regardless of the conversation language. Only write in another language if the user explicitly requests it.

**Research integration (mandatory):**
- If best-practices-researcher flagged a deprecation, the plan must avoid the deprecated pattern
- If architecture-strategist identified boundary constraints, steps must respect them
- If code-navigator found existing test patterns, new test steps must follow them
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

## Step 6 -- Plan Guard: Inline Validation

After drafting the plan, run these 6 checks before presenting to the user. This is an internal quality gate -- do not show it as a separate section to the user.

### Check 1: Placeholder scan

Search the plan for: "TBD", "TODO", "implement later", "fill in details", "add appropriate", "handle edge cases", "similar to Task N", raw `{...}` template text, and steps without file paths or expected outcomes. Replace every match with concrete content. (FIX)

### Check 2: Naming consistency

Extract all symbol names (functions, types, variables, file names) from every task. Flag any symbol appearing in 2+ tasks with different spellings. Normalize to the first-used spelling. (FIX)

### Check 3: Spec coverage (bidirectional)

If the plan has a brainstorm spec reference (Context section referencing `docs/brainstorms/*.md`) or a review source (frontmatter `review_source`), read the source and verify:
- **Forward:** each spec requirement maps to at least one plan task. Add a task for any gap. (ADD)
- **Reverse:** each plan task maps to a spec requirement or explicit infrastructure need. Flag tasks that do not trace back. (NOTE -- potential scope creep)

### Check 4: Task granularity

Flag tasks that: modify more than 3 files, have more than 5 sub-steps, lack an expected outcome, or reference no file paths. (NOTE)

### Check 5: Reference validity

Probe file paths mentioned in the plan:
- **Modify/Delete** targets must exist on disk. (FIX if missing)
- **Create** targets must NOT exist on disk. (NOTE if collision)
- Internal cross-references ("as defined in Task N") must resolve to an actual task. (FIX if dangling)

### Check 6: File map completeness

If the plan has a "File Map" section: every map entry must appear in at least one task, and every task file must appear in the map. (FIX for orphans, ADD for missing entries)

### Action routing

After running all 6 checks:
- **FIX:** auto-fix by editing the plan content inline.
- **ADD:** draft and insert missing content (tasks, acceptance criteria, file map entries).
- **REORDER:** move affected tasks to satisfy dependency ordering.
- **NOTE:** accumulate silently. If any NOTE findings exist, insert a `### Plan Guard Notes` subsection in the plan's Context section before the user sees the plan.

After applying fixes, proceed to Step 6.5. No re-run of checks. The human review gate (Step 7) is the convergence anchor.

## Step 6.5 -- Plan Guard: Agent Semantic Review

**Skip conditions (check in order -- if any match, proceed directly to Step 7):**
1. Complexity is **Light** (assessed in Step 1).
2. This is a **review-fix plan** (detected in Step 1 via review report reference).

If neither skip condition matches, dispatch the plan-reviewer agent:

### Agent dispatch

Spawn a single `quiver:plan-reviewer` agent with a self-contained prompt containing:

```
Agent(
  subagent_type="quiver:plan-reviewer",
  description="Semantic review of implementation plan",
  prompt="Review this implementation plan for logical coherence, dependency ordering,
  coverage completeness, and spec alignment.

  ## Plan

  {full plan content with Step 6 fixes already applied}

  ## Source Specification

  {spec content if available from the plan's Context section or spec_source frontmatter,
   otherwise: 'No source specification provided.'}

  ## Project Context

  {relevant directory listings for file paths mentioned in the plan}

  Report findings using the action taxonomy: FIX, ADD, REORDER, NOTE.
  If zero findings, state that explicitly.",
)
```

### Post-agent flow

1. Parse the agent's structured findings.
2. **Zero findings** -- proceed to Step 7.
3. **Findings exist** -- apply edits:
   - **FIX/ADD/REORDER:** edit the plan content inline.
   - **NOTE:** append to the `### Plan Guard Notes` subsection in the plan's Context section (create it if it does not exist from Step 6).
4. Do NOT re-dispatch the agent. One pass only. Proceed to Step 7.

## Step 7 -- Review Gate

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
- **Approve** -- move to Step 8. Do NOT stop after approval.
- **Modify** -- ask which steps to change, revise the plan, and re-present with `AskUserQuestion` again.
- **Reject** -- abandon the plan. **Stop here.**

## Step 8 -- Save and Follow-up

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

Follow all rules in `.claude/rules/skill-rules.md`. Additionally:

- **Don't** start writing implementation code -- this command plans only.
- **Don't** run agents sequentially -- always dispatch independent agents in parallel (multiple Agent tool calls in one response).
- **Don't** send vague prompts to agents -- every prompt must include the full task description, relevant file paths, and expected output format.
- **Don't** ignore agent findings -- if an agent flags a deprecation or boundary constraint, the plan must address it.
- **Don't** create plans for tasks the user wants done immediately -- ask first.

---

## Test Plan

**Trigger:** `/plan <task description>` (and `/quiver:plan` should also work)

**Setup:**
- Project root with optional `.claude/plans/` directory.
- For review-fix path: a `.claude/reports/review-*.md` file exists and is passed as the argument.

**Expected behavior:**
1. Skill gathers git context; on a non-git directory it continues with empty git fields and a warning line.
2. Skill restates the task and assesses complexity (Light / Standard / Deep) silently, dispatching the matched agents in parallel.
3. Skill detects review-fix context when the argument matches `.claude/reports/review-*.md` and adds `review_source` + `review_iteration` to the plan frontmatter.
4. Skill presents the synthesized plan and uses `AskUserQuestion` for the Step 7 review gate (`Approve` / `Modify` / `Reject`).
5. On `Approve`, skill saves the plan to `.claude/plans/YYYY-MM-DD-<name>-plan.md`, reads it back to verify, then invokes `AskUserQuestion` again for the Step 8 next-step gate.

**Verification checklist:**
- [ ] Slash menu shows `/plan`.
- [ ] Plan file is written under `.claude/plans/` with the date-prefixed filename.
- [ ] Multiple agents are dispatched in a single response when complexity is Standard or Deep (parallel execution).
- [ ] Review-fix detection produces frontmatter with `review_source` and `review_iteration`.
- [ ] No raw `{placeholder}` strings remain in the saved plan.
- [ ] The Step 7 and Step 8 user gates appear as `AskUserQuestion` calls, not plain-text prompts.
- [ ] Agent dispatch and Plan Guard checks execute correctly for Standard/Deep plans.
- [ ] Step 6.5 agent dispatch follows skip conditions (Light and review-fix plans skip).
- [ ] Plan Guard Notes subsection appears in the plan's Context section only when NOTE findings exist.
- [ ] `codegraph_available` flag detected and passed to agents when `.codegraph/` exists.
- [ ] Light and review-fix plans dispatch `quiver:code-locator`; Standard/Deep plans dispatch `quiver:code-navigator`.

**Known gotchas:**
- The code-navigator agent (`agents/research/code-navigator.md`) owns the Code Navigation Strategy. When updating the strategy in `skills/code-navigation/SKILL.md`, update the agent file too. `code-locator` (`agents/research/code-locator.md`) also copies this block -- update it there as well.
- `review_iteration` is determined by counting prior plans with the same `review_source` field; if naming conventions drift, the iteration count can desync.
