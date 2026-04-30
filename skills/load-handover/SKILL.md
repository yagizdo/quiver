---
name: load-handover
description: Load the most recent handover note from the previous session into context.
disable-model-invocation: true
---

# Previous Session Handover

---

## Instructions

**First**, use the Glob tool to list `.claude/handovers/*.md`. Sort results by filename descending (newest first, since filenames are timestamps).

Using the Glob results, determine which branch applies:

### Branch A — No Files
If the listing shows an error (e.g., "No such file or directory"), is empty, or contains **no `.md` files**:
> No handover files found for this project.
> This is a fresh session — no previous context to load.
**Stop here.**

### Branch B — Files Exist
If there are **one or more `.md` files**:
1. The **first `.md` file** in the listing is the most recent (sorted newest-first).
   Read it using the Read tool at path `.claude/handovers/{filename}`.
2. Present it using the output template below.
3. If more than one `.md` file exists, append: "{count} older handover(s) also available."

---

## Output Template

After reading the handover file, present this summary:

> **Session loaded:** `{filename}`
> **Date:** {date extracted from timestamp in filename}
> **Top Priority:** {first item from Next Steps section}

If the handover has no "Next Steps" section or it says "N/A", set Top Priority to "No next steps recorded" and ask the user what they'd like to focus on.

Then:
1. Confirm you understand the current state of the project.
2. List all Next Steps with their priority order and a short explanation of each.
3. Ask the user which one they'd like to work on.

---

## Anti-Patterns

- **Don't** dump the raw handover contents without a summary header — always lead with the output template.
- **Don't** auto-start the first Next Step without asking — always present the list and let the user choose.
- **Don't** read older handover files unless the user explicitly requests it.

---

## Verification

- Confirm the file read succeeded (non-empty content returned).
- If the file content looks malformed (no section headings, empty body), warn: "This handover may be incomplete — proceeding with available context."
- Confirm the output template was fully populated — no raw `{placeholder}` text remains in your response.

---

## Test Plan

**Trigger:** `/load-handover` (and `/quiver:load-handover` should also work)

**Setup:**
- `.claude/handovers/` exists in the project root with at least one `<timestamp>.md` file written by `/handover`.

**Expected behavior:**
1. Skill globs `.claude/handovers/*.md`, sorts descending, picks the newest filename.
2. With no files (or directory missing), skill prints `No handover files found for this project.` and exits.
3. With at least one file, skill reads the most recent and prints the output template (`Session loaded`, `Date`, `Top Priority`).
4. Skill lists every Next Steps item with a one-line explanation and asks the user which one to work on.
5. With a malformed file (no headings), skill warns once and continues with the available content.

**Verification checklist:**
- [ ] Slash menu shows `/load-handover`.
- [ ] Output uses the exact template wording for `Session loaded`, `Date`, `Top Priority`.
- [ ] When more than one handover exists, the skill appends `{count} older handover(s) also available.`
- [ ] No raw `{placeholder}` text remains in the printed summary.
- [ ] Older handovers are not read unless the user explicitly asks.

**Known gotchas:**
- Lexicographic sort relies on the `YYYY-MM-DD_HH-MM-SS.md` filename convention; manually-renamed handovers can break ordering.
- "Top Priority" comes from the first `Next Steps` bullet; if the section is missing, the skill must fall back gracefully rather than emit a placeholder.
