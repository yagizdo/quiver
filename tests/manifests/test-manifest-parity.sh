#!/bin/bash
# test-manifest-parity.sh
# Binds the shipped CLI manifests to each other. The local release helper lives in
# gitignored scripts/ and cannot be the enforcement point for a value that ships;
# this test runs in CI and is.
#
# Asserts:
#   1. .claude-plugin, .cursor-plugin and .codex-plugin carry the same version.
#   2. The Cursor agents array lists exactly the Claude agents array.
#   3. The README version badge matches .claude-plugin/plugin.json.
#
# gemini-extension.json is deliberately out of scope. Google retired Gemini CLI on
# 2026-06-18 and the extension only installs under a paid Code Assist license, so
# its version is a legacy artifact rather than a shipped install path. Adding it
# here would assert a number nobody can act on.
#
# Parsing is grep and sed, not jq -- jq is not a Quiver dependency, and a test that
# needs a tool the user must install first has the problem it exists to catch.
#
# Run directly: bash tests/manifests/test-manifest-parity.sh

set -u

EXIT=0
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"

CLAUDE="$REPO_ROOT/.claude-plugin/plugin.json"
CURSOR="$REPO_ROOT/.cursor-plugin/plugin.json"
CODEX="$REPO_ROOT/.codex-plugin/plugin.json"
README="$REPO_ROOT/README.md"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# First "version": "x.y.z" in the file.
version_of() {
  grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" \
    | head -1 \
    | sed 's/.*"\([^"]*\)"$/\1/'
}

# Every "./agents/..." entry, in file order.
agents_of() {
  grep -o '"\./agents/[^"]*"' "$1" | tr -d '"'
}

echo "Testing manifest parity..."

for f in "$CLAUDE" "$CURSOR" "$CODEX" "$README"; do
  if [ ! -f "$f" ]; then
    fail "missing file: ${f#"$REPO_ROOT"/}"
    echo ""
    echo "Some manifest parity tests failed."
    exit 1
  fi
done
pass "all shipped manifests and README exist"

# 1. Version agreement

CLAUDE_V="$(version_of "$CLAUDE")"
CURSOR_V="$(version_of "$CURSOR")"
CODEX_V="$(version_of "$CODEX")"

if [ -n "$CLAUDE_V" ]; then
  pass ".claude-plugin/plugin.json declares a version ($CLAUDE_V)"
else
  fail ".claude-plugin/plugin.json declares a version"
fi

if [ "$CURSOR_V" = "$CLAUDE_V" ]; then
  pass ".cursor-plugin/plugin.json version matches ($CURSOR_V)"
else
  fail ".cursor-plugin/plugin.json version matches (got '$CURSOR_V', expected '$CLAUDE_V')"
fi

if [ "$CODEX_V" = "$CLAUDE_V" ]; then
  pass ".codex-plugin/plugin.json version matches ($CODEX_V)"
else
  fail ".codex-plugin/plugin.json version matches (got '$CODEX_V', expected '$CLAUDE_V')"
fi

# 2. Cursor agents array equals the Claude agents array

CLAUDE_AGENTS="$(agents_of "$CLAUDE")"
CURSOR_AGENTS="$(agents_of "$CURSOR")"
CLAUDE_COUNT="$(printf '%s' "$CLAUDE_AGENTS" | grep -c .)"
CURSOR_COUNT="$(printf '%s' "$CURSOR_AGENTS" | grep -c .)"

# Every file under agents/ must be registered, or a CLI silently ships fewer.
DISK_COUNT="$(find "$REPO_ROOT/agents" -name '*.md' | grep -c .)"

if [ "$CLAUDE_COUNT" -eq "$DISK_COUNT" ]; then
  pass ".claude-plugin registers every agent file on disk ($DISK_COUNT)"
else
  fail ".claude-plugin registers every agent file on disk (registered $CLAUDE_COUNT, on disk $DISK_COUNT)"
fi

if [ "$CURSOR_AGENTS" = "$CLAUDE_AGENTS" ]; then
  pass ".cursor-plugin agents array equals the Claude agents array ($CURSOR_COUNT entries)"
else
  fail ".cursor-plugin agents array equals the Claude agents array (Cursor $CURSOR_COUNT, Claude $CLAUDE_COUNT)"
  diff <(printf '%s\n' "$CLAUDE_AGENTS") <(printf '%s\n' "$CURSOR_AGENTS") \
    | sed 's/^/    /'
fi

# 3. README version badge

BADGE_V="$(grep -o 'img\.shields\.io/badge/version-[^-]*-' "$README" | head -1 | sed 's|.*version-\(.*\)-$|\1|')"

if [ "$BADGE_V" = "$CLAUDE_V" ]; then
  pass "README version badge matches ($BADGE_V)"
else
  fail "README version badge matches (got '$BADGE_V', expected '$CLAUDE_V')"
fi

# --- Summary ---

if [ $EXIT -eq 0 ]; then
  echo ""
  echo "All manifest parity tests passed."
else
  echo ""
  echo "Some manifest parity tests failed."
fi

exit $EXIT
