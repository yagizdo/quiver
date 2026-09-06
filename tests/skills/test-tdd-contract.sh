#!/bin/bash
# test-tdd-contract.sh
# Guards the TDD contract, which lives in ten files by construction:
#   producer   skills/tdd/SKILL.md               -- Applicability, The Cycle, the red: and
#              skipped: evidence forms, and the one line consumers copy out of it: the
#              ### Subagent restatement
#   consumers  skills/plan/SKILL.md              -- Step 5 orders each task's steps test-first
#              skills/work/SKILL.md              -- Phase 3 runs the cycle, 5d tallies it
#              skills/work/orchestrator.md       -- the brief step names the file, the fenced
#                                                   prompt carries the restatement, the return
#                                                   contract carries the TDD line
#              skills/ship/SKILL.md              -- the Step 3 prompt carries the restatement,
#                                                   Step 6 keeps the red run out of the attempts
#              skills/hypothesis-debugging/SKILL.md -- Step 7 writes the test before the fix
#   registration skills/using-quiver/SKILL.md, .claude/rules/skill-rules.md,
#              .claude/rules/readme-structure.md, tests/skills/test-when-to-use-contract.sh
#
# Three drifts are silent. A restatement copy that drifts stops telling the subagent that a
# test it never saw fail, or a red line naming a test it did not write, is not red evidence --
# the prompt still reads as an ordinary test-first instruction, so nothing looks wrong. A
# consumer that stops naming the producer has nothing left to read at its build step and
# re-grows its own cycle text on the next edit, and that copy then drifts from the producer's
# with nothing raising an error. A re-grown five-step list in /plan puts the exact test code
# back inside the plan, which no reader notices because the plan still talks about tests.
# None of the three changes anything a reader would see, so every assertion reads the live
# files. No fixture is written and grepped with a rule hardcoded here.
#
# Run directly: bash tests/skills/test-tdd-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

REF="$REPO_ROOT/skills/tdd/SKILL.md"
PLAN="$REPO_ROOT/skills/plan/SKILL.md"
WORK="$REPO_ROOT/skills/work/SKILL.md"
ORCH="$REPO_ROOT/skills/work/orchestrator.md"
SHIP="$REPO_ROOT/skills/ship/SKILL.md"
HYPOTHESIS="$REPO_ROOT/skills/hypothesis-debugging/SKILL.md"
USING="$REPO_ROOT/skills/using-quiver/SKILL.md"
RULES="$REPO_ROOT/.claude/rules/skill-rules.md"
README_RULES="$REPO_ROOT/.claude/rules/readme-structure.md"
WTU="$REPO_ROOT/tests/skills/test-when-to-use-contract.sh"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <pattern> <label>
# The -- guards patterns that start with a dash. Bracket-expression metacharacters in a
# return-contract placeholder are escaped at the call site, not stripped here.
assert_in() {
  if grep -q -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

# assert_not_in <file> <pattern> <label>
assert_not_in() {
  if grep -q -- "$2" "$1"; then
    fail "$3"
  else
    pass "$3"
  fi
}

# Extract a frontmatter field, bounded to the block between the first two --- delimiters.
fm() {
  awk -v key="$2" '
    BEGIN { c = 0 }
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      print
      exit
    }' "$1"
}

# --- 1. Preflight ---
echo ""
echo "=== 1. Preflight ==="
MISSING=0
for f in "$REF" "$PLAN" "$WORK" "$ORCH" "$SHIP" "$HYPOTHESIS" "$USING" "$RULES" "$README_RULES" "$WTU"; do
  if [ -f "$f" ]; then
    pass "${f#$REPO_ROOT/} exists"
  else
    fail "missing ${f#$REPO_ROOT/}"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit 1
fi

# --- 2. The reference skill's shape ---
# What the consumers and the R10 routing hook read from the producer. A reference skill that
# becomes invocable, grows a when-to-use field, or grows a shell block stops being the inert
# pointer target the consumers assume (Global Constraint 3), and a when-to-use on it wires a
# skill nobody invokes into silent auto-dispatch.
echo ""
echo "=== 2. The reference skill has the shape its consumers read ==="

