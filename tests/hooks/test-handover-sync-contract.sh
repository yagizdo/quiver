#!/bin/bash
# test-handover-sync-contract.sh
# Binds the 8 handover section headings across the two files that hand-copy them:
#   skills/handover/SKILL.md          -- the /handover prompt, headings under the SYNC marker
#   hooks/scripts/pre-compact-handover.sh -- PROMPT_PREFIX, the same 8 headings for `claude -p`
#
# The two paths write into the same directory and are read back by the same consumer:
# skills/load-handover/SKILL.md, and any human opening the newest file in
# .claude/handovers/. Whether a note came from the skill or from the hook is invisible
# at read time, so the two only stay interchangeable while the headings match. Rename
# one side and nothing errors -- the hook keeps summarizing, the file keeps being
# written, and the drift only surfaces as a note that is shaped differently from the
# last three.
#
# Both files carry a `SYNC:` comment pointing at the other, and until this test existed
# those comments were the whole enforcement mechanism. They had already gone stale: each
# cited line numbers for the other file that were off by one. The numbers are gone now --
# a pointer that rots on every unrelated edit above it is worse than no pointer, and the
# heading equality this test asserts is the part that actually matters.
#
# Order is asserted, not just membership. Both prompts present the headings as the
# document order a note is written in, and a reordered list is a differently-shaped note.
#
# Run directly: bash tests/hooks/test-handover-sync-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
SKILL="$REPO_ROOT/skills/handover/SKILL.md"
HOOK="$REPO_ROOT/hooks/scripts/pre-compact-handover.sh"

EXPECTED_COUNT=8

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

echo ""
echo "=== 1. Preflight ==="
MISSING=0
if [ ! -f "$SKILL" ]; then
  fail "missing skills/handover/SKILL.md -- one half of the SYNC contract"
  MISSING=1
fi
if [ ! -f "$HOOK" ]; then
  fail "missing hooks/scripts/pre-compact-handover.sh -- the other half"
  MISSING=1
fi
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit 1
fi
pass "both SYNC contract files present"

echo ""
echo "=== 2. Each file still points at the other ==="
if grep -q '^<!-- SYNC:.*pre-compact-handover\.sh' "$SKILL"; then
  pass "skills/handover/SKILL.md carries a SYNC marker naming the hook"
else
  fail "skills/handover/SKILL.md has no SYNC marker naming hooks/scripts/pre-compact-handover.sh -- the marker is also the anchor section 3 extracts the headings from, so an editor who removes it removes the only in-file warning that the hook has a copy"
fi

if grep -q '^# SYNC:.*handover/SKILL\.md' "$HOOK"; then
  pass "pre-compact-handover.sh carries a SYNC comment naming the skill"
else
  fail "hooks/scripts/pre-compact-handover.sh has no SYNC comment naming skills/handover/SKILL.md -- someone editing PROMPT_PREFIX has nothing telling them a second copy exists"
fi

echo ""
echo "=== 3. Extract both heading lists ==="

# Skill side: H2 headings after the SYNC marker. The file continues with its own
# structural headings (## Quality Gates, ## Anti-Patterns, ...), so the list is capped
# at 8 rather than run to end of file. A deleted section pulls the next real heading in
# and section 4 reports it as a mismatch, which is the intent.
SKILL_HEADINGS="$(awk -v n="$EXPECTED_COUNT" '
  /^<!-- SYNC:/ { s = 1; next }
  s && /^## / { print; c++; if (c == n) exit }
' "$SKILL")"

# Hook side: H2 lines inside the PROMPT_PREFIX single-quoted string only. Scoped to that
# string so a future `## ...` shell comment at column 0 cannot join the list.
HOOK_HEADINGS="$(awk "
  /^PROMPT_PREFIX=/ { s = 1; next }
  s && /'\$/ { exit }
  s && /^## / { print }
" "$HOOK")"

SKILL_N="$(printf '%s\n' "$SKILL_HEADINGS" | grep -c '^## ')"
HOOK_N="$(printf '%s\n' "$HOOK_HEADINGS" | grep -c '^## ')"

if [ "$SKILL_N" -eq "$EXPECTED_COUNT" ]; then
  pass "skills/handover/SKILL.md has $EXPECTED_COUNT headings under the SYNC marker"
else
  fail "skills/handover/SKILL.md has $SKILL_N headings under the SYNC marker, expected $EXPECTED_COUNT -- both SYNC comments say 8, so adding or removing a section means editing three places, not one"
fi

if [ "$HOOK_N" -eq "$EXPECTED_COUNT" ]; then
  pass "pre-compact-handover.sh PROMPT_PREFIX has $EXPECTED_COUNT headings"
else
  fail "pre-compact-handover.sh PROMPT_PREFIX has $HOOK_N headings, expected $EXPECTED_COUNT"
fi

echo ""
echo "=== 4. The two lists are identical, in order ==="
if [ "$SKILL_HEADINGS" = "$HOOK_HEADINGS" ]; then
  pass "all $EXPECTED_COUNT headings match between the skill and the hook"
else
  fail "the heading lists have drifted -- an auto-saved handover and a /handover one would no longer be the same document, and nothing at runtime reports it"
  echo ""
  echo "  skills/handover/SKILL.md:"
  printf '%s\n' "$SKILL_HEADINGS" | sed 's/^/    /'
  echo ""
  echo "  hooks/scripts/pre-compact-handover.sh:"
  printf '%s\n' "$HOOK_HEADINGS" | sed 's/^/    /'
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
