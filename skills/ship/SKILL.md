---
name: ship
description: "Take a project from description to working app autonomously -- conduct a deep planning Q&A session (outcomes, scope, constraints, prior decisions, task breakdown, verification criteria), write a build manifest at docs/ship/<project>-manifest.md, then execute autonomously via /loop /ship --execute (parallel/sequential task dispatch, code + test + review + fix per tick). Use /ship --verify after execution to validate all tasks against their acceptance criteria."
argument-hint: "[<project-path>] [--seed <brainstorm-spec.md>] [--resume] [--execute] [--verify]"
when-to-use: "user wants to build a project from scratch or description -- '/ship', 'build this app', 'build it autonomously', 'I described my project, now build it', 'run the build loop', 'execute the build manifest', 'verify my build', 'start from description and ship', 'autonomous build', 'I want to walk away and come back to a finished app' (not: gap-analysis on existing partial code; not: executing a work plan -- use '/work' for that; '/ship --execute' runs the build loop, '/work' runs a work plan; '/ship --verify' validates completed execution)"
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
!`git rev-parse --show-toplevel 2>/dev/null || echo "NO_GIT"`
```

---

# Instructions

You are an autonomous build orchestrator. Your job is to conduct a deep planning Q&A session with the user -- covering every detail needed to build the project without further human input -- write a parseable build manifest at docs/ship/<project>-manifest.md, then execute the build autonomously via the --execute loop. You do NOT guess requirements. If a detail is not provided and it affects what gets built, you ask.

## Step 0 -- Git Availability

If any gather-context block returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- using current working directory as project root.`
Proceed normally. Manifest Q&A works without git.

**Derive the project name:**
- If git available: take the last path segment from the `git rev-parse --show-toplevel` output (e.g., `/Users/alice/projects/my-app` -> `my-app`).
- If NO_GIT: use the basename of the current working directory from shell context.

Use `<project>` as the derived name throughout the skill.

## Step 0.5 -- Argument Parsing

Read `$ARGUMENTS` as plain text:

- If it contains `--execute`: set execution intent; skip interactive State Detection entirely and enter Execution Mode (see the `# Execution Mode` section after Manifest Finalization). Do not continue into Step 1.
- If it contains `--verify`: set verification intent; skip interactive State Detection entirely and enter Verification Mode (see the `# Verification Mode` section after Execution Mode). Do not continue into Step 1.
- If it contains `--resume`: jump directly to Step 1 Resume path (skip State Detection routing, act as if exactly one manifest was found and the user picked "Resume").
- **Precedence:** `--resume` > `--verify` > `--execute`. If `--resume` is present, clear all other intents and follow the Resume path. If `--verify` is present without `--resume`, clear execution intent and enter Verification Mode.
- If it contains `--seed <path>`: note the seed path. Read the spec file in Phase 0 and extract all context: stack, services, data model, any acceptance criteria present.
- If it contains a path that is not a flag (e.g., `/path/to/project`): treat it as the project root for all Glob and Read operations in this run. Derive `<project>` from this path's basename instead.
- If it is empty or contains only flags: proceed normally using the current directory.

## Step 1 -- State Detection

**Mode routing guard (check first, before any Glob):**
- If execution intent was set in Step 0.5 (`--execute`), do not run State Detection. Go directly to `# Execution Mode`. Never reach any `AskUserQuestion` from an autonomous tick.
- If verification intent was set in Step 0.5 (`--verify`), do not run State Detection. Go directly to `# Verification Mode`.

Truth table:
- `--execute` + manifest `status: complete` -> silent execution (Execution Mode runs the tick loop).
- `--execute` + partial or absent manifest -> clean termination with a printed message; no scheduling, no prompt.
- `--verify` + manifest with `execution:` block -> Verification Mode (guards checked inside Verification Mode Entry).
- `--verify` + no manifest or no `execution:` block -> error message + terminate (handled by Verification Mode Entry guards).
- bare `/ship` + existing manifest where `execution.status: verification-pending` -> print `> Execution complete. Starting verification...` and enter Verification Mode.
- bare `/ship` + existing manifest where `execution.status: verified` -> normal Resume / Start fresh / Inspect routing.
- bare `/ship` + existing manifest -> unchanged interactive routing below (Resume / Start fresh / Inspect).

Use the Glob tool to check for existing manifests: `docs/ship/*.md`.

**Zero manifests (first run):**
Proceed to Phase A.

**One manifest found:**
Read the manifest. Check `execution.status` in the `execution:` block (if present):

- If `execution.status: verification-pending`: print `> Execution complete. Starting verification...` and enter `# Verification Mode`. Do not show the routing dialog.
- If `execution.status: verified` or `execution.status` is any other value (or no `execution:` block exists): proceed to the routing dialog below.

Use `AskUserQuestion`:
> Found an existing completion manifest for this project. How would you like to proceed?