NAME="$(fm "$REF" name)"
if [ "$NAME" = "tdd" ]; then
  pass "frontmatter name: is tdd"
else
  fail "frontmatter name: is '$NAME', expected tdd -- the consumers name skills/tdd/SKILL.md and R10 exempts the skill by that name"
fi

INVOCABLE="$(fm "$REF" user-invocable)"
if [ "$INVOCABLE" = "false" ]; then
  pass "frontmatter user-invocable: is false"
else
  fail "frontmatter user-invocable: is '$INVOCABLE', expected false -- a reference skill is read by other skills, never invoked"
fi

WHEN="$(fm "$REF" when-to-use)"
if [ -z "$WHEN" ]; then
  pass "frontmatter carries no when-to-use field"
else
  fail "frontmatter carries a when-to-use field ('$WHEN') -- R10 exempts this skill and the SessionStart hook would route to it (Global Constraint 3)"
fi

# grep -c prints 0 and exits 1 on no match, so the count is captured, not the status.
INLINE="$(grep -cF -- '!`' "$REF")"
if [ "$INLINE" = "0" ]; then
  pass "no inline shell block opener anywhere in the producer"
else
  fail "$INLINE line(s) carry an inline shell block opener in the producer -- a reference skill runs nothing (Global Constraint 3)"
fi

# Each heading is a full line, counted exactly. A second copy of ### Subagent restatement makes
# the extractor in section 4 read the wrong paragraph; a missing one makes it read nothing.
for h in '## Applicability' '## The Cycle' '## Evidence' '## For Skill Authors' '### Subagent restatement' '## Test Plan'; do
  N="$(grep -cxF -- "$h" "$REF")"
  if [ "$N" = "1" ]; then
    pass "heading '$h' appears exactly once"
  else
    fail "heading '$h' appears $N time(s), expected exactly once"
  fi
done

# The two evidence line forms and the third skipped reason live here. Section 5 asserts the
# consumers' return contracts quote the same shapes.
assert_in "$REF" '<command> -> exit <code>: <failing test> -- <first error line>' "the red: evidence line form lives in the producer"
assert_in "$REF" 'skipped: <reason>' "the skipped: evidence line form lives in the producer"
assert_in "$REF" 'no red evidence' "the producer names the 'no red evidence' skipped reason"

# --- 3. Pointers ---
# Consumption is a repo-relative path in prose, the same way /work names its orchestrator.
# A consumer that drops the path has nothing left to read at its build step and re-grows its
# own copy of the cycle on the next edit.
echo ""
echo "=== 3. Every consumer names the producer ==="

for f in "$PLAN" "$WORK" "$ORCH" "$SHIP" "$HYPOTHESIS" "$USING"; do
  assert_in "$f" 'skills/tdd/SKILL\.md' "${f#$REPO_ROOT/} names skills/tdd/SKILL.md"
done

# --- 4. The restatement copies ---
# The one line copied out of the producer (Global Constraint 1). It sits two lines below its
# heading -- heading, blank, paragraph -- and is a single line by construction, so a
# byte-for-byte comparison is one fixed-string grep. Each copy is reported on its own line so
# a drift names the file that drifted.
echo ""
echo "=== 4. The subagent restatement is copied byte-for-byte ==="

LINE="$(sed -n '/^### Subagent restatement/{n;n;p;}' "$REF")"
CANON_OK=0
if [ -z "$LINE" ]; then
  fail "no restatement paragraph two lines below '### Subagent restatement' in the producer -- the copies have nothing to be compared to"
else
  case "$LINE" in
    "Write the test for the behavior before the implementation"*)
      pass "canonical restatement extracted from the producer"
      CANON_OK=1
      ;;
    *)
      fail "the line two below '### Subagent restatement' does not start with 'Write the test for the behavior before the implementation' -- got: $LINE"
      ;;
  esac
fi

