#!/bin/bash
# test-ship-contract.sh
# Guards the strings /ship shares with the skills it invokes.
#
#   skills/work/SKILL.md   -- Phase 5d ends /work with a caller-neutral continuation
#                             line. /ship enters /work more than once (build and fix),
#                             so the line must not name one ship step: a sentence that
#                             says the caller "continues into its verification" sends
#                             a fix-stage /work run into verification instead of the
#                             re-review.
#
# The Skill tool does not return, so this line is the only thing that carries the turn
# back into the calling skill. A rewording that drops it raises no error; the turn ends
# on /work's summary. Every assertion reads the live skill files. No fixture is written.
#
# Run directly: bash tests/skills/test-ship-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

WORK="$REPO_ROOT/skills/work/SKILL.md"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <pattern> <label>
assert_in() {
  if grep -qF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

# assert_not_in <file> <pattern> <label>
assert_not_in() {
  if grep -qF -- "$2" "$1"; then
    fail "$3"
  else
    pass "$3"
  fi
}

echo ""
echo "=== 1. /work's continuation line names no caller step ==="

if [ ! -f "$WORK" ]; then
  fail "skills/work/SKILL.md not found at $WORK"
else
  assert_in "$WORK" 'follow its continuation step' "work 5d says 'follow its continuation step'"
  assert_not_in "$WORK" 'continues into its verification' "work 5d no longer names one /ship step as the continuation"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