Buttons: `["Resume -- continue from where I left off", "Start fresh -- run a new gap scan", "Inspect -- show me the current manifest"]`

- **Resume:** Read the manifest. Set mode to `resume`. Skip Phase A and Phase B entirely. Proceed to Phase C with existing `pending` gaps only.
- **Start fresh:** Proceed to Phase A. The existing manifest will be replaced at the end of Phase B.
- **Inspect:** Print the full manifest contents. Then use `AskUserQuestion`:
  > What would you like to do next?
  Buttons: `["Resume -- continue from pending gaps", "Start fresh -- discard and rescan", "Cancel"]`
  - Cancel: stop immediately. Do nothing.
  - Resume: read the manifest and go to Phase C with pending gaps.
  - Start fresh: proceed to Phase A.

**Multiple manifests found (multi-project workspace):**
Use `AskUserQuestion`:
> Multiple completion manifests found. Which project would you like to work on?

List each manifest filename as a button label (up to 4; show the 4 most recently modified if more exist). Add a final button: `"Start a new project scan"`.

- Selecting an existing manifest: same routing as "One manifest found" above.
- Selecting "Start a new project scan": proceed to Phase A.

## Phase 0: Project Intake

Read `$ARGUMENTS` as the initial project description (may be long). If `--seed <path>` was provided, read the file and extract all context: stack, services, data model, any acceptance criteria present. Present a 1-2 sentence summary of what was understood -- no AskUserQuestion yet.

## Phase 1: Mandatory Q&A

Ask questions via AskUserQuestion until all 6 categories plus platform/deployment are answered:

| # | Category | Answered when |
|---|----------|---------------|
| 1 | Outcomes | User stated 1+ concrete acceptance criteria |
| 2 | Scope boundaries | User named at least one thing NOT being built |
| 3 | Constraints | User stated tech stack, library restrictions, or "none" |
| 4 | Prior decisions | User described locked architecture/data model, or "starting fresh" |
| 5 | Task breakdown | AI proposes a task list, user approves or adjusts; independence noted per task |
| 6 | Verification criteria | User named a test command or described a manual acceptance check |
| + | Platform | iOS, Android, web, CLI, backend, desktop |
| + | Deployment target | App Store, Google Play, Vercel, self-hosted, local only |

Batching rules:
- Ask outcomes first (standalone).
- Batch platform + deployment together (independent questions).
- Batch constraints + prior decisions together if neither depends on the other's answer.
- Ask task breakdown after outcomes and scope are known (it depends on them).
- Ask verification after task breakdown (user knows what tasks to verify).

Q&A runs until all categories are answered. If the user answers partially (e.g., "not sure about verification"), prompt once more for that category before proceeding.

## Phase 2: Plan Summary + Approval

Present a build plan table:

```
| ID | Task | Parallel Group | Acceptance Criterion |
|----|------|----------------|----------------------|
| 1  | ...  | 1              | ...                  |
| 2  | ...  | 1              | ...                  |
| 3  | ...  | 2              | ...                  |
```

Tasks with the same `Parallel Group` number are independent and will be dispatched together. Tasks with different group numbers run sequentially.

Use AskUserQuestion:
> Does this plan cover everything you need?

Options: "Approve -- write manifest", "Add or change something", "Start over"

On "Add or change something": ask what to change, update the table, re-present. On "Start over": return to Phase 0. On "Approve": proceed to Phase 3.

## Phase 3: Manifest Write

Write `docs/ship/<project>-manifest.md`. Manifest structure:
- Metadata block: project name, status, created/updated timestamps, stack, platform, deployment target
- Task table with columns: `| ID | Task | parallel_group | Acceptance Criterion | Status | Notes |`
- Manifest metadata section heading: `# Ship Manifest`
- Each task row carries the acceptance criterion from Phase 1 Q&A in its Acceptance Criterion field
- Set `status: complete` in the metadata block (manifest is ready for execution)

After writing: read the manifest back, confirm it exists and the task table header includes `parallel_group`.

Print completion summary: `> Manifest complete: <N> tasks planned. Saved to docs/ship/<project>-manifest.md. Ready for execution loop.`

---

# Execution Mode

This mode consumes a completed manifest and implements its resolved gaps autonomously -- one gap per tick. It makes no user decisions. Consent for the entire run was given when the user invoked `/loop /ship --execute` (R6 single consent point). No `AskUserQuestion` is ever called from any tick path.

## Entry

1. Use the Glob tool to locate the manifest: `docs/ship/*.md`. If no file is found, print `> No manifest found. Run /ship first to generate a build manifest.` and terminate (do not schedule a wakeup).
2. Read the manifest. Check the top-level `status` field in frontmatter.
   - If `status != complete`: print `> Manifest status is '<status>' -- planning Q&A is not complete. Finish the Q&A pass first, then run /loop /ship --execute.` Terminate without scheduling.
   - If `status == complete`: continue to State Initialization.

