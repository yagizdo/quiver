---
name: tdd
description: "Test-first cycle and red-step evidence rule for skills that implement behavior a test can assert. Binds when the verification skill resolves a test command; defines what the red run must quote and when the cycle is skipped with a reason."
user-invocable: false
---

# TDD

Reference skill read by `/plan` Step 5, `/work` Phase 3 and `skills/work/orchestrator.md`, `/ship` Step 3, and `/hypothesis-debugging` Step 7. It is never invoked and runs nothing itself: the consumer resolves the test command per `skills/verification/SKILL.md`, follows the cycle here, and quotes the evidence.

## Applicability

The cycle binds to a change when both hold:

- The consumer resolved the test command per `skills/verification/SKILL.md` and the value is not `none`.
- The change produces behavior a test can assert. Documentation, a config value, a rename with no behavior change, and a migration with no code path do not.

When either fails, the outcome is `skipped: <reason>`, and the reason names which one: `test command none (<verification's reason>)` or `no testable behavior (<what the change is>)`. A skipped cycle is a recorded fact, not an error, and it never blocks the consumer.

The user's own project instructions win. A project whose `CLAUDE.md` says not to use TDD settles it, as `skills/using-quiver/SKILL.md` says.

## The Cycle

- *Red.* Write the test that names the behavior, in the project's existing test layout and framework. Run the resolved test command exactly as written. Record the red line: this run's exit code, the name of the test just written, and its first error line. When the runner fails before naming a test -- a compile or import error in the new test file -- the file path stands in for the name. A failure in a test that was not written in this step is a pre-existing failure, not red evidence.
- *Green.* Write the least implementation that makes that test pass. Run the resolved test command again. The pass line is the existing verification evidence: this run's exit code plus the runner's summary line.
- *Refactor.* Optional. Any further edit is followed by another run, and the most recent pass line is the one reported. The refactor step produces no evidence of its own.

The red run is not an attempt. A consumer with a fix-attempt budget counts only runs made after the implementation exists; the red run precedes the implementation, is expected to fail, and spends nothing.

## Evidence

```
red:     <command> -> exit <code>: <failing test> -- <first error line>
skipped: <reason>
```

Green has no line of its own: it is the `pass:` line `skills/verification/SKILL.md` defines, reported where the consumer already reports it. A consumer that receives neither a `red:` nor a `skipped:` line records `skipped: no red evidence`. The three skipped reasons are `test command none (...)`, `no testable behavior (...)`, and `no red evidence`.

## For Skill Authors

- Read this file at the build step, after the verification command is resolved and before the first implementation starts.
- Order the work test-first in the consumer's own instruction list: the test step and its run precede the implementation step and its run.
- Add a `TDD |` line to any subagent return contract that already carries a `TESTS |` line, with the two forms above, and treat a missing line as `skipped: no red evidence`.
- Paste the `### Subagent restatement` below into the subagent prompt verbatim. It is the only text from this file that is copied anywhere, and `tests/skills/test-tdd-contract.sh` compares the copies to it.

### Subagent restatement

Write the test for the behavior before the implementation and run the test command you were given exactly as written, then report the red step by quoting that run's exit code, the new test's name, and its first error line -- a test that was never seen failing, or a red line naming a test you did not write in this task, is not red evidence; when no test can be written, report skipped with the reason.

---

## Test Plan

**Trigger:** Reference skill -- not directly invoked. Read by `/plan` Step 5, `/work` Phase 3 and `skills/work/orchestrator.md`, `/ship` Step 3, and `/hypothesis-debugging` Step 7.

**Setup:**
- A Go module with tests.
- A Node project whose `package.json` has no `test` script.

**Expected behavior:**
1. In the Go module, a consumer prints a `red:` line naming the new test before the implementation edit, then a pass line.
2. In the Node project, a consumer prints `skipped: test command none (package.json has no test script)` once and no `red:` line.
3. A task that changes only documentation prints `skipped: no testable behavior (<what the change is>)`.
4. A subagent return with no `TDD` line is recorded as `skipped: no red evidence` and the task still merges.

**Verification checklist:**
- [ ] The Go module run prints a `red:` line naming the test just written, before the implementation edit, then a pass line after it.
- [ ] The Node project prints `skipped: test command none (package.json has no test script)` once, and no `red:` line.
- [ ] A documentation-only task prints `skipped: no testable behavior (...)`.
- [ ] A subagent return carrying no `TDD` line is recorded as `skipped: no red evidence` and the task still merges.
- [ ] The restatement in `skills/work/orchestrator.md` and `skills/ship/SKILL.md` is byte-identical to this file's.

**Known gotchas:**
- pytest interrupts collection on a top-level import of a not-yet-defined name: exit 2, zero tests run, and the file path stands in for the test name. A name error inside the test body is a named `FAILED` at exit 1 instead.
- go prints compiler `file:line:col` lines and `FAIL <pkg> [build failed]` for that package only; the other packages still run.
- cargo stops every target at exit 101 and prints no test name.
- mocha exits the failure count on failures, and 1 on a load error with `Exception during run:` and no failure list.
- jest prints the failure title under `FAIL <path>`, and `Test suite failed to run` on an import failure; it prints no end summary block with 20 or fewer suites.
- vitest prints `FAIL <file> > <suite> > <name>` in its `Failed Tests` block, and `FAIL <file> [ <file> ]` under `Failed Suites` on an import failure.
- node:test names a file that failed to load as a path subtest -- tap output on Node 22 and earlier, spec output on Node 23 and later.
- rspec prints `An error occurred while loading <file>` and runs no example.
- minitest and `bin/rails test` abort before `# Running:` with a Ruby trace.
- dart and flutter print `loading <path> [E]` then `Failed to load "<path>"` and still run the other files, in the expanded form when output is not a TTY.
- Exit code alone never separates a new red from a pre-existing failure -- pytest and mocha excepted -- the name on the line does.
