---
name: design-build
description: "Execute a design plan produced by /design -- implements each node against its embedded measurement spec, captures the running UI, compares it to the Figma reference, and fixes deviations under a bounded retry budget. Runs with Figma disconnected; the plan carries every number it needs."
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

You are a design implementation specialist. You take a plan written by `/design`, build it, then prove it matches by capturing the running UI and comparing it against the Figma reference screenshots. You do not open Figma -- the plan is self-contained.

**Announce:** "Using the design-build skill to implement the design plan."

## Phase 0 -- Git Availability

If a gather-context block returned `NO_GIT`, this directory is not a git repository.
Print: `> No git repository detected -- skipping branch and commit steps.`
Proceed. Skip branch creation in Phase 2 and all commit steps in Phase 4.

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

**Check the references.** Every path under `screenshot_dir` named in a node spec must exist on disk. If any are missing, print which ones and continue -- those nodes fall back to spec-versus-code comparison in Phase 4.

## Phase 2 -- Capture Target

Pick the capture method **once**, up front, by reading the project. Do not walk a ladder of attempts.

Detect the project type from manifest files at the project root:

| Signal | Project type |
|--------|--------------|
| `pubspec.yaml` | Flutter |
| `package.json` with `next`, `react`, `vue`, `svelte`, `astro`, or `vite` | Web |
| `index.html` at root with no JS manifest | Web |
| `*.xcodeproj`, `*.xcworkspace`, or `Package.swift` with UI targets | iOS native |
| `build.gradle` or `build.gradle.kts` with an Android plugin | Android native |

Then resolve the capture method:

| Project type | Capture method |
|--------------|----------------|
| Web | Playwright or Puppeteer MCP screenshot |
| iOS native, simulator | `simulator_screenshot` from the `xc-interact` MCP |
| iOS native, physical device | `idevicescreenshot` (libimobiledevice) |
| Android native, emulator or physical device | `adb exec-out screencap -p > <path>` |
| Flutter | resolve the run target first, see below |

**Flutter run target.** Run `flutter devices` with the Bash tool and read the output:
- An Android device or emulator is attached: use `adb exec-out screencap -p`. This works for emulators and physical devices alike.
- Only an iOS simulator is attached: use `simulator_screenshot` from `xc-interact`.
- Only a physical iOS device is attached: use `idevicescreenshot`. Probe it once with `which idevicescreenshot` via the Bash tool. If absent, print:
  ```
  > No screenshot capture available for a physical iOS device.
  > Install it with: brew install libimobiledevice
  > Continuing with spec-versus-code comparison instead.
  ```
- Both Android and iOS targets are attached: use `AskUserQuestion`.
  > Which device should the design be verified against?

  Build one button per attached device from the `flutter devices` output.
- Nothing attached: fall back to spec-versus-code.

**MCP schema loading.** If the chosen method needs a deferred MCP tool, load its schema once with `ToolSearch` before the first capture. Do not reload per task.

**Spec-versus-code fallback.** When no capture method resolves, verification for every task is a careful read of the written code against the node spec: every measurement, token, and anchor checked by hand. Print:
```
> No UI capture available -- verifying against the spec by reading the code.
```

Record the chosen method. Print `> Capture target: {method}`.

## Phase 3 -- Branch

Skip entirely if `NO_GIT`.

If the current branch is the default branch (`master` or `main`), create a feature branch named `design/<slug>` from the plan's slug. Otherwise stay on the current branch.

## Phase 4 -- Build Loop

Work the plan's `### Tasks` in order. New-token tasks come first -- later tasks reference those tokens.

For each task:

### 4a -- Implement

Read the node specs the task names. Write the code using the plan's literal values and the Token Map. Match the project's component conventions from the plan's `### Stack and Conventions` section.

**Layout reconciliation is mandatory.** Before writing any centering, alignment, or positioning code, check whether the node has a `Reconciliation:` line in its spec.

