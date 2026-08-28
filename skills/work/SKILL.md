---
name: work
description: "Execute a work plan or specification systematically -- read the plan, set up a branch, implement tasks with continuous testing, commit incrementally, and ship a PR. Use when you have a plan file, spec, or task list ready to execute."
argument-hint: "<plan file path or task description>"
when-to-use: "user wants to execute a saved plan or implement tasks step by step -- '/work', 'start implementation', 'execute the plan', 'work through these tasks'"
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

**Use when:** a plan file exists, the user provides a spec or task list, or the user says "execute", "build this", "implement the plan". Use `/quiver:plan` first if no plan exists yet. Use `/quiver:review` for code review.

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

**If already on a feature branch** (not main/master), use `AskUserQuestion`:
> You're on `{branch}`. Continue here or create a new branch?
Buttons: `["Continue on {branch}", "Create new branch"]`
If continuing, move to Phase 2.5.

**If on the default branch**, create a new branch by default: `git checkout -b <meaningful-name>` using a descriptive name (e.g., `feat/user-auth`, `fix/email-validation`). Never commit to the default branch without explicit user confirmation.

### Phase 2.5: Orchestration Decision

Parse the plan and count top-level tasks (one deliverable = one task, regardless of markup format). Announce before proceeding:
```
Strategy: {sequential | parallel orchestration} ({N} tasks found)
Reason: {why}
```

- **1-2 tasks:** Sequential. Proceed to Phase 3. The ledger below is orchestration-path-only; the sequential path keeps TodoWrite unchanged and writes nothing to disk.
- **3+ tasks:** Parallel orchestration. Resolve the workspace and check for a ledger (below), then follow `skills/work/orchestrator.md`. Skip Phase 3 entirely -- orchestration replaces it.

#### Resolve the workspace

`<plan-basename>` is the loaded plan file's name without `.md`. The workspace is `.claude/work/<plan-basename>/` and the ledger is `.claude/work/<plan-basename>/progress.md`.

Any path that reaches Phase 2.5 without a plan file has no plan basename -- Phase 1 Case B's "Other -- I'll provide a path or description" and Case C with 0 matches both do. Derive one instead of proceeding without it: slugify the task description to at most 40 characters and use `.claude/work/adhoc-<slug>/`. The workspace and ledger are otherwise identical, and the identity line names the task description in place of a plan file path. The orchestrator requires a workspace for every run -- every dispatch step writes to one. Name the derived workspace in the strategy line.

#### Check for a ledger

Read `.claude/work/<plan-basename>/progress.md`. Its first line is the identity line, exactly one:

```
# work ledger -- plan: <full plan file path>
```

Apply these rules, which restate `skills/work/orchestrator.md` Section 0:

| State | Action |
|-------|--------|
| No file, or a file whose first line is not a `# work ledger -- plan:` identity line | Fresh run. Create the directory if needed, overwrite the file with the identity line. Do not suffix -- a directory with no identity claims no plan. |
| First line names this plan file, and every completion line's task number and title match the plan | Resumable. Do not re-dispatch any task carrying a `Task <N> [<task title>]: complete (branch <branch>, commits <base7>..<head7>)` line. Merge a completed task's branch unless a `Task <N>: merged` line also exists for it -- a `complete` line records that the work was done, not that it landed. A complete line reading `commits none` has no branch to merge. Resume dispatch at the first task with no matching `complete` line. |

For a ledger naming a different plan file, or a completion line whose title no longer matches the plan, `skills/work/orchestrator.md` Section 0 "Resume rules" is authoritative -- follow it there and print the line it requires.

#### Announce

When tasks are skipped:
> Resuming from ledger: skipping Task 1, Task 2 (already complete).

When the ledger is stale:
> Plan changed since the last run -- starting fresh.

When a suffixed workspace is used:
> A ledger for a different plan already uses that name -- using .claude/work/<name>-2/.

### Phase 3: Build

Break the plan into TodoWrite tasks (specific, dependency-ordered, with testing tasks included). For each task: mark `in_progress`, read referenced files, match existing patterns, implement, run tests immediately (fix failures before moving on), mark `completed`, update plan checkboxes if present.

**Commits:** After each logical unit, commit if tests pass and the change is meaningful (`git add <specific files>` -- never `git add .`). Wait if tests fail or the message would say "WIP". Heuristic: "Can I write a message describing a complete, valuable change?"

**Blockers:** Stop immediately. Note in TodoWrite. Ask the user. Do not proceed until resolved.

### Phase 4: Quality Check

Before shipping, verify the work meets standards.

#### 4a -- Core checks (always run)

