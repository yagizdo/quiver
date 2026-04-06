# Orchestrator Reference

This document defines the subagent orchestration logic used by the work skill when a plan has 3+ tasks. It is NOT a standalone skill — it is referenced by `skills/work/SKILL.md` Phase 2.5.

---

## 1. Dependency Resolution

Dependency resolution determines the order in which tasks execute. It runs three steps, then builds execution groups.

### Step 1 — Explicit Dependencies

Read each task's `blockedBy` field from the plan. This field lists task numbers that must complete before this task can start.

Example plan fragment:

```yaml
- id: 1
  title: Create database schema
  blockedBy: []

- id: 2
  title: Build API endpoints
  blockedBy: [1]

- id: 3
  title: Add input validation
  blockedBy: [1]

- id: 4
  title: Write integration tests
  blockedBy: [2, 3]
```

Here, Tasks 2 and 3 both wait for Task 1. Task 4 waits for both 2 and 3.

### Step 2 — File Overlap Detection

Compare each pair of tasks' file lists to detect implicit dependencies. If two tasks modify the same file, the later task (by plan order) implicitly depends on the earlier one.

**Algorithm:**

1. Extract file paths from each task's `Files:` section — include all lines under `Create:`, `Modify:`, and `Test:`.
2. For each pair `(i, j)` where `i < j`:
   - Compute the intersection: `intersection(files[i], files[j])`
   - If the intersection is non-empty AND task `j` does not already depend on task `i` (directly or transitively), add `i` to task `j`'s `blockedBy`.
3. Transitive check: task `j` already depends on task `i` transitively if there is any chain `j → ... → i` in the existing dependency graph. Do not add redundant edges.

**Example:**

```
Task 1 — Files: src/models/user.ts, src/db/schema.ts
Task 2 — Files: src/api/users.ts, src/middleware/auth.ts
Task 3 — Files: src/api/users.ts, src/api/admin.ts
```

Tasks 2 and 3 both touch `src/api/users.ts`. Since 2 < 3, Task 3 gets an implicit `blockedBy: [2]`. Tasks 1 and 2 share no files, so no implicit dependency is added between them.

### Step 3 — Build Execution Groups

After resolving all dependencies (explicit + implicit), partition tasks into execution groups:

- **Group 0:** Tasks with no `blockedBy` — these start immediately, in parallel.
- **Group 1:** Tasks whose `blockedBy` entries are all in Group 0.
- **Group N:** Tasks whose `blockedBy` entries are all in Groups 0 through N-1.

Tasks within the same group run in parallel. Groups execute sequentially (Group 0 completes before Group 1 starts).

### Reporting the Graph

Before dispatching, print the execution plan so the user can see what will happen:

```
Dependency Graph:
  Group 0 (parallel): Task 1 [Create database schema]
  Group 1 (parallel): Task 2 [Build API endpoints], Task 3 [Add input validation]
  Group 2 (parallel): Task 4 [Write integration tests]

Dependencies:
  Task 2 → blocked by Task 1 (explicit)
  Task 3 → blocked by Task 1 (explicit)
  Task 4 → blocked by Task 2, Task 3 (explicit)

Dispatching Group 0...
```

---

## 2. Subagent Dispatch

### Prompt Template

Each subagent receives a self-contained prompt. The orchestrator fills in the template fields from the plan:

```
# Task: {task_title}

## Description
{task_description}

## Acceptance Criteria
{acceptance_criteria}

## Files to Modify
{file_list — exact paths, one per line, prefixed with Create/Modify/Test}

## Context
{plan_preamble and architecture notes from the plan header}

## Instructions
1. Read all files listed above to understand current state and existing patterns.
2. Implement the changes described, following the codebase's existing conventions.
3. Run the project's test suite after implementation.
4. Self-review your changes: check for missing edge cases, naming consistency, and adherence to acceptance criteria.
5. Summarize what you did, what tests pass, and any concerns.

## Constraints
- Only modify the files listed above. If you discover a needed change in another file, report it as a blocker instead of making the change.
- Follow existing code patterns (naming, structure, error handling).
- Do not add AI attribution comments or generated-by markers.
- If you encounter an ambiguity or need a decision from the user, report BLOCKED status with a clear description of what you need.
```

### Dispatch Mechanics

For each execution group, in order:

