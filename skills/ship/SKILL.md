---
name: ship
description: "Take a project from description to working app in one run -- conduct a deep planning Q&A session (outcomes, scope, constraints, prior decisions, task breakdown, verification criteria), write the answers as a plan at .claude/plans/<date>-<project>-ship-plan.md in the format /plan produces, hand that plan to /work --auto for a build that stops only for a genuine blocker, then verify the result with the build command, the test suite, a /review pass with one fix round, and a smoke launch when the plan carries a run command. /ship --execute and /ship --verify re-enter a run that was paused or deferred."
argument-hint: "[<project-path>] [--seed <brainstorm-spec.md>] [--resume] [--execute] [--verify]"
when-to-use: "user wants to build a project from scratch or description -- '/ship', 'build this app', 'I described my project, now build it', 'start from description and ship', 'autonomous build', 'I want to walk away and come back to a finished app', 'verify my build' (not: gap-analysis on existing partial code; not: executing a plan you already have -- use '/work' for that; '/ship --execute' hands a saved ship plan to /work, '/ship --verify' checks a finished build)"
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

You are a build orchestrator. Your job is to conduct a deep planning Q&A session with the user -- covering every detail needed to build the project without further human input -- write the answers as a plan `/work` can execute, hand that plan to `/work`, and verify what it built. The user answers questions once, approves once, and comes back to a built and verified project -- never to a prompt asking them to run the next command. You do NOT guess requirements. If a detail is not provided and it affects what gets built, you ask.

Ship runs no task and dispatches no subagent. `/work` executes the plan and `skills/work/orchestrator.md` is the only orchestrator. The questions are front-loaded: Phase 1 asks everything the build could otherwise stop to ask, and `/work` runs in its auto mode, which answers the routine gates -- branch, final commit, PR handoff, workspace, third failed fix attempt -- from the approval already given. A blocker, an unaddressed Critical finding, a merge conflict -- anything whose answer changes what gets built or deletes something -- still stops and asks. Ship never decides those on the user's behalf, and never grants a fix attempt past `/work`'s cap.

## Step 0 -- Git Availability

If any gather-context block returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- using current working directory as project root.`
Proceed normally. The Q&A works without git; `/work` degrades on its own (no branch, no commits, no PR).

**Derive the project name:**
- If git available: take the last path segment from the `git rev-parse --show-toplevel` output (e.g., `/Users/alice/projects/my-app` -> `my-app`).
- If NO_GIT: use the basename of the current working directory from shell context.

Use `<project>` as the derived name throughout the skill.

## Step 0.5 -- Argument Parsing

Read `$ARGUMENTS` as plain text:

- If it contains `--execute`: set execution intent; skip interactive State Detection entirely and enter `# Execution`. Do not continue into Step 1.
- If it contains `--verify`: set verification intent; skip interactive State Detection entirely and enter `# Verification`. Do not continue into Step 1.
- If it contains `--resume`: jump directly to the Step 1 Resume path (act as if exactly one ship plan was found -- the most recently modified when several exist -- and the user picked "Resume").
- **Precedence:** `--resume` > `--verify` > `--execute`. If `--resume` is present, clear all other intents and follow the Resume path. If `--verify` is present without `--resume`, clear execution intent and enter `# Verification`.
- If it contains `--seed <path>`: note the seed path. Read the spec file in Phase 0 and extract all context: stack, services, data model, any acceptance criteria present.
- If it contains a path that is not a flag (e.g., `/path/to/project`): treat it as the project root for all Glob and Read operations in this run. Derive `<project>` from this path's basename instead.
- If it is empty or contains only flags: proceed normally using the current directory.

## Step 1 -- State Detection

**Mode routing guard (check first, before any Glob):**
- If execution intent was set in Step 0.5 (`--execute`), do not run State Detection. Go directly to `# Execution`.
- If verification intent was set in Step 0.5 (`--verify`), do not run State Detection. Go directly to `# Verification`.

**The flags are entry points for an interrupted or deferred run, not the normal path.** A run started from Q&A reaches execution and verification on its own. `--execute` is for resuming after an interruption or for a plan approved with "plan only"; `--verify` is for re-verifying a finished build.

