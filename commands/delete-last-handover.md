---
name: delete-last-handover
description: Delete the most recent handover file to remove the last session's context.
---

# Clear Last Handover

---

## Instructions

**First**, use the Glob tool to list `.claude/handovers/*.md`. Sort results by filename descending (newest first, since filenames are timestamps).

Using the Glob results, determine which branch applies:

### Branch A — No Files
If the listing shows an error (e.g., "No such file or directory"), is empty, or contains **no `.md` files**:
> No handover files found — nothing to delete.

**Stop here.**

### Branch B — Files Exist
If there are **one or more `.md` files**:
1. The **first `.md` file** is the most recent (sorted newest-first). This is the deletion target.
2. State the pre-deletion confirmation:
   > **Target:** `{filename}`
   > **Remaining after deletion:** {count - 1} handover file(s)
3. Ask the user for confirmation using `AskUserQuestion`:
   > Delete `{filename}`? This cannot be undone.
   Actions: ["Yes, delete it", "Cancel"]
4. If cancelled, stop: > **Cancelled** — no files were deleted.
5. Delete it using the Bash tool:
   ```
   rm .claude/handovers/{filename}
   ```
6. **Memory cleanup:** Read the auto-memory file (`MEMORY.md` in your memory directory). Remove only lines that contain the `<!-- handover-sourced -->` marker from MEMORY.md using the Edit tool. Leave all other entries untouched. Count removed lines as {N}. After cleanup, inform the user:
   > Also removed {N} handover-sourced references from MEMORY.md.
   If no matching entries were found, skip this message.

---

## Output Template

After deletion, output:

> **Deleted:** `{filename}`
> **Remaining:** {count} handover file(s)

---

## Anti-Patterns

- **Don't** delete without stating the target filename first — the user needs to see what will be removed.
- **Don't** skip verification after deletion — always re-list to confirm the file is gone.
- **Don't** proceed if the directory doesn't exist — report "nothing to delete" and stop.

---

## Verification

Re-list `.claude/handovers/` after deletion to confirm the file is gone and the remaining count is correct.