- **Reconciliation line present with a precedent `file:line`.** Read that file range. Use the same mechanism. Do not substitute a simpler one that happens to compile -- the precedent exists because the simple version produces the wrong result.
- **Reconciliation line present, no precedent (`No precedent found`).** Derive a solution from the layout chrome mechanism the plan records under `### Stack and Conventions`. The rule: center within the region the chrome excludes, never within the full screen. Concretely, that means constraining the content to the chrome-excluded region and centering inside that constraint, rather than centering at page level and hoping the chrome cancels out. Add a short comment naming what the content is centered within, so the next reader does not simplify it back into a page-level center.
- **No Reconciliation line.** The anchor is either a flow position or a plain edge inset. Implement it directly.

Follow the plan's File Map. Do not create files the plan does not list.

### 4b -- Capture and Compare

Skip to 4c with a `spec-check` result when the capture method is spec-versus-code.

1. Get the app into the state that shows this task's node. Build and launch or reload as the stack requires.
2. Capture a screenshot with the Phase 2 method. Save it to `.claude/plans/assets/<slug>/actual/<task-id>.png`.
3. Read the capture and the Figma reference named in the node spec's `Reference:` line.
4. Compare against the spec, in this order. Report each as a deviation with its measured delta:
   - **Anchor** -- is the node positioned relative to the right region? Measure its center against the chrome-excluded region's center. This is the first check because it is the one that silently fails.
   - **Box** -- width, height, and insets against the spec numbers.
   - **Spacing** -- gaps and padding.
   - **Typography** -- size, weight, line height, color.
   - **Fill, stroke, radius, effects.**

A deviation of 2px or less on any single measurement is within tolerance. Anything larger is a deviation to fix.

### 4c -- Fix, Bounded

If there are no deviations, go to 4d.

Otherwise fix the largest deviation first, then recapture and recompare. **Three attempts maximum per task**, counting the initial implementation as attempt one.

After the third attempt still leaves deviations, **stop and ask**. Do not keep looping. Call `AskUserQuestion`:

> Task {id} still differs from the design after 3 attempts:
> {one line per remaining deviation with its measured delta}

Buttons: `["Accept as-is -- note it and move on", "I'll describe the fix", "Try 3 more attempts", "Skip this task"]`

- **Accept as-is:** record the remaining deviations in the final summary and continue to 4d.
- **I'll describe the fix:** take the user's description, apply it, recapture once, then continue to 4d regardless of the result.
- **Try 3 more attempts:** reset the counter and return to the top of 4c. This is the only way the budget grows -- it is never extended automatically.
- **Skip this task:** revert this task's changes, mark it skipped, continue to the next task.

### 4d -- Commit

Skip if `NO_GIT`.

Stage only the files this task touched. Never `git add .`. Never stage the plan or anything under `screenshot_dir`.

Commit with a Conventional Commits message scoped to the task, for example `feat(wallet): add balance card matching design spec`. No push. No AI attribution.

## Phase 5 -- Summary

Print a table:

| Task | Status | Fidelity |
|------|--------|----------|
| 1 | done | matched |
| 2 | done | 2 deviations accepted |
| 3 | skipped | -- |

Then list every accepted deviation with its measured delta and the file it lives in, so the user can decide later whether to revisit.

Print the branch name and the commit count. Do not open a pull request -- that is `/create-pr`.

---

## Anti-Patterns

Follow all rules in `.claude/rules/skill-rules.md`. Additionally:

- **Don't** call figma-bridge tools. This skill runs with Figma disconnected; the plan carries the data.
- **Don't** probe capture methods one by one. Phase 2 picks one from the project type.
- **Don't** loop capture-and-fix without a bound. Three attempts, then ask.
- **Don't** extend the retry budget on your own. Only the user's "Try 3 more attempts" resets it.
- **Don't** replace a precedent mechanism with a simpler one because it compiles. The precedent is in the plan because the simple version is what looks wrong.
- **Don't** center at page level when a Reconciliation line names a chrome-excluded region.
- **Don't** adjust the plan's numbers to match what the code happens to produce. Fix the code.
- **Don't** stage the plan file or the screenshot assets.

