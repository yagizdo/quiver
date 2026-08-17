#!/bin/bash
# test-design-plan-contract.sh
# Guards the three-way design-plan frontmatter contract:
#   producer  skills/design/SKILL.md        -- declares the schema, once
#   consumer  skills/design-build/SKILL.md  -- reads a subset, with defaults
#   consumer  skills/design-verify/SKILL.md -- reads a subset, with defaults
#
# Every contract in this repo that a consumer restated has drifted. This test fails
# mechanically when a field moves, a fence is duplicated, or a default goes undocumented.
#
# Run directly: bash tests/skills/test-design-plan-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="/tmp/quiver-design-contract-test"
EXIT=0

DESIGN="$REPO_ROOT/skills/design/SKILL.md"
BUILD="$REPO_ROOT/skills/design-build/SKILL.md"
VERIFY="$REPO_ROOT/skills/design-verify/SKILL.md"

# --- Helpers ---

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <pattern> <label>
assert_in() {
  if grep -q "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

# assert_not_in <file> <pattern> <label>
assert_not_in() {
  if grep -q "$2" "$1"; then
    fail "$3"
  else
    pass "$3"
  fi
}

# --- Preflight: the three skill files exist ---

echo "=== Preflight ==="
for f in "$DESIGN" "$BUILD" "$VERIFY"; do
  if [ -f "$f" ]; then
    pass "exists: ${f#$REPO_ROOT/}"
  else
    fail "missing: ${f#$REPO_ROOT/}"
  fi
done

if [ $EXIT -ne 0 ]; then
  echo ""
  echo "Skill files missing -- cannot check the contract."
  exit $EXIT
fi

# --- Fixtures ---

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# A plan carrying the full current frontmatter.
cat > "$TEST_DIR/current-design-plan.md" << 'PLAN'
---
name: wallet-design-plan
design_source: figma-bridge
figma_file_key: abc123
figma_file_name: Wallet
figma_node_ids: ["4029:12345"]
figma_frame_size: 375x812
screenshot_dir: .claude/plans/assets/wallet/
screenshot_scale: 2
stack: Dart, Flutter 3.24
commit_strategy: none
verify_gate: test
capture_preference: auto
created: 2026-08-17
---

### Node Specs

#### WalletCard (`4029:12345`)

- Type: FRAME
- Box: absolute x 24 y 320 w 327 h 48
- Fit: width fill, height fixed 48
- Content: "Continue" -- i18n key `wallet.continue`
- Route: /wallet
PLAN

# A plan written before the fidelity fields existed (commit c514685 shape).
cat > "$TEST_DIR/legacy-design-plan.md" << 'PLAN'
---
name: wallet-design-plan
design_source: figma-bridge
figma_file_key: abc123
figma_file_name: Wallet
figma_node_ids: ["4029:12345"]
screenshot_dir: .claude/plans/assets/wallet/
stack: Dart, Flutter 3.24
created: 2026-08-16
---

### Node Specs

#### WalletCard (`4029:12345`)

- Type: FRAME
- Box: absolute x 24 y 320 w 327 h 48
PLAN

# A hand-written measurement spec with no Figma provenance at all.
cat > "$TEST_DIR/handwritten-spec.md" << 'PLAN'
---
name: handwritten-spec
created: 2026-08-17
---

### Node Specs

#### LoginButton (`manual-1`)

- Type: BUTTON
- Box: absolute x 16 y 600 w 343 h 52
PLAN

# A file that is not a measurement spec.
cat > "$TEST_DIR/not-a-spec.md" << 'PLAN'
---
name: some-other-plan
---

## Steps
- [ ] Step 1
PLAN

# --- Assertion 1: both consumers accept a current plan ---
#
# /design-build documents: design_source: figma-bridge AND a ### Node Specs section.
# /design-verify documents: a ### Node Specs section, and nothing else.

echo ""
echo "=== 1. Current plan accepted by both consumers ==="

CUR="$TEST_DIR/current-design-plan.md"

if grep -q "^design_source: figma-bridge" "$CUR" && grep -q "^### Node Specs" "$CUR"; then
  pass "current plan satisfies /design-build validation"
else
  fail "current plan satisfies /design-build validation"
fi

if grep -q "^### Node Specs" "$CUR"; then
  pass "current plan satisfies /design-verify validation"
else
  fail "current plan satisfies /design-verify validation"
fi

# --- Assertion 2: the legacy plan is still accepted, and every absent field
#     has a documented default in the skill that reads it ---

echo ""
echo "=== 2. Legacy plan accepted, absent-field defaults documented ==="

LEG="$TEST_DIR/legacy-design-plan.md"

if grep -q "^design_source: figma-bridge" "$LEG" && grep -q "^### Node Specs" "$LEG"; then
  pass "legacy plan satisfies /design-build validation"
else
  fail "legacy plan satisfies /design-build validation"
fi

if grep -q "^### Node Specs" "$LEG"; then
  pass "legacy plan satisfies /design-verify validation"
else
  fail "legacy plan satisfies /design-verify validation"
fi

# Every field a consumer reads must appear in that consumer's defaults table,
# which is the row form: | `field` | ... | default |
assert_in "$BUILD" '`commit_strategy` |' "/design-build documents a default for commit_strategy"
assert_in "$BUILD" '`verify_gate` |' "/design-build documents a default for verify_gate"
assert_in "$BUILD" '`screenshot_dir` |' "/design-build documents a default for screenshot_dir"

assert_in "$VERIFY" '`figma_frame_size` |' "/design-verify documents a default for figma_frame_size"
assert_in "$VERIFY" '`screenshot_scale` |' "/design-verify documents a default for screenshot_scale"
assert_in "$VERIFY" '`screenshot_dir` |' "/design-verify documents a default for screenshot_dir"
assert_in "$VERIFY" '`capture_preference` |' "/design-verify documents a default for capture_preference"

# --- Assertion 2b: /design-verify validates on Node Specs only ---

echo ""
echo "=== 2b. /design-verify accepts a spec with no Figma provenance ==="

HAND="$TEST_DIR/handwritten-spec.md"

if grep -q "^### Node Specs" "$HAND"; then
  pass "hand-written spec satisfies /design-verify validation"
else
  fail "hand-written spec satisfies /design-verify validation"
fi

if grep -q "^design_source:" "$HAND"; then
  fail "hand-written spec has no design_source (fixture is wrong)"
else
  pass "hand-written spec has no design_source, and is still valid input"
fi

if grep -q "^### Node Specs" "$TEST_DIR/not-a-spec.md"; then
  fail "a non-spec file is rejected"
else
  pass "a non-spec file is rejected"
fi

# --- Assertion 3: each new field is named in exactly the skills that own it,
#     and the schema fence lives in the producer only ---

echo ""
echo "=== 3. Field ownership and single declaration point ==="

# Producer declares all five.
assert_in "$DESIGN" "figma_frame_size" "producer declares figma_frame_size"
assert_in "$DESIGN" "screenshot_scale" "producer declares screenshot_scale"
assert_in "$DESIGN" "commit_strategy" "producer declares commit_strategy"
assert_in "$DESIGN" "verify_gate" "producer declares verify_gate"
assert_in "$DESIGN" "capture_preference" "producer declares capture_preference"

# /design-verify reads the capture-side fields and none of the commit-side ones.
assert_in "$VERIFY" "figma_frame_size" "/design-verify reads figma_frame_size"
assert_in "$VERIFY" "screenshot_scale" "/design-verify reads screenshot_scale"
assert_in "$VERIFY" "capture_preference" "/design-verify reads capture_preference"
assert_not_in "$VERIFY" "commit_strategy" "/design-verify does not read commit_strategy"
assert_not_in "$VERIFY" "verify_gate" "/design-verify does not read verify_gate"

# /design-build reads the commit-side fields and none of the capture-side ones.
assert_in "$BUILD" "commit_strategy" "/design-build reads commit_strategy"
assert_in "$BUILD" "verify_gate" "/design-build reads verify_gate"
assert_not_in "$BUILD" "figma_frame_size" "/design-build does not read figma_frame_size"
assert_not_in "$BUILD" "screenshot_scale" "/design-build does not read screenshot_scale"
assert_not_in "$BUILD" "capture_preference" "/design-build does not read capture_preference"

# The schema fence is declared once. figma_file_name: is unique to that fence.
FENCE_HITS=$(grep -l "figma_file_name:" "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$FENCE_HITS" = "1" ]; then
  pass "the plan frontmatter fence appears in exactly one skill"
else
  fail "the plan frontmatter fence appears in $FENCE_HITS skills, expected 1"
fi

assert_in "$DESIGN" "figma_file_name:" "the one fence is in skills/design/SKILL.md"

# --- Assertion 4: /design-verify is routable by the SessionStart hook ---

echo ""
echo "=== 4. /design-verify frontmatter routes ==="

# The hook drops any skill whose when-to-use is not a single-line double-quoted string.
# Replicate its extraction exactly.
VERIFY_NAME=$(awk 'BEGIN{c=0} /^---/{c++;next} c==1 && /^name:/{gsub(/^name:[[:space:]]*/,""); print; exit}' "$VERIFY")
VERIFY_WTU=$(awk 'BEGIN{c=0} /^---/{c++;next} c==1 && /^when-to-use:/{gsub(/^when-to-use:[[:space:]]*/,""); print; exit}' "$VERIFY" | tr -d '"<>')

if [ "$VERIFY_NAME" = "design-verify" ]; then
  pass "name: matches the directory"
else
  fail "name: matches the directory (got '$VERIFY_NAME')"
fi

if [ -n "$VERIFY_WTU" ]; then
  pass "when-to-use: extracts non-empty via the hook's parser"
else
  fail "when-to-use: extracts non-empty via the hook's parser"
fi

# Single-line and double-quoted: the raw line must open and close with a quote.
if grep -q '^when-to-use: ".*"$' "$VERIFY"; then
  pass "when-to-use: is a single-line double-quoted string"
else
  fail "when-to-use: is a single-line double-quoted string"
fi

# End-to-end: the hook actually emits the route.
HOOK="$REPO_ROOT/hooks/scripts/session-start-auto-dispatch.sh"
if [ -x "$HOOK" ] || [ -f "$HOOK" ]; then
  ROUTES=$(bash "$HOOK" 2>/dev/null)
  if echo "$ROUTES" | grep -q "^/design-verify: "; then
    pass "the SessionStart hook emits a /design-verify route"
  else
    fail "the SessionStart hook emits a /design-verify route"
  fi
else
  fail "session-start-auto-dispatch.sh not found"
fi

# --- Assertion 5: R4 and R8 on the new skill, which nothing else checks ---

echo ""
echo "=== 5. Skill rules with no other automated check ==="

# R4 -- no CLAUDE_PLUGIN_ROOT outside the verification checklist line that names it.
PLUGIN_ROOT_HITS=$(grep -c "CLAUDE_PLUGIN_ROOT" "$VERIFY" || true)
if [ "$PLUGIN_ROOT_HITS" -le 1 ]; then
  pass "R4: no CLAUDE_PLUGIN_ROOT usage in design-verify"
else
  fail "R4: CLAUDE_PLUGIN_ROOT referenced $PLUGIN_ROOT_HITS times in design-verify"
fi

# R8 -- ASCII only, across all three skills.
for f in "$DESIGN" "$BUILD" "$VERIFY"; do
  if LC_ALL=C grep -q '[^ -~	]' "$f"; then
    fail "R8: non-ASCII characters in ${f#$REPO_ROOT/}"
  else
    pass "R8: ASCII-only in ${f#$REPO_ROOT/}"
  fi
done

# Every skill must carry a Test Plan -- the merge gate in CLAUDE.md.
for f in "$DESIGN" "$BUILD" "$VERIFY"; do
  if grep -q "^## Test Plan" "$f"; then
    pass "Test Plan present in ${f#$REPO_ROOT/}"
  else
    fail "Test Plan missing in ${f#$REPO_ROOT/}"
  fi
done

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
