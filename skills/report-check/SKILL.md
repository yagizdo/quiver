---
name: report-check
description: Analyze a review report for quality -- detects noise, false positives, overkill suggestions, and findings that exist to appear thorough. Usage: /report-check <path-to-report>
---

# Gather Context

```
!`git rev-parse --is-inside-work-tree 2>/dev/null || echo "NO_GIT"`
```

```
!`git branch --show-current 2>/dev/null || echo "NO_GIT"`
```

---

# Report Quality Check

Analyze a review report for quality issues -- noise, false positives, overkill suggestions, and findings that exist to appear thorough rather than to help the developer.

**Announce:** "Using the report-check skill to audit report quality."

---

## Step 0 -- Validate Input

If `$ARGUMENTS` is empty, print:

> Usage: `/report-check <path-to-review-report.md>`
> Analyzes a review report for quality issues -- noise, false positives, overkill suggestions.

**Stop here.**

If `$ARGUMENTS` contains a file path:
1. Read the file using the Read tool.
2. If the file does not exist or is not readable, print:
   > Report file not found: `{path}`
**Stop here.**

---

## Step 1 -- Read Report

1. Read the full report file.
2. Extract the branch name from the `## Review Context` section if present (look for a `Branch:` line).
3. Note the report structure: findings grouped by severity, verdict, filtered findings section.

---

## Step 2 -- Reconstruct Diff (optional)

If git is available AND a branch name was extracted from the report:

1. Determine the base branch:
   ```
   !`git rev-parse --verify main 2>/dev/null || echo "NO_MAIN"`
   ```
   Use `main` if it exists, otherwise `master`.

2. Get the diff:
   ```
   !`git diff {base}...{branch} 2>/dev/null || echo "NO_DIFF"`
   ```

3. If the diff is non-empty, it will be passed to the agent for cross-referencing.

Print status:
- With diff: `Analyzing report with diff cross-reference...`
- Without diff: `Analyzing report (no diff available for cross-reference)...`

If git is unavailable or no branch info exists, proceed without diff. The agent works report-only -- Phase 2 accuracy checks will be limited.

---

## Step 3 -- Dispatch Agent

Spawn the `quiver:report-checker` agent with a self-contained prompt containing:

1. The full report content, clearly delimited:
   ```
   <report>
   {full report markdown}
   </report>
   ```

2. The diff (if available), clearly delimited:
   ```
   <diff>
   {full diff output}
   </diff>
   ```
   If no diff is available, include:
   ```
   <diff>
   No diff available for cross-referencing.
   </diff>
   ```

3. Instruction: "Audit this review report for quality. Apply all three phases (substance verification, accuracy check, proportionality audit). Return structured findings using your output format."

---

## Step 4 -- Present Results

If agent returns zero issues:
> Report passed quality audit -- no issues found.

If agent returns issues, display the structured findings to the user.

Use `AskUserQuestion`:
> Quality audit found {N} issues in the report. What would you like to do?

Buttons:
- `Apply fixes to the report`
- `Show details only`
- `Skip -- keep as-is`

Handle each option:

<!-- SYNC: The apply-fixes procedure below (REMOVE/DOWNGRADE/REWRITE actions + recalculation steps) is duplicated in skills/review/SKILL.md Step 3.5 "Handle results" block. Keep both in sync. -->
**Apply fixes:**
1. For each issue with action REMOVE: delete the finding from the report file.
2. For each issue with action DOWNGRADE: change the finding's severity and move it to the correct severity section.
3. For each issue with action REWRITE: replace the finding's recommendation text with the corrected version.
4. After applying all fixes, recalculate:
   - Findings overview counts in `## Review Context`
   - Severity section contents (move downgraded findings, remove deleted ones)
   - Recommended Fix Order table (remove entries for deleted/downgraded findings)
   - Verdict line (recompute based on remaining finding severities)
5. Write the updated report back to the same file path.
6. Proceed to Step 5.

**Show details:**
1. Print the full audit output.
2. Re-ask via `AskUserQuestion`:
   > Apply the suggested fixes?
   Buttons: `Apply fixes` / `Skip -- keep as-is`

**Skip:**
Stop. Report unchanged.

---

## Step 5 -- Verify (if fixes applied)

1. Read the modified report file back using the Read tool.
2. Confirm no `{placeholder}` text remains in the report.
3. Print:
   > Report updated: {N} findings removed, {M} downgraded, {K} rewritten.

---

## Test Plan

**Trigger:** `/report-check <path>` (and `/quiver:report-check` should also work)

**Setup:**
- A review report file exists at the given path (e.g., `.claude/reports/review-*.md`).
- Optionally, the branch referenced in the report still exists locally.

**Expected behavior:**
1. No-arg invocation prints usage message and stops.
2. Invalid file path prints error and stops.
3. Valid path reads the report, optionally reconstructs the diff, and spawns the report-checker agent.
4. Agent findings are presented with action buttons (Apply / Show details / Skip).
5. Apply fixes modifies the report file and verifies the result.

**Verification checklist:**
- [ ] Slash menu shows `/report-check`.
- [ ] No arguments prints usage and stops.
- [ ] Non-existent file path prints error and stops.
- [ ] Valid report path spawns agent and displays findings.
- [ ] "Apply fixes" modifies the file and recalculates counts/verdict.
- [ ] "Skip" leaves the report unchanged.
- [ ] No `{placeholder}` text remains after applying fixes.

**Known gotchas:**
- The diff reconstruction depends on the branch still existing locally. If the branch was deleted after the review, the agent runs without diff (Phase 2 accuracy checks are limited).
- The report format parsed here matches the structure produced by `skills/review/SKILL.md` Step 3. If the report format changes, update the parsing in Step 4.
