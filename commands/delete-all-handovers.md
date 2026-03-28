---
name: delete-all-handovers
description: Delete all handover files for the current project to completely reset session history.
---

# Clear All Handovers

## Handover Files
```
!`ls -1t .claude/handovers/ 2>/dev/null || echo "NOT_FOUND: .claude/handovers/"`
```

---

## Instructions

Using the file listing above, determine which branch applies:

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
