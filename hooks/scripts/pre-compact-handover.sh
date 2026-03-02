#!/usr/bin/env bash
# PreCompact hook — auto-generates a handover from the session transcript before compaction.
set -euo pipefail

# Guard: jq must be available (don't block compaction if missing)
if ! command -v jq &>/dev/null; then
  echo "[quiver] WARNING: jq not found — skipping handover generation" >&2
  exit 0
fi

# Read stdin JSON event
EVENT=$(cat)

# Extract transcript_path (empty string if key is missing or null)
TRANSCRIPT_PATH=$(printf '%s' "$EVENT" | jq -r '.transcript_path // empty')

# Guard: no transcript path in event
if [[ -z "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Guard: transcript file doesn't exist
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# Resolve project dir
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
HANDOVER_DIR="${PROJECT_DIR}/.claude/handovers"

# Ensure handover directory exists
mkdir -p "$HANDOVER_DIR"

# Prompt template prefix — transcript is appended via stdin pipe to avoid ARG_MAX limits
PROMPT_PREFIX='Read the following Claude Code session transcript and produce a HANDOVER note.
Goal: The next Claude session (or a teammate) should be able to continue from where we left off.

Use these exact headings (H2 markdown):
## Summary
## What Was Done
## What We Tried / Dead Ends
## Bugs & Fixes
## Key Decisions (and Why)
## Gotchas / Things to Watch Out For
## Next Steps
## Important Files Map

Transcript:'

# Generate handover — pipe prompt + transcript to claude -p via stdin
CONTENT=$(
  {
    printf '%s\n' "$PROMPT_PREFIX"
    cat "$TRANSCRIPT_PATH"
  } | claude -p 2>/dev/null
) || CONTENT=""

# Guard: empty output (claude failed or produced nothing)
if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Save handover to timestamped file
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
OUT_FILE="${HANDOVER_DIR}/${TIMESTAMP}.md"
printf '%s\n' "$CONTENT" > "$OUT_FILE"

# Prune: keep only the 3 most recent .md files
# ls -1r gives reverse alpha order; filenames are timestamps so newest sort last alphabetically,
# meaning ls -1r gives newest first — identical to Python's sorted(..., reverse=True)
ls -1r "${HANDOVER_DIR}"/*.md 2>/dev/null | tail -n +4 | xargs rm -f || true

exit 0
