#!/bin/bash
# test-plugin-hooks.sh
# Validates the OpenCode plugin file (.opencode/plugins/quiver.js):
# - parses as valid JavaScript
# - exports the QuiverPlugin function
# - references all required hooks (config, experimental.chat.messages.transform,
#   experimental.session.compacting, session.created, tool.execute.before)
# - uses the EXTREMELY_IMPORTANT wrapper for the bootstrap

set -e

EXIT=0
PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_FILE="$PLUGIN_ROOT/.opencode/plugins/quiver.js"

# --- Helpers ---

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

assert_grep() {
  if grep -q "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

# --- Tests ---

echo "Testing OpenCode plugin (quiver.js)..."

# 1. Plugin file exists
if [ -f "$PLUGIN_FILE" ]; then
  pass "plugin file exists"
else
  fail "plugin file exists"
  exit 1
fi

# 2. Plugin file parses as valid JavaScript
if node --check "$PLUGIN_FILE" 2>/dev/null; then
  pass "plugin parses as valid JavaScript"
else
  fail "plugin parses as valid JavaScript"
  exit 1
fi

# 3. Old TypeScript plugin is removed
if [ -f "$PLUGIN_ROOT/.opencode/plugins/quiver.ts" ]; then
  fail "old .ts plugin is removed"
else
  pass "old .ts plugin is removed"
fi

# 4. Plugin exports QuiverPlugin
assert_grep "$PLUGIN_FILE" "export const QuiverPlugin" "plugin exports QuiverPlugin"

# 5. Plugin references the config hook
assert_grep "$PLUGIN_FILE" "config: async" "plugin has config hook"

# 6. Plugin references the transform hook
assert_grep "$PLUGIN_FILE" "experimental.chat.messages.transform" "plugin has experimental.chat.messages.transform hook"

# 7. Plugin references the compaction hook
assert_grep "$PLUGIN_FILE" "experimental.session.compacting" "plugin has experimental.session.compacting hook"

# 8. Plugin references the session.created hook
assert_grep "$PLUGIN_FILE" "session.created" "plugin has session.created hook"

# 9. Plugin references the tool.execute.before hook
assert_grep "$PLUGIN_FILE" "tool.execute.before" "plugin has tool.execute.before hook"

# 10. Plugin uses the EXTREMELY_IMPORTANT wrapper (load-bearing for both visual priority and dedup guard)
assert_grep "$PLUGIN_FILE" "EXTREMELY_IMPORTANT" "plugin uses EXTREMELY_IMPORTANT wrapper"

# 11. Plugin has double-injection guard
assert_grep "$PLUGIN_FILE" "firstUser.parts.some" "plugin has double-injection guard"

# 12. Plugin has module-level cache (_bootstrapCache)
assert_grep "$PLUGIN_FILE" "_bootstrapCache" "plugin has module-level cache"

# 13. Plugin uses fs.readFileSync to load the skill
assert_grep "$PLUGIN_FILE" "fs.readFileSync" "plugin reads skill file from disk"

# 14. Plugin pushes to config.skills.paths
assert_grep "$PLUGIN_FILE" "config.skills.paths" "plugin pushes to config.skills.paths"

# 15. Plugin guards against duplicate path entry
assert_grep "$PLUGIN_FILE" ".includes(quiverSkillsDir)" "plugin guards against duplicate path entry"

# 16. Plugin uses ctx.client.app.log for logging (not console.log)
if grep -q "client.app.log" "$PLUGIN_FILE"; then
  pass "plugin uses client.app.log for logging"
else
  fail "plugin uses client.app.log for logging"
fi

# 17. Root package.json exists
if [ -f "$PLUGIN_ROOT/package.json" ]; then
  pass "root package.json exists"
else
  fail "root package.json exists"
  exit 1
fi

# 18. Root package.json is valid JSON
if node -e "JSON.parse(require('fs').readFileSync('$PLUGIN_ROOT/package.json'))" 2>/dev/null; then
  pass "root package.json is valid JSON"
else
  fail "root package.json is valid JSON"
fi

# 19. Root package.json main field points to .js plugin
if grep -q '"main": ".opencode/plugins/quiver.js"' "$PLUGIN_ROOT/package.json"; then
  pass "root package.json main points to .opencode/plugins/quiver.js"
else
  fail "root package.json main points to .opencode/plugins/quiver.js"
fi

# 20. Root package.json has type: module
if grep -q '"type": "module"' "$PLUGIN_ROOT/package.json"; then
  pass "root package.json has type: module"
else
  fail "root package.json has type: module"
fi

# 21. Root package.json pins @opencode-ai/plugin
if grep -q '"@opencode-ai/plugin": "1.16.2"' "$PLUGIN_ROOT/package.json"; then
  pass "root package.json pins @opencode-ai/plugin to 1.16.2"
else
  fail "root package.json pins @opencode-ai/plugin to 1.16.2"
fi

# 22. .opencode/opencode.json does not reference the local plugin
if grep -q "quiver.ts" "$PLUGIN_ROOT/.opencode/opencode.json"; then
  fail ".opencode/opencode.json does not reference local quiver.ts"
else
  pass ".opencode/opencode.json does not reference local quiver.ts"
fi

# 23. .opencode/INSTALL.md exists
if [ -f "$PLUGIN_ROOT/.opencode/INSTALL.md" ]; then
  pass ".opencode/INSTALL.md exists"
else
  fail ".opencode/INSTALL.md exists"
fi

# 24. .opencode/README.md exists
if [ -f "$PLUGIN_ROOT/.opencode/README.md" ]; then
  pass ".opencode/README.md exists"
else
  fail ".opencode/README.md exists"
fi

# --- Summary ---

if [ $EXIT -eq 0 ]; then
  echo ""
  echo "All plugin hook tests passed."
else
  echo ""
  echo "Some plugin hook tests failed."
fi

exit $EXIT
