---
name: delete-all-handovers
description: Delete all handover files for the current project to completely reset session history.
disable-model-invocation: true
---

# Clear All Handovers

---

## Instructions

**First**, use the Glob tool to list `.claude/handovers/*.md`. Sort results by filename descending (newest first, since filenames are timestamps).

Using the Glob results, determine which branch applies:

### Branch A — No Files
If the listing shows an error (e.g., "No such file or directory"), is empty, or contains **no `.md` files**:
> No handover files found — nothing to purge.

**Stop here.**

### Branch B — Files Exist
If there are **one or more `.md` files**:
1. List the pre-deletion inventory:
   > **Files to delete ({count}):**
   > {bulleted list of all .md filenames}
2. Ask the user using the `AskUserQuestion` tool with these actions:
   - Question: "Delete all {count} handover file(s)? This cannot be undone."
   - Actions: `["Yes, delete all", "Cancel"]`
3. **Only proceed if the user selects "Yes, delete all".** If cancelled, stop and output:
   > **Cancelled** — no files were deleted.
4. Delete them all using the Bash tool:
   ```
   rm -f .claude/handovers/*.md
   ```
5. **Memory cleanup:** Read the auto-memory file (`MEMORY.md` in your memory directory). Remove only lines that contain the `<!-- handover-sourced -->` marker from MEMORY.md using the Edit tool. Leave all other entries untouched. Count removed lines as {N}. After cleanup, inform the user:
   > Also removed {N} handover-sourced references from MEMORY.md.
   If no matching entries were found, skip this message.

---

## Anti-Patterns

- **Don't** delete without listing the inventory first — the user needs to see what will be removed.
- **Don't** skip confirmation — bulk deletion is irreversible and must be explicitly approved.
- **Don't** proceed if the directory doesn't exist — report "nothing to purge" and stop.

---

## Output Template

After deletion, output:

> **Purged:** {count} handover file(s)
> **Files deleted:** {comma-separated filenames}
> **Status:** Clean slate.

---

## Verification

Re-list `.claude/handovers/` after deletion to confirm no `.md` files remain. If the directory is now empty, confirm: "Directory clean — 0 handover files."

---

## Test Plan

**Trigger:** `/delete-all-handovers` (and `/quiver:delete-all-handovers` should also work)

**Setup:**
- `.claude/handovers/` exists in the project root with two or more `.md` files.

**Expected behavior:**
1. Skill globs `.claude/handovers/*.md` and lists every filename with the count (`Files to delete (N): …`).
2. Skill calls `AskUserQuestion` with `["Yes, delete all", "Cancel"]`.
3. On cancel, skill prints `Cancelled — no files were deleted.` and exits without touching any files.
4. On confirm, skill runs `rm -f .claude/handovers/*.md`, then strips lines tagged `<!-- handover-sourced -->` from `MEMORY.md` via Edit, reporting how many were removed.
5. Skill re-lists the directory to confirm 0 `.md` files remain and prints the output template (`Purged`, `Files deleted`, `Status: Clean slate.`).

**Verification checklist:**
- [ ] Slash menu shows `/delete-all-handovers`.
- [ ] With an empty/missing handovers directory, skill prints the `nothing to purge` line and writes nothing.
- [ ] Inventory list shows every `.md` filename before deletion.
- [ ] Confirmation prompt is `AskUserQuestion`, not plain text.
- [ ] `MEMORY.md` lines without the `<!-- handover-sourced -->` marker stay intact.
- [ ] Final re-list reports `Directory clean — 0 handover files.`

**Known gotchas:**
- The `rm -f .claude/handovers/*.md` glob is shell-expanded; if the directory is missing entirely, `rm -f` exits 0, which is desired but means callers must rely on the pre-deletion existence check.
- Bulk deletion is irreversible; never skip the `AskUserQuestion` step, even when running automated tests.
