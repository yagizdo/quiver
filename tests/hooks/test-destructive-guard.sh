#!/bin/bash
# test-destructive-guard.sh
# Guards the destructive-command classifier:
#   producer  hooks/scripts/pre-tool-use-guard.sh -- classifies a Bash command into deny / ask / silence
#   consumer  Claude Code's PreToolUse hook contract -- reads permissionDecision off stdout
#
# Each case builds a real PreToolUse payload, JSON-escaping the command exactly the way the CLI
# does, and pipes it to the script. Feeding an unescaped command would test a payload Claude Code
# never sends: the spike in .claude/plans/2026-08-20-destructive-command-guard-plan.md recorded
# that `echo "rm -rf /"` arrives as "echo \"rm -rf /\"", and that escaping is load-bearing for
# the quoted false-positive cases.
#
# A silent case asserts empty stdout AND exit 0. A hook that exits nonzero on an ordinary command
# breaks every Bash call in the session, so the exit code is asserted, not assumed.
#
# Run directly: bash tests/hooks/test-destructive-guard.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/hooks/scripts/pre-tool-use-guard.sh"

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# Escape a command string for embedding in a JSON string literal: backslash first, then quote.
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Feed a raw payload to the script. Sets OUT and CODE.
feed() {
  OUT="$(printf '%s' "$1" | bash "$SCRIPT" 2>/dev/null)"
  CODE=$?
}

# run_case <command> <deny|ask|silent>
run_case() {
  cmd="$1"
  expect="$2"
  esc="$(json_escape "$cmd")"
  feed "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$esc\",\"description\":\"test case\"},\"tool_use_id\":\"toolu_test\"}"
  assert_decision "$cmd" "$expect"
}

# assert_decision <label> <deny|ask|silent> -- reads OUT and CODE.
assert_decision() {
  label="$1"
  expect="$2"
  if [ "$CODE" -ne 0 ]; then
    fail "[$label] expected $expect, but the script exited $CODE (a hook must always exit 0)"
    return
  fi
  case "$expect" in
    silent)
      if [ -z "$OUT" ]; then
        pass "[$label] silent"
      else
        fail "[$label] expected silence, got: $OUT"
      fi
      ;;
    deny|ask)
      case "$OUT" in
        *"\"permissionDecision\":\"$expect\""*)
          pass "[$label] $expect"
          ;;
        "")
          fail "[$label] expected $expect, got no output"
          ;;
        *)
          fail "[$label] expected $expect, got: $OUT"
          ;;
      esac
      ;;
  esac
}

echo ""
echo "=== 1. Preflight ==="
if [ ! -f "$SCRIPT" ]; then
  fail "missing $SCRIPT -- every classification case below will fail."
else
  pass "classifier present at hooks/scripts/pre-tool-use-guard.sh"
  if bash -n "$SCRIPT" 2>/dev/null; then
    pass "classifier parses (bash -n)"
  else
    fail "classifier has a syntax error (bash -n) -- fix before reading the cases below."
  fi
fi

echo ""
echo "=== 2. Deny tier: irreversible, never legitimate ==="
run_case 'rm -rf /'          deny
run_case 'rm -fr /'          deny
run_case 'sudo rm -rf /'     deny
run_case 'rm -rf ~'          deny
run_case 'rm -rf $HOME'      deny
run_case 'rm -rf ${HOME}'    deny
run_case 'foo $(rm -rf /)'   deny

echo ""
echo "=== 3. Safe-target allowlist: regenerable directories stay silent ==="
run_case 'rm -rf node_modules' silent
run_case 'rm -rf ./dist'       silent
run_case 'rm -rf build/'       silent

echo ""
echo "=== 4. rm ask tier: recoverable but destructive ==="
run_case 'rm -rf src'    ask
run_case 'rm -rf .'      ask
run_case 'rm -r -f data' ask

echo ""
echo "=== 5. git ask tier: history and working-tree loss ==="
run_case 'git push --force origin main' ask
run_case 'git push -f'                  ask
run_case 'git push --force-with-lease'  ask
run_case 'git reset --hard HEAD~1'      ask
run_case 'git clean -fdx'               ask
run_case 'git checkout .'               ask
run_case 'git branch -D feature'        ask

echo ""
echo "=== 6. Chained commands: classify every segment, not just the first ==="
run_case 'npm test && rm -rf tmp' ask

echo ""
echo "=== 7. False-positive traps: the pattern appears as data, not as a command ==="
run_case 'grep -rn "rm -rf /" docs/' silent
run_case 'echo "rm -rf /"'           silent
run_case 'git status'                silent

echo ""
echo "=== 8. Malformed input: never break the session ==="
feed ""
assert_decision "empty stdin" silent

feed '{"tool_name":"Bash","tool_input":{"command":'
assert_decision "malformed JSON" silent

feed '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"rm -rf /"}}'
assert_decision "tool_name is Write, not Bash" silent

echo ""
echo "=== 9. ASCII-only (R8) ==="
for f in "$SCRIPT" "$REPO_ROOT/tests/hooks/test-destructive-guard.sh"; do
  if [ ! -f "$f" ]; then
    continue
  fi
  # BSD grep has no \x escapes, so a bracket range is not portable here. Delete every ASCII
  # byte and measure what survives: nonzero means a non-ASCII byte is present.
  if [ "$(LC_ALL=C tr -d '\000-\177' < "$f" | wc -c | tr -d ' ')" != "0" ]; then
    fail "$(basename "$f") contains non-ASCII bytes"
  else
    pass "$(basename "$f") is ASCII-only"
  fi
done

echo ""
echo "=== 10. Packaging: the guard must actually ship ==="
# hooks.json registers this script by path. If .gitignore swallows it, the plugin installs with a
# PreToolUse hook pointing at a file that is not there, and every Bash call in the session pays for
# a hook that cannot run. A bare `scripts/` rule in .gitignore did exactly this once; the rule is
# anchored to /scripts/ now, and this case is what keeps it anchored.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$REPO_ROOT" check-ignore -q "$SCRIPT" 2>/dev/null; then
    fail "hooks/scripts/pre-tool-use-guard.sh is gitignored -- hooks.json would register a path that does not ship"
  else
    pass "hooks/scripts/pre-tool-use-guard.sh is not gitignored"
  fi
else
  pass "not a git repository -- packaging check skipped"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
