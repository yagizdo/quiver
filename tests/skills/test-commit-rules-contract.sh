#!/bin/bash
# test-commit-rules-contract.sh
# Guards the "# Commit Message Generation" section that joins /commit to /work:
#   producer  skills/commit/SKILL.md      -- the section holds every commit message rule
#   consumer  skills/work/SKILL.md        -- Phase 3 and the auto-mode 5a commit write messages by it
#   consumer  skills/work/orchestrator.md -- copies it into every task brief under "## Commit Messages"
#
# The consumers name the heading and the path; neither carries a rule of its own. A heading
# renamed in the producer leaves /work reading a section that does not exist, and a rule moved
# out of the section (subject-only, no attribution) silently stops reaching every worktree
# subagent, whose brief is the only text it has. A consumer that grows its own "Conventional
# Commits message" instruction back is a second rule set that drifts from the first.
#
# It reads the real files. No fixture is written.
#
# Run directly: bash tests/skills/test-commit-rules-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMIT="$REPO_ROOT/skills/commit/SKILL.md"
WORK="$REPO_ROOT/skills/work/SKILL.md"
ORCH="$REPO_ROOT/skills/work/orchestrator.md"

HEADING='# Commit Message Generation'

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

echo ""
echo "=== 1. Preflight ==="
MISSING=0
for f in "$COMMIT" "$WORK" "$ORCH"; do
  if [ ! -f "$f" ]; then
    fail "missing $f"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit $EXIT
fi
pass "producer and both consumer files present"

echo ""
echo "=== 2. Producer carries the section and its full rule set ==="
COUNT="$(grep -Fxc -- "$HEADING" "$COMMIT")"
if [ "$COUNT" -eq 1 ]; then
  pass "skills/commit/SKILL.md has exactly one line '$HEADING'"
else
  fail "skills/commit/SKILL.md has $COUNT lines reading '$HEADING' -- expected exactly 1; the consumers copy the section by this heading"
fi

# The section runs from the heading to the next '---' rule, the span a consumer copies.
SECTION="$(awk -v h="$HEADING" '$0 == h { s = 1; next } s && /^---/ { exit } s { print }' "$COMMIT")"
if printf '%s\n' "$SECTION" | grep -Fq -- "subject-only"; then
  pass "the section states the subject-only default"
else
  fail "the '$HEADING' section does not say 'subject-only' -- /work and its subagents copy only this section, so the default stops reaching them"
fi
if printf '%s\n' "$SECTION" | grep -Fq -- "attribution"; then
  pass "the section states the no-attribution rule"
else
  fail "the '$HEADING' section does not carry the no-attribution rule -- worktree subagents would commit without it"
fi

echo ""
echo "=== 3. Each consumer names the producer and carries no rule of its own ==="
for entry in "$WORK|skills/work/SKILL.md" "$ORCH|skills/work/orchestrator.md"; do
  file="${entry%%|*}"
  rel="${entry#*|}"
  if grep -Fq -- "skills/commit/SKILL.md" "$file"; then
    pass "$rel names skills/commit/SKILL.md"
  else
    fail "$rel does not name skills/commit/SKILL.md -- it has no path to read the commit message rules from"
  fi
  if grep -Fq -- "$HEADING" "$file"; then
    pass "$rel names '$HEADING'"
  else
    fail "$rel does not name '$HEADING' -- it no longer says which section holds the rules"
  fi
  if grep -Fq -- "Conventional Commits message" "$file"; then
    fail "$rel still says 'Conventional Commits message' as its own rule -- a second rule set drifts from skills/commit/SKILL.md"
  else
    pass "$rel carries no 'Conventional Commits message' rule of its own"
  fi
done

# The orchestrator writes the copied section under this heading and the subagent prompt's
# commit instruction points at it; both sit in orchestrator.md, so a rename of one leaves the
# subagent told to follow a section its brief does not have.
if grep -Fq -- "## Commit Messages" "$ORCH" && grep -E '^6\. ' "$ORCH" | grep -Fq -- "## Commit Messages"; then
  pass "orchestrator.md writes '## Commit Messages' into briefs and prompt item 6 names it"
else
  fail "orchestrator.md lost '## Commit Messages' in the brief recipe or in subagent prompt item 6"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
