#!/bin/bash
# test-design-launch-contract.sh
# Guards the design launch contract, which lives in two files by construction:
#   producer  skills/design-verify/SKILL.md -- "The app must be running and fresh": the mode
#             gate, the 3-attempt cap, and the capture-free degrade path
#   consumer  skills/design-build/SKILL.md  -- Phase 2b owns one run session and satisfies
#             that contract, citing it by heading
#
# The consumer cites the producer's heading verbatim. A rename on either side changes which
# app a fidelity measurement measures without changing anything a reader would notice, so
# the citation is asserted against the live heading rather than against a copy pinned here.
#
# Run directly: bash tests/skills/test-design-launch-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

BUILD="$REPO_ROOT/skills/design-build/SKILL.md"
VERIFY="$REPO_ROOT/skills/design-verify/SKILL.md"

CONTRACT_HEADING="The app must be running and fresh"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <pattern> <label>
# The -- guards patterns that start with a dash.
assert_in() {
  if grep -q -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

echo "=== 1. /design-verify declares the launch contract ==="

assert_in "$VERIFY" "^### $CONTRACT_HEADING\$" "the contract section exists under its cited heading"
assert_in "$VERIFY" 'capped at \*\*3 attempts\*\*' "the build-and-launch cap reads 3 attempts"
assert_in "$VERIFY" 'After the third failed attempt, continue without a capture' "the third failure degrades instead of stopping"
assert_in "$VERIFY" 'capture_method: none -- launch failed after 3 attempts' "the degrade path is recorded in the report"
assert_in "$VERIFY" 'an already-running instance is accepted' "standalone accepts a running app"
assert_in "$VERIFY" 'never trusted as fresh' "build never trusts a running app"

echo ""
echo "=== 2. The optional MCP capture row keeps a CLI fallback ==="

assert_in "$VERIFY" 'xcbuild or marionette MCP (optional)' "the MCP capture row is marked optional"
assert_in "$VERIFY" 'otherwise fall back to the CLI row' "the MCP row names its CLI fallback"

echo ""
echo "=== 3. /design-build owns the run session ==="

assert_in "$BUILD" '^## Phase 2b -- Open the Run Session$' "Phase 2b exists"
assert_in "$BUILD" '\*\*Start\.\*\*' "the session start step is written"
assert_in "$BUILD" '\*\*Hot reload after 3a, before 3b\.\*\*' "the hot reload step is written and placed"
assert_in "$BUILD" '\*\*Teardown on every exit path\.\*\*' "the teardown step covers every exit path"
assert_in "$BUILD" 'cancels any `AskUserQuestion`' "a cancelled question is an exit path for teardown"
assert_in "$BUILD" '\*\*No session owned\.\*\*' "the no-session fallback is defined"

echo ""
echo "=== 4. Launch failures draw from the existing 3c budget ==="

assert_in "$BUILD" 'spends an attempt from this same budget' "3c states that a launch failure costs an attempt"
assert_in "$BUILD" 'one counter per task' "3c states there is one counter, not one per failure kind"
assert_in "$BUILD" 'never gets a budget of its own' "Phase 2b refuses a second budget"

echo ""
echo "=== 5. The consumer cites the producer, and the citation resolves ==="

# The point of the whole file: a rename in either skill fails here.
if grep -q -- "\"$CONTRACT_HEADING\"" "$BUILD"; then
  pass "/design-build cites the contract by heading"
  if grep -q -- "^### $CONTRACT_HEADING\$" "$VERIFY"; then
    pass "the cited heading resolves to a section in /design-verify"
  else
    fail "the cited heading resolves to no section in /design-verify"
  fi
else
  fail "/design-build cites the contract by heading"
fi

echo ""
echo "================================"
if [ "$EXIT" = "0" ]; then
  echo "All design launch contract tests passed."
else
  echo "Some tests FAILED."
fi
exit "$EXIT"
