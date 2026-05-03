#!/usr/bin/env bash
# Codex Stop-event wrapper for handover auto-save.
# Guards against excessive saves (Stop fires every turn; PreCompact fires rarely).
# Delegates to the canonical pre-compact-handover.sh after the guard passes.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
HANDOVER_DIR="${PROJECT_DIR}/.claude/handovers"

# Guard: skip if a handover was saved in the last 10 minutes (600 seconds).
if [[ -d "$HANDOVER_DIR" ]]; then
  LAST_HANDOVER=$(ls -1t "${HANDOVER_DIR}"/*.md 2>/dev/null | head -1)
  if [[ -n "$LAST_HANDOVER" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      LAST_MOD=$(stat -f %m "$LAST_HANDOVER" 2>/dev/null || echo 0)
    else
      LAST_MOD=$(stat -c %Y "$LAST_HANDOVER" 2>/dev/null || echo 0)
    fi
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST_MOD ))
    if (( ELAPSED < 600 )); then
      exit 0
    fi
  fi
fi

# Delegate to the canonical hook script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/pre-compact-handover.sh"
