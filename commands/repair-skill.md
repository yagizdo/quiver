---
name: repair-skill
description: Diagnose and fix a broken skill by analyzing its structure, verifying API references against current docs, and applying targeted repairs.
argument-hint: "[optional: skill name or description of what broke]"
---

# Gather Project Context

```
!`ls -1 skills/`
```

```
!`find skills -mindepth 1 -maxdepth 1 -type d`
```

```
!`find .claude/skills -mindepth 1 -maxdepth 1 -type d`
```

```
!`cat .claude-plugin/plugin.json`
```

---

# Instructions

You are a skill diagnostician. Your goal is to identify exactly what is broken in a skill, verify against current documentation, and apply the minimum targeted repairs needed to fix it.

Before generating any diagnosis, load the `repair-skill` companion skill for diagnostic patterns, failure taxonomy, and repair strategies.

```
IDENTIFY --> DIAGNOSE --> RESEARCH --> PROPOSE --> APPLY & VERIFY
```

---

# Phase 1: Identify

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

# Phase 2: Diagnose

Using the diagnostic checklist and failure patterns from the `repair-skill` companion skill, analyze the identified skill.

**Run all checks in order:**

1. **Structural validation** -- Frontmatter exists and parses, `name` matches directory, `description` present, referenced files exist
2. **Content quality** -- Instructions are specific (not generic), no placeholder text, no contradictions, methodology ordered by impact
3. **Integration check** -- Skill path registered in `plugin.json` skills array, scripts pass `bash -n`
4. **User-reported issue** -- If `$ARGUMENTS` described a specific problem, prioritize diagnosing that

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

# Phase 3: Research

For each external library or API referenced in the skill:

1. Call `resolve-library-id` with the library name
2. Call `query-docs` with the resolved ID and a targeted query about the specific API patterns used in the skill
3. Compare the skill's instructions against the current docs -- flag deprecated APIs, changed parameters, or updated practices

**Rules:**
- Skip this phase entirely if the skill does not reference external libraries or APIs
- Maximum 3 context7 calls per library
- Record findings as additional diagnostic entries with severity levels

---

# Phase 4: Propose

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

# Phase 5: Apply & Verify

1. Apply each proposed edit using the Edit or Write tool
2. Re-read each modified file to confirm the changes applied correctly
3. Validate YAML frontmatter parses correctly (check for syntax issues)
4. Verify all referenced files still exist
5. Run `bash -n` on any modified scripts
6. If the user chose **Apply & Commit**, commit with message: `fix(skills): repair {skill-name}` -- ask for confirmation before committing

**Output:**

> **Skill repaired:** `{skill-path}`
> **Changes:** {count} file(s) modified
> **Issues fixed:** {count} ({critical} critical, {warning} warning)
> **Docs consulted:** {libraries looked up via context7, or "None"}
> **Committed:** `{hash}` {subject} *(only if committed)*

---

# Anti-Patterns

- **Don't** rewrite the entire skill -- make targeted repairs that fix the identified issues.
- **Don't** skip context7 lookup when the skill references external APIs -- stale docs are a top failure mode.
- **Don't** apply changes without showing before/after diffs and getting user approval.
- **Don't** invent new content beyond what is needed to fix the diagnosed issues.
- **Don't** commit with `--no-verify` -- if hooks fail, fix the underlying issue.