1. **Create tracking entries:** Call `TaskCreate` for each task in the group, recording task title, status `IN_PROGRESS`, and assigned group number.
2. **Spawn agents:** For each task, spawn one Agent with:
   - `subagent_type="general-purpose"`
   - `isolation="worktree"` (each agent works in its own git worktree)
   - `run_in_background=true`
   - The filled-in prompt template as the agent's instructions.
3. **Wait for group completion:** Wait for all agents in the current group to finish.
4. **Process results:** Collect each agent's output and determine status (see Result Collection below).
5. **Update tracking:** Call `TaskUpdate` for each task with its final status.
6. **Proceed to next group:** If all tasks in the current group are DONE or if independent tasks in the next group are unblocked, move to the next group.

### Result Collection

Each completed subagent maps to one of three statuses:

| Status    | Detection                                          | Action                                         |
|-----------|----------------------------------------------------|-------------------------------------------------|
| **DONE**  | All acceptance criteria met, tests pass            | Queue the task's branch for merge               |
| **BLOCKED** | Agent reports needing info, a decision, or access to a file outside its scope | Pause all tasks that depend on this one, report the blocker to the user |
| **FAILED** | Unrecoverable error (build failure, test crash, environment issue) | Pause all tasks that depend on this one, report the failure to the user |

**Handling BLOCKED/FAILED tasks:**

- All tasks that have a direct or transitive dependency on a BLOCKED/FAILED task are paused — they do not dispatch.
- Tasks in the same or later groups that are independent of the failed task continue normally.
- The orchestrator reports the situation to the user and waits for guidance before retrying paused tasks.

---

## 3. Merge Procedure

### Merge Order

Merge branches in topological order — a task's branch merges only after all of its dependencies have merged. Within the same execution group, merge in plan order (lower task ID first).

### Per-Branch Merge

For each completed task branch, in topological order:

1. Run `git merge <worktree-branch> --no-edit` into the working branch.
2. **Auto-merge succeeds:** Continue to the next branch. Clean up the worktree.
3. **Conflict detected:** Stop the merge sequence immediately. Report to the user with:
   - The conflicting file list (from `git diff --name-only --diff-filter=U`)
   - Which task branches have merged so far
   - Which task branches remain unmerged

Do not attempt automatic conflict resolution. The user must resolve conflicts before the merge sequence continues.

### Post-Merge Validation

After all branches have merged successfully:

1. Run the project's full test suite on the merged result.
2. If tests pass, report success.
3. If tests fail, report the failures with:
   - Which tests failed
   - Likely responsible task (based on which files the failing tests cover)
   - Suggestion: re-run the responsible task's agent with the test failure as context.

---

## 4. Progress Reporting

### At Start

When orchestration begins, report:

```
Orchestrating {N} tasks across {M} execution groups.
```

Print the dependency graph using the format shown in "Reporting the Graph" above, then announce dispatching the first group.

### During Execution

Use `TaskCreate` and `TaskUpdate` calls to maintain real-time status. Each task transitions through:

```
PENDING → IN_PROGRESS → DONE | BLOCKED | FAILED
```

When a group completes, announce it before dispatching the next:

```
Group 0 complete. All tasks DONE.
Dispatching Group 1 (2 tasks in parallel)...
```

### At End — Success

When all tasks complete successfully and merge cleanly:

```
All tasks complete.

| Task | Title                    | Status | Branch                    |
|------|--------------------------|--------|---------------------------|
| 1    | Create database schema   | DONE   | work/1-database-schema    |
| 2    | Build API endpoints      | DONE   | work/2-api-endpoints      |
| 3    | Add input validation     | DONE   | work/3-input-validation   |
| 4    | Write integration tests  | DONE   | work/4-integration-tests  |

Merge: All 4 branches merged successfully.
Tests: 47 passed, 0 failed.
```

### At End — Partial Failure

When some tasks fail or are blocked:

```
Orchestration paused — 1 task blocked, 1 task not started.

| Task | Title                    | Status      | Branch                    |
|------|--------------------------|-------------|---------------------------|
| 1    | Create database schema   | DONE        | work/1-database-schema    |
| 2    | Build API endpoints      | DONE        | work/2-api-endpoints      |
| 3    | Add input validation     | BLOCKED     | work/3-input-validation   |
| 4    | Write integration tests  | NOT STARTED | —                         |

Blocker (Task 3): "Validation rules not specified in plan — need user input on email format requirements."

Merged so far: Task 1, Task 2.
Awaiting: Resolve Task 3 blocker, then Task 3 and Task 4 can proceed.
```
