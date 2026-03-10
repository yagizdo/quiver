---
name: plan
description: "Agent-orchestrated planning methodology that dispatches parallel research agents before designing implementation steps. Use when implementing features, fixing multi-file bugs, refactoring, or any task that benefits from thinking before coding."
---

# Plan

Transform a task description into a structured, step-by-step implementation plan. The planning process dispatches research agents in parallel to gather codebase context, best practices, and architectural insights before designing steps. Plans are saved to disk, reviewed before execution, and serve as the single source of truth for the work session.

**Announce:** "Using the plan skill to create an implementation plan."

---

## When to Use

- Starting a new feature or significant enhancement
- Multi-file refactoring or architectural changes
- Bug fixes that touch 3+ files or span multiple layers
- Any task where the user says "plan", "break this down", or "how should we approach this"

## When NOT to Use

- Single-file edits with obvious changes
- Typo fixes, config tweaks, or dependency bumps
- Tasks the user explicitly wants done immediately without planning

---

## Workflow

```
+-----------+     +---------------+     +-----------+     +----------+     +----------+
| 1. SCOPE  | --> | 2. AGENT RECON| --> | 3. DESIGN | --> | 4. REVIEW| --> | 5. SAVE  |
| Clarify   |     | Parallel dispatch   | Draft plan|     | Confirm  |     | Write    |
+-----------+     +---------------+     +-----------+     +----------+     +----------+
```

### Phase 1: Scope

Restate the task in your own words. Identify:

1. **Goal** -- What does "done" look like? One sentence.
2. **Boundaries** -- What is in scope and what is explicitly out of scope.
3. **Unknowns** -- List anything ambiguous. If there are critical unknowns, ask ONE clarifying question and wait. Do not ask more than one question at a time.
4. **Complexity assessment** -- Classify as Light, Standard, or Deep (used to determine agent dispatch in Phase 2).

| Complexity | Signals | Agent Dispatch |
|------------|---------|----------------|
| **Light** | 1-3 files, single layer, well-understood area | Explore only |
| **Standard** | 3-10 files, 2+ layers, moderate unknowns | Explore + best-practices-researcher |
| **Deep** | 10+ files, architectural impact, security/payments/auth, unfamiliar domain | Explore + best-practices-researcher + architecture-strategist |

If the task is trivial (single file, obvious change), tell the user a full plan is unnecessary and offer to proceed directly. **Stop here** if they agree.

### Phase 2: Agent Recon

This is the core research phase. Dispatch agents in parallel based on the complexity assessment from Phase 1.

#### 2a -- Discover Available Agents

Scan agent directories to build the agent registry:

1. **Plugin agents:** Glob `agents/**/*.md` -- read YAML frontmatter for `name` and `description`.
2. **Project agents:** Glob `.claude/agents/*.md` -- same parsing.
3. **User agents:** Glob `~/.claude/agents/*.md` -- same parsing.

Agent identifiers use `quiver:{name}` for plugin agents. Project/user agents use bare `{name}`.

#### 2b -- Parallel Agent Dispatch

Spawn qualifying agents simultaneously using multiple Agent tool calls in a single response. Every agent prompt must be **self-contained** -- include the task description, relevant file paths, project context, and expected output format.

**Explore Agent** (always dispatched):

Purpose: Map the codebase area affected by the task.

Prompt must include:
- The task goal from Phase 1
- Directories/patterns to scan
- Request for: affected file paths, current patterns, test coverage, related utilities

Expected output: structured list of relevant files with one-line descriptions, current patterns observed, test file locations.

**best-practices-researcher** (dispatched for Standard and Deep):

Purpose: Gather framework-specific guidance and current best practices via context7.

Prompt must include:
- The task description
- Detected tech stack (language, framework, key libraries)
- Specific areas where best practices are needed (e.g., "authentication middleware patterns", "database migration strategies")

Expected output: best practices relevant to the task, deprecation warnings, recommended patterns.

**architecture-strategist** (dispatched for Deep only):

Purpose: Analyze the existing architecture and assess how the planned changes fit.

Prompt must include:
- The task description
- Project root file listing (`ls` output)
- Key structural files identified by Explore (if running sequentially) or broad scope hints
- Request for: current architectural patterns, boundary analysis, dependency direction, recommendations for where new code should live

Expected output: architecture context bullets, structural recommendations, risk areas.

**Custom agents** (dispatched when discovered and relevant):

If discovery finds project or user agents whose `description` matches the task domain, dispatch them in parallel alongside the standard agents. Include the same self-contained context.

#### 2c -- Synthesize Research

After all agents return, merge their findings into a unified research brief:

1. **Deduplicate** -- If multiple agents report the same file or pattern, keep the most detailed version.
2. **Organize by category:**
   - Codebase context (from Explore): affected files, current patterns, test coverage
   - Best practices (from best-practices-researcher): recommended approaches, deprecation alerts
   - Architectural guidance (from architecture-strategist): structural constraints, boundary rules, where new code belongs
3. **Flag conflicts** -- If agents disagree (e.g., best practices suggest pattern A but existing architecture uses pattern B), surface both with trade-offs. Do not silently resolve.

This research brief feeds directly into Phase 3 as the plan's Context section.

### Phase 3: Design

