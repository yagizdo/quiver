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
#   skills/ship/SKILL.md   -- names its state files under .claude/ship/ and the phase spec
#                             directory, and its `# State Files` section carries every
#                             roadmap, decision, and phase-file heading and field. The next
#                             /ship, often in a fresh session, resumes from those files only.
#   skills/local-files/SKILL.md -- lists .claude/ship/ as written by /ship, so the keep-local
#                             rule ship applies before its first write covers the directory.
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
SHIP="$REPO_ROOT/skills/ship/SKILL.md"
LOCAL="$REPO_ROOT/skills/local-files/SKILL.md"

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
  # The positive pin on 'follow its continuation step' lives in test-finding-verification-contract.sh.
  assert_not_in "$WORK" 'continues into its verification' "work 5d no longer names one /ship step as the continuation"
fi

echo ""
echo "=== 2. Ship names its state files and the keep-local rule ==="

if [ ! -f "$SHIP" ]; then
  fail "skills/ship/SKILL.md not found at $SHIP"
else
  for s in '.claude/ship/roadmap.md' '.claude/ship/decisions.md' '.claude/ship/phases/' '.claude/specs/' 'skills/local-files/SKILL.md'; do
    assert_in "$SHIP" "$s" "ship names $s"
  done
fi

# The schemas are read by the next /ship, often in a fresh session, so a heading renamed in
# one sentence and not in the template leaves a resume reading a section nothing writes.
# Scoped to the `# State Files` section, so a heading of ship's own cannot satisfy it.
# Fenced lines are skipped when looking for the section's end: a template may carry '# '.
echo ""
echo "=== 3. The State Files section carries every schema heading and field ==="

STATE="$(awk '
  /^```/ { fence = !fence }
  !fence && /^# State Files[[:space:]]*$/ { on = 1; next }
  on && !fence && /^# / { exit }
  on { print }
' "$SHIP" 2>/dev/null)"
if [ -z "$STATE" ]; then
  fail "skills/ship/SKILL.md has no '# State Files' section"
else
  pass "skills/ship/SKILL.md has a '# State Files' section"
  for h in '## Phases' '## Now' '## Next' '## Scope' '## Done Criteria' '## Questions and Answers' '## Decisions' '## Measurements' '## Log' '## Final Report'; do
    if printf '%s\n' "$STATE" | grep -qxF -- "$h"; then
      pass "State Files carries the heading line '$h'"
    else
      fail "State Files has no line reading exactly '$h'"
    fi
  done
  # The roadmap and the phase file each carry '## Goal', so one match cannot tell them apart.
  if [ "$(printf '%s\n' "$STATE" | grep -cxF '## Goal')" -eq 2 ]; then
    pass "State Files carries '## Goal' in both the roadmap and the phase file"
  else
    fail "State Files does not carry '## Goal' exactly twice (roadmap and phase file)"
  fi
  for f in phase name status stage depends_on spec plan fix_plan branch review_report fix_rounds; do
    if printf '%s\n' "$STATE" | grep -qE "^$f:"; then
      pass "phase file frontmatter carries '$f:'"
    else
      fail "phase file frontmatter has no line starting '$f:'"
    fi
  done
  if printf '%s\n' "$STATE" | grep -qF 'D<n>. <decision> -- <reason> (<user|agent>, <date>, phase <id>)'; then
    pass "decisions.md entry format is stated"
  else
    fail "decisions.md entry format 'D<n>. <decision> -- <reason> (<user|agent>, <date>, phase <id>)' is missing"
  fi
fi

echo ""
echo "=== 4. The local-files table names ship's directory ==="

if [ ! -f "$LOCAL" ]; then
  fail "skills/local-files/SKILL.md not found at $LOCAL"
elif grep -qE '^\| `\.claude/ship/` \| .*`/ship`' "$LOCAL"; then
  pass "skills/local-files/SKILL.md lists .claude/ship/ as written by /ship"
else
  fail "skills/local-files/SKILL.md has no '.claude/ship/' row naming /ship"
fi

# The split reads the context in use from the session transcript, found by the session id
# the skill body substitutes. The build hands off to /work and continues on its Phase 5d
# summary, the only end signal /work prints. A rename of any of these strings leaves the
# split deciding on nothing or the turn ending on /work's summary.
echo ""
echo "=== 5. The split measurement and the build handoff ==="

for s in '${CLAUDE_SESSION_ID}' 'cache_read_input_tokens' '/work <plan path> --auto' 'Phase 5d'; do
  assert_in "$SHIP" "$s" "ship names $s"
done
assert_in "$WORK" '#### 5d -- ' "work skill still has a 5d heading for ship's continuation key"

# The review is invoked by its qualified name (the bare /review is a bundled alias), with
# --run-checks so a branch review may run the tests that confirm a finding, and with
# --output so a saved report preference cannot move the report ship re-reads. The fix stage
# fixes only findings carrying the review's `Verification: confirmed` line, through a plan
# /work detects by `review_source`, and counts its one round in `fix_rounds`. --terminal
# would write no report at all, so ship must never pass it.
echo ""
echo "=== 6. The review call and the fix stage ==="

# --run-checks and the review's 'Verification: confirmed --' line are pinned on the full
# review line in test-finding-verification-contract.sh.
for s in 'quiver:review' '--output .claude/reports' 'Verification: confirmed' 'review_source' 'fix_rounds'; do
  assert_in "$SHIP" "$s" "ship names $s"
done
assert_not_in "$SHIP" '--terminal' "ship never passes --terminal to the review"
assert_not_in "$SHIP" '.claude/reports/ship-' "ship writes no separate ship report; the phase file holds it"
assert_in "$WORK" '`review_source`' "work 1c still detects a review-fix plan by review_source"

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
