---
description: Load the most recent handover note from the previous session into context.
---

# Previous Session Handover

!`latest=$(ls -1t .claude/handovers/*.md 2>/dev/null | head -1); if [ -n "$latest" ]; then cat "$latest"; else echo "No handover files found for this project."; echo "This is a fresh session — no previous context to load."; echo "Run /quiver:handover at the end of this session to start tracking."; fi`

---

The content above is the most recent handover from `.claude/handovers/`.

Review it and:
1. Confirm you understand the current state of the project
2. State what the top priority Next Step is
3. Proceed directly with the highest-priority Next Step unless the user has already provided instructions