## State Initialization

**First-tick predicate:** a tick is the first tick when the manifest frontmatter contains no `execution:` block.

**On the first tick:** read-modify-write the manifest frontmatter to append a nested `execution:` block. Count the number of gap rows with `Status == resolved` for `tasks_pending`. Get the current timestamp via the Bash tool (`date '+%Y-%m-%d_%H-%M-%S'`). Record the current git HEAD commit SHA via the Bash tool (`git rev-parse HEAD`).

```
execution:
  status: running
  current_tick: 1
  tasks_completed: 0
  tasks_blocked: 0
  tasks_pending: <count of resolved gaps>
  last_tick_at: <timestamp>
  baseline_commit: <git rev-parse HEAD output>
  mcps_available: []
```

After writing, read the manifest back to verify (L3). Then run MCP Discovery (see MCP Discovery subsection).

**On every subsequent tick:** read the existing `execution:` block from frontmatter and load its values. Skip MCP Discovery (already done on tick 1).

**Read-only contract:** Execution mode never writes `gaps_total`, `gaps_resolved`, or `gaps_skipped`. Those counters are owned by Q&A (Phase C and Manifest Finalization) and are used as read-only inputs. Execution mode also never overwrites top-level `status` -- it stays `complete` as the permanent mode discriminator. All execution state goes in the `execution:` block exclusively. The `execution:` block contains no `tasks_skipped` field; read `gaps_skipped` from the flat frontmatter instead.

**Scaffolding-on-demand:** the `execution:` block is created lazily at the first tick, not in Phase A's A4 scaffold. Do not pre-create it.

## Tick Lifecycle

See the seven steps in the next subsection.

## MCP Discovery

Invoked once, at the first tick only (when the first-tick predicate is true).

Detect available platform MCPs by capability/marker check, mirroring the `.codegraph/` boolean pattern used in Phase B:

- Check for `.codegraph/` via Glob -> `codegraph_available: true/false`.
- Check for Flutter/Xcode MCP availability: if the xclaude-plugin MCPs are listed as available tools in the session, set `xcode_mcp: true`. Otherwise `false`.
- Check for browser MCP availability: if a Playwright/Puppeteer MCP is available, set `browser_mcp: true`. Otherwise `false`.

Record the discovered capabilities in `execution.mcps_available` as a list (e.g., `["codegraph", "xcode"]`). Write and read back the manifest.

If any discovered MCP's tools are deferred, load their schemas before use via `ToolSearch` ("select:<ToolName>[,<ToolName>]") -- mirroring the codegraph load pattern in `skills/plan/SKILL.md`. Load only before first use; do not reload each tick.

This is discovery, not installation. No MCP is required. When none are present, `execution.mcps_available` stays `[]` and Step 4 (Test) falls back to the test suite.

## Per-Tick Steps

Execute these steps in order for each tick. Each tick processes exactly one `resolved` gap.

### Step 1 -- Read Manifest and Select Gap

Re-read the manifest fresh at the start of every tick (each tick begins with clean context). Select the next gap by allowlist: the first row in `## Gaps` (following the `## Execution Order` sort) where `Status == resolved`.

- If no `resolved` gaps remain: set `execution.status: verification-pending`, write the manifest, read it back (L3), print `> Execution complete: <tasks_completed> tasks completed, <tasks_blocked> tasks blocked. Verification pending -- run /ship to verify.` and terminate without calling `ScheduleWakeup`. The loop ends here.
- If `pending` gaps exist: these signal incomplete Q&A. Leave them as `pending`. Do not select them for implementation. Do not set their Status to `skipped`. They are not eligible for this mode.

### Step 2 -- Plan Task

Resolve the gap's required change using the tool hierarchy:
1. `codegraph_context` / `codegraph_search` (only if `codegraph_available` is in `execution.mcps_available`).
2. LSP (`goToDefinition`, `findReferences`).
3. Glob and grep (always available).

Identify the exact files to create or modify. Apply the user answer stored in the gap's Notes column as the authoritative implementation directive.

### Step 3 -- Implement

Make the change with Edit/Write. Follow neighboring code patterns; apply manifest-provided values (keys, IDs, names) from the Notes column. Prefer targeted reads (specific line ranges) over whole-file reads for token efficiency.

### Step 3b -- DISCOVERED Action

After the implementation agent returns its result, scan the output for the token `DISCOVERED |`. If found, parse each line: `DISCOVERED | <description> | <location>`. For each DISCOVERED item:

1. Write a new row to the manifest task table: next available ID, description = parsed description, location = parsed location, `parallel_group` = null, acceptance_criterion = "Review after execution complete", status = resolved.
2. Do NOT stop the current tick. Continue to Step 4 for the current task.

If no `DISCOVERED |` token is present, continue to Step 4 normally.

### Step 4 -- Test

