#!/bin/bash
# test-bootstrap-injection.sh
# Binds .opencode/bootstrap.md to the one thing that reads it,
# .opencode/plugins/quiver.js, and to the shape the plugin assumes.
#
# The bootstrap is an OpenCode overlay adapter (OR3 in .claude/rules/cli-overlay-rules.md):
# it carries the instruction-priority rule, the skill-check rule, the tool mapping, and
# the workflow chain that Claude Code gets from its own harness. It is NOT a skill --
# it lives outside skills/, carries no frontmatter, and the plugin reads it with fs
# rather than through OpenCode's skill loader.
#
# Two failures here are silent. If the plugin stops injecting the file, OpenCode sessions
# lose the skill-check rule entirely and behave like a stock agent -- no error, no log
# line, just skills that never fire. If it injects twice, the first user message carries
# the whole bootstrap twice on every agent step, which costs tokens on every turn and
# still looks like a working session. Section 3 pins both: the single unshift call site
# and the EXTREMELY_IMPORTANT dedup guard that keys off it.
#
# The frontmatter assertion runs in the other direction from the old skill test. The
# plugin no longer strips frontmatter, so a `---` block added to the top of bootstrap.md
# would be injected verbatim as YAML into the agent's context.
#
# Run directly: bash tests/opencode/test-bootstrap-injection.sh

set -u

EXIT=0
PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BOOTSTRAP="$PLUGIN_ROOT/.opencode/bootstrap.md"
PLUGIN_FILE="$PLUGIN_ROOT/.opencode/plugins/quiver.js"
OPENCODE_README="$PLUGIN_ROOT/.opencode/README.md"

# --- Helpers ---

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