for f in "$ORCH" "$SHIP"; do
  L="${f#$REPO_ROOT/}"
  if [ "$CANON_OK" -ne 1 ]; then
    fail "restatement in $L cannot be compared -- the canonical line was not extracted"
  elif grep -F -q -- "$LINE" "$f"; then
    pass "restatement in $L is byte-identical to the producer's"
  else
    fail "restatement in $L differs from the producer's -- the subagent prompt it is pasted into no longer tells the subagent that a test it never saw fail is not red evidence"
  fi
done

# --- 5. The return contracts and the tally ---
# Both dispatching skills return the red step on a TDD line, and both carry the skipped form
# beside it. A contract carrying only the red form makes a subagent with nothing to report
# invent one. The orchestrator names the default for a missing line; /ship states the red run
# is outside its attempt cap (Global Constraint 2); /work's 5d summary tallies the outcomes.
echo ""
echo "=== 5. Both return contracts carry the TDD line ==="

for f in "$ORCH" "$SHIP"; do
  L="${f#$REPO_ROOT/}"
  assert_in "$f" 'TDD | red: <command> -> exit <code>: <failing test> -- <first error line>' "$L declares the TDD red line form"
  assert_in "$f" 'TDD | skipped: <reason>' "$L declares the TDD skipped line form"
done

assert_in "$ORCH" 'no red evidence' "orchestrator reads a missing TDD line as 'no red evidence'"
assert_in "$SHIP" 'not one of the three attempts' "ship keeps the red run out of its three-attempt cap"
assert_in "$WORK" 'TDD: <n> red-verified' "work 5d summary carries the test-first tally"

# --- 6. Re-growth tripwires ---
# The two texts the wiring replaced. /plan used to spell the cycle out as a five-step list
# whose first step demanded the exact test code in the plan; using-quiver used to name TDD as
# a rigid workflow with no file behind it. Either one returning is a copy of the producer that
# drifts from it silently (Global Constraint 1).
echo ""
echo "=== 6. Neither replaced text has grown back ==="

assert_not_in "$PLAN" 'Write the failing test (show exact test code)' "no re-grown five-step TDD list in /plan"
assert_not_in "$USING" '(TDD, hypothesis-debugging)' "using-quiver names the skill file, not a bare TDD label"

# --- 7. Registration ---
# The skill is exempt from R10 by name in the rule text, exempt in the routing test's own
# exemption list, and excluded from the README by name. A skill missing from any one of the
# three is either routed silently or documented as user-facing.
echo ""
echo "=== 7. The reference skill is registered as exempt ==="

if grep -q 'tdd' <<<"$(grep '^\*\*R10\.' "$RULES")"; then
  pass "R10 in skill-rules.md names tdd among the internal reference skills"
else
  fail "R10 in skill-rules.md does not name tdd -- the exemption the skill relies on is undocumented"
fi

assert_in "$README_RULES" 'verification, tdd, using-quiver' "readme-structure.md names tdd in the exclusion list"

# The surrounding spaces make tdd a whole word, so a future exemption list entry that merely
# contains the three letters does not satisfy this.
if grep -q '^EXEMPT=.* tdd ' "$WTU"; then
  pass "test-when-to-use-contract.sh exempts tdd"
else
  fail "test-when-to-use-contract.sh does not exempt tdd -- the routing test would demand a when-to-use field on a skill that must not carry one"
fi

# Global Constraint 7. grep's exit code is branched on explicitly: 0 is a match and a failure,
# 1 is the clean case, and anything else is grep itself failing. Treating any nonzero as a pass
# would go green on a Unicode producer the moment the option is unsupported. -P is deliberately
# not used: /usr/bin/grep on macOS has no -P and exits 2 with a usage error.
LC_ALL=C grep -q '[^[:print:][:space:]]' "$REF"
ASCII_STATUS=$?
if [ "$ASCII_STATUS" -eq 0 ]; then
  fail "non-ASCII byte in the producer"
elif [ "$ASCII_STATUS" -eq 1 ]; then
  pass "the producer is ASCII only"
else
  fail "grep error while checking the producer for non-ASCII bytes (exit $ASCII_STATUS)"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
