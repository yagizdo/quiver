#!/bin/bash
# test-local-files-contract.sh
# Guards where Quiver's development files live. Brainstorm specs moved from
# docs/brainstorms/ to .claude/specs/: /brainstorm writes them there, /plan Step 6
# Check 3 finds them there, /advise names the path in its no-write rule, and
# /visual-companion copies mockups beside the spec. A skill still naming the old
# path either writes a spec nothing reads or looks for one in a directory nothing
# writes, and neither raises an error. Every assertion reads the live skill files.
#
# Run directly: bash tests/skills/test-local-files-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

echo "=== 1. No skill names the old brainstorm spec path ==="

HITS="$(grep -rn 'docs/brainstorms' "$REPO_ROOT/skills" 2>/dev/null)"
if [ -z "$HITS" ]; then
  pass "no file under skills/ names docs/brainstorms"
else
  fail "files under skills/ still name docs/brainstorms:"
  echo "$HITS" | sed "s|$REPO_ROOT/||; s|^|    |"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
