---
name: design-build
description: "Execute a design plan produced by /design -- implements each node against its embedded measurement spec, delegates fidelity measurement to /design-verify, and fixes the reported deviations under a bounded retry budget. Runs with Figma disconnected; the plan carries every number it needs."
argument-hint: "<path to a *-design-plan.md, or empty to pick one>"
when-to-use: "user wants to build a design plan into working pixel-accurate UI -- '/design-build', 'build the design plan', 'implement the figma plan', 'make it match the design', 'fix the pixel differences'"
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

**Path given.** If `$ARGUMENTS` ends in `.md` or contains `/`, read that file.

**No arguments.** Use the Glob tool on `.claude/plans/*-design-plan.md`. Treat an empty result as none found.

- One match: read it and print `> Executing design plan: {filename}`.
- Several matches: use `AskUserQuestion` with one button per plan, most recent first, plus `"Other -- I'll give a path"`.
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

If the current branch is the default branch (`master` or `main`), create a feature branch named `design/<slug>` from the plan's slug. Otherwise stay on the current branch.

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

1. Invoke the `design-verify` skill with the plan path, this task's node IDs, this task's
   ID, and mode `build`:
   `/design-verify <plan path> --nodes <this task's node IDs> --task <task id> --mode build`
2. Read `<screenshot_dir>/verify/<task-id>.md`.

**An absent report file means the verify step did not run.** That is the only thing it
means -- a clean verification still writes a report. Treat the task as `spec-check`,
record that verification did not run, and continue to 3d. Do not loop, do not re-invoke,
and do not infer that the task passed.

All capture resolution, image normalization, metric selection, check order, and tolerance
live in `/design-verify`. They are not restated here, and this skill does not second-guess
them.

### 3c -- Fix, Bounded

If the report lists no deviations, go to 3d.

Otherwise fix the largest delta in the report's deviation table first, then re-run 3b --
re-invoke `design-verify` and re-read the report. **Three attempts maximum per task**,
counting the initial implementation as attempt one.

After the third attempt still leaves deviations, **stop and ask**. Do not keep looping. Call `AskUserQuestion`:

> Task {id} still differs from the design after 3 attempts:
> {one line per remaining deviation with its measured delta}

Buttons: `["Accept as-is -- note it and move on", "I'll describe the fix", "Try 3 more attempts", "Skip this task"]`

- **Accept as-is:** record the remaining deviations in the final summary and continue to 3d.
- **I'll describe the fix:** take the user's description, apply it, re-run 3b once, then continue to 3d regardless of the result.
- **Try 3 more attempts:** reset the counter and return to the top of 3c. This is the only way the budget grows -- it is never extended automatically.
- **Skip this task:** revert this task's changes, mark it skipped, continue to the next task.

### 3d -- Gate, then Commit

**Verification gate.** Read `verify_gate` from the plan frontmatter.

- `build` -- run the project's build command.
- `test` -- run the project's test command.
- `none` (the default) -- no gate; go straight to the commit policy.

A failing gate **blocks the commit**. Feed the failure output back into 3c as a
deviation and re-enter the fix loop under the same 3-attempt budget. Never commit past a
failing gate, and never commit a task the gate has not cleared.

**Commit policy.** Read `commit_strategy` from the plan frontmatter. The user chose this
at plan time, so nothing here asks again.

- `none` (the default) -- write no commit. Say so once, on the first task:
  `> commit_strategy: none -- changes stay in the working tree.` Do not repeat it per
  task.
- `per-task` -- skip if `NO_GIT`. Stage only the files this task touched. Never
  `git add .`. Never stage the plan or anything under `screenshot_dir`. Commit with a
  Conventional Commits message scoped to the task, for example
  `feat(wallet): add balance card matching design spec`. No push. No AI attribution.
- `single` -- accumulate. Commit nothing here; after the last task, make one commit
  covering every file the run touched, with a Conventional Commits message scoped to the
  plan. Same staging rules, same exclusions, no push, no AI attribution.

## Phase 4 -- Summary and Handoff

Print a table:

| Task | Status | Fidelity |
|------|--------|----------|
| 1 | done | matched |
| 2 | done | 2 deviations accepted |
| 3 | skipped | -- |