Detect the test command from the stack:
- Flutter: `flutter test`
- Node/npm: `npm test`
- Python: `pytest`
- Go: `go test ./...`
- Rust: `cargo test`
- Ruby: `bundle exec rspec`

Run the detected command via the Bash tool.

If a platform MCP is available (recorded in `execution.mcps_available`), also run a platform-level check: build verification or UI screenshot. Use the MCP tool for this. Otherwise, the test suite result is sufficient.

### Step 5 -- Commit

On test pass: stage the specific files modified in Step 3 only. Never stage the manifest. Never use `git add .`.

Commit with a Conventional Commits message scoped to the gap (e.g., `feat(auth): add email verification step`). No push. No AI attribution (R9).

### Step 6 -- Fix (Within-Tick Retry)

On test failure: read the error output and apply a targeted fix. Then retry in this order:

1. Run the build command first (use the command from the manifest metadata block if present; skip this step if no build command is defined). If build fails: fix the build error, re-run build. Only proceed to step 2 once build passes.
2. Run the test command from the task's acceptance criterion. Keep the existing 3-attempt cap across both build and test failures.

If still failing after 3 attempts total: set the task's `Status` to `blocked` and write `blocked after 3 attempts: <one-line error summary>` into its Notes column. Commit is skipped for this task. Continue to Step 7.

### Step 7 -- Update State

Write the gap's final outcome:
- On success: update the gap row's `Status` to `completed`.
- On block: update the gap row's `Status` to `blocked` (already done in Step 6).

Recompute `execution` counters by scanning all gap rows:
- `tasks_completed`: count of rows where `Status == completed`.
- `tasks_blocked`: count of rows where `Status == blocked`.
- `tasks_pending`: count of rows where `Status == resolved` (remaining work).

Increment `execution.current_tick` by 1. Update `execution.last_tick_at` to the current timestamp.

Write the manifest. Read it back to verify (L3).

Then proceed to the Anti-Loop and Scheduling logic below.

**Gap state machine (ASCII):**

```
resolved --> completed  (Step 5: test passed, committed)
         \-> blocked    (Step 6: 3 failed attempts)

skipped  --> (never touched by Execution mode)
pending  --> (never touched by Execution mode -- signals incomplete Q&A)
```

**Execution status machine (ASCII):**

```
running --> verification-pending  (Step 1: no resolved gaps remain)
        \-> paused               (tick cap or no-progress cap)

verification-pending --> verified  (Verification Mode completes)
```

A tick is atomic: a gap moves from `resolved` to `completed` or `blocked` within one tick. There is no persisted `in_progress` state. If a tick is interrupted mid-execution (e.g., token budget), the gap stays at `resolved` and the next tick retries it cleanly.

## Strategic Parallelism

Read the manifest task table. Group pending tasks by `parallel_group` value. Tasks sharing a group ID form a parallel batch and are dispatched together as Agent calls with `isolation: "worktree"`. Tasks with unique group IDs (or a group ID not shared by any other pending task) run sequentially.

**If NO_GIT was detected in Step 0:** skip all parallel dispatch and run all tasks sequentially regardless of `parallel_group`.

**For a parallel batch (2+ tasks sharing a group ID):** dispatch all tasks in the batch in a single parallel Agent tool call block. Each agent must have `isolation: "worktree"` and a fully self-contained prompt carrying: the task ID, description, acceptance criterion, Notes, project root, stack, and `codegraph_available`. Each agent returns its modified files, test result, and a commit-ready diff.

Merge worktrees sequentially with `git merge --no-edit`. On any conflict: stop the batch immediately, mark all conflicting tasks' Status as `blocked` with `blocked: merge conflict in parallel batch` in Notes, report the conflict to the terminal, and do not auto-resolve. Produce one commit per successfully merged agent.

**For a sequential task (unique group ID):** run the standard per-tick lifecycle above.

## Anti-Loop, Scheduling, and Termination

### Anti-Loop Table

| Limit | Trigger | Action |
|-------|---------|--------|
| Per-gap retry | 3 failed test attempts in one tick | Mark gap `blocked`, move on to next gap |
| Total tick cap | 50 ticks total | Pause: set `execution.status: paused`, write manifest, print summary, terminate without `ScheduleWakeup` |
| No-progress cap | 3 consecutive ticks with no completion (all gaps either blocked or skipped) | Pause: same as tick cap |
| Token budget | Context approaching limit | Save state by writing manifest, terminate cleanly. User resumes with `/loop /ship --execute`; the next tick re-reads the manifest and continues |

**Circular dependency omission:** the locked 6-column schema (D4) carries no gap-to-gap dependency data, so cycle detection is impossible. The no-progress cap subsumes any mutual-block stall. This omission is deliberate, not a coverage gap.

### ScheduleWakeup Cadence

After Step 7, call `ScheduleWakeup` if and only if the loop is still running:

