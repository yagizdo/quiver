---
name: work
description: Execute a work plan or specification systematically -- read the plan, set up a branch, implement tasks with continuous testing, commit incrementally, and ship a PR.
argument-hint: "<plan file path or task description>"
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

```
!`find . -maxdepth 4 -type d -name "plans" 2>/dev/null || echo "NOT_FOUND: plans dirs"`
```

```
!`ls -1 .claude/plans/ 2>/dev/null || echo "NOT_FOUND: .claude/plans/"`
```

---

# Instructions

You are a plan executor. Your job is to load a work plan, set up the environment, implement each step with continuous testing, commit incrementally, and ship the result. Follow the **work** skill methodology.

## Step 0 -- Git Availability

If any gather-context block above returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch/commit context.`
Proceed to Step 1. Treat all git-sourced fields (branch, log, diff, status) as empty. Skip branch creation in Step 2, commit steps in Step 3, and git-dependent actions in Step 5.

## Step 1 -- Load the Plan

### Case A: Path provided

If `$ARGUMENTS` is a file path (ends in `.md` or contains `/`):
- Read that file as the work plan.
- Print: `> Executing plan: {plan filename} ({step count} steps) on branch {branch}`
- **Proceed directly to Step 2.** The user chose this plan explicitly -- no confirmation needed.

### Case B: No arguments

If `$ARGUMENTS` is empty, collect all `.md` files from every `plans/` directory discovered by the `find` block, plus the `.claude/plans/` listing from the `ls` block.

**Plans found:**
- If exactly one plan exists across all directories, read it and use `AskUserQuestion`:
  > Found one plan: `{relative path}` (in `{directory}`)
  > **Goal:** {goal from plan}
  > **Steps:** {step count}
  Buttons: `["Execute this plan", "Other -- I'll provide a path or description"]`
- If multiple plans exist, present them via `AskUserQuestion` with full relative paths as buttons (most recent first), plus an "Other -- I'll provide a path or description" option. Show the directory in each label so the user can distinguish plans in different locations.
- If the user picks "Other", ask for a path or task description.

**No plans found:**
> No plans found in any `plans/` directory. Usage:
> - `/work <path-to-plan.md>` -- execute a specific plan
> - `/work <plan-name>` -- search for a plan by name
> - `/work <task description>` -- work on a task directly
> - `/plan <task>` -- create a plan first
**Stop here.**

### Case C: Name or description provided

If `$ARGUMENTS` is not a file path (does not end in `.md` and does not contain `/`) and is not empty:

**Step C1 -- Discover plan files.** From the `find` output above, read every discovered `plans/` directory. For each directory, list its `.md` files. Combine with the `.claude/plans/` listing from the `ls` block. This gives you the full set of plan files across the project.

**Step C2 -- Match by filename.** Compare `$ARGUMENTS` against each plan file's name (stem without `.md` extension):
- **Exact match:** The stem equals `$ARGUMENTS` (case-insensitive). E.g., input `test-feature` matches `test-feature.md`.
- **Partial match:** The stem contains `$ARGUMENTS` as a substring (case-insensitive). E.g., input `feature` matches `test-feature.md` and `test-feature-v2.md`.

**Step C3 -- Rank and select.** Rank exact matches above partial matches.
- **1 match** -- Read the plan file, print `> Executing plan: {filename} from {directory}`, proceed to Step 2. No confirmation needed.
- **Multiple matches** -- Use `AskUserQuestion` to present candidates. Show full relative paths as button labels (e.g., `superpowers/plans/test-feature-v2.md`). Add a `"None of these -- treat as task description"` button.
- **0 matches** -- Treat `$ARGUMENTS` as an inline task description. Print `> No matching plan found for "{$ARGUMENTS}". Treating as task description.` Proceed to Step 2 with the description as the work specification.

### After loading the plan

1. If the plan references files, patterns, or prior research -- read those now.
2. Check if the plan references a review report:
   - Check YAML frontmatter for `review_source` field.
   - Fall back to scanning content for `.claude/reports/review-*.md` paths.
   - If found, load the review report and note this as a review-fix plan for Step 4.
   - Read the plan's `review_iteration` frontmatter field (default: `1` if absent). If `review_iteration >= 2`, this is the final iteration -- only Phase 4c verification applies, no additional review agents.

## Step 2 -- Setup Environment

**If git is NOT available (Step 0 detected `NO_GIT`):** Skip this step entirely -- proceed to Step 3.

Check the current branch from the context above.

**If already on a feature branch** (not main/master/develop):
- Use `AskUserQuestion`:
  > You're on `{branch}`. Continue here or create a new branch?
  Buttons: `["Continue on {branch}", "Create new branch"]`

**If on the default branch:**
- Create a new branch: `git checkout -b <meaningful-name>` derived from the plan goal.
- Use a descriptive branch name (e.g., `feat/user-auth`, `fix/email-validation`).

## Step 2.5 -- Orchestration Decision

Determine execution strategy based on the loaded plan.

1. **Count tasks.** A "task" is any top-level work unit in the plan -- a numbered step, a heading-delimited section, a checklist item, or a YAML list entry. Plans from different tools use different formats; count by semantic units, not by a specific markup convention.

2. **Announce the decision** (mandatory -- always print this before proceeding):

   ```
   Strategy: {sequential | parallel orchestration} ({N} tasks found)
   Reason: {one-line explanation -- e.g., "2 tasks, below parallel threshold" or "5 tasks with 3 independent groups"}
   ```

3. **Route:**
   - **1-2 tasks:** Sequential. Proceed to Step 3.
   - **3+ tasks:** Parallel orchestration per the **work** skill's orchestrator reference. This REPLACES Step 3 -- skip directly to Step 4.

## Step 3 -- Execute

Follow the **work** skill's Phase 3 (Build) methodology:

1. Break the plan into actionable tasks using TodoWrite.
2. For each task in dependency order:
   - Mark as `in_progress`.
   - Read referenced files. Match existing patterns.
   - Implement the change.
   - Run relevant tests. Fix failures immediately.
   - Mark as `completed`.
   - Update plan checkboxes (`- [ ]` to `- [x]`) if applicable.
   - Commit when a logical unit is complete (not WIP).
3. Stage specific files -- never `git add .`.

**On blockers:** Stop immediately. Note the blocker. Ask the user. Do not force through.

## Step 4 -- Quality Check

Before shipping:

1. Run the project's test suite.
2. Run linting if configured.
3. Verify all TodoWrite tasks are completed.
4. For non-trivial changes, check system-wide impact (callbacks, middleware, parallel interfaces).
5. If this is a review-fix plan (detected in Step 1), run review finding verification per the work skill's Phase 4c methodology. Present the verification summary table. Block on unaddressed Critical findings. Verify acceptance criteria. Present the convergence verdict. If the cycle is COMPLETE, proceed to Step 5 without dispatching additional review agents.

## Step 5 -- Ship

**If git is NOT available (Step 0 detected `NO_GIT`):** Skip commit and PR steps. Summarize what was completed and remaining follow-ups, then stop.

**Every git action requires explicit user confirmation via `AskUserQuestion`.**
**No AI attribution in commits or PRs unless the user explicitly asks.**

1. If uncommitted changes remain, delegate to `/quiver:commit`.
2. After committing, use `AskUserQuestion`:
   > All work is committed on `{branch}`. What next?
   Buttons: `["Create a pull request", "Done -- I'll handle the rest"]`
3. If creating a PR, draft title and summary, present for confirmation, then create via `gh pr create`.
4. Update plan frontmatter `status: active` to `status: completed` if applicable.
5. Summarize: what was completed, PR link (if any), remaining follow-ups.

---

## Anti-Patterns

- **Don't** ignore plan references -- read the files and patterns the plan points to.
- **Don't** save all testing for the end -- test after each change.
- **Don't** use `git add .` -- stage specific files only.
- **Don't** commit with "WIP" messages -- wait for a complete logical unit.
- **Don't** force through blockers -- stop, note the issue, ask the user.
- **Don't** commit, push, or create a PR without asking the user first.
- **Don't** add AI attribution unless the user explicitly requests it.