### Locating the ship plan

Used here and by both re-entry modes. Use the Glob tool: `.claude/plans/*-ship-plan.md`.

A ship plan's state is read from disk, never remembered:

- **in progress** -- its work ledger exists at `.claude/work/<plan-basename>/progress.md`, where `<plan-basename>` is the plan filename without `.md`. `/work` writes the ledger for plans of 3+ tasks and leaves it in place after an interrupted run.
- **finished** -- the plan's frontmatter reads `status: completed`; `/work` Phase 5c sets it when its run completes.
- **not started** -- neither of the above.

**Zero plans (first run):** proceed to Phase 0.

**One plan found:** read it, then use `AskUserQuestion`:
> Found an existing ship plan: `<path>` (<not started | in progress | finished>). How would you like to proceed?

Buttons: `["Resume -- hand the plan to /work", "Start fresh -- run a new Q&A", "Inspect -- show me the plan"]`

- **Resume:** for a not-started or in-progress plan, enter `# Execution` with this plan path. For a finished plan there is nothing left to build -- enter `# Verification` instead.
- **Start fresh:** proceed to Phase 0. The existing plan stays on disk; Phase 3 writes a new one at today's path. A second run on the same day lands on the same path and overwrites it -- the Phase 2 approval is the consent for that write.
- **Inspect:** print the full plan contents. Then use `AskUserQuestion`:
  > What would you like to do next?
  Buttons: `["Resume", "Start fresh", "Cancel"]`
  - Cancel: stop immediately. Do nothing.
  - Resume and Start fresh: as above.

**Multiple plans found (multi-project workspace):**
Use `AskUserQuestion`:
> Multiple ship plans found. Which one would you like to work on?

List each plan filename with its state as a button label (up to 4; show the 4 most recently modified if more exist). Add a final button: `"Start a new project"`.

- Selecting an existing plan: same routing as "One plan found" above.
- Selecting "Start a new project": proceed to Phase 0.

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
| 5 | Task breakdown | AI proposes a task list, user approves or adjusts; dependencies noted per task |
| 6 | Verification criteria | User named a test command or described a manual acceptance check, and said whether a command launches the app (recorded as the run command, or none) |
| + | Platform | iOS, Android, web, CLI, backend, desktop |
| + | Deployment target | App Store, Google Play, Vercel, self-hosted, local only |

Batching rules:
- Ask outcomes first (standalone).
- Batch platform + deployment together (independent questions).
- Batch constraints + prior decisions together if neither depends on the other's answer.
- Ask task breakdown after outcomes and scope are known (it depends on them).
- Ask verification after task breakdown (user knows what tasks to verify).

Q&A runs until all categories are answered. If the user answers partially (e.g., "not sure about verification"), prompt once more for that category before proceeding.

Ask here anything that would otherwise become a question during the build: a service or library choice the task list leaves open, a data shape two tasks share, a name the user cares about, an environment the tests need. Ten questions up front cost less than one interruption mid-run. After Phase 2 the only questions left are `/work`'s blocker gates.

## Phase 2: Plan Summary + Approval

Present a build plan table:

```
| ID | Task | Blocked by | Acceptance Criterion |
|----|------|------------|----------------------|
| 1  | ...  | --         | ...                  |
| 2  | ...  | 1          | ...                  |
| 3  | ...  | 1          | ...                  |
```

`Blocked by` carries the dependencies from Q&A category 5. `/work` builds its execution groups from these and from file overlap (`skills/work/orchestrator.md` Section 1): tasks with no unmet dependency run in parallel, the rest wait.

Use AskUserQuestion:
> Does this plan cover everything you need? Approving starts the build -- I write the plan, hand it to /work, then verify the result. Nothing stops to ask again unless a task blocks, a review finding is Critical, or a merge conflicts.

Options: "Approve -- build it", "Approve the plan only -- do not build yet", "Add or change something", "Start over"

On "Add or change something": ask what to change, update the table, re-present. On "Start over": return to Phase 0.

