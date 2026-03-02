---
description: Summarize the current work state and prepare a handover note for the next session.
---

# Automatically Gathered Context

## Git Status
!`git status --short`

## Git Diff Summary
!`git diff --stat`

# Handover Instructions

<!-- SYNC: The 8 section headings below must match hooks/scripts/pre-compact-handover.sh PROMPT_PREFIX. -->
Using the context above and our conversation, prepare a structured handover note with these exact sections:

## Summary
One-paragraph TL;DR of the session.

## What Was Done
Files modified, features completed, problems solved.

## What We Tried / Dead Ends
Approaches that didn't work and why.

## Bugs & Fixes
Issues found and how they were resolved.

## Key Decisions (and Why)
Architectural choices made this session.

## Gotchas / Things to Watch Out For
Non-obvious constraints, traps, or environment quirks.

## Next Steps
Ordered list — first item is the highest priority action for the next session.

## Important Files Map
Key files and their roles in the current work.

---

## Save to Disk (Required)

After writing the summary above, do all of the following:

### 1. Write handover file
Get a timestamp: run `date '+%Y-%m-%d_%H-%M-%S'` via Bash.
Create directory: `.claude/handovers/` in the project root (if it doesn't exist).
Write the full 8-section handover to: `.claude/handovers/{timestamp}.md`

### 2. Prune old handover files
List all `.md` files in `.claude/handovers/`, sorted by name (newest first).
Delete all files beyond the 3 most recent.

### 3. Update MEMORY.md
In the project memory file, update (or add) a `## Last Handover` section:
```
## Last Handover
- file: .claude/handovers/{timestamp}.md
- summary: {one sentence from the Summary section}
```

### 4. Save any active plan
If there is an unsaved implementation plan in context, save it to `PLAN.md`. Skip if already current.

After completing all saves, confirm: "Handover saved to .claude/handovers/{timestamp}.md — ready to close the session."
