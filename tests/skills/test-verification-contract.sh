#!/bin/bash
# test-verification-contract.sh
# Guards the verification contract, which lives in six files by construction:
#   producer   skills/verification/SKILL.md      -- the Command Resolution table, the
#              Evidence Rule, and the one paragraph consumers copy out of it: the
#              ### Subagent restatement
#   consumers  skills/work/SKILL.md              -- Phase 2.5 resolves the command once
#              skills/work/orchestrator.md       -- briefs carry it, the fenced prompt
#                                                   carries the restatement, TESTS quotes it
#              skills/ship/SKILL.md              -- test_command / build_command fields,
#                                                   the Step 3 prompt carries the restatement
#              skills/design-build/SKILL.md      -- the 3d gate command
#              skills/hypothesis-debugging/SKILL.md -- Step 7 runs the resolved test
#
# Each consumer names the producer at its verification step and reads it there. The
# contract fails silently in two directions. A consumer that stops naming the producer
# re-grows its own stack table, and that copy drifts from the producer's with nothing
# raising an error -- the consumer keeps resolving a command the producer stopped
# recommending. A restatement copy that drifts drops the evidence clause from the subagent
# prompt it is pasted into, so a subagent is no longer told that a zero-test run, an
# unreturned command, or a remembered result is not a pass. Neither case changes anything
# a reader would notice, so every assertion reads the live skill files. No fixture is
# written and grepped with a rule hardcoded here.
#
# Run directly: bash tests/skills/test-verification-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

REF="$REPO_ROOT/skills/verification/SKILL.md"
WORK="$REPO_ROOT/skills/work/SKILL.md"
ORCH="$REPO_ROOT/skills/work/orchestrator.md"
SHIP="$REPO_ROOT/skills/ship/SKILL.md"
DESIGN_BUILD="$REPO_ROOT/skills/design-build/SKILL.md"
HYPOTHESIS="$REPO_ROOT/skills/hypothesis-debugging/SKILL.md"
README_RULES="$REPO_ROOT/.claude/rules/readme-structure.md"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <pattern> <label>
# The -- guards patterns that start with a dash. Bracket-expression metacharacters in a
# ledger placeholder are escaped at the call site, not stripped here.
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
for f in "$REF" "$WORK" "$ORCH" "$SHIP" "$DESIGN_BUILD" "$HYPOTHESIS" "$README_RULES"; do
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
# What the consumers and the R10 routing hook read from the producer. A reference skill
# that becomes invocable or grows a shell block stops being the inert pointer target the
# consumers assume (Global Constraint 3). The when-to-use side of that constraint and the
# R10 exemption are enforced by tests/skills/test-when-to-use-contract.sh.
echo ""
echo "=== 2. The reference skill has the shape its consumers read ==="

NAME="$(fm "$REF" name)"
if [ "$NAME" = "verification" ]; then
  pass "frontmatter name: is verification"
else
  fail "frontmatter name: is '$NAME', expected verification -- the consumers name skills/verification/SKILL.md and R10 exempts the skill by that name"
fi

INVOCABLE="$(fm "$REF" user-invocable)"
if [ "$INVOCABLE" = "false" ]; then
  pass "frontmatter user-invocable: is false"
else
  fail "frontmatter user-invocable: is '$INVOCABLE', expected false -- a reference skill is read by other skills, never invoked"
fi

# grep -c prints 0 and exits 1 on no match, so the count is captured, not the status.
INLINE="$(grep -cF -- '!`' "$REF")"
if [ "$INLINE" = "0" ]; then
  pass "no inline shell block opener anywhere in the producer"
else
  fail "$INLINE line(s) carry an inline shell block opener in the producer -- a reference skill runs nothing (Global Constraint 3)"
fi

# Each heading is a full line, counted exactly. A second copy of a heading makes the
# restatement extractor in section 4 read the wrong paragraph; a missing one makes it
# read nothing.
for h in '## Command Resolution' '## Evidence Rule' '## For Skill Authors' '### Subagent restatement' '## Test Plan'; do
  N="$(grep -cxF -- "$h" "$REF")"
  if [ "$N" = "1" ]; then
    pass "heading '$h' appears exactly once"
  else
    fail "heading '$h' appears $N time(s), expected exactly once"
  fi
done