**"Approve -- build it" is the run's single consent point (R6).** It authorizes the plan write, the handoff to `/work --auto`, every per-task commit, the verification pass, and the one review fix round. Proceed to Phase 3 and do not stop between phases. It does not authorize a push or a pull request -- those are never automatic -- and it does not stand in for a blocker: `/work` still asks when a task cannot proceed, a Critical finding is unaddressed, or a merge conflicts.

**"Approve the plan only"** writes the plan and stops there, for a user who wants to read or edit it first. Print the plan path and the `/ship --execute` command, then terminate.

## Phase 3: Plan Write

Get the date via the Bash tool (`date '+%Y-%m-%d'`) and write `.claude/plans/<date>-<project>-ship-plan.md`, creating `.claude/plans/` if it does not exist. The file is a plan in the format `skills/plan/SKILL.md` Step 5 defines -- read that section before writing, and do not improvise a format of your own. `/work` reads this file exactly as it reads a `/plan` output; the format has one home, and this skill does not restate it.

What the Q&A answers become:

- **Frontmatter:** `name: <project>-ship-plan`, `status: active`, `created: <date>`, then `stack`, `platform`, and `deployment_target` from the Phase 1 answers, then `test_command`, `build_command`, and `run_command`. `stack` carries the tech-stack half of the category 3 answer. `test_command` and `build_command` are resolved once, here, by reading `skills/verification/SKILL.md` and following its Command Resolution, with the Phase 1 category 6 answer as rule 1 when it names a command. Each holds the command string or `none (<reason>)`, never an empty field. `run_command` holds the launch command category 6 named, or `none`.
- **Goal:** the category 1 outcomes, as the plan's opening section.
- **`## Global Constraints`:** the section Step 5 defines, holding the category 3 answer -- the library restrictions and stated limits, one imperative sentence per numbered entry -- and the category 2 scope boundaries as "Do not build ..." entries, which is how Step 4.5 treats out-of-scope items. `/work` copies this section verbatim into every task brief and `/review --plan` binds its findings to it, so a constraint the plan does not record is one no implementer can honor.
- **Tasks:** one per row of the approved Phase 2 table, in the task format Step 5 defines, each with its `**Files:**` line, its `**Provides:**` line where another task names what it creates, and its acceptance criterion from the table. A dependency from the `Blocked by` column is written as a `blockedBy: [<task numbers>]` line under the task's `**Files:**` line -- the explicit-dependency field `skills/work/orchestrator.md` Section 1 reads; a task with none carries no line. When `test_command` is not `none`, order each task's steps test-first as Step 5 describes, naming `skills/tdd/SKILL.md`; `/work` follows that cycle when it builds.
- **Acceptance Criteria:** the category 1 outcomes and the category 6 check, as the plan's closing section.

Then run the eight checks of `skills/plan/SKILL.md` Step 6 by reading that section. The Q&A answers (and the `--seed` spec, when given) are the source specification Check 3 reads. Apply its action routing; do not present the checks to the user.

After writing: read the plan back and confirm the `## Global Constraints` heading and at least one `**Provides:**` line are present. Category 2 always names something not being built, so the heading is always there; a plan whose tasks share no symbol is a Check 8 miss, not a valid ship plan -- fix it before continuing.

Print: `> Plan complete: <N> tasks. Saved to .claude/plans/<date>-<project>-ship-plan.md.`

Then route on the Phase 2 answer:

- **"Approve -- build it":** print `> Building.` and continue straight into `# Execution`. Do not ask again, do not print a command for the user to run, and do not wait for a reply.
- **"Approve the plan only":** print `> Plan saved. Run /ship --execute when you want the build.` and terminate.

---

# Execution

Consent for this phase was given at Phase 2's "Approve -- build it", or by the `/ship --execute` invocation. Ship implements nothing here: it hands the plan to `/work` and waits.

**Locate the plan.** When entered from Phase 3, the plan is the file just written. On `--execute` re-entry, locate it as Step 1 describes; with no ship plan, print `> No ship plan found. Run /ship first.` and terminate; with several, ask which one with `AskUserQuestion` (up to 4, most recent first).

