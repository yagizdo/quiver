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
# the quoted false-positive cases. json_escape below encodes newlines as \n for the same reason --
# a raw newline in a JSON string literal is invalid JSON, so a harness that left them raw could
# not express a multi-line command at all.
#
# A silent case asserts zero bytes of stdout AND exit 0. Both halves are measured, not assumed:
# stdout is captured through a file rather than a command substitution, because $( ) strips
# trailing newlines and would let a script that prints a blank line pass as silent. A hook that
# exits nonzero on an ordinary command breaks every Bash call in the session.
#
# Run directly: bash tests/hooks/test-destructive-guard.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/hooks/scripts/pre-tool-use-guard.sh"

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT
OUTFILE="$TMPDIR_TEST/out"

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# Escape a command string for embedding in a JSON string literal: backslash first, then quote,
# then fold the line breaks into \n so a multi-line command stays valid JSON.
json_escape() {
  printf '%s' "$1" \
    | sed 's/\\/\\\\/g; s/"/\\"/g' \
    | awk '{printf "%s%s", sep, $0; sep="\\n"}'
}

# Render a command as a single-line test label. A multi-line command would otherwise break the
# PASS/FAIL column alignment and make a failure hard to read.
label_of() {
  printf '%s' "$1" | tr '\n' '~'
}

# Feed a raw payload to the script. Sets OUT, OUT_BYTES and CODE.
feed() {
  printf '%s' "$1" | bash "$SCRIPT" > "$OUTFILE" 2>/dev/null
  CODE=$?
  OUT="$(cat "$OUTFILE")"
  OUT_BYTES="$(wc -c < "$OUTFILE" | tr -d ' ')"
}

# payload_for <command> -- the exact JSON the CLI sends for a Bash tool call.
payload_for() {
  esc="$(json_escape "$1")"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test case"},"tool_use_id":"toolu_test"}' "$esc"
}

# run_case <command> <deny|ask|silent>
run_case() {
  feed "$(payload_for "$1")"
  assert_decision "$(label_of "$1")" "$2"
}

# run_reason <command> <deny|ask> <substring the reason must contain>
# The reason string is the guard's entire marginal value over the prompt the CLI already shows,
# and it interpolates a target lifted out of the command, so it is asserted rather than trusted.
run_reason() {
  feed "$(payload_for "$1")"
  lbl="$(label_of "$1")"
  assert_decision "$lbl" "$2"
  reason="$(printf '%s' "$OUT" | sed -n 's/.*"permissionDecisionReason":"\([^"]*\)".*/\1/p')"
  case "$reason" in
    *"$3"*) pass "[$lbl] reason names '$3'" ;;
    "")     fail "[$lbl] reason is empty -- expected it to name '$3'" ;;
    *)      fail "[$lbl] reason does not name '$3', got: $reason" ;;
  esac
}

# run_reason_excludes <command> <deny|ask> <substring the reason must NOT contain>
run_reason_excludes() {
  feed "$(payload_for "$1")"
  lbl="$(label_of "$1")"
  assert_decision "$lbl" "$2"
  reason="$(printf '%s' "$OUT" | sed -n 's/.*"permissionDecisionReason":"\([^"]*\)".*/\1/p')"
  case "$reason" in
    *"$3"*) fail "[$lbl] reason should not name '$3', got: $reason" ;;
    *)      pass "[$lbl] reason omits '$3'" ;;
  esac
}

# assert_decision <label> <deny|ask|silent> -- reads OUT, OUT_BYTES and CODE.
assert_decision() {
  label="$1"
  expect="$2"
  if [ "$CODE" -ne 0 ]; then
    fail "[$label] expected $expect, but the script exited $CODE (a hook must always exit 0)"
    return
  fi
  case "$expect" in
    silent)
      if [ "$OUT_BYTES" -eq 0 ]; then
        pass "[$label] silent"
      else
        fail "[$label] expected silence, got $OUT_BYTES bytes: $OUT"
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
run_case 'rm -rf ~/'         deny
run_case 'rm -rf $HOME'      deny
run_case 'rm -rf $HOME/'     deny
run_case 'rm -rf ${HOME}'    deny
run_case 'rm -rf ${HOME}/'   deny
run_case 'foo $(rm -rf /)'   deny