1. **Tests pass.** Run the project's test command (check CLAUDE.md or detect from project structure).
2. **Linting passes.** Run the project's lint command if one exists.
3. **All TodoWrite tasks marked completed.** No tasks left in progress.
4. **Code follows existing patterns.** No new conventions introduced unless the plan explicitly called for them.
5. **No uncommitted changes** that belong to this work.
6. **Plan checkboxes updated** (if applicable).
7. **Post-merge test suite passes** (when orchestration was used); all worktree branches merged with no unresolved conflicts.

**These are BLOCKING -- fix all before proceeding to Phase 5.**

#### 4b -- System-wide impact check

For non-trivial changes, pause and consider:

| Question | Action |
|----------|--------|
| What else fires when this runs? (callbacks, middleware, observers, hooks) | Trace two levels out from your change. Read the actual code. |
| Do tests exercise the real chain? | If every dependency is mocked, add at least one integration test using real objects. |
| Can failure leave orphaned state? | If state is persisted before an external call, test the failure path. |
| What other interfaces expose this? | Grep for the method/behavior in related classes. Add parity if needed. |

**Skip this check for:** leaf-node changes with no callbacks, no state persistence, no parallel interfaces. Purely additive changes (new helper, new partial) need only a quick scan.

**WARNING (review but do not block):** linting warnings present; no integration tests for changes touching callbacks or middleware; plan acceptance criteria not explicitly verified (NOTE: for review-fix plans, acceptance criteria are BLOCKING per Phase 4c step 6).

#### 4c -- Review finding verification (review-fix plans only)

If Phase 1 identified this as a review-fix plan and the review report was successfully loaded:

1. **Parse findings.** Extract all non-filtered findings from the review report, grouped by severity (Critical, High, Medium, Low). Skip the `## Filtered Findings` section entirely.

2. **Map findings to plan steps.** Match each finding to a plan task by file path or title/description. Findings with no matching plan step are marked "Not in scope."

3. **Check addressed status.** For each in-scope finding, verify the referenced file was modified (`git diff`) and the corresponding TodoWrite task is `completed`. Both conditions met = **Addressed**; otherwise = **Not addressed**.

4. **Cross-reference check.** Flag when a file modified to fix finding A is also referenced by finding B (potential regression area). Present these as notes, not blockers.

5. **Present verification summary** as a table with columns: ID, Severity, Finding, Status, Notes. Then apply gates:
   - **BLOCKING**: Any Critical finding marked "Not addressed." Use `AskUserQuestion`:
     > Critical review finding not addressed: {finding title}
     > Original finding: {finding text}
     Buttons: `["I've verified this is fixed", "Fix it now", "Skip -- not applicable"]`
   - **WARNING**: Any High/Medium/Low finding marked "Not addressed." List in summary but do not block.
   - **INFO**: Findings marked "Not in scope." Listed for awareness only.

6. **Acceptance criteria check.** If the plan has an `Acceptance Criteria` section, mark each criterion as **Met** or **Not met**. If any are **Not met**, use `AskUserQuestion`:
   > Acceptance criterion not met: {criterion text}
   Buttons: `["Fix it now", "Skip -- criterion is outdated", "Mark as met (I've verified manually)"]`
   All criteria must be **Met** to proceed to Phase 5.

7. **Convergence verdict.** If all in-scope findings are **Addressed** AND all acceptance criteria are **Met**, the review-fix cycle is **COMPLETE** -- proceed to Phase 5, do NOT trigger another review. If `review_iteration >= 2`, the cycle is **COMPLETE** regardless of remaining Low/Medium warnings; only unaddressed Critical findings can block. Print:
   ```
   Review-Fix Cycle Status: Iteration {review_iteration} | Findings {addressed}/{total_in_scope} | Criteria {met}/{total_criteria} | COMPLETE
   ```