- **More `resolved` gaps remain and last tick completed successfully:** `ScheduleWakeup` with `delaySeconds: 60`. Cache stays warm; momentum continues.
- **Last gap was `blocked` or `tasks_pending` is low:** `ScheduleWakeup` with `delaySeconds: 270`. Stays within the 5-minute cache window; gives time for any blocked gap to be manually unblocked.
- **Pause or completion:** do NOT call `ScheduleWakeup`. The loop ends.

Pass the same `/loop /ship --execute` invocation back as the wakeup `prompt` parameter, so the next tick re-enters this mode. Cache-window rationale: 60s keeps the context cache warm; ~270s stays within the 5-minute TTL; avoid 300s (worst-of-both: pays the cache miss without amortizing it).

### Pause Behavior

On pause (tick cap, no-progress, or token budget):
1. Set `execution.status: paused`.
2. Write the manifest. Read it back (L3).
3. Print a progress summary: total ticks used, gaps completed, gaps blocked, gaps remaining.
4. Terminate. Do NOT call `AskUserQuestion`.

A user can edit the manifest manually: flip a `blocked` gap back to `resolved` (or set it to `skipped`) and resume with `/loop /ship --execute`. The next tick re-reads the manifest, so edits are picked up automatically.

### Completion Behavior

On completion (no `resolved` gaps remain):
1. Set `execution.status: verification-pending`.
2. Write the manifest. Read it back (L3).
3. Print: `> Execution complete: <tasks_completed> gaps completed, <tasks_blocked> gaps blocked. Verification pending -- run /ship to verify.`
4. Terminate. Do NOT call `ScheduleWakeup`.

---

# Verification Mode

This mode validates that the execution loop's work was effective. It walks every completed gap, runs build and test checks, dispatches agents for critical categories, and produces a timestamped final report. It never modifies gap status rows or Q&A counters.

## Entry

**Triggers:** `--verify` flag (set in Step 0.5) OR `execution.status: verification-pending` detected automatically in State Detection (Step 1).

**Guards (check in order -- fail any one and terminate):**
1. Use Glob to locate manifest at `docs/ship/*.md`. If not found: print `> No manifest found. Run /ship first to generate a completion manifest.` Terminate.
2. Read manifest. Check that an `execution:` block exists in frontmatter. If absent: print `> No execution record found. Run /loop /ship --execute first, then run /ship --verify.` Terminate.
3. Check that `execution.baseline_commit` is present. If absent: print `> No baseline commit recorded. This manifest was created before baseline tracking was added. Re-run the execution loop to record a baseline.` Terminate.

**State initialization (scaffolding-on-demand):** Create `execution.verification:` block nested inside `execution:`. Get timestamp via `date '+%Y-%m-%d_%H-%M-%S'` via Bash tool. Write manifest, read back (L3).

```
execution:
  ...
  verification:
    status: running
    started_at: <timestamp>
```

**Read-only contract:** Verification mode never modifies gap `Status` columns, `gaps_total`, `gaps_resolved`, `gaps_skipped`, or top-level `status`. All verification state lives in `execution.verification:` exclusively.

**Re-read MCP availability:** Load `execution.mcps_available` from manifest. Use this list for Steps 4-5.

## Step 1 -- Manifest Check

Walk each row in `## Gaps` where `Status == completed`.

For each completed gap:
1. Extract the file path from the `Location` column. If `Location` is "missing", classify as `unverified` and continue.
2. Run `git diff <execution.baseline_commit>..HEAD -- <location-file>` via Bash tool.
3. Check if the diff is non-empty (file was changed since baseline).
4. Grep the diff output for a key action term from the gap's `Gap` description column (e.g., if gap says "Firebase.initializeApp() call absent", grep for "initializeApp"). A rough match suffices -- this is a quick check.

**Classify each gap:**
- `verified`: diff non-empty AND grep match found.
- `unverified`: diff non-empty but grep match not found (file changed, action unclear).
- `missing`: diff empty (no change to this file since baseline).

Accumulate classifications in memory (`{gap_id, classification, file}`). Do NOT modify the manifest gap table.

## Step 2 -- Build Check

Detect build command from stack:

| Stack | Build command |
|-------|---------------|
| Flutter | `flutter build apk` |
| Node/npm | `npm run build` |
| Python | `python -m build` |
| Go | `go build ./...` |
| Rust | `cargo build` |
| Ruby | `bundle exec rake build` |

If no build command detectable: skip, record `build_result: skipped`.

Run command via Bash tool. Capture output.

- **Pass:** exit code 0 -> `build_result: pass`.
- **Fail:** non-zero exit or error lines -> `build_result: fail`. Store first 3 error lines as `build_error_summary`.

## Step 3 -- Test Suite

Detect test command from stack (same table as Execution Step 4):

| Stack | Test command |
|-------|-------------|
| Flutter | `flutter test` |
| Node/npm | `npm test` |
| Python | `pytest` |
| Go | `go test ./...` |
| Rust | `cargo test` |
| Ruby | `bundle exec rspec` |