echo ""
echo "=== 2b. Deny tier: the glob spellings erase exactly the same thing ==="
run_case 'rm -rf /*'         deny
run_case 'rm -rf ~/*'        deny
run_case 'rm -rf $HOME/*'    deny
run_case 'rm -rf ${HOME}/*'  deny

echo ""
echo "=== 2c. Deny tier: quoting the target does not downgrade it ==="
# Quoting "$HOME" is the spelling shellcheck asks for, so the guard must see through it.
run_case 'rm -rf "/"'        deny
run_case 'rm -rf "$HOME"'    deny
run_case "rm -rf '/'"        deny
run_case "rm -rf '\$HOME'"   deny

echo ""
echo "=== 2d. Deny tier: sudo options sit between sudo and the command ==="
run_case 'sudo -E rm -rf /'            deny
run_case 'sudo -u root rm -rf /'       deny
run_case 'sudo --preserve-env rm -rf /' deny

echo ""
echo "=== 3. Safe-target allowlist: regenerable directories stay silent ==="
run_case 'rm -rf node_modules'   silent
run_case 'rm -rf ./dist'         silent
run_case 'rm -rf build/'         silent
run_case 'rm -rf "node_modules"' silent

echo ""
echo "=== 4. rm ask tier: recoverable but destructive ==="
run_case 'rm -rf src'    ask
run_case 'rm -rf .'      ask
run_case 'rm -r -f data' ask

echo ""
echo "=== 5. git ask tier: history and working-tree loss ==="
run_case 'git push --force origin main'   ask
run_case 'git push -f'                    ask
run_case 'git push --force-with-lease'    ask
run_case 'git push --force-with-lease=main:abc123' ask
run_case 'git push --force-if-includes'   ask
run_case 'git reset --hard HEAD~1'        ask
run_case 'git checkout .'                 ask
run_case 'git restore .'                  ask

echo ""
echo "=== 5b. git clean: the f and d bits accumulate across arguments ==="
# `git clean -f -d` is the spelling git's own hint text prints, so the split form must reach the
# same prompt as the cluster form. --dry-run deletes nothing and must not.
run_case 'git clean -fdx'        ask
run_case 'git clean -f -d'       ask
run_case 'git clean -d -f'       ask
run_case 'git clean --force -d'  ask
run_case 'git clean -f'          silent
run_case 'git clean --dry-run -f' silent

echo ""
echo "=== 5c. git branch: -D is shorthand for --delete --force ==="
run_case 'git branch -D feature'               ask
run_case 'git branch -d -f feature'            ask
run_case 'git branch --delete --force feature' ask
run_case 'git branch -d feature'               silent
run_case 'git branch --delete feature'         silent

echo ""
echo "=== 6. Chained commands: classify every segment, not just the first ==="
run_case 'npm test && rm -rf tmp' ask

echo ""
echo "=== 6b. A quoted argument must not blank the classifier for what follows ==="
# The command arrives JSON-escaped, so a double quote anywhere earlier once truncated extraction
# and silenced everything after it. `git commit -m "msg" && git push --force` is the shape
# skills/commit/SKILL.md emits, so this is an everyday command, not an evasion.
run_case 'echo "done" && rm -rf /'                deny
run_case 'cd "my dir" && rm -rf /'                deny
run_case 'echo "start"; rm -rf /'                 deny
run_case 'git commit -m "msg" && git push --force' ask
run_case 'echo "done" && git reset --hard'        ask
run_case 'echo "done" && git clean -fdx'          ask
run_case 'echo "done" && git branch -D main'      ask
run_case 'echo "done" && git checkout .'          ask

echo ""
echo "=== 6c. Multi-line commands: a newline is a separator too ==="
# A newline arrives as the two characters \ n. Until the classifier decoded them, a multi-line
# script collapsed into one segment and only its first line was ever classified.
run_case 'npm test
rm -rf /' deny
run_case 'cd /tmp
sudo rm -rf /' deny
run_case 'cd /tmp
rm -rf ~' deny
run_case 'git add -A
git commit -m x
git push --force' ask
run_case 'rm -rf /
echo done' deny
run_case 'npm run build
npm test' silent

