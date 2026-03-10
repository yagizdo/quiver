---
name: work
description: Execute a work plan or specification systematically -- read the plan, set up a branch, implement tasks with continuous testing, commit incrementally, and ship a PR.
argument-hint: "<plan file path or task description>"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree`
```

```
!`git branch --show-current`
```

```
!`git log --oneline -5`
```

```
!`git status --short`
```

```
!`ls -1 .claude/plans/`
```

---

# Instructions

You are a plan executor. Your job is to load a work plan, set up the environment, implement each step with continuous testing, commit incrementally, and ship the result. Follow the **work** skill methodology.

## Step 1 -- Load the Plan

**If `$ARGUMENTS` is a file path** (ends in `.md` or contains `/`):
- Read that file as the work plan.

**If `$ARGUMENTS` is a description** (not a file path):
- Check `.claude/plans/` for plans whose goal matches the description. If one matches, use it. If multiple match, present options via `AskUserQuestion`. If none match, treat the description as an inline task spec.

**If `$ARGUMENTS` is empty:**
- Look at the available plans listed above. If exactly one exists, ask the user if they want to execute it. If multiple exist, present them via `AskUserQuestion` with the plan filenames as buttons (most recent first), plus an "Other -- I'll describe the task" option. If none exist:
  > No plans found. Usage:
  > - `/work <path-to-plan.md>` -- execute a specific plan
  > - `/work <task description>` -- work on a task directly
  > - `/plan <task>` -- create a plan first
  **Stop here.**

## Step 2 -- Review and Confirm

1. Read the plan file (or inline spec).
2. If the plan references files, patterns, or prior research -- read those now.
3. Summarize what you are about to build in 2-3 sentences.
4. Use `AskUserQuestion`:
   > Ready to execute: {summary}
   > **Branch:** {current branch from context above}
   > **Steps:** {step count if plan has numbered steps}
   Buttons: `["Start working", "Let me review the plan first", "Cancel"]`

   - **Start working** -- proceed to Step 3.
   - **Let me review the plan first** -- display the full plan and wait for the user to confirm after reviewing.
   - **Cancel** -- stop here.

## Step 3 -- Setup Environment

Check the current branch from the context above.

**If already on a feature branch** (not main/master/develop):
- Use `AskUserQuestion`:
  > You're on `{branch}`. Continue here or create a new branch?
  Buttons: `["Continue on {branch}", "Create new branch"]`

**If on the default branch:**
- Create a new branch: `git checkout -b <meaningful-name>` derived from the plan goal.
- Use a descriptive branch name (e.g., `feat/user-auth`, `fix/email-validation`).

## Step 4 -- Execute

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

## Step 5 -- Quality Check

Before shipping:

1. Run the project's test suite.
2. Run linting if configured.
3. Verify all TodoWrite tasks are completed.
4. For non-trivial changes, check system-wide impact (callbacks, middleware, parallel interfaces).

## Step 6 -- Ship

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

- **Don't** skip Step 2 confirmation -- always confirm before starting work.
- **Don't** ignore plan references -- read the files and patterns the plan points to.
- **Don't** save all testing for the end -- test after each change.
- **Don't** use `git add .` -- stage specific files only.
- **Don't** commit with "WIP" messages -- wait for a complete logical unit.
- **Don't** force through blockers -- stop, note the issue, ask the user.
- **Don't** commit, push, or create a PR without asking the user first.
- **Don't** add AI attribution unless the user explicitly requests it.
