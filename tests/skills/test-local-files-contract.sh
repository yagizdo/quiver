#!/bin/bash
# test-local-files-contract.sh
# Guards where Quiver's development files live. Brainstorm specs moved from
# docs/brainstorms/ to .claude/specs/: /brainstorm writes them there, /plan Step 6
# Check 3 finds them there, /advise names the path in its no-write rule, and
# /visual-companion copies mockups beside the spec. A skill still naming the old
# path either writes a spec nothing reads or looks for one in a directory nothing
# writes, and neither raises an error. It also binds skills/local-files/SKILL.md, the
# one home of the keep-local rule, to every skill that writes a development directory
# and names it at its write step. Every assertion reads the live skill files.
#
# Run directly: bash tests/skills/test-local-files-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

echo "=== 1. No skill names the old brainstorm spec path ==="

HITS="$(grep -rn 'docs/brainstorms' "$REPO_ROOT/skills" 2>/dev/null)"
if [ -z "$HITS" ]; then
  pass "no file under skills/ names docs/brainstorms"
else
  fail "files under skills/ still name docs/brainstorms:"
  echo "$HITS" | sed "s|$REPO_ROOT/||; s|^|    |"
fi

echo ""
echo "=== 2. The keep-local rule has the shape its consumers read ==="

# Writers name skills/local-files/SKILL.md at their write step and read the rule
# there. A reference skill that becomes invocable or grows a shell block stops being
# the inert pointer target they assume, and a second ## Keep-Local Rule heading leaves
# a reader with two rules to choose from.
REF="$REPO_ROOT/skills/local-files/SKILL.md"
if [ ! -f "$REF" ]; then
  fail "missing skills/local-files/SKILL.md"
else
  # Bounded to the frontmatter block between the first two --- delimiters.
  INVOCABLE="$(awk '/^---[[:space:]]*$/ { c++; if (c == 2) exit; next } c == 1 && /^user-invocable:/ { sub(/^user-invocable:[[:space:]]*/, ""); print; exit }' "$REF")"
  if [ "$INVOCABLE" = "false" ]; then
    pass "frontmatter user-invocable: is false"
  else
    fail "frontmatter user-invocable: is '$INVOCABLE', expected false -- a reference skill is read by other skills, never invoked"
  fi

  # grep -c prints 0 and exits 1 on no match, so the count is captured, not the status.
  INLINE="$(grep -cF -- '!`' "$REF")"
  if [ "$INLINE" = "0" ]; then
    pass "no inline shell block opener in skills/local-files/SKILL.md"
  else
    fail "$INLINE line(s) carry an inline shell block opener in skills/local-files/SKILL.md -- a reference skill runs nothing"
  fi

  N="$(grep -cxF -- '## Keep-Local Rule' "$REF")"
  if [ "$N" = "1" ]; then
    pass "heading '## Keep-Local Rule' appears exactly once"
  else
    fail "heading '## Keep-Local Rule' appears $N time(s), expected exactly once"
  fi
fi

echo ""
echo "=== 3. Every writer names the keep-local rule ==="

# One entry per skill that writes a development directory. A writer that drops the
# pointer creates its directory with nothing keeping it out of git, and no error says so.
CONSUMERS=(
  skills/plan/SKILL.md
  skills/brainstorm/SKILL.md
  skills/review/SKILL.md
  skills/senior-review/SKILL.md
  skills/handover/SKILL.md
  skills/design/SKILL.md
  skills/work/orchestrator.md
  skills/ship/SKILL.md
)
for c in "${CONSUMERS[@]}"; do
  if [ ! -f "$REPO_ROOT/$c" ]; then
    fail "missing $c"
  elif grep -qF -- 'apply the keep-local rule in `skills/local-files/SKILL.md`' "$REPO_ROOT/$c"; then
    pass "$c names skills/local-files/SKILL.md"
  else
    fail "$c does not tell the model to apply the keep-local rule in skills/local-files/SKILL.md"
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
