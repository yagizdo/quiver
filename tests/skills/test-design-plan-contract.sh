#!/bin/bash
# test-design-plan-contract.sh
# Guards the two-way design-plan frontmatter contract:
#   producer  skills/design/SKILL.md        -- declares the schema, once
#   consumer  skills/design-build/SKILL.md  -- reads a subset, with defaults
#
# Every contract in this repo that a consumer restated has drifted. This test fails
# mechanically when a field moves, a fence is duplicated, or a default goes undocumented.
#
# The field list is read out of the consumer's own defaults table rather than hardcoded
# here, so adding a field to that table without adding it to the producer's fence fails
# this test with no edit to it.
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

# --- Helpers ---

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

# assert_not_in <file> <pattern> <label>
assert_not_in() {
  if grep -q -- "$2" "$1"; then
    fail "$3"
  else
    pass "$3"
  fi
}

# --- Preflight: both skill files exist ---

echo "=== Preflight ==="
for f in "$DESIGN" "$BUILD"; do
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

# --- Assertion 1: the consumer's validation rule is declared where it is applied ---
#
# This reads the skill file. Writing a fixture here and grepping it with a rule this test
# hardcodes proves only that grep works: the rule can change in the skill and the fixture
# assertion still passes.

echo ""
echo "=== 1. Consumer validation rule ==="

assert_in "$BUILD" 'design_source: figma-bridge` in frontmatter and a `### Node Specs` section' \
  "/design-build requires design_source and a Node Specs section"
assert_in "$DESIGN" '^### Node Specs$' \
  "/design writes the Node Specs section the consumer validates on"

# --- Assertion 2: every field the consumer reads is declared by the producer ---
#
# The list comes out of the consumer's own defaults table, so a field added there and not
# to the producer's fence fails here with no edit to this test. This is the assertion that
# catches /design silently dropping a field /design-build still reads.

echo ""
echo "=== 2. Consumer fields are producer-declared ==="