**Stay on the branch ship started on.** Ship creates no branch. Started on `main` or `master`, `/work` Phase 2 creates the feature branch itself; started on a feature branch, its auto mode continues there. Do not switch branches to pre-empt either case.

**Hand off.** Invoke the `work` skill through the Skill tool with the plan path and `--auto` as its arguments (`/work <plan path> --auto`), and let it run to completion. `/work` loads the file as a plan (its Case A path), resolves the verification command per `skills/verification/SKILL.md`, follows `skills/tdd/SKILL.md` on every task under its three-attempt fix cap, lets a subagent make the small wiring edits a task needs outside its file list and report them as discovered, commits per task, and in auto mode answers its routine gates from the Phase 2 approval: it continues on the current branch, commits the final leftovers, prints `/review` and `/create-pr` as text instead of running them, and keeps its workspace. It still stops for a blocker, an unaddressed Critical finding, or a merge conflict; when it does, that question is the user's, not ship's -- never answer it for them.

**Continue.** When `/work` returns, print `> Build finished. Verifying.` and continue into `# Verification` in this same invocation. A `/work` run that stopped on a blocker or a merge conflict has said so; still run verification -- its report is where the remaining work is listed.

**Re-entry.** `/ship --execute` invokes `/work` with the same plan path and `--auto`. For a plan of 3+ tasks `/work` resumes from its ledger at `.claude/work/<plan-basename>/progress.md` and re-dispatches no task carrying a `complete` line. A 1-2 task plan has no ledger; `/work` runs it from the top on the branch that carries the earlier commits.

---

# Verification

This phase checks what `/work` built. It runs the build, runs the tests, reviews the branch, spends one fix round on the review's Critical and High findings, smoke-launches the app when the plan carries a run command, and writes a report. It changes no plan field.

## Entry

**Triggers:** `--verify` (set in Step 0.5), or continuation from `# Execution`.

1. Locate the ship plan as Step 1 describes. With no ship plan, print `> No ship plan found. Run /ship first.` and terminate. With several, ask which one with `AskUserQuestion`.
2. Read `test_command`, `build_command`, and `run_command` from the plan frontmatter. A field that is absent resolves to `none (field missing)`; do not write it back.
3. Note the current branch from the gather-context output. Verification runs on the branch `/work` left the session on.

## Step 1 -- Build

When `build_command` is `none`: print `Build: skipped -- <reason>`.

Otherwise run it via the Bash tool and quote one evidence line per the Evidence Rule in `skills/verification/SKILL.md`: `pass: <command> -> exit 0: <summary line>` or `fail: <command> -> exit <code>: <first error line>`.

## Step 2 -- Tests

When `test_command` is `none`: print `Tests: skipped -- <reason>`.

Otherwise run it via the Bash tool and quote one evidence line per the same Evidence Rule. A run whose summary line shows zero tests executed is `skipped: <reason>`, never `pass` -- cross-cutting rule 1 of that file.

## Step 3 -- Review and One Fix Round

Invoke the `review` skill on the working branch in its default fast mode, passing `--base <default branch>` (`main` or `master`, whichever the repository has) so it does not ask for the base branch, and `--plan <ship plan path>` so its Global Constraints bind the findings. The skill saves its report under `.claude/reports/` and names the path; read that report.

- **No Critical or High findings:** print `Review: <N> findings, none Critical or High` and continue.
- **Critical or High findings present:** invoke the `work` skill once with the report path and `--auto` as its arguments. `/work` loads the report as its specification (its Case A path); its Critical-finding gate still asks when a Critical finding stays unaddressed after the fix. When it returns, re-read the report and print `Review: <N> findings, <M> Critical/High, fix round done -- <K> still open`. Stop after that single pass whatever remains; a second round is the user's call, and the report lists what is left.

Skip this step with `Review: skipped -- no git repository` when Step 0 detected `NO_GIT`.

## Step 4 -- Smoke

When `run_command` is `none`: print `Smoke: skipped -- no run command`.

