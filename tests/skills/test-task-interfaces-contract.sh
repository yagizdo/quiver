#!/bin/bash
# test-task-interfaces-contract.sh
# Guards the "**Provides:**" interface field that joins /plan to /work:
#   producer  skills/plan/SKILL.md        -- Step 5 specifies the field, Step 6 Check 8 polices it
#   consumer  skills/work/orchestrator.md -- copies every declared line into each brief's ## Interfaces block
#
# The whole interface between the two skills is one bold label written at the start of a line.
# A rename in the producer with no matching rename in the consumer breaks extraction with NO
# user-visible symptom: /work writes briefs carrying no `## Interfaces` block, which looks
# exactly like the legitimate case of a plan whose tasks share no symbol. Every subagent then
# invents its own signature in its own worktree, and the mismatch surfaces at merge instead of
# at dispatch. This test is the only thing that catches that.
#
# It also pins the Plan Guard check that fills the field in and the degrade-cleanly clause that
# keeps the absent-block path silent. Check 8 is the only step that adds a missing declaration,
# and its two check-count strings drift apart on any half-finished renumber; the orchestrator's
# "omits the `## Interfaces` heading" clause is one careless edit from deletion, and deleting it
# turns a valid empty state into noise.
#
# It reads the real files. It never writes a fixture and greps it with a rule hardcoded here --
# that form passes whatever the fixture says, which is the opposite of a drift guard.
#
# Run directly: bash tests/skills/test-task-interfaces-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLAN="$REPO_ROOT/skills/plan/SKILL.md"
ORCH="$REPO_ROOT/skills/work/orchestrator.md"

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# --- Preflight ---
# Every later section reads one of these two files. A missing file makes each of those greps
# report "string not found", which reads as drift rather than as a moved file.
echo ""
echo "=== 1. Preflight ==="
MISSING=0
if [ ! -f "$PLAN" ]; then
  fail "missing $PLAN -- the producer that specifies the **Provides:** field and polices it in Check 8."
  MISSING=1
fi
if [ ! -f "$ORCH" ]; then
  fail "missing $ORCH -- the task-brief consumer that copies the field into the ## Interfaces block."
  MISSING=1
fi
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit $EXIT
fi
pass "producer and consumer files present"

# --- Producer ---
# Line-anchored: the orchestrator extracts on the label at the start of a line, so a
# **Provides:** buried mid-sentence documents the field without making it extractable.
echo ""
echo "=== 2. Producer declares the field ==="
if grep -Eq '^\*\*Provides:\*\* ' "$PLAN"; then
  pass "skills/plan/SKILL.md writes '**Provides:** ' at the start of a line"
else
  fail "skills/plan/SKILL.md has no line starting with '**Provides:** ' -- the format spec no longer shows the label where /work looks for it, and every brief loses its ## Interfaces block"
fi

# --- Plan Guard ---
# Check 8 is what puts a declaration on a task that forgot one. Without it the field is
# advisory, and a plan can name a symbol across two tasks with no signature anywhere.
echo ""
echo "=== 3. Plan Guard polices the field ==="
if grep -Fq -- '### Check 8:' "$PLAN"; then
  pass "skills/plan/SKILL.md Step 6 carries '### Check 8:'"
else
  fail "skills/plan/SKILL.md Step 6 has no '### Check 8:' heading -- nothing in the plan pipeline adds a missing **Provides:** entry, so the field only ever holds what the drafting pass happened to write"
fi

if grep -Fq -- 'these 8 checks' "$PLAN"; then
  pass "skills/plan/SKILL.md Step 6 opens on 'these 8 checks'"
else
  fail "skills/plan/SKILL.md Step 6 no longer says 'these 8 checks' -- the count that tells the run how many checks to execute disagrees with the checks present"
fi

if grep -Fq -- 'all 8 checks' "$PLAN"; then
  pass "skills/plan/SKILL.md action routing runs after 'all 8 checks'"
else
  fail "skills/plan/SKILL.md action routing no longer says 'all 8 checks' -- the routing gate opens before Check 8 has run"
fi

# The positive assertions above both pass while a stale 7 survives in the other string, so a
# half-finished renumber needs its own tripwire.
if grep -q 'these 7 checks\|all 7 checks' "$PLAN"; then
  fail "skills/plan/SKILL.md still says 'these 7 checks' or 'all 7 checks' -- one of the two count strings was renumbered and the other was not"
else
  pass "no stale 7-check count string survives in skills/plan/SKILL.md"
fi

# --- Consumer ---
# The literal label, not the bare word: '**Provides:**' is the hand-synced token between the two
# files and the consumer has to name it in the form the producer writes it. A bare 'Provides'
# would match the word appearing anywhere in a 350-line file.
echo ""
echo "=== 4. Consumer copies the field into briefs ==="
if grep -Fq -- '**Provides:**' "$ORCH"; then
  pass "skills/work/orchestrator.md names the '**Provides:**' label verbatim"
else
  fail "skills/work/orchestrator.md no longer names '**Provides:**' -- the brief-writing step has nothing to extract, and every brief silently drops its interface block"
fi

# Substring, not -Fxq: the consumer names the heading inside prose rather than writing it as a
# line of its own.
if grep -Fq -- '## Interfaces' "$ORCH"; then
  pass "skills/work/orchestrator.md names the '## Interfaces' brief heading"
else
  fail "skills/work/orchestrator.md no longer names '## Interfaces' -- briefs would carry the declarations under some other heading, and the dispatch prompt's fixed-signature constraint points at a section that does not exist"
fi

# --- Degrade-cleanly clause ---
# Constraint: absence of any declaration must degrade to exactly the previous behavior -- no
# error, no warning, no empty heading. One sentence carries that guarantee.
echo ""
echo "=== 5. The absent-block path stays silent ==="

# A literal grep, not the paragraph-scoped awk its sibling test uses. Section 2 Part 1 item 1
# already contains 'omits' in the Global Constraints absent-case clause, and the interface rule
# was appended to that same numbered item, so an awk RS="" record holding both 'Provides' and
# 'omits' is satisfied by the pre-existing clause and stays green after the new one is deleted.
# The phrase below names the heading, so nothing else in the file can stand in for it.
if grep -Fq -- 'omits the `## Interfaces` heading' "$ORCH"; then
  pass "skills/work/orchestrator.md keeps the phrase 'omits the \`## Interfaces\` heading'"
else
  fail "skills/work/orchestrator.md no longer says it omits the '## Interfaces' heading -- a plan whose tasks share no symbol would get an empty heading in every brief, which reads as 'this task has no collaborators' rather than 'this plan declared none'"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
