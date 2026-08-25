#!/bin/bash
# run-all.sh
# Runs every test under tests/ and exits nonzero if any of them did.
#
# Discovery, not a list: a new tests/**/test-*.sh joins this runner with no edit here.
# A shared helper added later must NOT match that glob -- name it lib-*.sh.
#
# Each test runs as its own `bash` process, never sourced. The executable bit stops
# mattering, and tests/commands/test-work-plan-discovery.sh ends inside
# /tmp/quiver-plan-test -- a sourced run would hand that directory to the next test.
#
# A failing test does not stop the run. After a change touching several rules files,
# how many contracts drifted is the useful number, not just the first one.
#
# Finding zero tests is a failure, not a pass. A rename that makes the glob match
# nothing would otherwise leave CI green forever while testing nothing.
#
# Run directly: bash tests/run-all.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASSED=0
FAILED=0
FAILED_LIST=""

echo "Running tests under $REPO_ROOT/tests"

while IFS= read -r TEST; do
  REL="${TEST#"$REPO_ROOT"/}"
  echo ""
  echo "=== $REL ==="
  if bash "$TEST"; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    FAILED_LIST="$FAILED_LIST
  $REL"
  fi
done < <(find "$REPO_ROOT/tests" -name 'test-*.sh' | sort)

echo ""
echo "================================"

if [ $((PASSED + FAILED)) -eq 0 ]; then
  echo "No tests found under $REPO_ROOT/tests matching test-*.sh."
  exit 1
fi

if [ "$FAILED" -eq 0 ]; then
  echo "All $PASSED test files passed."
  exit 0
fi

echo "$PASSED passed, $FAILED FAILED:$FAILED_LIST"
exit 1