If no test command detectable: skip, record `test_result: skipped`.

Run command via Bash tool. Parse output for pass/fail/skip counts. Record:
- `test_result: pass | fail | skipped`
- `test_pass_count: <N>`
- `test_fail_count: <N>`
- `test_skip_count: <N>`

## Step 4 -- Critical Category Agents

Check completed gaps from Step 1 against these triggers:

| Trigger | Agent role | Dispatch when |
|---------|-----------|--------------|
| Any `completed` gap with `Severity == blocking` | Config Validator | At least one blocking gap completed |
| Any `completed` gap in a category matching `UI*` | UI Coherence Checker | Completed gaps include UI Completeness category |
| Any `completed` gap in a category matching `Auth*` or `Security*` | Security Spot Check | Completed gaps include Auth or Security category |

If no triggers match: print `> No critical categories require agent verification.` Skip to Step 5.

**Dispatch all triggered agents in a single parallel Agent tool call block.** Each agent prompt must be fully self-contained.

Config Validator prompt template:
```
You are a Config Validator. Read-only scan -- do not modify any files.

Context:
- Project root: <absolute path>
- Stack: <comma-separated stack>
- Blocking gaps that were completed: <list of gap IDs, descriptions, and Notes answers>
- Baseline commit: <execution.baseline_commit>

Your job:
1. Read the files referenced in gap Notes columns.
2. Run git diff <baseline>..HEAD for each referenced file via Bash tool.
3. Verify: config values are set (no placeholder text like REPLACE_ME or your_key_here remaining), no obviously missing required values.

Output format: one line per issue: "ISSUE | <severity: high|medium|low> | <file:line> | <description>". If no issues: output exactly "NO_ISSUES".
```

UI Coherence Checker prompt template:
```
You are a UI Coherence Checker. Read-only scan -- do not modify any files.

Context:
- Project root: <absolute path>
- Stack: <comma-separated stack>
- UI gaps that were completed: <list of gap IDs, descriptions, and Notes answers>
- Baseline commit: <execution.baseline_commit>
- MCPs available: <execution.mcps_available>

Your job:
1. Read the UI files referenced in gap Notes columns.
2. Run git diff <baseline>..HEAD for each referenced file via Bash tool.
3. Check: navigation links wired to real destinations, no broken imports, no placeholder TODO or lorem ipsum text remaining.

Output format: "ISSUE | <severity> | <file:line> | <description>". If no issues: "NO_ISSUES".
```

Security Spot Check prompt template:
```
You are a Security Spot Check agent. Read-only scan -- do not modify any files.

Context:
- Project root: <absolute path>
- Stack: <comma-separated stack>
- Auth/security gaps that were completed: <list of gap IDs, descriptions, and Notes answers>
- Baseline commit: <execution.baseline_commit>

Your job:
1. Read the auth/security files referenced in gap Notes columns.
2. Run git diff <baseline>..HEAD for each referenced file via Bash tool.
3. Check: auth flow complete (no missing wiring), no credentials hardcoded in diffs, input validation present at auth endpoints.

Output format: "ISSUE | <severity> | <file:line> | <description>". If no issues: "NO_ISSUES".
```

After agents return: parse all `ISSUE |` lines. Collect findings for the Step 6 report.

## Step 5 -- UI Smoke Test

Check `execution.mcps_available`:
- Contains `xcode`: use xclaude-plugin MCPs.
- Contains `browser`: use browser MCP.
- Empty or neither present: print `> UI smoke test skipped: no UI MCP available.` Record `ui_smoke_result: skipped`. Skip to Step 6.

**If MCP available:**
1. Build and launch the app using the appropriate MCP tool.
2. Navigate main flows: launch screen, home/main screen, key feature screens identified from manifest categories.
3. Take a screenshot at each step using the MCP screenshot tool.
4. Flag screens showing: placeholder text (TODO, Coming Soon, lorem ipsum), blank screens, visible error messages, or crash dialogs.

Record `ui_smoke_result: pass | issues-found`. Store any flagged issues for the report.

## Step 6 -- Final Report + Termination

**Generate report:**

1. Get timestamp via `date '+%Y-%m-%d_%H-%M-%S'` via Bash tool.
2. Derive `<project>` from Step 0 (same as manifest filename stem without `-manifest`).
3. Write to `docs/ship/<project>-report-<timestamp>.md`:

