#!/bin/bash
# test-global-constraints-contract.sh
# Guards the "## Global Constraints" heading that joins /plan to /work and /review:
#   producer  skills/plan/SKILL.md        -- Step 4.5 derives the block, Step 5 writes the section
#   consumer  skills/work/orchestrator.md -- reproduces the block verbatim in every task brief
#   consumer  skills/review/SKILL.md      -- Step 1.8 extracts the block and passes it to every agent
#   consumer  skills/work/SKILL.md        -- states the block binds every task in the run
#
# The whole interface between the three skills is one section heading in one file. A rename in
# the producer with no matching rename in the consumers breaks extraction in both of them with
# NO user-visible symptom: /work writes briefs carrying no constraints and /review reports N/A,
# and both look exactly like the legitimate no-constraints-derived case. This test is the only
# thing that catches that.
#
# It also pins the two degrade-cleanly clauses that keep the absent-block path silent -- the
# orchestrator's "the brief omits the heading entirely" and Step 1.8's "no note". Both are one
# careless edit from deletion, and deleting either turns a valid empty state into noise.
#
# It reads the real files. It never writes a fixture and greps it with a rule hardcoded here --
# that form passes whatever the fixture says, which is the opposite of a drift guard.
#
# Run directly: bash tests/skills/test-global-constraints-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLAN="$REPO_ROOT/skills/plan/SKILL.md"
ORCH="$REPO_ROOT/skills/work/orchestrator.md"
REVIEW="$REPO_ROOT/skills/review/SKILL.md"
WORK="$REPO_ROOT/skills/work/SKILL.md"

HEADING='## Global Constraints'

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# --- Preflight ---
# Every later section reads one of these four files. A missing file makes each of those
# greps report "string not found", which reads as drift rather than as a moved file.
echo ""
echo "=== 1. Preflight ==="
MISSING=0
if [ ! -f "$PLAN" ]; then
  fail "missing $PLAN -- the producer of the $HEADING section."
  MISSING=1
fi
if [ ! -f "$ORCH" ]; then
  fail "missing $ORCH -- the task-brief consumer of the block."
  MISSING=1
fi
if [ ! -f "$REVIEW" ]; then
  fail "missing $REVIEW -- the agent-prompt consumer of the block."
  MISSING=1
fi
if [ ! -f "$WORK" ]; then
  fail "missing $WORK -- the /work entry point that binds tasks to the block."
  MISSING=1
fi
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit $EXIT
fi
pass "producer and all three consumer files present"

# --- Producer ---
# Matched whole-line and literal: the consumers extract on the heading text exactly, so a
# heading that grew a suffix is the same broken interface as a heading that was renamed.
echo ""
echo "=== 2. Producer writes the canonical heading ==="
if grep -Fxq -- "$HEADING" "$PLAN"; then
  pass "skills/plan/SKILL.md carries the literal heading '$HEADING'"
else
  fail "skills/plan/SKILL.md has no line reading exactly '$HEADING' -- with no producer heading there is nothing for /work or /review to extract, and both degrade silently"
fi

# --- Consumers ---
# The bare string, not the heading: the consumers name the section in prose, in a report
# field, and in a brief template, and only the orchestrator reproduces it as a heading.
echo ""
echo "=== 3. Every consumer still names the section ==="
for entry in \
  "$ORCH|skills/work/orchestrator.md|task briefs would carry no constraints and read as a run that derived none" \
  "$REVIEW|skills/review/SKILL.md|Step 1.8 would extract nothing and the report's Global Constraints field would read N/A on every run" \
  "$WORK|skills/work/SKILL.md|the run would stop treating the block as binding on its tasks"
do
  file="${entry%%|*}"
  rest="${entry#*|}"
  rel="${rest%%|*}"
  why="${rest#*|}"
  if grep -Fq -- "Global Constraints" "$file"; then
    pass "$rel names Global Constraints"
  else
    fail "$rel no longer names Global Constraints -- $why"
  fi
done

# --- Degrade-cleanly clauses ---
# Constraint 4 of the plan: absence of the block must degrade to exactly today's behavior --
# no error, no warning, no empty heading. Two sentences carry that guarantee, one per
# consumer, and neither is protected by anything else in the tree.
echo ""
echo "=== 4. The absent-block path stays silent ==="

# awk paragraph mode (RS = "") makes a record out of each blank-line-delimited block, which
# is the "same paragraph" the clause has to stay in. Scoping it that way is what stops a
# stray "omits" elsewhere in the file from standing in for the deleted clause.
if awk 'BEGIN { RS = "" } index($0, "Global Constraints") > 0 && index($0, "omits") > 0 { found = 1 } END { exit found ? 0 : 1 }' "$ORCH"; then
  pass "skills/work/orchestrator.md keeps 'omits' in the same paragraph as Global Constraints"
else
  fail "skills/work/orchestrator.md has no paragraph holding both 'Global Constraints' and 'omits' -- the clause that makes a brief drop the heading instead of writing an empty one is gone, and an empty heading reads as 'no constraints were derived' rather than 'this run has none'"
fi

# Counted before the region is read so a renamed step reports as a renamed step. The region
# extractor below re-enters on every anchor, so a duplicate heading would silently widen it.
ANCHORS="$(grep -c '^## Step 1\.8' "$REVIEW")"
if [ "$ANCHORS" -eq 1 ]; then
  pass "'## Step 1.8' appears exactly once as a heading in skills/review/SKILL.md"
else
  fail "'## Step 1.8' appears $ANCHORS times as a heading in skills/review/SKILL.md -- expected exactly 1"
fi

if awk '
    /^## Step 1\.8/ { s = 1; next }
    /^## / { s = 0 }
    s && index($0, "no note") > 0 { found = 1 }
    END { exit found ? 0 : 1 }' "$REVIEW"; then
  pass "skills/review/SKILL.md Step 1.8 keeps the phrase 'no note'"
else
  fail "skills/review/SKILL.md Step 1.8 no longer says 'no note' -- a review with no plan block would start reporting the absence instead of behaving exactly as it did before Step 1.8 existed"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
