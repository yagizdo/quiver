---
name: work
description: "Execute a work plan or specification systematically -- read the plan, set up a branch, implement tasks with continuous testing, commit incrementally, and ship a PR. Use when you have a plan file, spec, or task list ready to execute."
argument-hint: "<plan file path or task description>"
disable-model-invocation: true
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
!`git status --short 2>/dev/null || echo "NO_GIT"`
```

---

# Work

Execute a work plan, specification, or task list systematically. The focus is on shipping complete features by understanding requirements quickly, following existing patterns, and maintaining quality throughout.

**Announce:** "Using the work skill to execute the plan."

**Before starting Phase 1**, use the Glob tool to gather plan context silently (do not show results to the user):
1. `.claude/plans/*.md` -- existing plans
2. `**/plans/*.md` (max depth 4) -- plans in other locations

Treat empty Glob results as "no plans found". Proceed regardless.

---

## When to Use

- A plan file exists in `.claude/plans/` (created by `/quiver:plan`)
- The user provides a specification, todo file, or task list to execute
- The user says "execute", "build this", "implement the plan", or "work on this"

## When NOT to Use

- The task needs planning first -- use `/quiver:plan` instead
- The task is a single-file edit that needs no coordination
- The user wants a code review -- use `/quiver:review`

---

## Workflow

```
+----------+     +---------+     +---------+     +---------+     +--------+
| 1. LOAD  | --> | 2. SETUP| --> | 3. BUILD| --> | 4. CHECK| --> | 5. SHIP|
| Read plan|     | Branch  |     | Execute |     | Quality |     | PR     |
+----------+     +---------+     +---------+     +---------+     +--------+
```

### Phase 0: Git Availability

If any gather-context block above returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch/commit context.`
Proceed to Phase 1. Treat all git-sourced fields (branch, log, diff, status) as empty. Skip branch creation in Phase 2, commit steps in Phase 3, and git-dependent actions in Phase 5.

### Phase 1: Load and Clarify

#### 1a -- Load the plan

**Case A: Path provided.** If `$ARGUMENTS` is a file path (ends in `.md` or contains `/`):
- Read that file as the work plan.
- Print: `> Executing plan: {plan filename} ({step count} steps) on branch {branch}`
- Proceed directly to Phase 1b. The user chose this plan explicitly -- no confirmation needed.

**Case B: No arguments.** If `$ARGUMENTS` is empty, collect all `.md` files from every `plans/` directory discovered by the Glob block above, plus the `.claude/plans/` listing.

- If exactly one plan exists across all directories, read it and use `AskUserQuestion`:
  > Found one plan: `{relative path}` (in `{directory}`)
  > **Goal:** {goal from plan}
  > **Steps:** {step count}
  Buttons: `["Execute this plan", "Other -- I'll provide a path or description"]`
- If multiple plans exist, present them via `AskUserQuestion` with full relative paths as buttons (most recent first), plus an `"Other -- I'll provide a path or description"` option. Show the directory in each label so the user can distinguish plans in different locations.
- If the user picks "Other", ask for a path or task description.

If no plans found:
> No plans found in any `plans/` directory. Usage:
> - `/work <path-to-plan.md>` -- execute a specific plan
> - `/work <plan-name>` -- search for a plan by name
> - `/work <task description>` -- work on a task directly
> - `/plan <task>` -- create a plan first

**Stop here.**

**Case C: Name or description provided.** If `$ARGUMENTS` is not a file path and is not empty:

1. **Discover plan files.** Read every `plans/` directory discovered by the Glob block. Combine with `.claude/plans/` listing.
2. **Match by filename.** Compare `$ARGUMENTS` against each plan file's stem (without `.md` extension):
   - **Exact match:** stem equals `$ARGUMENTS` (case-insensitive).
   - **Partial match:** stem contains `$ARGUMENTS` as a substring (case-insensitive).
3. **Rank and select.** Rank exact matches above partial matches.
   - **1 match** -- Read the plan file, print `> Executing plan: {filename} from {directory}`, proceed to Phase 1b. No confirmation needed.
   - **Multiple matches** -- Use `AskUserQuestion` to present candidates with full relative paths as button labels. Add a `"None of these -- treat as task description"` button.
   - **0 matches** -- Treat `$ARGUMENTS` as an inline task description. Print `> No matching plan found for "{$ARGUMENTS}". Treating as task description.` Proceed to Phase 1b with the description as the work specification.

#### 1b -- Review references

If the plan links to files, patterns, or prior research -- read those now. Understanding context before coding prevents rework.

#### 1c -- Detect review-fix plan

Check if this is a plan created to address review findings:
- **Primary**: Check plan YAML frontmatter for a `review_source` field (e.g., `review_source: .claude/reports/review-2026-03-10_14-30-00.md`).
- **Fallback**: Scan plan content for paths matching `.claude/reports/review-*.md` or `review-*_*-*-*.md`.
- If detected, read the review report file. If the file exists, note this as a **review-fix plan** and carry the parsed findings forward to Phase 4. If the file does not exist, warn: "Review report not found at {path}. Proceeding without review-aware verification."
- If no review reference detected, proceed normally.
- **Iteration tracking**: Read the plan's `review_iteration` frontmatter field (default: `1` if absent). If `review_iteration >= 2`, this is the **final iteration** -- Phase 4c verification is the only quality gate, and Phase 4d agent review is skipped unconditionally.

#### 1d -- Flag ambiguities

If the plan contains genuine contradictions (e.g., two steps that conflict, a referenced file that does not exist), note them. If the plan is clear, skip this step entirely -- do not invent ambiguities.

#### 1e -- Proceed or clarify

- **No plan found:** Ask the user what to work on.
- **Plan has contradictions** flagged in 1d: Ask about those specific contradictions only.
- **Plan is clear:** Move directly to Phase 2. Do NOT ask "should I proceed?", "are you sure?", "shall I start?", or any variation of confirmation. The user invoked `/work` with a plan -- that IS the approval. Summarizing the plan back and asking to continue is wasted time.

### Phase 2: Setup Environment

**If git is NOT available (Phase 0 detected `NO_GIT`):** Skip this phase entirely -- proceed to Phase 2.5.

Check the current branch:

```bash
git branch --show-current
```

**If already on a feature branch** (not main/master):
- Use `AskUserQuestion`:
  > You're on `{branch}`. Continue here or create a new branch?
  Buttons: `["Continue on {branch}", "Create new branch"]`
- If continuing, move to Phase 2.5.

**If on the default branch**, choose how to proceed:

| Option | When to use |
|--------|-------------|
| **New branch** | Default. `git checkout -b <meaningful-name>` from latest default branch. |
| **Worktree** | Parallel development or keeping default branch workspace clean. Use the `using-git-worktrees` skill if available. |
| **Stay on default** | Only with explicit user confirmation. Never commit to default branch without permission. |

Use a descriptive branch name based on the task (e.g., `feat/user-auth`, `fix/email-validation`).

### Phase 2.5: Orchestration Decision

After setting up the environment, determine the execution strategy.

1. **Count tasks.** Parse the plan and count top-level work units. A "task" is any top-level section that describes a discrete, independently completable piece of work -- regardless of heading format or label. Plans from other tools (e.g., superpowers, ce-plan, custom specs) use varied formats: numbered steps, heading sections, YAML lists, or markdown checklists. Count by semantic intent (one deliverable = one task), not by a specific markup convention.

2. **Announce the decision** to the user before proceeding:

```
Strategy: {sequential | parallel orchestration} ({N} tasks found)
Reason: {why -- e.g., "2 tasks, below parallel threshold" or "4 tasks with 2 independent groups"}
```

3. **Route by count:**

| Task Count | Strategy | Action |
|------------|----------|--------|
| **1-2** | Sequential | Proceed to Phase 3 (Build) as normal. No subagents. |
| **3+** | Parallel orchestration | Follow the orchestration procedure below. Skip Phase 3 entirely -- orchestration replaces it. |

4. **For 3+ tasks -- orchestration procedure:**
   Follow `skills/work/orchestrator.md` for the full procedure. In brief: parse tasks,
   resolve dependencies (explicit + file overlap), report the execution plan, dispatch
   one worktree-isolated subagent per task, collect results, merge in topological order,
   run post-merge tests, then proceed to Phase 4.

### Phase 3: Build

#### 3a -- Create task list

Break the plan into actionable tasks using TodoWrite. Each task should be:
- Specific and completable (not "refactor everything")
- Ordered by dependency (what must come first)
- Include testing tasks alongside implementation tasks

#### 3b -- Task execution loop

For each task in priority order:

1. Mark the task as `in_progress` in TodoWrite.
2. Read any files referenced by the task.
3. Look for similar patterns in the codebase -- match existing conventions exactly.
4. Implement the change.
5. Run relevant tests after the change. Fix failures immediately -- do not accumulate broken tests.
6. Mark the task as `completed` in TodoWrite.
7. If the plan document has checkboxes, update `- [ ]` to `- [x]` for the completed item.
8. Evaluate whether to commit (see incremental commits below).

#### 3c -- Incremental commits

After completing each task, decide whether to create a commit:

| Commit when... | Wait when... |
|----------------|-------------|
| A logical unit is complete (model, service, component) | Only a partial unit is done |
| Tests pass and the change is meaningful | Tests are failing |
| Switching contexts (backend to frontend, model to controller) | Change is pure scaffolding with no behavior |
| About to attempt risky or uncertain changes | Commit message would be "WIP" |

**Heuristic:** "Can I write a commit message that describes a complete, valuable change?" If yes, commit. If the message would say "WIP" or "partial", wait.

```
git add <specific files for this logical unit>
git commit -m "feat(scope): description of this unit"
```

Stage specific files -- avoid `git add .` to prevent accidental inclusions.

#### 3d -- Handling blockers

If you encounter a blocker (missing dependency, unclear requirement, failing infrastructure):
- **Stop immediately.** Do not guess or force through.
- Note the blocker in TodoWrite.
- Ask the user for clarification or guidance.
- Do not proceed past the blocked step until resolved.

### Phase 4: Quality Check

Before shipping, verify the work meets standards.

#### 4a -- Core checks (always run)

1. **Tests pass.** Run the project's test command (check CLAUDE.md or detect from project structure).
2. **Linting passes.** Run the project's lint command if one exists.
3. **All TodoWrite tasks marked completed.** No tasks left in progress.
4. **Code follows existing patterns.** No new conventions introduced unless the plan explicitly called for them.

#### 4b -- System-wide impact check

For non-trivial changes, pause and consider:

| Question | Action |
|----------|--------|
| What else fires when this runs? (callbacks, middleware, observers, hooks) | Trace two levels out from your change. Read the actual code. |
| Do tests exercise the real chain? | If every dependency is mocked, add at least one integration test using real objects. |
| Can failure leave orphaned state? | If state is persisted before an external call, test the failure path. |
| What other interfaces expose this? | Grep for the method/behavior in related classes. Add parity if needed. |

**Skip this check for:** leaf-node changes with no callbacks, no state persistence, no parallel interfaces. Purely additive changes (new helper, new partial) need only a quick scan.

#### 4c -- Review finding verification (review-fix plans only)

If Phase 1 identified this as a review-fix plan and the review report was successfully loaded:

1. **Parse findings.** Extract all non-filtered findings from the review report, grouped by severity (Critical, High, Medium, Low). Skip the `## Filtered Findings` section entirely.

2. **Map findings to plan steps.** For each finding, identify whether the plan had a corresponding task:
   - Match by file path referenced in the finding against files mentioned in plan steps.
   - Match by finding title/description against plan step descriptions.
   - Findings with no matching plan step are marked "Not in scope."

3. **Check addressed status.** For each in-scope finding:
   - Verify the referenced file was modified (check `git diff` for changes to that file).
   - Verify the corresponding TodoWrite task is marked `completed`.
   - If both conditions met: mark as **Addressed**.
   - If file not modified or task incomplete: mark as **Not addressed**.

4. **Cross-reference check.** Flag when a file modified to fix finding A is also referenced by finding B (potential regression area). Present these as notes, not blockers.

5. **Present verification summary:**

   ```
   ## Review Finding Verification
   | ID | Severity | Finding | Status | Notes |
   |----|----------|---------|--------|-------|
   | C1 | Critical | SQL injection in auth.py:42 | Addressed | File modified, task completed |
   | H1 | High     | Missing input validation | Addressed | File modified, task completed |
   | M1 | Medium   | Inconsistent error handling | Not in scope | No plan step for this finding |
   | L1 | Low      | Naming convention | Not addressed | File not modified |
   ```

6. **Apply gates:**
   - **BLOCKING**: Any Critical finding marked "Not addressed" (in-scope but not fixed). Use `AskUserQuestion`:
     > Critical review finding not addressed: {finding title}
     > Original finding: {finding text}
     Buttons: `["I've verified this is fixed", "Fix it now", "Skip -- not applicable"]`
   - **WARNING**: Any High/Medium/Low finding marked "Not addressed" (in-scope but not fixed). List in summary but do not block.
   - **INFO**: Findings marked "Not in scope." Listed for awareness only.

7. **Acceptance criteria check.** If the plan has an `Acceptance Criteria` section, verify each criterion:
   - For each criterion, check whether the implementation satisfies it (file exists, test passes, pattern applied, etc.).
   - Mark each as **Met** or **Not met** in the verification summary.
   - All criteria must be **Met** to proceed to Phase 5. If any are **Not met**, use `AskUserQuestion`:
     > Acceptance criterion not met: {criterion text}
     Buttons: `["Fix it now", "Skip -- criterion is outdated", "Mark as met (I've verified manually)"]`

8. **Convergence verdict.** After gates and acceptance criteria:
   - If all in-scope findings are **Addressed** AND all acceptance criteria are **Met**: the review-fix cycle is **COMPLETE**. Proceed to Phase 5. Do NOT trigger another review.
   - If `review_iteration >= 2`: the cycle is **COMPLETE** regardless of remaining Low/Medium warnings. Only unaddressed Critical findings can block. Proceed to Phase 5.
   - Present the convergence status:
     ```
     ## Review-Fix Cycle Status
     Iteration: {review_iteration} of 2 (max)
     Findings addressed: {addressed}/{total_in_scope}
     Acceptance criteria met: {met}/{total_criteria}
     Status: COMPLETE -- ready to ship
     ```

<!-- SYNC: This verification parses the report format defined in skills/review/SKILL.md:362 (Synthesized report structure section). If the report structure changes, update the parsing logic here. New sections (What's Working Well, Recommended Fix Order) are additive and do not affect this parsing. -->

#### 4d -- Optional: Agent-assisted review

**SKIP this phase entirely if this is a review-fix plan.** The Phase 4c verification is the quality gate for review-fix work. Dispatching review agents on review-fix changes creates infinite loops -- the agents will always find new issues that weren't in the original scope.

For **non-review-fix plans** with large, risky, or security-sensitive changes, consider dispatching review agents. Discover available review agents by scanning `agents/review/*.md` and dispatch them using the `orchestrate-agents` skill patterns.

**Do not use review agents by default.** Tests + linting + pattern-following is sufficient for most work. Reserve agent reviews for:
- Large refactors (10+ files) that are NOT review-fix plans
- Security-sensitive changes (auth, permissions, data access)
- Complex business logic or algorithms

### Phase 5: Ship

**If git is NOT available (Phase 0 detected `NO_GIT`):** Skip commit and PR steps. Summarize what was completed and remaining follow-ups, then stop.

**CRITICAL: Every git action in this phase requires explicit user confirmation via `AskUserQuestion`. NEVER commit, push, or create a PR without asking first.**

**NO ATTRIBUTION: Do not add `Co-Authored-By`, `Generated with Claude`, `Built with AI`, or any similar attribution lines to commit messages or PR descriptions. Keep them clean. Only add attribution if the user explicitly requests it.**

#### 5a -- Final commit

If there are uncommitted changes after Phase 4:

1. Stage the relevant files (specific files only -- never `git add .`):
   ```
   git add <relevant files>
   ```

2. Delegate to `/quiver:commit`. This skill generates a Conventional Commits message, presents it to the user via `AskUserQuestion` with Commit / Commit & Push / Edit / Cancel options, and only executes after the user explicitly chooses. It handles the full commit (and optional push) flow with built-in confirmation.

3. If the user cancelled the commit, respect that -- do not re-ask or proceed to 5b.

#### 5b -- Create PR

After committing (or if all commits were already made during Phase 3), ask the user what to do next. Do NOT push or create a PR without asking.

1. Use `AskUserQuestion`:
   > All work is committed on `{branch_name}`. What would you like to do next?
   Buttons: `["Create a pull request", "Done -- I'll handle the rest"]`

   - **Create a pull request** -- delegate to `/quiver:create-pr`. It handles push, title generation, body formatting, and confirmation.
   - **Done** -- stop here. Move to 5c.

#### 5c -- Update plan status

If the work document has YAML frontmatter with a `status` field, update it:
```
status: active  -->  status: completed
```

#### 5d -- Notify user

Summarize:
- What was completed
- Link to the PR (if one was created)
- Any follow-up work needed or remaining tasks

---

## Key Principles

### Start fast, finish completely

Get clarification once at the start, then execute. The goal is to finish the feature, not create perfect process. A shipped feature beats a perfect feature that does not ship.

### The plan is your guide

The plan references similar code and patterns for a reason. Read those references. Match what exists. Do not reinvent.

### Test as you go

Run tests after each change, not at the end. Fix failures immediately. Continuous testing prevents compounding surprises.

### Quality is built in

Follow existing patterns. Write tests for new code. Run linting before pushing. Do not bolt quality on at the end.

### Commit incrementally

Small, focused commits are easier to review, easier to revert, and easier to debug with `git bisect`. Each commit should tell a coherent story.

---

## Anti-Patterns

- **Don't** skip Phase 1 clarification -- ask now, not after building the wrong thing.
- **Don't** ignore plan references -- the plan has file paths and pattern links for a reason.
- **Don't** save all testing for the end -- test continuously or suffer compounding failures.
- **Don't** use `git add .` -- stage specific files to avoid accidental inclusions.
- **Don't** commit with "WIP" messages -- wait until a logical unit is complete.
- **Don't** force through blockers -- stop, note the issue, ask the user.
- **Don't** over-review simple changes -- save agent reviews for genuinely complex or risky work.
- **Don't** leave TodoWrite tasks unfinished -- track progress or lose track of what is done.
- **Don't** move on at 80% -- finish the feature before starting something new.
- **Don't** commit directly to the default branch without explicit user permission.
- **Don't** commit, push, or create a PR without asking the user first via `AskUserQuestion` -- every git action in Phase 5 requires explicit confirmation.
- **Don't** add AI attribution to commits or PRs (`Co-Authored-By`, `Generated with Claude`, etc.) unless the user explicitly asks for it.
- **Don't** trigger another review cycle after completing a review-fix plan -- Phase 4c verification is the terminal quality gate. Dispatching review agents on review-fix work creates infinite loops.
- **Don't** spawn subagents for 1-2 task plans -- the overhead exceeds the benefit. Use sequential execution.
- **Don't** skip dependency resolution -- always check both explicit `blockedBy` and file overlap before dispatching parallel agents.
- **Don't** attempt automatic merge conflict resolution -- report conflicts to the user and stop.
- **Don't** continue dispatching dependent tasks when a dependency has failed or is blocked.

---

## Quality Gates

**BLOCKING** (fix before shipping):
- All tests pass
- All TodoWrite tasks completed
- No uncommitted changes that belong to this work
- Plan checkboxes updated (if applicable)
- Post-merge test suite passes (when orchestration was used)
- All worktree branches merged successfully (no unresolved conflicts)

**WARNING** (review but do not block):
- Linting warnings present
- No integration tests for changes that touch callbacks or middleware
- Plan had acceptance criteria that were not explicitly verified (NOTE: for review-fix plans, acceptance criteria are BLOCKING per Phase 4c step 7)

---

## Test Plan

**Trigger:** `/work [plan-path | plan-name | task description]` (and `/quiver:work` should also work)

**Setup:**
- Current directory is a git repo with at least one plan in `.claude/plans/` or a related `plans/` directory.
- For the review-fix path: a plan with `review_source` frontmatter pointing at an existing `.claude/reports/review-*.md` file.

**Expected behavior:**
1. Skill runs the four git shell blocks plus the silent Glob over `.claude/plans/` and `**/plans/*.md`.
2. Phase 1 loads the plan via Case A (path), Case B (no args), or Case C (name match), printing the executing-plan banner before proceeding.
3. Phase 0 NO_GIT handling skips branch creation, commits, and PR steps cleanly when the directory is not a git repo.
4. Phase 2.5 announces `Strategy: sequential` for 1-2 tasks or `parallel orchestration` for 3+ tasks before continuing.
5. For review-fix plans, Phase 4c parses the report's findings (skipping `## Filtered Findings`), runs the verification table, applies the BLOCKING/WARNING gates, and prints the convergence verdict; Phase 4d is skipped automatically.
6. Phase 5 delegates commit and PR creation to `/quiver:commit` and `/quiver:create-pr`, gating each git action with `AskUserQuestion` and never adding AI attribution.

**Verification checklist:**
- [ ] Slash menu shows `/work`.
- [ ] Plan banner is printed before any code changes (`> Executing plan: <name>`).
- [ ] Orchestration decision line appears for every plan, including 1-2 task plans.
- [ ] In a non-git directory, the skill still loads the plan and runs Phase 3-4 but exits at Phase 5 without commit/PR.
- [ ] Review-fix plans produce the verification table and convergence verdict; non-review-fix plans skip Phase 4c entirely.
- [ ] Final commit and PR steps both go through `AskUserQuestion`; the skill never auto-pushes.

**Known gotchas:**
- Phase 4c parses the synthesized report format produced by the review skill; the SYNC comment near the verification block must stay paired with the matching marker in `skills/review/SKILL.md`.
- For 3+ task plans the orchestrator (`skills/work/orchestrator.md`) replaces Phase 3; do not run Phase 3's TodoWrite loop in addition to it.
- `git add .` is banned anywhere in this skill; agents reading the plan must stage explicit file paths.