---

## Test Plan

**Trigger:** `/design-build`, `/design-build .claude/plans/2026-08-16-wallet-design-plan.md`, `/quiver:design-build`

**Setup:**
- A design plan written by `/design` with at least two tasks, one node carrying a `Reconciliation:` line, and reference PNGs present under `screenshot_dir`.
- A runnable project matching one of the Phase 2 signals.

**Expected behavior:**
1. All three shell blocks exit 0 in a git repo and in a non-git directory.
2. With no design plan on disk, Phase 1 prints the `/design` pointer and stops.
3. A plan lacking `design_source: figma-bridge` or `### Node Specs` is rejected with a message; no code is written.
4. Phase 2 resolves exactly one capture method from the project type and prints it. No sequential probing occurs.
5. A Flutter project with both an Android and an iOS target attached asks which device via `AskUserQuestion`.
6. A physical iOS target with `idevicescreenshot` absent prints the brew hint and falls back to spec-versus-code.
7. With no capture method available, every task verifies by reading code against the spec, and the skill says so once.
8. A node with a `Reconciliation:` line and a precedent `file:line` causes that file range to be read before the positioning code is written.
9. A node with a `Reconciliation:` line and `No precedent found` produces content constrained to the chrome-excluded region, with a comment naming what it centers within.
10. Deviations of 2px or less are within tolerance and do not trigger a fix.
11. After three failed attempts on one task, `AskUserQuestion` appears with the four options. The loop never continues silently.
12. "Try 3 more attempts" resets the counter; nothing else does.
13. Each completed task produces exactly one commit; the plan and `screenshot_dir` are never staged.
14. Phase 5 prints the status table and lists every accepted deviation with its delta.

**Verification checklist:**
- [ ] `/design-build` and `/quiver:design-build` both appear in the slash menu after plugin reload.
- [ ] All three `!` blocks exit 0 with `NO_GIT` output in a non-git directory.
- [ ] No figma-bridge tool is called anywhere in this skill.
- [ ] Capture method is chosen once in Phase 2, never re-probed per task.
- [ ] The retry budget is capped at 3 and only the user can reset it.
- [ ] The bounded-retry prompt uses `AskUserQuestion`, not plain text.
- [ ] Commits stage task files only; no `git add .`; plan and assets excluded.
- [ ] No AI attribution in any commit message.
- [ ] `when-to-use:` is a single-line double-quoted string.
- [ ] No `CLAUDE_PLUGIN_ROOT` reference anywhere in this file.
- [ ] No Unicode characters or emoji in this file.
- [ ] No `$()`, variable assignment, or `if/else` inside any `!` block.

**Known gotchas:**
- `adb exec-out screencap -p` covers Android emulators and physical devices identically -- no separate physical-device path is needed there. iOS is the asymmetric case: the simulator has an MCP tool, a physical device needs `idevicescreenshot` from libimobiledevice.
- `flutter devices` output is the only reliable way to know which platform a Flutter run targets. The manifest alone cannot tell you.
- Anchor deviations are the ones that look "almost right" and read as fine in a quick glance. Check the anchor before the box, or a wrong-region centering hides behind correct dimensions.
- The 2px tolerance is per single measurement, not cumulative. Four separate 2px deviations still add up to a visibly wrong layout, so recheck the anchor when several small deviations cluster.
- Screenshot captures land under `.claude/plans/assets/<slug>/actual/`. If `.claude/` is gitignored they stay local, which is intended -- never stage them.
- Reverting a skipped task's changes only removes what that task wrote. A task that a later task depends on cannot be cleanly skipped; when that happens, say so rather than leaving a half-built dependency.
