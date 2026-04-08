#!/bin/bash
# test-work-plan-discovery.sh
# Validates plan discovery: directory finding, filename matching, and edge cases.
# Covers test cases 1-11 from the spec.

set -e

TEST_DIR="/tmp/quiver-plan-test"
EXIT=0

# --- Helpers ---

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

assert_found() {
  if echo "$1" | grep -qi "$2"; then
    pass "$3"
  else
    fail "$3"
  fi
}

assert_not_found() {
  if echo "$1" | grep -qi "$2"; then
    fail "$3"
  else
    pass "$3"
  fi
}

# --- Setup ---

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/plans"
mkdir -p "$TEST_DIR/.claude/plans"
mkdir -p "$TEST_DIR/superpowers/plans"
mkdir -p "$TEST_DIR/nested/deep/plans"
mkdir -p "$TEST_DIR/a/b/c/d/e/plans"  # depth 5 -- should be excluded

cat > "$TEST_DIR/plans/test-feature.md" << 'PLAN'
---
goal: Test feature plan
steps: 3
---
## Steps
- [ ] Step 1
- [ ] Step 2
- [ ] Step 3
PLAN

cat > "$TEST_DIR/superpowers/plans/test-feature-v2.md" << 'PLAN'
---
goal: Test feature v2
steps: 2
---
## Steps
- [ ] Step 1
- [ ] Step 2
PLAN

cat > "$TEST_DIR/.claude/plans/review-fix-plan.md" << 'PLAN'
---
goal: Fix review findings
steps: 4
---
## Steps
- [ ] Step 1
- [ ] Step 2
- [ ] Step 3
- [ ] Step 4
PLAN

cat > "$TEST_DIR/nested/deep/plans/deep-plan.md" << 'PLAN'
---
goal: Deep nested plan
steps: 1
---
## Steps
- [ ] Step 1
PLAN

cat > "$TEST_DIR/plans/another-thing.md" << 'PLAN'
---
goal: Another thing
steps: 2
---
## Steps
- [ ] Step 1
- [ ] Step 2
PLAN

cat > "$TEST_DIR/a/b/c/d/e/plans/too-deep.md" << 'PLAN'
---
goal: Too deep to find
steps: 1
---
## Steps
- [ ] Step 1
PLAN

cd "$TEST_DIR"

# --- Directory Discovery Tests ---

echo "=== Directory Discovery ==="
DIRS=$(find . -maxdepth 4 -type d -name "plans" 2>/dev/null)

assert_found "$DIRS" "./plans" "Root plans/ discovered"
assert_found "$DIRS" "./superpowers/plans" "superpowers/plans/ discovered"
assert_found "$DIRS" "./nested/deep/plans" "nested/deep/plans/ discovered"
assert_found "$DIRS" "./.claude/plans" ".claude/plans/ discovered via find"
assert_not_found "$DIRS" "./a/b/c/d/e/plans" "Depth 5 excluded (maxdepth 4)"

# --- .claude/plans/ ls block ---

echo ""
echo "=== .claude/plans/ ls block ==="
LS_OUT=$(ls -1 .claude/plans/ 2>/dev/null || echo "NOT_FOUND")
assert_found "$LS_OUT" "review-fix-plan.md" ".claude/plans/ contents listed via ls"

# --- Collect all plan files (simulates prompt logic aggregation) ---

ALL_PLANS=""
for dir in $DIRS; do
  FILES=$(ls -1 "$dir"/*.md 2>/dev/null || true)
  ALL_PLANS="$ALL_PLANS
$FILES"
done

echo ""
echo "=== Test 1: Exact match in root plans/ ==="
assert_found "$ALL_PLANS" "plans/test-feature.md" "Exact match: plans/test-feature.md"

echo ""
echo "=== Test 2: Exact match in .claude/plans/ ==="
assert_found "$ALL_PLANS" ".claude/plans/review-fix-plan.md" "Exact match: .claude/plans/review-fix-plan.md"

echo ""
echo "=== Test 3: Partial match ==="
PARTIAL=$(echo "$ALL_PLANS" | grep -i "feature" || true)
assert_found "$PARTIAL" "test-feature.md" "Partial match finds test-feature.md"
assert_found "$PARTIAL" "test-feature-v2.md" "Partial match finds test-feature-v2.md"

echo ""
echo "=== Test 4: Case-insensitive match ==="
CASE_MATCH=$(echo "$ALL_PLANS" | grep -i "Test-Feature" || true)
assert_found "$CASE_MATCH" "test-feature" "Case-insensitive match works"

echo ""
echo "=== Test 5: Nested directory discovery ==="
assert_found "$ALL_PLANS" "nested/deep/plans/deep-plan.md" "Nested dir: deep-plan.md found"

echo ""
echo "=== Test 6: Superpowers directory ==="
assert_found "$ALL_PLANS" "superpowers/plans/test-feature-v2.md" "superpowers/plans/ file found"

echo ""
echo "=== Test 7: Multiple matches across dirs ==="
MULTI=$(echo "$ALL_PLANS" | grep -i "test" || true)
COUNT=$(echo "$MULTI" | grep -c "." || true)
if [ "$COUNT" -ge 2 ]; then
  pass "Multiple matches found ($COUNT files match 'test')"
else
  fail "Expected 2+ matches for 'test', got $COUNT"
fi

echo ""
echo "=== Test 8: No match ==="
NO_MATCH=$(echo "$ALL_PLANS" | grep -i "nonexistent-xyz" || true)
if [ -z "$NO_MATCH" ]; then
  pass "No match for 'nonexistent-xyz' -- falls back to inline task"
else
  fail "Unexpected match for 'nonexistent-xyz'"
fi

echo ""
echo "=== Test 9: Path input (Case A) ==="
if [ -f "plans/test-feature.md" ]; then
  pass "Direct path plans/test-feature.md exists and is readable"
else
  fail "Direct path plans/test-feature.md not found"
fi

echo ""
echo "=== Test 10: No args lists all plans ==="
TOTAL=$(echo "$ALL_PLANS" | grep -c "\.md$" || true)
if [ "$TOTAL" -ge 5 ]; then
  pass "All plans discovered ($TOTAL .md files across all dirs)"
else
  fail "Expected 5+ plans, found $TOTAL"
fi

echo ""
echo "=== Test 11: Beyond depth limit ==="
assert_not_found "$ALL_PLANS" "too-deep.md" "Depth 5 file excluded from results"

# --- Cleanup ---

rm -rf "$TEST_DIR"

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