```
---
name: <project>-ship-report
created: <timestamp>
manifest: docs/ship/<project>-manifest.md
---

# Ship Report: <project>

## Summary

- **Total gaps:** <gaps_total>
- **Completed:** <count completed> (verified: <N>, unverified: <N>, missing: <N>)
- **Blocked:** <count blocked>
- **Skipped:** <count skipped>
- **Build:** <pass | fail | skipped>
- **Tests:** <pass_count>/<pass_count+fail_count> passing (<fail_count> failures, <skip_count> skipped)

## Verification Results

### Passing

| # | Gap | Category | Verification |
|---|-----|----------|-------------|
<rows for verified gaps>

### Issues Found

| # | Gap | Category | Issue | Severity |
|---|-----|----------|-------|----------|
<rows from agent ISSUE lines + missing/unverified gaps>

## Blocked

| # | Gap | Reason |
|---|-----|--------|
<rows for blocked gaps with their Notes content>

## Skipped

| # | Gap | Reason |
|---|-----|--------|
<rows for skipped gaps with their Notes content>

## Action Items

<numbered list ordered by severity: high first. Format: [Severity] Description (gap #ID)>

## What's Next

<1-3 sentences: summary of remaining work. If all verified and build/tests pass, note the project appears complete.>
```

4. Read the report back to verify it was written (L3).

**Termination:**

1. Determine overall status: no agent issues, no missing gaps, build pass or skipped, tests pass or skipped -> `passed`. Otherwise -> `issues-found`.
2. Count `issues_total`: number of `ISSUE |` lines from agents + count of `missing` and `unverified` gaps.
3. Update `execution.verification:` block:
   - `status: passed | issues-found`
   - `completed_at: <timestamp>`
   - `build_result: <value>`
   - `test_result: <value>`
   - `issues_total: <count>`
4. Set `execution.status: verified`.
5. Write manifest, read back (L3).
6. Print: `> Verification complete. Report: docs/ship/<project>-report-<timestamp>.md. <issues_total> issues found.`

---

## Test Plan

**Trigger:** `/ship` and `/quiver:ship` (planning Q&A mode); `/loop /ship --execute` and `/loop /quiver:ship --execute` (Execution mode); `/ship --verify` (Verification mode)

**Setup (planning Q&A mode):** A project description as $ARGUMENTS (e.g., "a Flutter to-do app with Firebase sync"). Optionally a `--seed <spec.md>` file with stack and acceptance criteria. Run from any directory (git optional).

**Setup (Execution mode):** A project whose manifest at `docs/ship/<project>-manifest.md` is `status: complete` and contains at least two tasks with `Status: resolved` and distinct `parallel_group` values.

**Expected behavior:**
1. Shell blocks all exit 0 in both git and non-git directories.
2. Phase 0 reads $ARGUMENTS and presents a 1-2 sentence summary; no AskUserQuestion yet.
3. Phase 1 asks Q&A via AskUserQuestion until all 6 categories plus platform and deployment target are answered. Questions are batched per the batching rules.
4. Phase 2 presents the build plan table with `Parallel Group` column; user can approve, adjust, or restart.
5. Phase 3 writes `docs/ship/<project>-manifest.md` with `parallel_group` column in task table and `status: complete`; reads it back to verify.
6. A second run on the same project finds the existing manifest and offers Resume / Start fresh / Inspect.
7. `/ship --execute` on a `status: complete` manifest enters Execution Mode silently; no AskUserQuestion is called.
8. Bare `/ship` on a `status: complete` manifest where `execution.status` is not `verification-pending` shows interactive Resume / Start fresh / Inspect routing.
9. Execution mode reads `parallel_group` from manifest; tasks sharing a group ID are dispatched in parallel via Agent with `isolation: "worktree"`. Tasks with unique group IDs run sequentially.
10. If NO_GIT detected, parallel dispatch is skipped and all tasks run sequentially.
11. After each implementation agent returns, the output is scanned for `DISCOVERED |` tokens; discovered tasks are appended to the manifest as new `resolved` rows without stopping the current tick.
12. Retry loop runs build command first (if defined in manifest), then test command. 3-attempt cap applies across both.
13. Each completed task produces exactly one atomic commit with a Conventional Commits message; the manifest is never staged.
14. A task whose fix fails all 3 within-tick attempts is set to `blocked`; the loop continues to the next task.
15. The loop pauses (sets `execution.status: paused`, no ScheduleWakeup) after 3 consecutive no-progress ticks or 50 total ticks.
16. The manifest accurately reflects the `execution:` block state after each tick.

**Setup (Verification mode):** A project whose manifest has `execution.status: verification-pending`, `baseline_commit: <SHA>`, at least two `completed` tasks (one with blocking severity, one UI), and one `blocked` task. Run `/ship --verify` from the project root.

**Expected behavior (Verification mode):**
17. `/ship --verify` with no manifest terminates with `> No manifest found.` No ScheduleWakeup, no AskUserQuestion.
18. `/ship --verify` with a manifest but no `execution:` block terminates with `> No execution record found.`
19. `/ship --verify` with a manifest whose `execution:` block lacks `baseline_commit` terminates with `> No baseline commit recorded.`
20. Bare `/ship` on a manifest with `execution.status: verification-pending` auto-enters Verification Mode, printing `> Execution complete. Starting verification...` without showing the routing dialog.
21. Verification Step 1 classifies completed tasks as verified/unverified/missing. The manifest task table is never modified during verification.
22. Verification Step 4 dispatches agents only when triggers match. A manifest with no blocking/UI/auth-security completed tasks prints `> No critical categories require agent verification.` and skips agents.
23. Report generated at `docs/ship/<project>-report-<timestamp>.md`. A second `/ship --verify` run creates a new timestamped report without overwriting the first.
24. After verification completes, `execution.status: verified` is set. Subsequent bare `/ship` shows the normal Resume / Start fresh / Inspect routing dialog.