<!-- SYNC: This verification parses the report format defined in skills/review/SKILL.md:367 (Synthesized report structure section). If the report structure changes, update the parsing logic here. New sections (What's Working Well, Recommended Fix Order, Senior Assessment) are additive and do not affect this parsing. -->

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

**NO ATTRIBUTION: Do not add `Co-Authored-By`, `Generated with Claude`, `Built with AI`, or any similar attribution lines to commit messages or PR descriptions. Only add attribution if the user explicitly requests it.**

#### 5a -- Final commit

If there are uncommitted changes after Phase 4, stage the relevant files (specific files only -- never `git add .`) then delegate to `/quiver:commit`. If the user cancels, do not re-ask or proceed to 5b.

#### 5b -- Create PR

After committing (or if all commits were already made during Phase 3), use `AskUserQuestion`:
> All work is committed on `{branch_name}`. What would you like to do next?
Buttons: `["Create a pull request", "Done -- I'll handle the rest"]`

- **Create a pull request** -- delegate to `/quiver:create-pr`.
- **Done** -- stop here. Move to 5c.

#### 5c -- Update plan status

If the work document has YAML frontmatter with a `status` field, update it:
```
status: active  -->  status: completed
```

#### 5c-bis -- Clean up the orchestration workspace

Runs only when orchestration was used, every task reached DONE, and Phase 4a check 7 passed. A run that ends blocked, failed, or cancelled skips this step entirely -- the surviving directory is what makes the retry cheap, and deleting it throws away the resume.

1. Resolve `<workspace-dir>` to the directory this run actually used -- the suffixed one (`-2`, `-3`) if the orchestrator's suffix-retry rule fired, otherwise `.claude/work/<plan-basename>/`. Confirm `<workspace-dir>` exists and that its `progress.md` first line names this plan file. If either check fails, delete nothing and say so -- the directory belongs to a different run. Never re-derive the path from `<plan-basename>` after this step.
2. Name `<workspace-dir>` and its file count, then gate the delete on `AskUserQuestion`:
   > Orchestration finished and the work is committed. Delete the run workspace at `<workspace-dir>` ({N} files)?
   Buttons: `["Delete it", "Keep it"]`
   On "Keep it", print one line saying it was kept and continue to 5d.
3. On "Delete it", remove `<workspace-dir>` -- the exact path confirmed in step 1 and shown in step 2, no other -- then re-list `.claude/work/` to confirm it is gone, and name what was deleted in the 5d summary.

#### 5d -- Notify user

Summarize:
- What was completed
- Link to the PR (if one was created)
- Any follow-up work needed or remaining tasks

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
- **Don't** skip dependency resolution -- check both explicit `blockedBy` and file overlap before dispatching parallel agents; stop dispatching dependent tasks when a dependency fails.
- **Don't** attempt automatic merge conflict resolution -- report conflicts to the user and stop.

---

## Test Plan

**Trigger:** `/work [plan-path | plan-name | task description]` (and `/quiver:work` should also work)

**Setup:** Git repo with at least one plan in `.claude/plans/` or a `plans/` directory. For the review-fix path: a plan with `review_source` frontmatter pointing at an existing `.claude/reports/review-*.md` file.

**Expected behavior:**
1. Skill runs four git shell blocks plus the silent Glob over `.claude/plans/` and `**/plans/*.md`.
2. Phase 1 loads the plan via Case A/B/C, printing the executing-plan banner before proceeding.
3. Phase 0 NO_GIT handling skips branch creation, commits, and PR steps cleanly.
4. Phase 2.5 announces the strategy (sequential or parallel) and task count before continuing.
5. For review-fix plans, Phase 4c parses findings, applies BLOCKING/WARNING gates, and prints the convergence verdict; Phase 4d is skipped automatically.
6. Phase 5 delegates to `/quiver:commit` and `/quiver:create-pr`, gating each action with `AskUserQuestion`.
7. A 3+ task plan creates `.claude/work/<plan-basename>/progress.md` with the identity line before the first group dispatches; a successful run through Phase 5 offers to delete it.

**Verification checklist:**
- [ ] Slash menu shows `/work`; plan banner printed before code changes.
- [ ] Orchestration decision line appears for every plan (including 1-2 task plans).
- [ ] Non-git directory: plan loads and Phases 3-4 run; Phase 5 exits without commit/PR.
- [ ] Review-fix plans: verification table and convergence verdict shown; non-review-fix plans skip Phase 4c.
- [ ] Commit and PR steps both go through `AskUserQuestion`; skill never auto-pushes.
- [ ] Interrupting a run after Group 0 and re-invoking /work on the same plan re-dispatches no task carrying a complete line, and prints which tasks it skipped.
- [ ] A ledger whose identity line names a different plan file is left untouched and a suffixed workspace is used instead.
- [ ] Workspace deletion goes through AskUserQuestion and is verified by a re-list.

**Known gotchas:**
- Phase 4c parses the synthesized report format from the review skill; the SYNC comment must stay paired with the matching marker in `skills/review/SKILL.md`.
- For 3+ task plans the orchestrator (`skills/work/orchestrator.md`) replaces Phase 3; do not run Phase 3's TodoWrite loop alongside it.
- `git add .` is banned; always stage explicit file paths.
- The orchestration workspace survives a blocked, failed, or cancelled run on purpose -- that is what makes the next invocation resumable.
- The ledger, not the printed progress table, is the authority after a compaction.