assert_grep() {
  # $1 file, $2 pattern (fixed string), $3 label
  if grep -Fq "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

# Counts pattern occurrences, not matching lines. `grep -c .` on empty input
# prints 0 and exits 1; this file has no set -e.
count_matches() {
  grep -Fo "$2" "$1" 2>/dev/null | grep -c .
}

assert_once() {
  # $1 file, $2 pattern (fixed string), $3 label
  n="$(count_matches "$1" "$2")"
  if [ "$n" -eq 1 ]; then
    pass "$3 (exactly one site)"
  elif [ "$n" -eq 0 ]; then
    fail "$3 -- no occurrence found, so this assertion now tests nothing"
  else
    fail "$3 -- found $n occurrences, expected exactly 1"
  fi
}

echo ""
echo "=== 1. Preflight ==="
MISSING=0
for f in "$BOOTSTRAP" "$PLUGIN_FILE" "$OPENCODE_README"; do
  if [ -f "$f" ]; then
    pass "file exists: ${f#"$PLUGIN_ROOT"/}"
  else
    fail "file exists: ${f#"$PLUGIN_ROOT"/}"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit 1
fi

echo ""
echo "=== 2. The bootstrap carries what OpenCode needs ==="

# No frontmatter. The plugin injects the file verbatim; a `---` block at the top
# reaches the agent as raw YAML.
if head -1 "$BOOTSTRAP" | grep -q '^---$'; then
  fail "bootstrap.md starts with a YAML frontmatter delimiter -- the plugin no longer strips it, so it would be injected verbatim"
else
  pass "bootstrap.md carries no frontmatter"
fi

assert_grep "$BOOTSTRAP" "## Instruction Priority" "bootstrap states the instruction-priority hierarchy"
assert_grep "$BOOTSTRAP" "user instructions always take precedence" "bootstrap says the user's instructions win"
assert_grep "$BOOTSTRAP" "native \`skill\` tool" "bootstrap names OpenCode's native skill tool as the loading mechanism"
assert_grep "$BOOTSTRAP" "## OpenCode Tool Mapping" "bootstrap carries the OpenCode tool mapping"
assert_grep "$BOOTSTRAP" "\`todowrite\`" "tool mapping names todowrite"
assert_grep "$BOOTSTRAP" "\`apply_patch\`" "tool mapping names apply_patch"
assert_grep "$BOOTSTRAP" "## Quiver Workflow" "bootstrap carries the workflow chain"

# The chain is the one place the bootstrap names skills, so a skill removed from the tree
# leaves a dangling invocation here. Both of these already moved once: /handover grew its
# delete flags, and /design-verify was retired.
assert_grep "$BOOTSTRAP" "/handover --clear" "workflow chain names the handover clear flag"
if grep -Fq "design-verify" "$BOOTSTRAP"; then
  fail "bootstrap names /design-verify, which no longer exists in skills/"
else
  pass "bootstrap does not name the retired /design-verify"
fi

# Every /slash name in the workflow section must be a real skill directory. The scan is
# scoped to that section because it is the only place the bootstrap names actual skills --
# the section above it writes `/skill-name` as a placeholder, and a whole-file sweep reads
# that as a missing skill. Plugin skills live in skills/; the two maintainer skills are
# project-local under .claude/skills/ and are deliberately not chain steps, so a mention
# of either here would be wrong too.
CHAIN="$(awk '/^## Quiver Workflow/ { f=1 } f' "$BOOTSTRAP")"
if [ -z "$CHAIN" ]; then
  fail "no '## Quiver Workflow' section in bootstrap.md -- the chain assertions below scan nothing"
else
  UNKNOWN=""
  for name in $(printf '%s\n' "$CHAIN" | grep -Eo '/[a-z][a-z-]+' | sed 's#^/##' | sort -u); do
    [ -d "$PLUGIN_ROOT/skills/$name" ] || UNKNOWN="$UNKNOWN $name"
  done
  if [ -z "$UNKNOWN" ]; then
    pass "every /skill-name in the workflow chain is a real directory under skills/"
  else
    fail "workflow chain names skills that do not exist under skills/:$UNKNOWN"
  fi
fi

echo ""
echo "=== 3. The plugin injects it, once ==="

assert_once "$PLUGIN_FILE" "path.join(__dirname, '..', 'bootstrap.md')" "plugin resolves .opencode/bootstrap.md"
assert_grep "$PLUGIN_FILE" "experimental.chat.messages.transform" "plugin injects via the message transform hook"

# The single write into the message array. Two call sites would inject twice per step.
assert_once "$PLUGIN_FILE" "firstUser.parts.unshift(" "plugin has exactly one bootstrap injection site"

# The wrapper is load-bearing twice over: it marks priority for the agent, and its
# substring is what the dedup guard keys on. Changing one without the other re-enables
# double injection silently.
assert_grep "$PLUGIN_FILE" "<EXTREMELY_IMPORTANT>" "plugin wraps the bootstrap in EXTREMELY_IMPORTANT"
assert_grep "$PLUGIN_FILE" "p.text.includes('EXTREMELY_IMPORTANT')" "plugin's double-injection guard keys on the wrapper it writes"
assert_grep "$PLUGIN_FILE" "firstUser.parts.some" "plugin checks the first user message before injecting"

# The plugin reads the file verbatim now. A returned stripFrontmatter would mean the
# bootstrap grew frontmatter again and something started trimming it.
if grep -Fq "stripFrontmatter" "$PLUGIN_FILE"; then
  fail "plugin still carries stripFrontmatter -- bootstrap.md has no frontmatter, so the step is dead code or the file regrew one"
else
  pass "plugin no longer strips frontmatter"
fi

# The skills directory registration is separate from the bootstrap and must survive it.
assert_grep "$PLUGIN_FILE" "config.skills.paths.push(quiverSkillsDir)" "plugin still auto-registers the skills directory"

echo ""
echo "=== 4. The overlay is documented as one ==="

# OR3 in .claude/rules/cli-overlay-rules.md: an adapter of canonical content lives in
# its CLI's home and says so, or the next reader files it as a skill that went missing.
assert_grep "$OPENCODE_README" "bootstrap.md" ".opencode/README.md names the bootstrap file"
assert_grep "$OPENCODE_README" "OR3" ".opencode/README.md states the OR3 overlay-adapter classification"

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
