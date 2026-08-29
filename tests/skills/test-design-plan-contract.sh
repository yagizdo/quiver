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
# Every assertion reads a skill file. None writes a fixture and greps it with a rule
# hardcoded here -- that form passes whatever the skills say, which is the opposite of a
# drift guard.
#
# Run directly: bash tests/skills/test-design-plan-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

DESIGN="$REPO_ROOT/skills/design/SKILL.md"
BUILD="$REPO_ROOT/skills/design-build/SKILL.md"
VERIFY="$REPO_ROOT/skills/design-verify/SKILL.md"

# --- Helpers ---

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <pattern> <label>
# The -- guards patterns that start with a dash, such as the --mode build flag.
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

# --- Assertion 1: each consumer's validation rule is declared where it is applied ---
#
# These read the skill files. Writing a fixture here and grepping it with a rule this
# test hardcodes proves only that grep works: the rule can change in the skill and the
# fixture assertion still passes.

echo ""
echo "=== 1. Consumer validation rules ==="

assert_in "$BUILD" 'design_source: figma-bridge` in frontmatter and a `### Node Specs` section' \
  "/design-build requires design_source and a Node Specs section"
assert_in "$VERIFY" 'Validate on `### Node Specs` and nothing else' \
  "/design-verify validates on the Node Specs section only"
assert_in "$VERIFY" 'this skill never requires' \
  "/design-verify states it never requires Figma provenance"

# --- Assertion 2: every field a consumer reads has a documented default ---
#
# A plan written before a field existed still has to load. The default is what makes that
# true, and it belongs in the skill that reads the field.

echo ""
echo "=== 2. Absent-field defaults documented ==="

# Every field a consumer reads must appear in that consumer's defaults table,
# which is the row form: | `field` | ... | default |
assert_in "$BUILD" '`commit_strategy` |' "/design-build documents a default for commit_strategy"
assert_in "$BUILD" '`verify_gate` |' "/design-build documents a default for verify_gate"
assert_in "$BUILD" '`screenshot_dir` |' "/design-build documents a default for screenshot_dir"

assert_in "$VERIFY" '`figma_frame_size` |' "/design-verify documents a default for figma_frame_size"
assert_in "$VERIFY" '`screenshot_scale` |' "/design-verify documents a default for screenshot_scale"
assert_in "$VERIFY" '`screenshot_dir` |' "/design-verify documents a default for screenshot_dir"
assert_in "$VERIFY" '`capture_preference` |' "/design-verify documents a default for capture_preference"

# --- Assertion 2b: the strings restated across the producer/consumer handshake ---
#
# These are the only strings in the contract written in one file and read in another.
# Nothing else in the repo declares them, so a rename on either side is silent: every
# build-loop verification degrades to the unverified branch while this suite still prints
# "All tests passed". Frontmatter fields, by contrast, are each declared once.

echo ""
echo "=== 2b. Restated handshake strings ==="

assert_in "$VERIFY" '<screenshot_dir>/verify/<task-id>.md' "/design-verify writes the agreed report path"
assert_in "$BUILD"  '<screenshot_dir>/verify/<task-id>.md' "/design-build reads the agreed report path"
assert_in "$VERIFY" '<screenshot_dir>/actual/<task-id>.png' "/design-verify names the agreed capture path"

# The build-mode invocation, flag by flag.
assert_in "$BUILD"  '--nodes' "/design-build passes --nodes"
assert_in "$VERIFY" '--nodes' "/design-verify accepts --nodes"
assert_in "$BUILD"  '--task' "/design-build passes --task"
assert_in "$VERIFY" '--task' "/design-verify accepts --task"
assert_in "$BUILD"  '--mode build' "/design-build passes --mode build"
assert_in "$VERIFY" '--mode build' "/design-verify accepts --mode build"
assert_in "$VERIFY" '--mode standalone' "/design-verify accepts --mode standalone"

# Report frontmatter fields the build loop reads to tell "measured and matched" from
# "never measured". Without these an empty deviation table reads as a pass.
for field in comparison_path confidence created; do
  assert_in "$VERIFY" "$field" "/design-verify writes $field into the deviation report"
  assert_in "$BUILD"  "$field" "/design-build reads $field from the deviation report"
done

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

# /design-build reads the commit-side fields, plus capture_preference for the one capture
# decision that is its own: whether Phase 2b opens a run session at all. A plan that
# captures nothing has nothing for a session to keep fresh, and starting one costs a full
# build and launch whose output nothing consumes. The capture path itself stays
# /design-verify's -- the frame size and the scale are still never read here.
assert_in "$BUILD" "commit_strategy" "/design-build reads commit_strategy"
assert_in "$BUILD" "verify_gate" "/design-build reads verify_gate"
assert_in "$BUILD" "capture_preference" "/design-build reads capture_preference for the session gate"
assert_not_in "$BUILD" "figma_frame_size" "/design-build does not read figma_frame_size"
assert_not_in "$BUILD" "screenshot_scale" "/design-build does not read screenshot_scale"

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
#
# R10's canonical verifier is tests/skills/test-when-to-use-contract.sh, which applies this
# shape check to every non-exempt skill. The narrower copy stays here because this file is
# the /design pipeline's own contract and must fail on its own when /design-verify stops
# routing -- but R10 shape rules are edited there first, and a tightening that lands only
# in one of the two copies is drift.
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

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