Then list every accepted deviation with its measured delta and the file it lives in, so the user can decide later whether to revisit. Name the deviation report path for each task, so the measurements stay reachable after this run ends.

Print the branch name and the commit count.

Then call `AskUserQuestion`:

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
- **Don't** loop the fix cycle without a bound. Three attempts, then ask.
- **Don't** extend the retry budget on your own. Only the user's "Try 3 more attempts" resets it.
- **Don't** replace a precedent mechanism with a simpler one because it compiles. The precedent is in the plan because the simple version is what looks wrong.
- **Don't** center at page level when a Reconciliation line names a chrome-excluded region.
- **Don't** write a `fill` axis as the literal `Box:` number.
- **Don't** adjust the plan's numbers to match what the code happens to produce. Fix the code.
- **Don't** commit when `commit_strategy` is absent or `none`. Absence means the user was never asked.
- **Don't** commit past a failing verification gate.
- **Don't** stage the plan file or the screenshot assets.
- **Don't** restate the plan frontmatter schema. `skills/design/SKILL.md` Step 9 declares it; this file lists only the fields it reads.

---

## Test Plan

**Trigger:** `/design-build`, `/design-build .claude/plans/2026-08-16-wallet-design-plan.md`, `/quiver:design-build`

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
8. An absent deviation report is recorded as `spec-check` and does not loop or read as a pass.
9. A node with a `Reconciliation:` line and a precedent `file:line` causes that file range to be read before the positioning code is written.
10. A node with a `Reconciliation:` line and `No precedent found` produces content constrained to the chrome-excluded region, with a comment naming what it centers within.
11. After three failed attempts on one task, `AskUserQuestion` appears with the four options. The loop never continues silently.
12. "Try 3 more attempts" resets the counter; nothing else does.
13. `verify_gate: build` or `test` runs that command before the commit; a failure blocks the commit and re-enters 3c.
14. `commit_strategy: none` or absent writes no commit and says so exactly once.
15. `commit_strategy: per-task` produces one commit per task; `single` produces exactly one commit after the last task. The plan and `screenshot_dir` are never staged.
16. Phase 4 prints the status table, lists every accepted deviation with its delta and report path, and ends with the four-button handoff.

**Verification checklist:**
- [ ] `/design-build` and `/quiver:design-build` both appear in the slash menu after plugin reload.
- [ ] All three `!` blocks exit 0 with `NO_GIT` output in a non-git directory.
- [ ] No figma-bridge tool is called anywhere in this skill.
- [ ] No capture command, tolerance value, or check order appears anywhere in this file.
- [ ] No screenshot binary or capture MCP server is named anywhere in this file.
- [ ] The plan frontmatter fence is not reproduced; only the fields this skill reads are listed, each with a default.
- [ ] The retry budget is capped at 3 and only the user can reset it.
- [ ] The bounded-retry prompt uses `AskUserQuestion`, not plain text.
- [ ] No commit is written when `commit_strategy` is absent.
- [ ] Commits stage task files only; no `git add .`; plan and assets excluded.
- [ ] No AI attribution in any commit message.
- [ ] `when-to-use:` is a single-line double-quoted string.
- [ ] No `CLAUDE_PLUGIN_ROOT` reference anywhere in this file.
- [ ] No Unicode characters or emoji in this file.
- [ ] No `$()`, variable assignment, or `if/else` inside any `!` block.

**Known gotchas:**
- The retry budget is a cross-file loop: 3c counts attempts here, but each attempt's measurement happens in `/design-verify`. The counter never lives in the report file -- it is this skill's state.
- An absent deviation report and a report with zero deviations mean opposite things. `/design-verify` writes a report on every path precisely so the difference is unambiguous.
- Deviation reports and captures land under `.claude/plans/assets/<slug>/`. If `.claude/` is gitignored they stay local, which is intended -- never stage them.
- Reverting a skipped task's changes only removes what that task wrote. A task that a later task depends on cannot be cleanly skipped; when that happens, say so rather than leaving a half-built dependency.
- `commit_strategy: single` still has to skip when `NO_GIT`. The accumulate branch is easy to write as if git is always present.