echo ""
echo "=== 7. False-positive traps: the pattern appears as data, not as a command ==="
run_case 'grep -rn "rm -rf /" docs/'      silent
run_case 'echo "rm -rf /"'                silent
run_case 'git status'                     silent
run_case 'echo "a;b"'                     silent
run_case 'sed -i "" "s/rm -rf //" f.txt'  silent
# A heredoc body is written, not run. Classification stops at the opener, so a documentation
# edit that quotes a destructive command on its own line is never denied.
run_case 'cat <<EOF > notes.md
rm -rf /
EOF'                                      silent
run_case 'cat <<EOF > notes.md
git push --force
EOF'                                      silent
# ...but anything before the opener still classifies.
run_case 'rm -rf / && cat <<EOF
hello
EOF'                                      deny
# A multi-line double-quoted argument is text being printed, not an argument list, and is dropped
# for the same reason a heredoc body is. Without this the second line of a sentence *about* a
# destructive command is classified as that command -- and the deny tier cannot be overridden.
run_case 'echo "line one
rm -rf src"'                              silent
run_case 'echo "note:
rm -rf / is bad"'                         silent
run_case 'echo "warning:
git push --force loses commits"'          silent
# A single-line quoted span is still an argument list, so its target survives.
run_case 'rm -rf "$HOME"'                 deny
run_case 'echo "done" && rm -rf /'        deny

echo ""
echo "=== 8. Malformed input: never break the session ==="
feed ""
assert_decision "empty stdin" silent

feed '{"tool_name":"Bash","tool_input":{"command":'
assert_decision "malformed JSON" silent

feed '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"rm -rf /"}}'
assert_decision "tool_name is Write, not Bash" silent

echo ""
echo "=== 8b. Tier precedence: deny wins across segments, first ask wins ==="
# The deferred-ASK_REASON design at the bottom of the classifier exists only so that a deny found
# in a later segment still beats an ask found in an earlier one. Without a case that orders them
# that way, replacing set_ask with an immediate emit would pass every other test in this file.
run_case 'rm -rf src && rm -rf /'  deny
run_case 'git push --force && rm -rf /' deny
run_reason 'rm -rf src && git push --force' ask 'PERMANENT DELETE -- src'

echo ""
echo "=== 8c. Reason text: the prompt must name what is about to be lost ==="
# A tier with an empty or wrong target tells the user nothing the CLI's own prompt does not.
run_reason 'rm -rf /'                deny 'REFUSED, NOT ASKED -- recursive force delete of /.'
run_reason 'rm -rf "$HOME"'          deny 'REFUSED, NOT ASKED -- recursive force delete of $HOME.'
run_reason 'rm -rf /*'               deny 'REFUSED, NOT ASKED -- recursive force delete of /*.'
run_reason 'rm -rf src'              ask  'PERMANENT DELETE -- src and'
run_reason 'rm -rf node_modules src' ask  'PERMANENT DELETE -- src and'
run_reason_excludes 'rm -rf node_modules src' ask 'node_modules'
run_reason 'git push --force'        ask  'REWRITES REMOTE HISTORY --'
run_reason 'git reset --hard'        ask  'DISCARDS UNCOMMITTED WORK --'
run_reason 'git clean -f -d'         ask  'DELETES UNTRACKED FILES --'
run_reason 'git branch -D feature'   ask  'FORCE-DELETES A BRANCH --'
run_reason 'git checkout .'          ask  'DISCARDS UNCOMMITTED WORK -- every change in the working tree, overwritten'

echo ""
echo "=== 8d. Output is valid JSON the CLI can parse ==="
feed "$(payload_for 'rm -rf "my dir"')"
if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  pass "a target carrying quotes still emits parseable JSON"
else
  fail "a target carrying quotes emitted unparseable JSON: $OUT"
fi

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
echo "=== 11. Budget: the hook runs before every Bash call ==="
# hooks/hooks.json sets "timeout": 5. The rm branch is the only one whose cost scales with the
# command, so a large delete is the shape that can cross it.
BIG="rm -rf$(awk 'BEGIN{for(i=0;i<1000;i++) printf " f%d", i}')"
START="$(date +%s)"
feed "$(payload_for "$BIG")"
ELAPSED="$(( $(date +%s) - START ))"
if [ "$CODE" -ne 0 ]; then
  fail "1000-target delete exited $CODE"
elif [ "$ELAPSED" -ge 5 ]; then
  fail "1000-target delete took ${ELAPSED}s -- at or over the 5s timeout in hooks/hooks.json"
else
  pass "1000-target delete classified in under 5s (${ELAPSED}s)"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
