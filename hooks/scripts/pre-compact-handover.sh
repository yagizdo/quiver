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

# Keep handovers out of git: the bash copy of the keep-local rule in
# skills/local-files/SKILL.md (bound by tests/skills/test-local-files-contract.sh).
# A hook cannot read project instructions, so tracked files under the directory are
# its only "track this" signal. Every git call sits in a condition: under set -e a
# nonzero exit (check-ignore 1, ls-files 128 outside a repo) would end the hook.
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  && [[ -z "$(git -C "$PROJECT_DIR" ls-files .claude/handovers 2>/dev/null)" ]]; then
  # check-ignore exits 0 when ignored, 1 when not, 128 on an error such as a
  # symlinked .claude. Only 1 means "add the entry".
  IGNORE_RC=0
  git -C "$PROJECT_DIR" check-ignore -q .claude/handovers/x 2>/dev/null || IGNORE_RC=$?
  # Exclude patterns are relative to the repo top; the project dir may sit below it.
  PREFIX=$(git -C "$PROJECT_DIR" rev-parse --show-prefix 2>/dev/null) || PREFIX=""
  EXCLUDE_FILE=$(git -C "$PROJECT_DIR" rev-parse --git-path info/exclude 2>/dev/null) || EXCLUDE_FILE=""
  if [[ "$IGNORE_RC" -eq 1 && -n "$EXCLUDE_FILE" ]]; then
    # --git-path can print a path relative to the project dir, not the hook's cwd.
    [[ "$EXCLUDE_FILE" == /* ]] || EXCLUDE_FILE="${PROJECT_DIR}/${EXCLUDE_FILE}"
    ENTRY="${PREFIX}.claude/handovers/"
    {
      # A .gitignore negation outranks this file, so check-ignore can still exit 1
      # with the entry already in; the exact-line check stops a re-append.
      if ! grep -qxF -- "$ENTRY" "$EXCLUDE_FILE"; then
        mkdir -p "$(dirname "$EXCLUDE_FILE")"
        # Append, never rewrite; a missing final newline would join the user's last line.
        if [[ -s "$EXCLUDE_FILE" && -n "$(tail -c 1 "$EXCLUDE_FILE")" ]]; then
          printf '\n' >> "$EXCLUDE_FILE"
        fi
        printf '%s\n' "$ENTRY" >> "$EXCLUDE_FILE"
      fi
    } 2>/dev/null || true
  fi
fi

# Ensure handover directory exists
mkdir -p "$HANDOVER_DIR"

# SYNC: The 8 section headings below must match skills/handover/SKILL.md, under its
# own SYNC marker. Verified by tests/hooks/test-handover-sync-contract.sh.
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
