#!/bin/bash
# test-work-ledger-contract.sh
# Guards the /work orchestration ledger contract, which lives in two files by construction:
#   producer  skills/work/orchestrator.md -- Section 0 declares the workspace layout, the
#             identity line, the six ledger line forms, and the subagent return contract
#   consumer  skills/work/SKILL.md        -- Phase 2.5 restates the workspace path, the
#             identity line, and the complete-line spelling to decide what to skip on resume
#
# The consumer restates the producer's strings verbatim. A rename on either side changes
# which tasks a resumed run re-dispatches without changing anything a reader would notice,
# so every assertion reads the live skill files. No fixture is written and grepped with a
# rule hardcoded here.
#
# Run directly: bash tests/skills/test-work-ledger-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

PRODUCER="$REPO_ROOT/skills/work/orchestrator.md"
CONSUMER="$REPO_ROOT/skills/work/SKILL.md"
GITIGNORE="$REPO_ROOT/.gitignore"

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

echo "=== 1. Preflight ==="

for f in "$PRODUCER" "$CONSUMER"; do
  if [ -f "$f" ]; then
    pass "${f#$REPO_ROOT/} exists"
  else
    fail "${f#$REPO_ROOT/} is missing"
  fi
done

if [ "$EXIT" != "0" ]; then
  echo ""
  echo "Preflight failed -- skipping the rest."
  exit "$EXIT"
fi

echo ""
echo "=== 2. The producer declares all six ledger line forms ==="

# Each pattern is long enough that renaming a placeholder fails the assertion. The
# leading [ of a task-title placeholder is escaped so BRE reads it as a literal
# bracket rather than opening a bracket expression.
assert_in "$PRODUCER" 'Group <G>: dispatched (' "dispatched line form declared"
assert_in "$PRODUCER" '\[<task title>]: complete (branch ' "complete line form declared"
assert_in "$PRODUCER" '\[<task title>]: blocked -- ' "blocked line form declared"
assert_in "$PRODUCER" '\[<task title>]: failed -- ' "failed line form declared"
assert_in "$PRODUCER" 'Group <G>: merged (' "merged line form declared"
assert_in "$PRODUCER" 'Group <G>: merge stopped -- conflict in ' "merge-stopped line form declared"

echo ""
echo "=== 3. Restated handshake strings appear in both files ==="

# These four cross the producer/consumer boundary. The other five line forms exist only
# in the producer, which is why section 2 asserts them there and this section does not.
for f in "$PRODUCER" "$CONSUMER"; do
  L="${f#$REPO_ROOT/}"
  assert_in "$f" '\.claude/work/<plan-basename>/' "workspace path in $L"
  assert_in "$f" 'progress\.md' "ledger filename in $L"
  assert_in "$f" '# work ledger -- plan:' "identity line in $L"
  assert_in "$f" '\[<task title>]: complete (branch ' "full complete-line spelling in $L"
done

echo ""
echo "=== 4. The return contract is declared once, in the producer ==="

for field in 'STATUS |' 'BRANCH |' 'BASE |' 'COMMITS |' 'TESTS |' 'REASON |' 'REPORT |'; do
  assert_in "$PRODUCER" "$field" "return contract declares $field"
done
assert_in "$PRODUCER" 'Anything beyond these lines is ignored' "the return cap is stated"

# The pasted-context field and the dangling back-reference this change removed. Their
# return is the regression these two assertions catch.
assert_not_in "$PRODUCER" 'plan_preamble' "no plan_preamble field in the dispatch prompt"
assert_not_in "$PRODUCER" 'files listed above' "no dangling 'files listed above' back-reference"

echo ""
echo "=== 5. No dangling skill reference in the consumer ==="

# Computed from the file, not hardcoded -- a hardcoded name stops guarding the next one.
FOUND=0
for name in $(grep -oE '`[A-Za-z0-9._-]+` skill' "$CONSUMER" | sed -e 's/^`//' -e 's/` skill$//' | sort -u); do
  FOUND=$((FOUND + 1))
  if [ -d "$REPO_ROOT/skills/$name" ]; then
    pass "referenced skill '$name' resolves to skills/$name/"
  else
    fail "referenced skill '$name' has no directory at skills/$name/"
  fi
done
if [ "$FOUND" = "0" ]; then
  pass "no backtick-quoted skill references to resolve"
fi

echo ""
echo "=== 6. Rules with no other automated check ==="

# R8 -- the consumer is ASCII-only. The bracket expression carries a literal tab; \t
# inside a bracket expression matches a backslash and a t, not a tab.
if LC_ALL=C grep -q '[^ -~	]' "$CONSUMER"; then
  fail "R8: non-ASCII characters in ${CONSUMER#$REPO_ROOT/}"
else
  pass "R8: ASCII-only in ${CONSUMER#$REPO_ROOT/}"
fi

# orchestrator.md is deliberately exempt: it already carries non-ASCII bytes, which R8
# permits for a file that had them before the rule was applied.

assert_in "$GITIGNORE" '^\.claude/work/$' "the workspace is gitignored"

echo ""
echo "================================"
if [ "$EXIT" = "0" ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit "$EXIT"