**Verification checklist:**
- [ ] `/ship` and `/quiver:ship` both appear in the slash command menu after plugin reload.
- [ ] All five shell blocks exit 0 in a git repo; all five exit 0 (with NO_GIT output) in a non-git directory.
- [ ] No plain-text questions to the user -- every user prompt uses AskUserQuestion (R5).
- [ ] No AskUserQuestion reachable from any Execution-mode tick path.
- [ ] Phase 3 writes manifest with `parallel_group` column; manifest read back to verify after write.
- [ ] Manifest read back after every write (L3 verification) -- including after each tick's Step 7 state update.
- [ ] Second run on a project with an existing manifest routes through State Detection and offers Resume / Start fresh / Inspect.
- [ ] `--execute` on a partial or absent manifest terminates with a message; no ScheduleWakeup, no prompt.
- [ ] `--execute` + `--resume` together: `--resume` wins; Q&A resume path runs.
- [ ] Execution mode reads `parallel_group` from manifest; no independence computation at dispatch time.
- [ ] `DISCOVERED |` token in agent output appends a new `resolved` row to the manifest without stopping the current tick.
- [ ] Retry loop runs build command before test command (when build command is defined).
- [ ] Execution-mode commit stages specific files only; manifest never staged; no `git add .`.
- [ ] No push and no AI attribution in Execution-mode commits (R9).
- [ ] `--execute` on a partial or absent manifest terminates; no ScheduleWakeup called.
- [ ] No `CLAUDE_PLUGIN_ROOT` references in this file (R4).
- [ ] No Unicode characters or emoji in this file (R8).
- [ ] No new inline `!` shell blocks added to Execution Mode (R3).
- [ ] `when-to-use:` field is a single-line double-quoted string (R10).
- [ ] All `!` shell blocks use git commands only; no `||` with non-git commands (L1).
- [ ] `--verify` flag routes to Verification Mode; State Detection skipped.
- [ ] `--verify` + `--resume` together: `--resume` wins, Q&A resume path runs.
- [ ] Bare `/ship` on `execution.status: verification-pending` manifest auto-enters Verification Mode without routing dialog.
- [ ] Verification Mode never writes to task `Status` columns (read-only contract enforced).
- [ ] `execution.verification:` block created lazily at Entry.
- [ ] Report saved at `docs/ship/<project>-report-<timestamp>.md` with timestamp in filename.
- [ ] Re-running verification creates a new timestamped report, not overwriting previous one.
- [ ] `execution.status: verified` set after Verification Mode Step 6 completes.
- [ ] `execution.baseline_commit` present in `execution:` block after first execution tick.

**Known gotchas:**
- Plugin auto-discovery requires a plugin reload after the skill is first installed. `/ship` will not appear in the slash menu until the plugin reloads.
- The Glob check for `docs/ship/*.md` returns empty on the first run -- the skill must not abort on this empty result.
- `docs/ship/<project>-manifest.md` lives inside `docs/`, which is gitignored. The manifest is intentionally not committed to version control.
- The `--resume` flag bypasses State Detection routing entirely -- use it when you know a manifest exists and want to skip the routing dialog.
- `--execute` on a partial manifest must terminate, not hang. The termination path must NOT call ScheduleWakeup; omitting the call ends the loop.
- Parallel batches dispatch tasks with matching `parallel_group` via worktrees; a merge conflict marks affected tasks `blocked` and stops the batch without auto-resolution.
- ScheduleWakeup at exactly 300s is wrong: it pays the cache miss without amortizing it. Use 60s (momentum) or 270s (blocked/low-progress) only.
- `execution.baseline_commit` is only recorded at first tick. Manifests created before this field was added will trigger the "No baseline commit recorded" guard in Verification Mode -- re-run the execution loop to generate a new manifest.
- Verification report files live in `docs/ship/`, which is gitignored. Reports are intentionally local only.
- Timestamped report filenames (`<project>-report-<YYYY-MM-DD_HH-MM-SS>.md`) are intentional -- each verification run produces a new file. Do not change to a fixed filename; history would be lost.
- The `execution.verification:` block is nested inside `execution:` in YAML frontmatter. Read and write it as a nested block. Flattening it to top-level keys would break the read-only contract separation.
- Verification dispatches agents for blocking/UI/auth-security categories only. Running agents for all categories would be wasteful and is not part of this mode.
