#!/bin/bash
# test-using-quiver-bootstrap.sh
# Validates the using-quiver meta-skill and its bootstrap injection setup.
# Verifies the file exists, has correct frontmatter, contains the load-bearing
# <SUBAGENT-STOP> and <EXTREMELY-IMPORTANT> blocks, and the OpenCode symlink resolves.

set -e

EXIT=0
PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# --- Helpers ---

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

assert_file_exists() {
  if [ -f "$1" ]; then
    pass "file exists: $2"
  else
    fail "file exists: $2"
  fi
}

assert_symlink_resolves() {
  if [ -L "$1" ] && [ -e "$1" ]; then
    pass "symlink resolves: $2"
  else
    fail "symlink resolves: $2"
  fi
}

assert_grep() {
  if grep -q "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

assert_not_grep() {
  if grep -q "$2" "$1"; then
    fail "$3"
  else
    pass "$3"
  fi
}

# --- Tests ---

echo "Testing using-quiver meta-skill..."

# 1. The using-quiver skill file exists
assert_file_exists "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "skills/using-quiver/SKILL.md"

# 2. The file has valid YAML frontmatter
if head -1 "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" | grep -q "^---$"; then
  pass "file starts with YAML frontmatter delimiter"
else
  fail "file starts with YAML frontmatter delimiter"
fi

# 3. Frontmatter contains name field
assert_grep "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "^name: using-quiver" "frontmatter has name: using-quiver"

# 4. Frontmatter contains description field
assert_grep "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "^description:" "frontmatter has description field"

# 5. The file contains a <SUBAGENT-STOP> block (load-bearing for subagent correctness)
assert_grep "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "<SUBAGENT-STOP>" "file contains <SUBAGENT-STOP> block"

# 6. The file contains an <EXTREMELY-IMPORTANT> block
assert_grep "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "<EXTREMELY-IMPORTANT>" "file contains <EXTREMELY-IMPORTANT> block"

# 7. The file contains the "Instruction Priority" hierarchy
assert_grep "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "Instruction Priority" "file has Instruction Priority section"

# 8. The file contains the Red Flags table
assert_grep "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "Red Flags" "file has Red Flags table"

# 9. The file contains OpenCode tool mapping
assert_grep "$PLUGIN_ROOT/skills/using-quiver/SKILL.md" "OpenCode" "file mentions OpenCode tool mapping"

# 10. The using-quiver symlink exists in .opencode/skills/ and resolves
assert_symlink_resolves "$PLUGIN_ROOT/.opencode/skills/using-quiver" ".opencode/skills/using-quiver"

# 11. The symlink points to the canonical skill
SYMLINK_TARGET=$(readlink "$PLUGIN_ROOT/.opencode/skills/using-quiver")
if [ "$SYMLINK_TARGET" = "../../skills/using-quiver/" ]; then
  pass "symlink target is ../../skills/using-quiver/"
else
  fail "symlink target is ../../skills/using-quiver/ (got: $SYMLINK_TARGET)"
fi

# 12. Content is readable via the symlink
if head -3 "$PLUGIN_ROOT/.opencode/skills/using-quiver/SKILL.md" | grep -q "name: using-quiver"; then
  pass "content readable via symlink"
else
  fail "content readable via symlink"
fi

# 13. Skill list count is 20 (19 existing + 1 new using-quiver)
SKILL_COUNT=$(find -L "$PLUGIN_ROOT/.opencode/skills/" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$SKILL_COUNT" -ge 20 ] 2>/dev/null; then
  pass "at least 20 skills available (found: $SKILL_COUNT)"
else
  fail "at least 20 skills available (found: $SKILL_COUNT)"
fi

# --- Summary ---

if [ $EXIT -eq 0 ]; then
  echo ""
  echo "All using-quiver bootstrap tests passed."
else
  echo ""
  echo "Some using-quiver bootstrap tests failed."
fi

exit $EXIT
