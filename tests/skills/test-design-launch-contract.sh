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
echo "=== 1b. An unnamed stack still resolves ==="

# The tables name four stacks. A fifth -- Kotlin/JVM, Go, a Makefile build -- must take a
# fallback row instead of hitting undefined behavior.
assert_in "$VERIFY" '| Any other stack |' "the build-and-launch table has a fallback row"
assert_in "$VERIFY" 'costs zero attempts' "an impossible launch spends no attempt"
assert_in "$BUILD" '| Any other target |' "the refresh table has a fallback row"
assert_in "$BUILD" 'is not an error' "an unnamed stack is stated to be no error"

echo ""
echo "=== 2. Every capture path is a CLI command, and the device rows are gated on one ==="

# No MCP server captures a physical iOS device -- the xcodebuild-wrapping ones stop at
# build, install, launch, and test. A capture row that needs an MCP is therefore a row
# that silently drops to a spec read on the one target the device order exists to reach.
assert_in "$VERIFY" 'No MCP server is required for any native target' "native capture rows need no MCP server"
assert_in "$VERIFY" 'marionette --uri' "the Flutter device capture row names its CLI"
assert_in "$VERIFY" 'pymobiledevice3 developer' "the physical iOS capture row names its CLI"

# The probe has to run before the target order is applied. Ranking a device first and
# discovering afterwards that nothing can photograph it trades a measured comparison for
# a spec read on exactly the target that was chosen for being most accurate.
assert_in "$VERIFY" '^### Probe the capture tooling once, before resolving the target$' "the tooling probe has its own step"
assert_in "$VERIFY" 'A device row is only reachable when a capture path for it resolved' "device rows are gated on a resolved capture path"

# Launch and capture are two halves of one resolution. Split, the run photographs a
# binary it never built.
assert_in "$VERIFY" 'The launch row and the capture row resolve to the same target' "launch and capture share one target"
assert_in "$VERIFY" '| iOS physical device |' "the launch table has a physical device row"
assert_in "$VERIFY" 'falls back to the simulator once' "a signing failure falls back once"

echo ""
echo "=== 3. /design-build owns the run session ==="

assert_in "$BUILD" '^## Phase 2b -- Open the Run Session$' "Phase 2b exists"
assert_in "$BUILD" '\*\*Start\.\*\*' "the session start step is written"
assert_in "$BUILD" '\*\*Hot reload after 3a, before 3b\.\*\*' "the hot reload step is written and placed"
assert_in "$BUILD" '\*\*Teardown on every exit path\.\*\*' "the teardown step covers every exit path"
assert_in "$BUILD" 'cancels any `AskUserQuestion`' "a cancelled question is an exit path for teardown"
assert_in "$BUILD" '\*\*No session owned\.\*\*' "the no-session fallback is defined"

echo ""
echo "=== 4. Launch failures draw on the session's own budget, not a task's ==="

# The two budgets must stay named apart in both places that describe them. Charging a
# launch to 3c drains task 1's counter before its implementation attempt exists, so the
# task's own mandatory first step lands over budget.
assert_in "$BUILD" 'spends a session attempt, not one of these' "3c keeps launch failures off the task counter"
assert_in "$BUILD" 'one counter per task' "3c states there is one counter for every other failure kind"
assert_in "$BUILD" '\*\*A failed launch costs a session attempt\.\*\*' "Phase 2b names the session budget"
assert_in "$BUILD" 'separate from 3c' "Phase 2b states the two budgets are separate"

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