Draft the plan using the format defined in [Plan Document Structure](#plan-document-structure). Choose a detail level based on the complexity assessment:

| Level | When | Content |
|-------|------|---------|
| **Brief** | Light complexity, 1-3 files | Goal, steps, acceptance criteria |
| **Standard** | Standard complexity, moderate scope | + context, risks, file map, dependencies, best practices applied |
| **Comprehensive** | Deep complexity, architecture changes | + alternatives considered, phased rollout, rollback strategy, architectural constraints |

**Task granularity rules:**
- Each step should be completable in 2-10 minutes
- Each step should be independently verifiable (test, visual check, or command output)
- Steps follow the pattern: what to do, which file(s), expected outcome
- Include exact file paths (sourced from Explore agent findings)
- Order steps so each builds on the last -- never reference a step that hasn't happened yet
- Incorporate best practices and architectural guidance from Phase 2 into step design

**Research integration rules:**
- If best-practices-researcher flagged a deprecation, the plan must avoid the deprecated pattern and note the alternative
- If architecture-strategist identified boundary constraints, steps must respect them
- If Explore found existing test patterns, new test steps must follow the same patterns
- Reference agent findings in the Context section with attribution: "(from best-practices-researcher)", "(from architecture-strategist)"

### Phase 4: Review

Present the plan to the user and **wait for explicit confirmation** before proceeding. Do not write the plan file or start implementation until the user approves.

The user may:
- **Approve** ("yes", "looks good", "proceed") -- move to Phase 5
- **Modify** ("change step 3 to...", "add a migration step") -- revise and re-present
- **Reject** ("different approach", "let's not plan this") -- abandon the plan
- **Ask questions** -- answer, then re-present if the plan changed

If the plan exceeds 15 steps, flag this to the user: "This plan has {N} steps. Consider splitting into sub-plans or phasing the work."

### Phase 5: Save

Write the plan to disk at the project's plan directory:

```
.claude/plans/YYYY-MM-DD-<descriptive-name>-plan.md
```

Create the `.claude/plans/` directory if it does not exist.

**Verify:** Read the file back and confirm it was written correctly.

After saving, present follow-up options via `AskUserQuestion`:

> Plan saved to `{plan_path}`. What would you like to do?

Buttons: `["Start implementation", "Clear context and start working", "Refine further", "Save and revisit later"]`

- **Start implementation** -- invoke the `work` skill and execute the plan step by step in the current context.
- **Clear context and start working** -- instruct the user to clear context and start fresh. Output:
  > Plan saved. To start with a clean context, run these two commands:
  > 1. `/clear`
  > 2. `/quiver:work {plan_path}`
  >
  > This frees up all tokens used during planning. The plan is safely stored on disk.
- **Refine plan** -- re-enter Phase 3 to adjust steps, scope, or details.
- **Save and revisit later** -- stop here.

---

## Plan Document Structure

Every plan file uses this format:

```markdown
---
goal: "<one-line goal>"
type: feat | fix | refactor | chore
status: draft | active | completed | abandoned
date: YYYY-MM-DD
complexity: light | standard | deep
agents_consulted:
  - <agent-name>
---

# <Plan Title>

## Goal

<1-2 sentences: what "done" looks like>

## Context

### Codebase Analysis
<Bullet points from Explore agent: relevant files, current patterns, test coverage>

### Best Practices
<Key findings from best-practices-researcher: recommended approaches, deprecation alerts>
(Omit if agent was not dispatched)

### Architectural Guidance
<Findings from architecture-strategist: structural constraints, boundary rules>
(Omit if agent was not dispatched)

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `path/to/file` | create / modify / delete | What changes and why |

## Steps

### Step 1: <Short title>

- **File(s):** `path/to/file`
- **Do:** <Specific action>
- **Verify:** <How to confirm this step worked>

### Step 2: <Short title>

...

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| <What could go wrong> | high / medium / low | <How to prevent or handle it> |

## Acceptance Criteria

- [ ] <Criterion 1>
- [ ] <Criterion 2>
```

**Rules for the document:**
- The `## Context` subsections are included based on which agents were dispatched
- The `## Risks` section is omitted for Brief plans
- The `## File Map` section is omitted when fewer than 3 files are involved
- Steps must be numbered sequentially with no gaps
- Each step's `Verify` line is mandatory -- never write a step without a way to check it
- The `agents_consulted` frontmatter field lists which agents contributed to the plan

---

## Anti-Patterns

- **Don't** start coding during planning -- the plan skill researches and documents only
- **Don't** write vague steps like "refactor the module" -- specify which files, which functions, what the result looks like
- **Don't** include time estimates -- focus on what needs doing, not how long it takes
- **Don't** plan beyond what was requested -- if the user asked to fix a bug, don't add a refactoring phase unless the bug requires it
- **Don't** save the plan without user confirmation -- Phase 4 (Review) is a hard gate
- **Don't** run agents sequentially when they can run in parallel -- always dispatch independent agents simultaneously
- **Don't** ignore agent findings -- if best-practices-researcher flags a deprecation, the plan must address it
- **Don't** send vague prompts to agents -- every agent prompt must be self-contained with task context, file paths, and expected output format

---

## Quality Gates

**BLOCKING** (fix before saving):
- Every step has a Verify line
- Goal is stated in one sentence, not a paragraph
- File paths are specific (no "somewhere in src/")
- Steps are ordered so dependencies flow forward
- Agent findings are reflected in the plan (not ignored)

**WARNING** (review but don't block):
- Plan exceeds 15 steps without phasing
- No risks identified for a Standard or Comprehensive plan
- Acceptance criteria are missing or trivially obvious
- Best practices agent was skipped for a Standard+ complexity task
