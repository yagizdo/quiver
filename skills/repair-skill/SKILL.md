---
name: repair-skill
description: Diagnose and fix a broken skill by analyzing its structure, verifying API references against current docs, and applying targeted repairs.
argument-hint: "[optional: skill name or description of what broke]"
disable-model-invocation: true
---

# Repair Skill

Diagnose and fix a broken Claude Code skill end-to-end. This skill bundles the workflow (Identify / Diagnose / Research / Propose / Apply) at the top and the diagnostic reference (anatomy, failure taxonomy, checklists, repair strategies, context7 guide) at the bottom; cross-references are in-document section links, not external file loads.

**Before starting**, gather project context silently (do not show results to the user):
1. Glob `skills/*/SKILL.md` -- skill directories
2. Glob `.claude/skills/*/SKILL.md` -- alternative skill location
3. Read `.claude-plugin/plugin.json` -- plugin manifest

Treat missing paths as empty. Proceed regardless.

You are a skill diagnostician. Use the [Skill Repair Reference](#skill-repair-reference) below as the source of truth for diagnostic patterns, failure taxonomy, and repair strategies.

```
IDENTIFY --> DIAGNOSE --> RESEARCH --> PROPOSE --> APPLY & VERIFY
```

---

## Phase 1: Identify

Silently determine which case applies:

### Branch A -- Argument Provided

If `$ARGUMENTS` is not empty, interpret it as either:
- A **skill name** (match against discovered skill directories), or
- A **problem description** (identify the affected skill from conversation context, then focus diagnosis on the described issue)

Read the full skill directory: `SKILL.md`, plus any files in `references/` and `scripts/`.

Proceed to Phase 2.

### Branch B -- No Arguments

If `$ARGUMENTS` is empty, check conversation context for:
- Recent skill invocations or SKILL.md references
- Error messages related to a skill
- User complaints about skill behavior

If a skill is identifiable from context, confirm with the user and proceed.

If ambiguous, list all discovered skills and ask the user to pick one using `AskUserQuestion`:

> Which skill needs repair?
>
> {numbered list of discovered skills}

### Branch C -- No Skills Found

If no skill directories were found in the data-gathering output:

> No skills found in this project. Skills live in `skills/{name}/SKILL.md` or `.claude/skills/{name}/SKILL.md`.

**Stop here.**

---

## Phase 2: Diagnose

Using the [Diagnostic Checklist](#diagnostic-checklist) and [Common Failure Patterns](#common-failure-patterns) below, analyze the identified skill.

**Run all checks in order:**

1. **Structural validation** -- Frontmatter exists and parses, `name` matches directory, `description` present, referenced files exist (see [Structural Validation](#1-structural-validation)).
2. **Content quality** -- Instructions are specific (not generic), no placeholder text, no contradictions, methodology ordered by impact (see [Content Quality](#2-content-quality)).
3. **Integration check** -- Skill path registered in `plugin.json` skills array, scripts pass `bash -n` (see [Integration Check](#4-integration-check)).
4. **User-reported issue** -- If `$ARGUMENTS` described a specific problem, prioritize diagnosing that.

**Output a diagnostic summary:**

```
**Diagnostic Summary for `{skill-name}`**

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | {issue} | CRITICAL/WARNING/INFO | {brief description} |
| ... | ... | ... | ... |
```

If no issues found, report the skill as healthy and stop:

> Skill `{skill-name}` passed all diagnostic checks. No repairs needed.

**Stop here** if healthy.

---

## Phase 3: Research

For each external library or API referenced in the skill, run the [Context7 Lookup Guide](#context7-lookup-guide) below:

1. Call `resolve-library-id` with the library name
2. Call `query-docs` with the resolved ID and a targeted query about the specific API patterns used in the skill
3. Compare the skill's instructions against the current docs -- flag deprecated APIs, changed parameters, or updated practices

**Rules:**
- Skip this phase entirely if the skill does not reference external libraries or APIs
- Maximum 3 context7 calls per library
- Record findings as additional diagnostic entries with severity levels

---

## Phase 4: Propose

Present all proposed changes grouped by file, with before/after diffs:

```
**Proposed Repairs for `{skill-name}`**

### Change 1: {filename} -- {section}

**Current:**
> {exact text from file}

**Proposed:**
> {corrected text}

**Reason:** {why this fixes the issue}

---
{repeat for each change}
```

Then ask the user to choose using `AskUserQuestion`:

> How should I proceed?
>
> 1. **Apply & Commit** -- Apply changes and commit (`fix(skills): repair {name}`)
> 2. **Apply Only** -- Apply changes without committing
> 3. **Revise** -- Adjust proposed changes based on your feedback
> 4. **Cancel** -- Abort without changes

**Wait for the user's response. Do not proceed without approval.**

If the user chooses **Revise**, incorporate their feedback and re-present the proposal. Loop until they choose Apply, Apply & Commit, or Cancel.

If the user chooses **Cancel**:

> Repair cancelled. No changes were made.

**Stop here.**

---

## Phase 5: Apply & Verify

1. Apply each proposed edit using the Edit or Write tool. Use the [Repair Strategies](#repair-strategies) section to choose the right fix for each failure pattern.
2. Re-read each modified file to confirm the changes applied correctly.
3. Validate YAML frontmatter parses correctly (check for syntax issues).
4. Verify all referenced files still exist.
5. Run `bash -n` on any modified scripts.
6. If the user chose **Apply & Commit**, commit with message: `fix(skills): repair {skill-name}` -- ask for confirmation before committing.

**Output:**

> **Skill repaired:** `{skill-path}`
> **Changes:** {count} file(s) modified
> **Issues fixed:** {count} ({critical} critical, {warning} warning)
> **Docs consulted:** {libraries looked up via context7, or "None"}
> **Committed:** `{hash}` {subject} *(only if committed)*

---

## Workflow Anti-Patterns

- **Don't** rewrite the entire skill -- make targeted repairs that fix the identified issues.
- **Don't** skip context7 lookup when the skill references external APIs -- stale docs are a top failure mode.
- **Don't** apply changes without showing before/after diffs and getting user approval.
- **Don't** invent new content beyond what is needed to fix the diagnosed issues.
- **Don't** commit with `--no-verify` -- if hooks fail, fix the underlying issue.

---

# Skill Repair Reference

This section contains diagnostic patterns, failure taxonomies, and repair strategies for fixing broken Claude Code skills. The Phase 2 / Phase 3 / Phase 5 workflow steps reference these subsections directly.

---

## Skill Anatomy

A valid skill is a directory under `skills/` containing at minimum a `SKILL.md` file.

### Required Structure

```
skills/{name}/
  SKILL.md          # Main skill file (required)
  references/       # Supporting docs (optional)
  scripts/          # Helper scripts (optional)
```

### SKILL.md Required Fields

| Field | Required | Validation |
|-------|----------|------------|
| `name` | Yes | Must match directory name. Kebab-case. |
| `description` | Yes | Quoted string. Should describe when/why to use the skill. |
| `disable-model-invocation` | Recommended | `true` for knowledge-base skills that should not be invoked as agents. |

### Frontmatter Validation Rules

- YAML must be valid (no tabs, proper quoting, correct nesting).
- `name` value must exactly match the parent directory name.
- `description` must be a non-empty string. Wrap in quotes if it contains colons or special YAML characters.
- No unknown fields that could confuse the runtime.

---

## Common Failure Patterns

| # | Pattern | Severity | Symptoms | Detection Method |
|---|---------|----------|----------|------------------|
| F1 | Missing/malformed frontmatter | CRITICAL | Skill not recognized, load errors | YAML parse check |
| F2 | `name` mismatch | CRITICAL | Skill not found when referenced | Compare `name` field to directory name |
| F3 | Stale API references | WARNING | Instructions produce errors when followed | Context7 lookup against current docs |
| F4 | Deprecated function calls | WARNING | Code examples fail at runtime | Context7 lookup, changelog review |
| F5 | Vague/generic instructions | WARNING | Agent produces shallow or off-target output | Manual review: look for "as needed", "if applicable", "consider" |
| F6 | Broken file references | CRITICAL | Skill references files that don't exist | Check `references/` and `scripts/` paths |
| F7 | Overly long skill (>300 lines) | INFO | Token waste, diluted focus | Line count check |
| F8 | Missing examples | INFO | Hard to understand when to use the skill | Check for absence of example blocks |
| F9 | Wrong model recommendation | WARNING | Skill suggests `haiku` for complex reasoning tasks, or `opus` for simple lookups | Review model guidance against task complexity |
| F10 | Script syntax errors | CRITICAL | Hook/helper scripts fail | `bash -n` check |

---

## Diagnostic Checklist

Run these checks in order. Stop at any CRITICAL finding -- fix it before continuing.

### 1. Structural Validation

- [ ] `SKILL.md` exists in the skill directory
- [ ] YAML frontmatter parses without errors
- [ ] `name` field matches directory name
- [ ] `description` field is present and non-empty
- [ ] All files referenced in the skill body actually exist

### 2. Content Quality

- [ ] Instructions are specific and actionable (not generic advice)
- [ ] Examples are realistic and domain-specific
- [ ] Methodology steps are ordered by impact
- [ ] No placeholder text ("TODO", "TBD", "add later")
- [ ] No contradictory instructions

### 3. API/Library Verification (context7)

- [ ] Identify all external library/API references in the skill
- [ ] For each library: resolve library ID via `resolve-library-id`
- [ ] Query current docs for specific APIs/patterns mentioned
- [ ] Flag any deprecated APIs, changed parameters, or updated practices
- [ ] Verify code examples match current library versions

### 4. Integration Check

- [ ] Skill directory is under a path registered in `plugin.json` `skills` array
- [ ] If skill has scripts, they pass `bash -n` syntax check
- [ ] Cross-references to other skills use correct paths

---

## Repair Strategies

### F1: Missing/Malformed Frontmatter

**Fix:** Add or correct the YAML frontmatter block. Ensure `---` delimiters are on their own lines, no tabs are used, and strings with special characters are quoted.

### F2: Name Mismatch

**Fix:** Update the `name` field to match the directory name exactly. Do not rename the directory -- change the field.

### F3/F4: Stale API References

**Fix:** Use context7 to look up current documentation. Replace outdated API calls, parameters, and patterns with current equivalents. Preserve the skill's intent while updating the implementation details.

### F5: Vague Instructions

**Fix:** Replace generic phrases with specific, actionable directives. "Consider security implications" becomes "Check for SQL injection in user-input parameters, XSS in rendered output, and CSRF token presence on state-changing endpoints."

### F6: Broken File References

**Fix:** Either create the missing file or update the reference. If the referenced content was important, reconstruct it from context. If it was optional, remove the reference.

### F7: Overly Long Skill

**Fix:** Identify the highest-impact sections and trim the rest. Move detailed reference material to `references/` files. Keep SKILL.md under 200 lines for focused skills, 300 for comprehensive ones.

### F8: Missing Examples

**Fix:** Add 2-3 realistic trigger examples in XML format showing when the skill should be used.

### F9: Wrong Model Recommendation

**Fix:** Match model to task complexity: `haiku` for lightweight checks, `sonnet` for balanced work, `opus` for deep reasoning, `inherit` when unsure.

### F10: Script Syntax Errors

**Fix:** Run `bash -n` on the script, fix reported syntax errors. Common issues: unclosed quotes, missing `fi`/`done`, incorrect variable expansion.

---

## Context7 Lookup Guide

### Extracting Library References

Scan the skill body for:
- Import/require statements in code examples
- Package names mentioned in prose (e.g., "uses the Stripe API")
- CLI tool references (e.g., "run `eslint`")
- Framework patterns (e.g., "Rails ActiveRecord", "React hooks")

### Formulating Queries

For each identified library:

1. **Resolve:** Call `resolve-library-id` with the library name (e.g., "stripe", "react", "rails")
2. **Query:** Call `query-docs` with the resolved ID and a targeted query about the specific API pattern used in the skill
3. **Compare:** Check the returned docs against what the skill instructs

### Query Examples

| Skill References | resolve-library-id | query-docs Query |
|-----------------|-------------------|------------------|
| `Stripe.charges.create` | "stripe node" | "create a charge" |
| `useEffect cleanup` | "react" | "useEffect cleanup function" |
| `ActiveRecord.find_by` | "rails" | "find_by query method" |

### Comparison Checklist

- Are the function/method signatures still correct?
- Have required parameters changed?
- Are there new required options or deprecated ones?
- Has the recommended pattern changed (e.g., callbacks to promises)?
- Are version-specific notes still accurate?

**Limit:** Maximum 3 context7 calls per library to avoid excessive token usage.

---

## Test Plan

**Trigger:** `/repair-skill <skill-name>` or `/repair-skill <problem description>` or `/repair-skill` (interactive); `/quiver:repair-skill` should also work.

**Setup:**
- Project root with at least one skill directory under `skills/<name>/SKILL.md` or `.claude/skills/<name>/SKILL.md`.

**Expected behavior:**
1. Skill silently globs both skill locations and reads `.claude-plugin/plugin.json`; with no skills found, exits via Branch C.
2. Phase 1 picks the target skill from `$ARGUMENTS` (Branch A) or conversation context / interactive selection (Branch B).
3. Phase 2 runs the Diagnostic Checklist and outputs a `Diagnostic Summary` table; stops cleanly with a "passed all checks" message when healthy.
4. Phase 3 runs context7 lookups (max 3 per library) only when the skill references external libraries; skipped otherwise.
5. Phase 4 presents before/after diffs and asks `AskUserQuestion` with `Apply & Commit / Apply Only / Revise / Cancel`; loops on Revise; stops on Cancel without writing.
6. Phase 5 applies edits, re-reads files to verify, validates YAML, runs `bash -n` on scripts, and (when chosen) prepares the `fix(skills): repair <name>` commit -- still gated by user confirmation per global rules.

**Verification checklist:**
- [ ] Slash menu shows `/repair-skill`.
- [ ] Diagnostic Summary table maps each issue to the F1-F10 failure pattern.
- [ ] Context7 calls do not exceed 3 per library; libraries with no references trigger zero calls.
- [ ] Cancel branch results in zero file modifications and no commit.
- [ ] Apply branch re-reads each modified file to confirm content; YAML and script syntax checks pass before completion.
- [ ] The `Apply & Commit` path still asks for explicit user confirmation before running `git commit`.

**Known gotchas:**
- The Authoring/Repair Reference (Skill Anatomy, F1-F10, Checklists, Strategies, Context7 Guide) is the single source of truth -- the workflow phases reference it via in-doc anchors instead of loading a separate file.
- The Diagnostic Summary stops the workflow at any CRITICAL finding; do NOT silently continue to repair Lows when a Critical is unresolved.
- Avoid `--no-verify` even if hooks fail; surface the error to the user and let them decide.