FIELDS=$(awk '
  /^### Frontmatter fields this skill reads$/ { inblk = 1; next }
  inblk && /^## / { inblk = 0 }
  inblk && /^\| `/ { gsub(/^\| `/, ""); sub(/`.*$/, ""); print }
' "$BUILD")

if [ -z "$FIELDS" ]; then
  fail "the consumer's defaults table lists at least one field"
else
  for field in $FIELDS; do
    assert_in "$BUILD"  "\`$field\` |"  "/design-build documents a default for $field"
    assert_in "$DESIGN" "^$field:"      "/design declares $field in the plan fence"
  done
fi

# A field with no consumer is checked by name or by nothing. figma_frame_size is written
# for a measurement tool this repo does not contain: it is the enclosing screen frame's
# logical size, and the node specs record the parent chain by name rather than by box, so
# a plan scoped to a component carries that size in this field and nowhere else. The loop
# above cannot reach it -- it derives its list from the consumer's table -- so the guard is
# explicit. Delete it only together with the field.

assert_in "$DESIGN" "^figma_frame_size:" \
  "/design declares figma_frame_size, which no skill reads yet"

# --- Assertion 3: the schema fence lives in the producer only ---

echo ""
echo "=== 3. Single declaration point ==="

# figma_file_name: is unique to that fence.
FENCE_HITS=$(grep -l "figma_file_name:" "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$FENCE_HITS" = "1" ]; then
  pass "the plan frontmatter fence appears in exactly one skill"
else
  fail "the plan frontmatter fence appears in $FENCE_HITS skills, expected 1"
fi

assert_in "$DESIGN" "figma_file_name:" "the one fence is in skills/design/SKILL.md"

# The consumer lists fields, never the fence. figma_file_key: is fence-only text.
assert_not_in "$BUILD" "figma_file_key:" "/design-build does not reproduce the fence"

# --- Assertion 4: /design-build is routable by the SessionStart hook ---

echo ""
echo "=== 4. /design-build frontmatter routes ==="

# The hook drops any skill whose when-to-use is not a single-line double-quoted string.
# Replicate its extraction exactly.
#
# R10's canonical verifier is tests/skills/test-when-to-use-contract.sh, which applies this
# shape check to every non-exempt skill. The narrower copy stays here because this file is
# the /design pipeline's own contract and must fail on its own when /design-build stops
# routing -- but R10 shape rules are edited there first, and a tightening that lands only
# in one of the two copies is drift.
BUILD_NAME=$(awk 'BEGIN{c=0} /^---/{c++;next} c==1 && /^name:/{gsub(/^name:[[:space:]]*/,""); print; exit}' "$BUILD")
BUILD_WTU=$(awk 'BEGIN{c=0} /^---/{c++;next} c==1 && /^when-to-use:/{gsub(/^when-to-use:[[:space:]]*/,""); print; exit}' "$BUILD" | tr -d '"<>')

if [ "$BUILD_NAME" = "design-build" ]; then
  pass "name: matches the directory"
else
  fail "name: matches the directory (got '$BUILD_NAME')"
fi

if [ -n "$BUILD_WTU" ]; then
  pass "when-to-use: extracts non-empty via the hook's parser"
else
  fail "when-to-use: extracts non-empty via the hook's parser"
fi

# Single-line and double-quoted: the raw line must open and close with a quote.
if grep -q '^when-to-use: ".*"$' "$BUILD"; then
  pass "when-to-use: is a single-line double-quoted string"
else
  fail "when-to-use: is a single-line double-quoted string"
fi

# End-to-end: the hook actually emits the route.
HOOK="$REPO_ROOT/hooks/scripts/session-start-auto-dispatch.sh"
if [ -x "$HOOK" ] || [ -f "$HOOK" ]; then
  ROUTES=$(bash "$HOOK" 2>/dev/null)
  if echo "$ROUTES" | grep -q "^/design-build: "; then
    pass "the SessionStart hook emits a /design-build route"
  else
    fail "the SessionStart hook emits a /design-build route"
  fi
else
  fail "session-start-auto-dispatch.sh not found"
fi

# --- Assertion 5: R4 and R8 on both skills, which nothing else checks ---

echo ""
echo "=== 5. Skill rules with no other automated check ==="

# R4 -- no CLAUDE_PLUGIN_ROOT outside the verification checklist line that names it.
for f in "$DESIGN" "$BUILD"; do
  PLUGIN_ROOT_HITS=$(grep -c "CLAUDE_PLUGIN_ROOT" "$f" || true)
  if [ "$PLUGIN_ROOT_HITS" -le 1 ]; then
    pass "R4: no CLAUDE_PLUGIN_ROOT usage in ${f#$REPO_ROOT/}"
  else
    fail "R4: CLAUDE_PLUGIN_ROOT referenced $PLUGIN_ROOT_HITS times in ${f#$REPO_ROOT/}"
  fi
done

# R8 -- ASCII only, across both skills.
for f in "$DESIGN" "$BUILD"; do
  if LC_ALL=C grep -q '[^ -~	]' "$f"; then
    fail "R8: non-ASCII characters in ${f#$REPO_ROOT/}"
  else
    pass "R8: ASCII-only in ${f#$REPO_ROOT/}"
  fi
done

# Every skill must carry a Test Plan -- the merge gate in CLAUDE.md. It lives in
# TEST-PLAN.md beside SKILL.md, not inside it: the body loads on every invocation and the
# test instructions do not. Presence alone is not the gate -- an empty file or a stub with
# no Trigger line satisfies a file-exists check and tells a reviewer nothing -- so the file
# must also be non-empty and carry its Trigger. The second loop is the other half: a
# section left behind in SKILL.md is a copy that drifts from the sibling and still loads.
SKILL_DIRS=0
for d in "$REPO_ROOT"/skills/*/; do
  [ -f "$d/SKILL.md" ] || continue
  SKILL_DIRS=$((SKILL_DIRS + 1))
  name="$(basename "$d")"
  tp="$d/TEST-PLAN.md"
  if [ ! -f "$tp" ]; then
    fail "skills/$name/TEST-PLAN.md missing -- the merge gate in CLAUDE.md"
  elif [ ! -s "$tp" ]; then
    fail "skills/$name/TEST-PLAN.md is empty"
  elif ! grep -q "Trigger" "$tp"; then
    fail "skills/$name/TEST-PLAN.md carries no Trigger line"
  else
    pass "skills/$name/TEST-PLAN.md present, non-empty, carries Trigger"
  fi
done

# A scan that finds no skill directories passes on nothing.
if [ "$SKILL_DIRS" -gt 0 ]; then
  pass "$SKILL_DIRS skill directories checked for a sibling Test Plan"
else
  fail "no skills/*/SKILL.md found -- this section asserted nothing"
fi

for f in "$REPO_ROOT"/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$f")")"
  if grep -q "^## Test Plan" "$f"; then
    fail "skills/$name/SKILL.md still carries a '## Test Plan' section -- it belongs in TEST-PLAN.md"
  else
    pass "skills/$name/SKILL.md carries no inline Test Plan"
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