Otherwise launch the app with the run command via the Bash tool with `run_in_background`, then wait on a cheap readiness condition -- a port answering, a "Ready" log line, a booted simulator -- inside an `until` loop with a deadline of at most 120 seconds and a failure check on the log (a crash line, `Error:`, `EADDRINUSE`). Never poll by re-running the launch command. When a screenshot tool is available in the session (an iOS simulator or browser MCP), capture the first screen and flag placeholder text, a blank screen, or a visible error. Stop the process when done.

Record `Smoke: pass`, `Smoke: fail -- <first error line>`, or `Smoke: timeout -- <condition> not met in <N>s`.

## Step 5 -- Report

Get a timestamp via the Bash tool (`date '+%Y-%m-%d_%H-%M-%S'`) and write `.claude/reports/ship-<project>-<timestamp>.md`, creating the directory if needed:

```
# Ship Report: <project>

- **Plan:** <ship plan path>
- **Branch:** <branch>
- **Build:** <evidence line or skipped reason>
- **Tests:** <evidence line or skipped reason>
- **Review:** <report path> -- <N> findings, <M> Critical/High, <K> open after the fix round
- **Smoke:** <result>

## Open Items

<numbered list: every Critical/High finding still open, every task /work reported blocked or failed, every smoke flag. "None." when empty.>

## What's Next

<1-3 sentences. When every line above is a pass or a skip and Open Items is empty, say the project appears complete and name the branch to merge.>
```

Read the report back to confirm it was written (L3). Print `> Verification complete. Report: <path>. <count> open items.` and terminate.

A second `/ship --verify` writes a new timestamped report; earlier ones are never overwritten.

---

## Test Plan

**Trigger:** `/ship` and `/quiver:ship` (Q&A, then build, then verification); `/ship --execute` (hand a saved ship plan to `/work`); `/ship --verify` (verification only)

**Setup (Q&A):** A project description as $ARGUMENTS (e.g., "a Flutter to-do app with Firebase sync"). Optionally a `--seed <spec.md>` file with stack and acceptance criteria. Run from the default branch of a git repository; a non-git directory also works.

**Setup (`--execute`):** A ship plan at `.claude/plans/<date>-<project>-ship-plan.md` with three or more tasks and, for the resume case, a ledger at `.claude/work/<plan-basename>/progress.md` carrying at least one `complete` line.

**Setup (`--verify`):** A ship plan whose branch `/work` has finished, with `test_command` and `build_command` resolved and `run_command` set to a real launch command in one variant and `none` in another.

**Expected behavior:**
1. Shell blocks all exit 0 in both git and non-git directories.
2. Phase 0 reads $ARGUMENTS and presents a 1-2 sentence summary; no AskUserQuestion yet.
3. Phase 1 asks Q&A via AskUserQuestion until all 6 categories plus platform and deployment target are answered; category 6 records a run command or `none`.
4. Phase 2 presents the table with a `Blocked by` column; the approve question says `/work` asks before committing or opening a PR.
5. Phase 3 writes the plan in the `skills/plan/SKILL.md` Step 5 format, runs the Step 6 checks, reads the file back, and confirms `## Global Constraints` and a `**Provides:**` line are present.
6. "Approve -- build it" flows Q&A -> plan -> `/work --auto` -> verification -> report in one invocation; no question is asked between approval and the report unless a task blocks, a Critical finding stays unaddressed, or a merge conflicts.
7. "Approve the plan only" writes the plan, prints the `/ship --execute` command, and terminates without building.
8. Execution invokes `work` through the Skill tool with the plan path and `--auto`; ship creates no branch and calls no Agent.
9. `/ship --execute` on a plan with a ledger re-dispatches no task carrying a `complete` line; on a plan without one, `/work` starts from the first task.
10. A second bare `/ship` finds the plan and offers Resume / Start fresh / Inspect, with the state read from the ledger and the `status` field.
11. Verification Steps 1-2 quote an evidence line each, or a skipped reason; a zero-test run is `skipped`, never `pass`.
12. Verification Step 3 invokes `review` with `--base` and `--plan`; a report with a Critical or High finding triggers exactly one `work --auto` pass on the report path, and a second round is never started.
13. Verification Step 4 launches the app only when `run_command` is not `none`; otherwise it prints `Smoke: skipped -- no run command`.
14. The report lands at `.claude/reports/ship-<project>-<timestamp>.md`; a second `--verify` adds a file and overwrites nothing.

