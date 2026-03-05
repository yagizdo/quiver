#!/usr/bin/env bash
# PreCompact hook — auto-generates a handover from the session transcript before compaction.
set -euo pipefail

# Extract transcript_path from stdin JSON using sed (no jq dependency)
TRANSCRIPT_PATH=$(sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

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

# SYNC: The 8 section headings below must match commands/handover.md lines 89-122.
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
  } | timeout 150 claude -p 2>/dev/null
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
# meaning ls -1r gives newest first.
count=0
while IFS= read -r f; do
  count=$((count + 1))
  if (( count > 3 )); then
    rm -f "$f"
  fi
done < <(ls -1r "${HANDOVER_DIR}"/*.md 2>/dev/null)

exit 0
