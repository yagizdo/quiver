---
description: Delete all handover files for the current project to completely reset session history.
---

# Clear All Handovers

## Handover Files
```
!`ls -1t .claude/handovers/`
```

---

## Instructions

Using the file listing above, determine which branch applies:

### Branch A — No Files
If the listing shows an error (e.g., "No such file or directory"), is empty, or contains **no `.md` files**:
> No handover files found — nothing to purge.
> **Tip:** `/quiver:handover` to create one.

**Stop here.**

### Branch B — Files Exist
If there are **one or more `.md` files**:
1. List the pre-deletion inventory:
   > **Files to delete ({count}):**
   > {bulleted list of all .md filenames}
2. Ask the user: "Delete all {count} handover file(s)? This cannot be undone."
3. **Only proceed if the user confirms.** If declined, stop and output:
   > **Cancelled** — no files were deleted.
4. Delete them all using the Bash tool:
   ```
   rm -f .claude/handovers/*.md
   ```

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
> **Tip:** `/quiver:handover` to start fresh tracking, `/quiver:load-handover` to verify.

---

## Verification

Re-list `.claude/handovers/` after deletion to confirm no `.md` files remain. If the directory is now empty, confirm: "Directory clean — 0 handover files."