# Six bold-led table rows: Node, Python, Go, Rust, Ruby, Flutter/Dart. A seventh is a
# stack Global Constraint 6 excludes; five is a stack a consumer has to guess at.
ROWS="$(grep -c '^| \*\*' "$REF")"
if [ "$ROWS" = "6" ]; then
  pass "the resolution table has exactly six stack rows"
else
  fail "the resolution table has $ROWS stack rows, expected exactly 6 (Global Constraint 6)"
fi

# The table is here. Section 6 asserts the mirror image: it is in no consumer.
assert_in "$REF" 'flutter test' "the stack table lives in the producer"

# --- 3. Pointers ---
# Consumption is a repo-relative path in prose, the same way /work names its orchestrator.
# A consumer that drops the path has nothing left to read at its verification step and
# re-grows its own table on the next edit.
echo ""
echo "=== 3. Every consumer names the producer ==="

for f in "$WORK" "$ORCH" "$SHIP" "$DESIGN_BUILD" "$HYPOTHESIS"; do
  assert_in "$f" 'skills/verification/SKILL\.md' "${f#$REPO_ROOT/} names skills/verification/SKILL.md"
done

# --- 4. The restatement copies ---
# The one paragraph copied out of the producer (Global Constraint 1). It sits two lines
# below its heading -- heading, blank, paragraph -- and is a single line by construction so
# a byte-for-byte comparison is one fixed-string grep. Each copy is reported on its own
# line so a drift names the file that drifted.
echo ""
echo "=== 4. The subagent restatement is copied byte-for-byte ==="

LINE="$(sed -n '/^### Subagent restatement/{n;n;p;}' "$REF")"
CANON_OK=0
if [ -z "$LINE" ]; then
  fail "no restatement paragraph two lines below '### Subagent restatement' in the producer -- the copies have nothing to be compared to"
else
  case "$LINE" in
    "Run the test command you were given"*)
      pass "canonical restatement extracted from the producer"
      CANON_OK=1
      ;;
    *)
      fail "the line two below '### Subagent restatement' does not start with 'Run the test command you were given' -- got: $LINE"
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
    fail "restatement in $L differs from the producer's -- the subagent prompt it is pasted into no longer carries the evidence clause verbatim"
  fi
done

# --- 5. The orchestrator grammar ---
# The brief label the subagent reads the command from, and the two TESTS line forms it
# returns. Task 4's Phase 2.5 text names the label; the ledger reads the TESTS line.
echo ""
echo "=== 5. The orchestrator declares the brief label and the TESTS grammar ==="

assert_in "$ORCH" 'TESTS | <command> -> exit <code>: <summary line>' "TESTS evidence line form declared"
assert_in "$ORCH" 'TESTS | skipped: <reason>' "TESTS skipped line form declared"
assert_in "$ORCH" 'Test command:' "brief label 'Test command:' declared"

# --- 6. The ship fields and the dead tables ---
# /ship resolves once at manifest-write time into two named fields, and the two stack
# tables it used to carry are gone. The flutter test loop is the gate behind the
# producer's own checklist item: it catches any consumer pasting the table back in, not
# only /ship.
echo ""
echo "=== 6. /ship carries the fields and no consumer carries the table ==="

assert_in "$SHIP" 'test_command' "ship metadata names test_command"
assert_in "$SHIP" 'build_command' "ship metadata names build_command"
assert_not_in "$SHIP" 'Detect test command from stack' "no restated test-command table in ship"
assert_not_in "$SHIP" 'Detect build command from stack' "no restated build-command table in ship"

for f in "$WORK" "$ORCH" "$SHIP" "$DESIGN_BUILD" "$HYPOTHESIS"; do
  assert_not_in "$f" 'flutter test' "no stack table in ${f#$REPO_ROOT/}"
done

# --- 7. Registration ---
# The reference skill is excluded from the README by name.
# The rules file used to say user-invocable: false was set on one skill only; that
# sentence is false once this skill exists, and its return is the regression caught here.
echo ""
echo "=== 7. The reference skill is registered in the README rules file ==="

assert_in "$README_RULES" 'verification' "readme-structure.md names verification in the exclusion list"
assert_not_in "$README_RULES" 'set only on' "readme-structure.md no longer claims user-invocable: false is set on one skill only"

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
