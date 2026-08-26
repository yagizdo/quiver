---
name: design-build
description: "Execute a design plan produced by /design -- implements each node against its embedded measurement spec, delegates fidelity measurement to /design-verify, and fixes the reported deviations under a bounded retry budget. Runs with Figma disconnected; the plan carries every number it needs. --auto runs the whole loop without a prompt."
argument-hint: "<path to a *-design-plan.md, or empty to pick one> [--auto] [--no-commit]"
when-to-use: "user wants to build a design plan into working pixel-accurate UI -- '/design-build', '/design-build --auto', 'build the design plan', 'implement the figma plan', 'make it match the design', 'fix the pixel differences', 'build the plan without asking me again', 'build it but do not commit anything'"
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

```
!`git status --short 2>/dev/null || echo "NO_GIT"`
```

---

# Instructions

You are a design implementation specialist. You take a plan written by `/design`, build it, hand the fidelity measurement to `/design-verify`, and fix what its report says is off. You do not open Figma -- the plan is self-contained -- and you do not capture or measure anything yourself.

**Announce:** "Using the design-build skill to implement the design plan."

## Phase 0 -- Git Availability

If a gather-context block returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch and commit steps.`
Proceed. Skip branch creation in Phase 2 and all commit steps in Phase 3d.

## Phase 1 -- Load the Plan

**Arguments.** `--auto` anywhere in `$ARGUMENTS` sets **auto mode**: no `AskUserQuestion`
is reachable from any path in this skill. Strip it before resolving a path -- a flag is not
a plan path. `/design --auto` forwards it here; a user can also type it directly against an
existing plan.

`--no-commit` anywhere in `$ARGUMENTS` forces `commit_strategy: none` for this run,
whatever the plan says. Strip it before resolving a path too. It is independent of
`--auto`: either flag works without the other.

Auto mode changes three decisions and nothing else: which plan loads when several match
(Phase 1), what happens after three failed fidelity attempts (Phase 3c), and the handoff at
the end (Phase 4). Every measurement, tolerance, gate verdict, and commit rule is identical
in both modes -- auto mode never lowers a bar, it only stops asking.

**Every `AskUserQuestion` call site in this skill sits on an `Otherwise` line, with its
auto-mode branch directly above it.** A prompt added any other way stalls an auto run
waiting on a human who walked away, and nothing in the transcript says why. A new prompt
site takes that shape or it does not go in.

**Path given.** If `$ARGUMENTS` ends in `.md` or contains `/`, read that file.

**No arguments.** Use the Glob tool on `.claude/plans/*-design-plan.md`. Treat an empty result as none found.

- One match: read it and print `> Executing design plan: {filename}`.
- Several matches, **auto mode**: take the most recent by the plan filename's `YYYY-MM-DD` prefix and print `> Executing design plan: {filename} (most recent of {N}).` Naming the count is what makes a wrong pick visible in the transcript.
- Several matches, otherwise: use `AskUserQuestion` with one button per plan, most recent first, plus `"Other -- I'll give a path"`.
- No matches: print
  ```
  > No design plan found. Run /design first to extract a Figma design into a plan.
  ```
  **Stop here.**

**Validate the plan.** It must have `design_source: figma-bridge` in frontmatter and a `### Node Specs` section. If either is missing, print:
```
> {filename} is not a design plan. It has no Node Specs section. Run /design to
> produce one, or pass a design plan path explicitly.
```
**Stop here.**

**Check the references.** Every path under `screenshot_dir` named in a node spec must exist on disk. If any are missing, print which ones and continue. What a missing reference means for verification is `/design-verify`'s decision, not this skill's.

### Frontmatter fields this skill reads

The plan schema is declared once, in `skills/design/SKILL.md` Step 9. This skill does not
reproduce that fence. It reads these fields and applies these defaults when a field is
absent:

| Field | Used for | Default when absent |
|-------|----------|---------------------|
| `commit_strategy` | Phase 3d's commit policy | `none` |
| `verify_gate` | which command must pass before a commit | `none` |
| `screenshot_dir` | where the deviation reports land | `.claude/plans/assets/<slug>/`, slug derived from the plan filename |

Plans written before these fields existed carry none of them, and they live in
`.claude/plans/`, which is gitignored -- no migration can reach them. The defaults are
load-bearing, not defensive styling. Default `commit_strategy` to `none` specifically:
an older plan predates the question being asked, so the user never consented to a commit.

## Phase 2 -- Branch

Skip entirely if `NO_GIT`.

If the current branch is not the default branch (`master` or `main`), stay on it. Nothing below runs.

On the default branch, resolve `design/<slug>` from the plan's slug, then check two things before touching it:

1. **Uncommitted work.** The third gather-context block already holds `git status --short`. If it is non-empty, do not switch branches -- a checkout carries those changes onto the new branch or fails outright. Stay put and print:
   `> Uncommitted changes present -- building on {current branch} instead of creating design/<slug>.`
2. **The branch already exists.** Run `git rev-parse --verify design/<slug>` with the Bash tool. A re-run of the same plan hits this every time, and `git checkout -b` aborts on it.
   - Exists: `git checkout design/<slug>` and print `> Continuing on existing branch design/<slug>.`
   - Does not exist: `git checkout -b design/<slug>`.

Read `git branch --show-current` back afterwards and print the branch the build actually runs on. A silent checkout failure otherwise puts the whole run on the default branch.

## Phase 2b -- Open the Run Session

`/design-verify --mode build` never trusts an already-running instance as fresh -- its
"The app must be running and fresh" section is the contract, and this phase is what
satisfies it. Rebuilding from scratch once per task satisfies it too, and is the slowest
way to.

Open **one** run session for the whole run, hot reload it after each task's
implementation, and tear it down when the run ends.

**Start.** After the branch is resolved and before the first task, launch the app in the
background with the Bash tool, using the build-and-launch command `/design-verify` lists
for the resolved target. Record that this run owns the session and print once:
`> Run session: {target}`, or `> Run session: none -- each verify rebuilds.`

Start no session when no run target resolves. Which plans capture at all is
`/design-verify`'s decision and this skill does not read the field that carries it -- a
run whose verify never captures pays one launch and no reloads.

**A failed launch costs an attempt.** A launch that fails consumes one attempt from the
first task's 3c budget, exactly as a deviation fix does. It never adds an attempt and it
never gets a budget of its own -- only the user's "Try 3 more attempts" resets the
counter. Once the budget is spent on launches, stop trying to own a session for the rest
of the run.

**Hot reload after 3a, before 3b.** The reload is what makes the session fresh; skipping
it hands `/design-verify` the previous task's binary.

| Target | Refresh |
|--------|---------|
| Flutter | write `r` to the running `flutter run` process (`R` after a change it cannot hot reload, such as a new asset or a `main()` edit) |
| Web dev server | nothing to run -- the dev server's own HMR already reloaded |
| iOS or Android | no hot reload exists; reinstall and relaunch with that target's command |
| Any other target | assume no hot reload: restart the session with the command that started it. When restarting is not possible, tear the session down and fall through to "No session owned" below. |

A stack this table does not name is not an error. It takes the last row, and a stack whose
session could not start or restart takes the no-session path -- the run still builds every
task and still verifies each one.

**Teardown on every exit path.** Kill the process this run started when the run ends --
after the last task, after a stop, after a task is skipped or its gate fails, when the
user picks "Stop here", and when the user cancels any `AskUserQuestion`. A cancelled
question is an exit path, not a pause. Never kill a process this run did not start: a
simulator or dev server the user had open before the run stays open.

**No session owned.** When the session never started, its budget was spent, or teardown
already ran, each 3b invocation falls back on `/design-verify`'s own build-and-launch
under its own 3-attempt cap. The run continues; it is slower, not blocked.

## Phase 3 -- Build Loop

Work the plan's `### Tasks` in order. New-token tasks come first -- later tasks reference those tokens.

For each task:

### 3a -- Implement

Read the node specs the task names. Write the code using the plan's literal values and the Token Map. Match the project's component conventions from the plan's `### Stack and Conventions` section.

Three spec lines override the raw measurements when they are present:

- **`Fit:`** wins over `Box:` on any axis it marks `fill`. The `Box:` number is what that
  axis measured at one frame size; writing it as a fixed dimension produces a component
  that is wrong at every other width. Implement `fill` as the framework's fill mechanism.
- **`Content:`** is the literal copy, and its i18n decision is binding. When it names a
  key, add the key and reference it. Never invent or paraphrase copy.
- **`Route:`** is where the node lives at runtime. Build it so that route reaches it.

**Layout reconciliation is mandatory.** Before writing any centering, alignment, or positioning code, check whether the node has a `Reconciliation:` line in its spec.

- **Reconciliation line present with a precedent `file:line`.** Read that file range. Use the same mechanism. Do not substitute a simpler one that happens to compile -- the precedent exists because the simple version produces the wrong result.
- **Reconciliation line present, no precedent (`No precedent found`).** Derive a solution from the layout chrome mechanism the plan records under `### Stack and Conventions`. The rule: center within the region the chrome excludes, never within the full screen. Concretely, that means constraining the content to the chrome-excluded region and centering inside that constraint, rather than centering at page level and hoping the chrome cancels out. Add a short comment naming what the content is centered within, so the next reader does not simplify it back into a page-level center.
- **No Reconciliation line.** The anchor is either a flow position or a plain edge inset. Implement it directly.

Follow the plan's File Map. Do not create files the plan does not list.

### 3b -- Verify

This skill does not capture and does not compare. It delegates, then reads a file.

1. **Note the report's current state.** Read `<screenshot_dir>/verify/<task-id>.md` if it
   exists and keep its `created:` value. Absent is a state too -- record that instead.
2. Invoke the `design-verify` skill with the plan path, this task's node IDs, this task's
   ID, and mode `build`:
   `/design-verify <plan path> --nodes <this task's node IDs> --task <task id> --mode build`
3. Re-read `<screenshot_dir>/verify/<task-id>.md`.

**The report path is fixed per task, so the file's existence proves nothing on a re-run.**
A verify that aborts before writing -- a shut-down simulator, a bad plan path, a denied
permission -- leaves the previous attempt's report exactly where the new one would go.
Compare `created:` against the value noted in step 1. Unchanged, or still absent, means
this attempt's verification did not run: treat the task as `unverified`, record that, and
continue to 3d. Do not loop, do not re-invoke, and do not read the stale deviations as
current -- doing so spends the retry budget re-fixing a delta that was already fixed.

**Classify the report before acting on it.** Deviation rows are not the only signal:

| Report state | Status |
|--------------|--------|
| deviation rows present | go to 3c |
| empty table, `comparison_path: imagemagick-*`, `confidence: high` | `matched` -- go to 3d |
| empty table, any other `comparison_path`, `confidence: low`, or nodes listed as skipped under `## Notes` | `unverified` -- record the reason from the report, go to 3d |
| `created:` unchanged, or the file is absent | `unverified` (verification did not run) -- go to 3d |

**An empty deviation table is not by itself a pass.** `spec-check` means nothing was
compared, `confidence: low` means the comparison could not be trusted, and a node under
`## Notes` was never captured at all. Every one of those produces an empty table, and
reporting any of them as `matched` claims a fidelity measurement that never happened.

All capture resolution, image normalization, metric selection, check order, and tolerance
live in `/design-verify`. They are not restated here, and this skill does not second-guess
them.

### 3c -- Fix, Bounded

There are two ways in: 3b classified the report as carrying deviation rows, or 3d's gate
failed and handed its output here as the deviation. `matched` and `unverified` never
enter -- both go straight to 3d.

Fix the largest delta in the report's deviation table first, then re-run 3b --
re-invoke `design-verify` and re-read the report. **Three attempts maximum per task**,
counting the initial implementation as attempt one.

A failed run-session launch (Phase 2b) spends an attempt from this same budget. There is
one counter per task, not one per failure kind.

After the third attempt still leaves deviations, **stop**. Do not keep looping.

**In auto mode**, take the "Accept as-is" path without asking: record the remaining
deviations with their measured deltas, leave the code in place, and continue to 3d on the
same terms that bullet already sets -- including its rule about not re-running a gate this
task already failed. Print one line so the run stays readable:

```
> Task {id}: {N} deviations accepted after 3 attempts.
```

The budget is never extended in auto mode. "Try 3 more attempts" is a human's call, and a
loop that grants itself more attempts has no cap. Phase 4 lists every accepted deviation
with its delta and its report path, which is where the user decides whether to revisit.

**Otherwise** call `AskUserQuestion`:

> Task {id} still differs from the design after 3 attempts:
> {one line per remaining deviation with its measured delta}

Buttons: `["Accept as-is -- note it and move on", "I'll describe the fix", "Try 3 more attempts", "Skip this task"]`

- **Accept as-is:** record the remaining deviations in the final summary and continue to 3d. When this loop was entered from a gate failure, 3d does not re-run the gate -- see the gate budget below.
- **I'll describe the fix:** take the user's description, apply it, re-run 3b once, then continue to 3d regardless of the result.
- **Try 3 more attempts:** reset the counter and return to the top of 3c. This is the only way the budget grows -- it is never extended automatically.
- **Skip this task:** undo what this task wrote, mark it skipped, continue to the next task. Undo has one mechanism per environment, and none of them is `git revert` -- under the default `commit_strategy: none` there is no commit to revert:
  - **Git available:** `git restore -- <files this task modified>` for tracked files, then delete the files this task created. Take that file list from 3a's own record of what it wrote, never from `git status` -- an earlier task's uncommitted work sits in the same tree and is not this task's to undo.
  - **`NO_GIT`, or any file this task shares with an earlier task:** undo nothing. Leave the code in place, mark the task `skipped (changes left in place)`, and name those files in the Phase 4 summary. Hand-unpicking interleaved edits is worse than the half-built state, and there is no restore point to fall back to.

### 3d -- Gate, then Commit

**Verification gate.** Read `verify_gate` from the plan frontmatter.

- `build` -- run the project's build command.
- `test` -- run the project's test command.
- `none` (the default) -- no gate; go straight to the commit policy.

**The gate runs at most twice per task.** Run it; on a failure, feed the failure output
back into 3c as a deviation and re-enter the fix loop under the same 3-attempt budget;
then run it one final time. That second run is the last for this task whatever it returns.

Record the outcome as this task's **gate verdict**, `cleared` or `failed`. Everything
downstream reads the verdict; the gate itself never runs a third time.

3c's "Accept as-is" returns here with the verdict already `failed`. **Do not re-run the
gate on that path** -- re-running it re-enters 3c, which returns here, which re-runs it.
The 3-attempt budget bounds 3c's internal loop, not the 3c-to-3d cycle, so a gate failing
for a reason this task cannot fix (a pre-existing compile error elsewhere) would otherwise
have no exit but "Skip this task".

**Commit policy.** Read `commit_strategy` from the plan frontmatter. The user chose this
at plan time, so nothing here asks again.

**`--no-commit` overrides it to `none`** before anything below is read. It reports itself
once on the first task, in place of the `none` line below rather than alongside it:
`> --no-commit: changes stay in the working tree.` The override is run-scoped --
it never rewrites the plan, so the same plan still commits on a run without the flag. This
is the only way to run a plan carrying `per-task` or `single` without commits, because Step
8 of `/design` is not re-asked here.

- `none` (the default) -- write no commit. Say so once, on the first task:
  `> commit_strategy: none -- changes stay in the working tree.` Do not repeat it per
  task.
- `per-task` -- skip if `NO_GIT`. Skip when this task's gate verdict is `failed`, and say
  which task and why. Otherwise stage only the files this task touched. Never `git add .`.
  Never stage the plan or anything under `screenshot_dir`. Commit with a Conventional
  Commits message scoped to the task, for example
  `feat(wallet): add balance card matching design spec`. No push. No AI attribution.
- `single` -- accumulate. Commit nothing here; after the last task, make one commit
  covering every file the run touched, with a Conventional Commits message scoped to the
  plan. Same staging rules, same exclusions, no push, no AI attribution.
  **Enforce the gate verdicts at that point.** Under `single` there is no per-task commit
  for a failing gate to block, so a task the gate rejected would otherwise ride into the
  final commit alongside the cleared ones. If any task's verdict is `failed`, write no
  commit at all: print each failed task with its gate output and leave everything in the
  working tree. Splitting the commit is not an option -- a later task builds on an earlier
  one's files, so the cleared subset is not independently committable.

## Phase 4 -- Summary and Handoff

Print a table:

| Task | Status | Fidelity | Gate |
|------|--------|----------|------|
| 1 | done | matched | cleared |
| 2 | done | 2 deviations accepted | cleared |
| 3 | done | unverified (spec-check, no capture tooling) | failed |
| 4 | skipped (changes left in place) | -- | -- |

`matched` means a measured comparison found no deviations. Anything 3b classified as
`unverified` prints as `unverified` with the reason from the report -- never as `matched`.

Then list every accepted deviation with its measured delta and the file it lives in, so the user can decide later whether to revisit. Name the deviation report path for each task, so the measurements stay reachable after this run ends. Name every task whose changes were left in place after a skip.

Print the branch name and the commit count.

**In auto mode**, print the next steps as text and stop:

```
> Next: /review to read the diff, /commit to commit, /create-pr to open a PR.
```

Invoke none of them. The consent this run carries covers the build and the measurement --
not a review, not a commit the plan's `commit_strategy` did not authorize, and not a pull
request.

Otherwise call `AskUserQuestion`:

> Build finished. What next?

Buttons: `["Review the changes -- /review", "Commit -- /commit", "Open a PR -- /create-pr", "Stop here"]`

- **Review the changes:** invoke the `review` skill.
- **Commit:** invoke the `commit` skill.
- **Open a PR:** invoke the `create-pr` skill.
- **Stop here:** stop.

Do not open a pull request directly -- `/create-pr` owns that.

---

## Anti-Patterns

Follow all rules in `.claude/rules/skill-rules.md`. Additionally:

- **Don't** call figma-bridge tools. This skill runs with Figma disconnected; the plan carries the data.
- **Don't** capture or compare here. 3b delegates to `/design-verify` and reads its report.
- **Don't** restate `/design-verify`'s capture commands, tolerance, or check order. One copy, in one file.
- **Don't** treat an absent deviation report as a pass. A clean verification still writes a report.
- **Don't** treat an empty deviation table as a pass either. Read `comparison_path` and `confidence` first.
- **Don't** trust a report at the task's path without checking `created:` against the value noted before the invocation. The path is fixed, so a stale report sits exactly where a fresh one would.
- **Don't** loop the fix cycle without a bound. Three attempts, then ask -- or, in auto mode, accept and move on.
- **Don't** re-run the gate after "Accept as-is". That is the 3c-to-3d cycle the attempt budget does not bound.
- **Don't** extend the retry budget on your own. Only the user's "Try 3 more attempts" resets it, and auto mode never reaches that button.
- **Don't** call `AskUserQuestion` from any path in auto mode. The whole contract is that `/design` Step 8 was the run's last question.
- **Don't** invoke `/review`, `/commit`, or `/create-pr` from the auto handoff. Naming them is the handoff; running them is a decision nobody consented to.
- **Don't** replace a precedent mechanism with a simpler one because it compiles. The precedent is in the plan because the simple version is what looks wrong.
- **Don't** center at page level when a Reconciliation line names a chrome-excluded region.
- **Don't** write a `fill` axis as the literal `Box:` number.
- **Don't** adjust the plan's numbers to match what the code happens to produce. Fix the code.
- **Don't** commit when `commit_strategy` is absent or `none`. Absence means the user was never asked.
- **Don't** write `--no-commit` into the plan. It is one run's override, and the plan is what the user chose at Step 8.
- **Don't** commit past a failing verification gate. Under `single` that means withholding the whole accumulate commit, not skipping one task's files.
- **Don't** answer "Skip this task" with `git revert`. The default strategy writes no commit, so there is nothing to revert.
- **Don't** stage the plan file or the screenshot assets.
- **Don't** restate the plan frontmatter schema. `skills/design/SKILL.md` Step 9 declares it; this file lists only the fields it reads.

---

## Test Plan

**Trigger:** `/design-build`, `/design-build .claude/plans/2026-08-16-wallet-design-plan.md`, `/design-build <plan> --auto`, `/quiver:design-build`

**Setup:**
- A design plan written by `/design` with at least two tasks, one node carrying a `Reconciliation:` line, and reference PNGs present under `screenshot_dir`.
- A second, legacy plan carrying none of `commit_strategy`, `verify_gate`, or `screenshot_dir`.
- A runnable project.

**Expected behavior:**
1. All three shell blocks exit 0 in a git repo and in a non-git directory.
2. With no design plan on disk, Phase 1 prints the `/design` pointer and stops.
3. A plan lacking `design_source: figma-bridge` or `### Node Specs` is rejected with a message; no code is written.
4. The legacy plan loads and builds on the documented defaults, committing nothing.
5. A node with a `Fit:` axis of `fill` is implemented with the framework's fill mechanism, not the `Box:` literal.
6. A node with a `Content:` line carrying an i18n key produces that key, never invented copy.
7. 3b invokes `/design-verify` with mode `build` and reads `<screenshot_dir>/verify/<task-id>.md`. No capture command runs in this skill.
8. An absent deviation report is recorded as `unverified` and does not loop or read as a pass. A report whose `created:` is unchanged after the invocation is recorded the same way, and its stale deviations are not re-fixed.
8b. A report with an empty deviation table and `comparison_path: spec-check` (or `confidence: low`, or a node listed under `## Notes`) is recorded as `unverified`, never `matched`.
8c. On the default branch with an existing `design/<slug>`, the run checks that branch out instead of failing at `git checkout -b`. With a dirty working tree it stays on the current branch and says so.
9. A node with a `Reconciliation:` line and a precedent `file:line` causes that file range to be read before the positioning code is written.
10. A node with a `Reconciliation:` line and `No precedent found` produces content constrained to the chrome-excluded region, with a comment naming what it centers within.
11. After three failed attempts on one task, `AskUserQuestion` appears with the four options. The loop never continues silently.
11b. In auto mode the same point accepts the remaining deviations, prints the one-line count, and continues to 3d without asking. The 3-attempt budget is not extended.
12. "Try 3 more attempts" resets the counter; nothing else does.
13. `verify_gate: build` or `test` runs that command before the commit; a failure blocks the commit and re-enters 3c. The gate runs at most twice per task, and "Accept as-is" after a gate failure moves on instead of re-running it -- a permanently failing gate never loops.
14. `commit_strategy: none` or absent writes no commit and says so exactly once.
15. `commit_strategy: per-task` produces one commit per task, skipping any task whose gate verdict is `failed`; `single` produces exactly one commit after the last task, and none at all if any task's gate failed. The plan and `screenshot_dir` are never staged.
15b. "Skip this task" restores the modified files and deletes the created ones when git is available, and leaves them in place with a stated reason under `NO_GIT` or on files an earlier task also wrote.
16. Phase 4 prints the status table, lists every accepted deviation with its delta and report path, and ends with the four-button handoff.
16b. Phase 2b starts exactly one run session for the whole run, hot reloads it after each task's 3a, and tears it down at the end. A project with no resolvable run target starts none and the run continues.
16c. Teardown runs on every exit path, including a skipped task, a failed gate, "Stop here", and a cancelled `AskUserQuestion`. A simulator or dev server the user had open before the run is left running.
16d. A failed run-session launch consumes an attempt from the task's 3c budget rather than getting its own, and three failures stop session ownership for the rest of the run without stopping the run.
16e. With no session owned, each 3b invocation still verifies -- `/design-verify` rebuilds and relaunches under its own cap.
17. `--auto` is stripped before a plan path is resolved, and `/design-build --auto` with several plans on disk takes the most recent and names the count instead of asking.
18. A full `/design --auto` run reaches no `AskUserQuestion` after `/design` Step 8, all the way to the Phase 4 summary.
19. The auto handoff prints the `/review`, `/commit`, and `/create-pr` commands as text and invokes none of them.
20. `--no-commit` against a plan carrying `commit_strategy: per-task` writes no commit, says so once, and leaves the plan file unchanged. Re-running the same plan without the flag commits normally.
21. `--no-commit` works with or without `--auto`, and `--auto` works without `--no-commit`.

**Verification checklist:**
- [ ] `/design-build` and `/quiver:design-build` both appear in the slash menu after plugin reload.
- [ ] All three `!` blocks exit 0 with `NO_GIT` output in a non-git directory.
- [ ] No figma-bridge tool is called anywhere in this skill.
- [ ] No capture command, tolerance value, or check order appears anywhere in this file.
- [ ] No screenshot binary or capture MCP server is named anywhere in this file.
- [ ] The plan frontmatter fence is not reproduced; only the fields this skill reads are listed, each with a default.
- [ ] The retry budget is capped at 3 and only the user can reset it.
- [ ] Exactly one run session per run: started once, hot reloaded per task, torn down on every exit path.
- [ ] Launch failures draw from the 3c budget and never create a second counter.
- [ ] The gate runs at most twice per task and never re-runs after "Accept as-is".
- [ ] Report freshness is checked by `created:`, not by the file existing.
- [ ] Every empty-table outcome is classified from `comparison_path` and `confidence`.
- [ ] The bounded-retry prompt uses `AskUserQuestion`, not plain text -- and is unreachable in auto mode.
- [ ] Every `AskUserQuestion` site in this skill has an auto-mode branch ahead of it.
- [ ] Auto mode changes no measurement, tolerance, gate verdict, or commit rule.
- [ ] No commit is written when `commit_strategy` is absent.
- [ ] `--no-commit` overrides the plan for the run and never edits the plan file.
- [ ] Commits stage task files only; no `git add .`; plan and assets excluded.
- [ ] No AI attribution in any commit message.
- [ ] `when-to-use:` is a single-line double-quoted string.
- [ ] No `CLAUDE_PLUGIN_ROOT` reference anywhere in this file.
- [ ] No Unicode characters or emoji in this file.
- [ ] No `$()`, variable assignment, or `if/else` inside any `!` block.

**Known gotchas:**
- The retry budget is a cross-file loop: 3c counts attempts here, but each attempt's measurement happens in `/design-verify`. The counter never lives in the report file -- it is this skill's state.
- Teardown is easy to write only on the happy path. The exit paths that skip it -- a cancelled question, a skipped task, a stop -- are the ones that leave an orphaned simulator or dev server behind.
- An absent deviation report and a report with zero deviations mean opposite things. `/design-verify` writes a report on every path precisely so the difference is unambiguous.
- Deviation reports and captures land under `.claude/plans/assets/<slug>/`. If `.claude/` is gitignored they stay local, which is intended -- never stage them.
- Undoing a skipped task's changes only removes what that task wrote, and only when git can restore them. A task whose files an earlier task also touched cannot be cleanly skipped; when that happens, say so rather than hand-unpicking interleaved edits.
- The verification report path is fixed per task, so a failed re-verify is invisible from the filesystem alone. `created:` is the only thing that separates this attempt's report from the last one's.
- `commit_strategy: single` still has to skip when `NO_GIT`. The accumulate branch is easy to write as if git is always present.
