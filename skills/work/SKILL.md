---
name: work
description: "Execute a work plan or specification systematically -- read the plan, set up a branch, implement tasks with continuous testing, commit incrementally, and ship a PR. Use when you have a plan file, spec, or task list ready to execute."
---

# Work

Execute a work plan, specification, or task list systematically. The focus is on shipping complete features by understanding requirements quickly, following existing patterns, and maintaining quality throughout.

**Announce:** "Using the work skill to execute the plan."

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

### Phase 1: Load and Clarify

1. **Read the work document.** If the user provided a path, read it. If not, check `.claude/plans/` for the most recent plan file. If no plan exists, ask the user what to work on.

2. **Review references.** If the plan links to files, patterns, or prior research -- read those now. Understanding context before coding prevents rework.

3. **Flag ambiguities.** If anything is unclear or contradictory, ask clarifying questions now. Better to ask one question upfront than build the wrong thing. If the plan is clear, skip this step.

4. **Get approval to proceed.** Summarize what you are about to build in 2-3 sentences and confirm the user wants to proceed.

### Phase 2: Setup Environment

Check the current branch:

```bash
git branch --show-current
```

**If already on a feature branch** (not main/master):
- Ask: "Continue on `{current_branch}`, or create a new branch?"
- If continuing, move to Phase 3.

**If on the default branch**, choose how to proceed:

| Option | When to use |
|--------|-------------|
| **New branch** | Default. `git checkout -b <meaningful-name>` from latest default branch. |
| **Worktree** | Parallel development or keeping default branch workspace clean. Use the `using-git-worktrees` skill if available. |
| **Stay on default** | Only with explicit user confirmation. Never commit to default branch without permission. |

Use a descriptive branch name based on the task (e.g., `feat/user-auth`, `fix/email-validation`).

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

#### 4c -- Optional: Agent-assisted review

For large, risky, or security-sensitive changes, consider dispatching review agents. Discover available review agents by scanning `agents/review/*.md` and dispatch them using the `orchestrate-agents` skill patterns.

**Do not use review agents by default.** Tests + linting + pattern-following is sufficient for most work. Reserve agent reviews for:
- Large refactors (10+ files)
- Security-sensitive changes (auth, permissions, data access)
- Complex business logic or algorithms

### Phase 5: Ship

**CRITICAL: Every git action in this phase requires explicit user confirmation via `AskUserQuestion`. NEVER commit, push, or create a PR without asking first.**

**NO ATTRIBUTION: Do not add `Co-Authored-By`, `Generated with Claude`, `Built with AI`, or any similar attribution lines to commit messages or PR descriptions. Keep them clean. Only add attribution if the user explicitly requests it.**

#### 5a -- Final commit

If there are uncommitted changes after Phase 4:

1. Stage the relevant files (specific files only -- never `git add .`):
   ```
   git add <relevant files>
   ```

2. Delegate to `/quiver:commit`. This command generates a Conventional Commits message, presents it to the user via `AskUserQuestion` with Commit / Commit & Push / Edit / Cancel options, and only executes after the user explicitly chooses. It handles the full commit (and optional push) flow with built-in confirmation.

3. If the user cancelled the commit, respect that -- do not re-ask or proceed to 5b.

#### 5b -- Create PR

After committing (or if all commits were already made during Phase 3), ask the user what to do next. Do NOT push or create a PR without asking.

1. Use `AskUserQuestion`:
   > All work is committed on `{branch_name}`. What would you like to do next?
   Buttons: `["Create a pull request", "Done -- I'll handle the rest"]`

   - **Create a pull request** -- if not already pushed, push first with `git push -u origin <branch-name>`. Then draft the PR title and summary, and present for confirmation (step 2).
   - **Done** -- stop here. Move to 5c.

2. If creating a PR, draft the title and summary, then ask for confirmation:
   > Proposed PR:
   > **Title:** {title}
   > **Summary:** {summary}
   Buttons: `["Create this PR", "Edit before creating", "Skip PR"]`

   - **Create this PR** -- create the PR as shown.
   - **Edit before creating** -- ask the user what to change, revise, then re-present.
   - **Skip PR** -- the branch is pushed, but no PR is created.

   PR template:
   ```
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   - What was built and why
   - Key decisions made

   ## Testing
   - Tests added or modified
   - Manual testing performed

   ## Changes
   - List of significant changes
   EOF
   )"
   ```

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

---

## Quality Gates

**BLOCKING** (fix before shipping):
- All tests pass
- All TodoWrite tasks completed
- No uncommitted changes that belong to this work
- Plan checkboxes updated (if applicable)

**WARNING** (review but do not block):
- Linting warnings present
- No integration tests for changes that touch callbacks or middleware
- Plan had acceptance criteria that were not explicitly verified