**Verification checklist:**
- [ ] `/ship` and `/quiver:ship` both appear in the slash command menu after plugin reload.
- [ ] All five shell blocks exit 0 in a git repo; all five exit 0 (with NO_GIT output) in a non-git directory.
- [ ] No plain-text questions to the user -- every user prompt uses AskUserQuestion (R5).
- [ ] The plan frontmatter carries `stack`, `platform`, `deployment_target`, `test_command`, `build_command`, and `run_command`, none empty.
- [ ] Phase 1 category 3 lands in the plan: the tech-stack half in `stack`, the restrictions under `## Global Constraints`. A user who answered "no ORM, raw SQL only" can find that sentence in the plan.
- [ ] Every task carries `**Files:**`; every task another task names carries `**Provides:**`; no task carries a `none` placeholder.
- [ ] Plan read back after the write (L3); report read back after the write.
- [ ] Ship invokes `work` and `review` through the Skill tool and never calls the Agent tool itself.
- [ ] Ship never creates a branch, never commits, never pushes, and never opens a PR; `/work --auto` commits, and pushes or opens nothing.
- [ ] Both `work` invocations carry `--auto`; a run with no blocker reaches the report with no question after Phase 2.
- [ ] `--execute` with no ship plan terminates with a message; no prompt.
- [ ] `--execute` + `--resume` together: `--resume` wins; the Step 1 Resume path runs.
- [ ] `--verify` + `--resume` together: `--resume` wins.
- [ ] `--verify` runs only the verification phase and changes no plan field.
- [ ] Verification Step 3 stops after one fix round however many findings remain.
- [ ] No `CLAUDE_PLUGIN_ROOT` references in this file (R4).
- [ ] No Unicode characters or emoji in this file (R8).
- [ ] No new inline `!` shell blocks beyond the five git blocks (R3).
- [ ] `when-to-use:` field is a single-line double-quoted string (R10).
- [ ] All `!` shell blocks use git commands only; no `||` with non-git commands (L1).
- [ ] This file names `skills/plan/SKILL.md`, `skills/verification/SKILL.md`, and `skills/tdd/SKILL.md` and restates none of them.

**Known gotchas:**
- Plugin auto-discovery requires a plugin reload after the skill is first installed. `/ship` will not appear in the slash menu until the plugin reloads.
- The Glob for `.claude/plans/*-ship-plan.md` returns empty on the first run -- the skill must not abort on this empty result.
- `.claude/plans/` and `.claude/work/` are the same directories `/plan` and `/work` use, so a ship plan is visible to `/work` Case B's plan picker and resumes from the same ledger. That is the point: ship writes a plan, not a format of its own.
- Phase 2's approval is the run's last routine question because `/work --auto` answers the rest from it. The questions that survive -- a blocker, an unaddressed Critical finding, a merge conflict -- are the ones whose answer changes what gets built; ship must not answer those for the user, and must not add a flag that skips them.
- The three-attempt fix cap lives in `/work` (Phase 3 and the orchestrator prompt), not here. Ship adds no retry of its own; a task accepted after three failures shows up in `/work`'s summary and again in verification.
- Starting ship on a feature branch makes `/work --auto` continue on that branch. Start on the default branch when the build should land on a fresh one.
- The task format, its `**Provides:**` field, and the eight plan checks live in `skills/plan/SKILL.md`; `tests/skills/test-task-interfaces-contract.sh` pins them there. Restating them here is the drift this rewrite removed.
- The verification and TDD subagent restatements are pasted only into `skills/work/orchestrator.md`. Ship dispatches no subagent, so it carries neither; the contract tests check the orchestrator's copy alone.
- Verification Step 3 passes `--base` so `/review` does not prompt for the base branch on a feature branch, and `--plan` so its Step 1.8 finds the Global Constraints. Dropping either makes the pass interactive or blind to the constraints.
- A `/work` run that ends blocked keeps its ledger on purpose; `/ship --execute` is the retry, and the ledger is what makes it cheap.
