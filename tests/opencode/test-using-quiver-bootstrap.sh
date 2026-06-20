#!/bin/bash
# test-using-quiver-bootstrap.sh
# Validates the using-quiver meta-skill and its bootstrap injection setup.
# Verifies the file exists, has correct frontmatter, contains the load-bearing
# <SUBAGENT-STOP> and <EXTREMELY-IMPORTANT> blocks, and that the plugin's
# transform hook is wired correctly (no symlink required -- the plugin
# auto-registers the skills directory via the config hook).

set -e

EXIT=0
PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_FILE="$PLUGIN_ROOT/skills/using-quiver/SKILL.md"
PLUGIN_FILE="$PLUGIN_ROOT/.opencode/plugins/quiver.js"

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
assert_file_exists "$SKILL_FILE" "skills/using-quiver/SKILL.md"

# 2. The file has valid YAML frontmatter
if head -1 "$SKILL_FILE" | grep -q "^---$"; then
  pass "file starts with YAML frontmatter delimiter"
else
  fail "file starts with YAML frontmatter delimiter"
fi

# 3. Frontmatter contains name field
assert_grep "$SKILL_FILE" "^name: using-quiver" "frontmatter has name: using-quiver"

# 4. Frontmatter contains description field
assert_grep "$SKILL_FILE" "^description:" "frontmatter has description field"

# 5. Frontmatter contains when-to-use field (R10 hard rule)
assert_grep "$SKILL_FILE" "when-to-use:" "frontmatter has when-to-use field"

# 6. Frontmatter disables model invocation (skill is auto-injected by plugin)
assert_grep "$SKILL_FILE" "disable-model-invocation: true" "frontmatter disables model invocation"

# 7. The file contains a <SUBAGENT-STOP> block (load-bearing for subagent correctness)
assert_grep "$SKILL_FILE" "<SUBAGENT-STOP>" "file contains <SUBAGENT-STOP> block"

# 8. The file contains an <EXTREMELY-IMPORTANT> block
assert_grep "$SKILL_FILE" "<EXTREMELY-IMPORTANT>" "file contains <EXTREMELY-IMPORTANT> block"

# 9. The file contains the "Instruction Priority" hierarchy
assert_grep "$SKILL_FILE" "Instruction Priority" "file has Instruction Priority section"

# 10. The file contains the Red Flags table
assert_grep "$SKILL_FILE" "Red Flags" "file has Red Flags table"

# 11. The file contains OpenCode tool mapping (for users who read the skill directly)
assert_grep "$SKILL_FILE" "OpenCode" "file mentions OpenCode tool mapping"

# 12. The file ends with a ## Test Plan section (CLAUDE.md rule)
assert_grep "$SKILL_FILE" "^## Test Plan" "file has Test Plan section"

# 13. The plugin registers the skills directory via the config hook
#     (replaces the old .opencode/skills/using-quiver symlink mechanism)
assert_grep "$PLUGIN_FILE" "config.skills.paths.push(quiverSkillsDir)" "plugin auto-registers skills directory via config hook"

# 14. The plugin injects bootstrap via experimental.chat.messages.transform
assert_grep "$PLUGIN_FILE" "experimental.chat.messages.transform" "plugin injects bootstrap via message transform hook"

# 15. The plugin's bootstrap uses the EXTREMELY_IMPORTANT wrapper (load-bearing for both visual priority and dedup guard)
assert_grep "$PLUGIN_FILE" "EXTREMELY_IMPORTANT" "plugin bootstrap uses EXTREMELY_IMPORTANT wrapper"

# 16. The plugin has the double-injection guard (keyed on EXTREMELY_IMPORTANT substring)
assert_grep "$PLUGIN_FILE" "firstUser.parts.some" "plugin has double-injection guard"

# 17. .opencode/skills/ does NOT need to exist -- the plugin auto-registers skills via config.skills.paths
if [ -d "$PLUGIN_ROOT/.opencode/skills" ]; then
  # If it does exist, that's fine too (legacy symlinks from old install).
  pass ".opencode/skills/ optional (legacy symlinks may remain)"
else
  pass ".opencode/skills/ not required (plugin auto-registers skills)"
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
