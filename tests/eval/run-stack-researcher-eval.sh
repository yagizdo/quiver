#!/usr/bin/env bash
#
# Behavior eval for the stack-researcher agent: handed three pre-build
# questions in an empty directory, does it return one block per question with
# a status from its grammar, the documented Node default for Q1, the live
# registry range for Q2, and needs-measurement for the Q3 fact it cannot
# measure here?
#
# Costs real money (capped at 5 USD per run). Not named test-*.sh on purpose --
# tests/run-all.sh globs test-*.sh, so neither the local runner nor CI can
# pick this up by accident. tests/eval/test-stack-researcher-eval.sh runs this
# harness against fake claude, npm and adb executables, for free.
#
#   bash tests/eval/run-stack-researcher-eval.sh [--keep]
#
# Refuses to run while `adb devices` lists a device or a running emulator. The
# input tells the agent no device is attached, and the Q3 check expects
# needs-measurement; with a device attached the agent may run the command
# itself and answer from a measurement, which is correct behavior the check
# would fail.
#
# The Q2 check compares against the typescript-eslint peer range read from the
# npm registry at run time, not a pinned string: the range moves with every
# typescript-eslint release, and a pinned copy would fail a correct answer.
#
# A failed check is a measurement of the agent. Fix
# agents/research/stack-researcher.md, never the check, until it passes.
#
set -uo pipefail

keep=false
[ "${1:-}" = "--keep" ] && keep=true

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../.." && pwd -P)

if command -v adb >/dev/null 2>&1; then
  attached=$(adb devices 2>/dev/null | awk 'NF && $1 !~ /^\*/ && !/^List of devices attached/')
  if [ -n "$attached" ]; then
    echo "ABORT: adb lists an attached Android device:"
    echo "$attached" | sed 's/^/  /'
    echo "Q3 expects needs-measurement because the agent is told no device is attached."
    echo "Disconnect the device or stop the emulator, then run again."
    exit 1
  fi
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "ABORT: npm is not on PATH. The Q2 check reads the live typescript-eslint peer range with npm view."
  exit 1
fi

for tool in claude python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ABORT: $tool is not on PATH."
    exit 1
  fi
done

peer_range=$(npm view typescript-eslint@latest peerDependencies.typescript 2>/dev/null)
ts_latest=$(npm view typescript dist-tags.latest 2>/dev/null)
if [ -z "$peer_range" ] || [ -z "$ts_latest" ]; then
  echo "ABORT: npm view returned nothing. Check the network and the npm registry, then run again."
  exit 1
fi
echo "Registry: typescript-eslint@latest peer range for typescript is '$peer_range'; typescript latest is $ts_latest"

tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)
# The agent's project root. It must stay empty, so the run's own files go in
# $tmp beside it, not inside it.
project="$tmp/project"
mkdir "$project"

cleanup_note() {
  if [ "$keep" = true ]; then
    echo "Workspace kept: $tmp"
  else
    rm -rf "$tmp"
  fi
}

fail_keep() {
  echo "Workspace kept for inspection: $tmp"
  exit 1
}

cost_line() {
  python3 - "$tmp/run.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
turns = d.get("num_turns", "?")
secs = "%.1fs" % (d["duration_ms"] / 1000.0) if "duration_ms" in d else "?s"
usd = "$%.4f" % d["total_cost_usd"] if "total_cost_usd" in d else "$?"
print("Cost: %s turns, %s, %s" % (turns, secs, usd))
PY
}

cd "$project"

# dontAsk still lets file reads inside the working directory run unprompted,
# so the working directory must be the empty throwaway root. Refuse anywhere
# else.
cwd=$(pwd -P)
case "$cwd" in
  "$tmp"/*) : ;;
  *) echo "ABORT: cwd $cwd is not under the temp dir $tmp"; exit 1 ;;
esac

# Quoted delimiter: the backticks in the questions reach the model as text.
IFS= read -r -d '' PROBE <<'EOF' || true
Dispatch exactly one subagent: call the Agent tool with subagent_type="quiver:stack-researcher" and pass it the block between BEGIN and END below as its prompt, unchanged. Do not research anything yourself. When the agent returns, print its report verbatim and nothing else: no preamble, no summary, no code fence.

BEGIN
Objective: build a Node.js CLI in TypeScript that captures an Android emulator screenshot through adb and lints its source.
Stack: TypeScript 7 on Node.js 22, Node standard library only; adb (Android platform-tools) as an external tool
Environment: macOS host; target is an Android emulator on API 36, not attached to this machine
Project root: @PROJECT_ROOT@ (empty)
Constraints:
- no runtime dependencies beyond the Node standard library
Questions:
1. How should the CLI read the PNG that `adb exec-out screencap -p` writes to stdout from Node child_process, and does a default limit stop it? -- settled by: the API, the option values and the default limit with its source
2. Which linter fits a TypeScript 7 project: typescript-eslint or oxlint? -- settled by: whether each supports TypeScript 7, from registry metadata or the project's support policy
3. What is the exact format of the inset lines `adb shell dumpsys window displays` prints on Android API 36? -- settled by: the literal line format on that API level
END
EOF
PROBE=${PROBE//@PROJECT_ROOT@/$project}

# The agent reads open-web pages, and a page can carry instructions. dontAsk
# denies every call outside this list instead of running it. curl and gh stay
# off it: curl can post a local file to any host and gh api can call a write
# endpoint with the maintainer's token. The agent reads pages with WebFetch
# instead and names the denied curl in its Gaps section.
# dontAsk also runs whatever the loaded settings files allow, so user settings
# stay out: a maintainer's own allow rules, such as Bash(curl *) or a wildcard
# around a script name, would otherwise widen this list. Project and local
# settings come from the empty temp root and add nothing.
echo "Running the stack-researcher agent (one dispatch, three questions)..."
claude -p "$PROBE" \
  --plugin-dir "$repo_root" \
  --setting-sources project,local \
  --max-budget-usd 5 \
  --permission-mode dontAsk \
  --allowedTools "Agent" "WebSearch" "WebFetch" "mcp__plugin_quiver_context7" \
    "Bash(npm view *)" \
  --output-format json > "$tmp/run.json"
claude_exit=$?

report="$tmp/report.md"
python3 - "$tmp/run.json" "$report" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
open(sys.argv[2], "w").write(str(d.get("result") or ""))
PY

if [ ! -s "$report" ]; then
  echo
  echo "HARNESS BLOCKED: the run returned no report (claude exit $claude_exit)."
  python3 - "$tmp/run.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as exc:
    print("  could not parse run.json:", exc)
    sys.exit(0)
for k in ("type", "subtype", "is_error"):
    if k in d:
        print("  %s: %s" % (k, d[k]))
PY
  cost_line
  fail_keep
fi

echo
echo "----- report -----"
cat "$report"
echo
echo "----- end of report -----"

# One file per question block: from its "### Q<n>" heading to the next heading.
# Scoped on the number alone, so a malformed status still leaves the content
# checks something to read.
for n in 1 2 3; do
  awk -v n="$n" '
    $0 ~ "^### Q" n "([^0-9]|$)" { inside = 1; print; next }
    inside && /^##/ { exit }
    inside { print }
  ' "$report" > "$tmp/q$n.txt"
done

statuses='answered|narrowed|open|needs-measurement|premise-false'
# 1 MiB written as 1024 * 1024, 1048576, 1 MiB or 1 MB. A product such as
# 64 * 1024 * 1024, or a size like 51 MB, contains the same characters and is
# not the default, so neighbouring digits and multiplications do not count.
# Parentheses around the pair are looked through, so 64 * (1024 * 1024) is
# still a product while (1024 * 1024 bytes) still counts.
one_mib='(^|[^*0-9 (])[ ]*\(?[ ]*1024[ ]*\*[ ]*1024[ ]*\)?[ ]*([^ *0-9)]|$)|(^|[^0-9.,])1,?048,?576([^0-9]|$)|(^|[^0-9.,])1 ?Mi?B([^A-Za-z]|$)'

passes=0
fails=0

echo
printf '%-6s %-34s %s\n' "RESULT" "CHECK" "EVIDENCE"
printf '%-6s %-34s %s\n' "------" "----------------------------------" "--------"

record() {
  # record <PASS|FAIL> <check> <evidence>
  if [ "$1" = PASS ]; then
    passes=$((passes + 1))
  else
    fails=$((fails + 1))
  fi
  printf '%-6s %-34s %s\n' "$1" "$2" "$(printf '%s' "$3" | head -1 | cut -c1-90)"
}

# check_block <n> <check> <grep flags> <pattern>
check_block() {
  hit=$(grep "$3" -m1 -- "$4" "$tmp/q$1.txt" || true)
  if [ -n "$hit" ]; then
    record PASS "$2" "$hit"
  else
    record FAIL "$2" "not found in the Q$1 block"
  fi
}

for n in 1 2 3; do
  heading=$(grep -Em1 "^### Q$n([^0-9]|$)" "$tmp/q$n.txt" || true)
  if printf '%s\n' "$heading" | grep -Eq "^### Q$n -- ($statuses)[[:space:]]*$"; then
    record PASS "Q$n heading uses a listed status" "$heading"
  else
    record FAIL "Q$n heading uses a listed status" "${heading:-no ### Q$n heading}"
  fi
done

check_block 1 "Q1 names maxBuffer" -F 'maxBuffer'
check_block 1 "Q1 states the 1 MiB default" -E "$one_mib"
check_block 1 "Q1 sets encoding to buffer" -Ei 'encoding[^.]{0,20}buffer'
check_block 1 "Q1 uses exec-out" -F 'exec-out'
check_block 2 "Q2 quotes the live peer range" -F "$peer_range"

heading=$(grep -Em1 "^### Q3([^0-9]|$)" "$tmp/q3.txt" || true)
if printf '%s\n' "$heading" | grep -Eq '^### Q3 -- needs-measurement[[:space:]]*$'; then
  record PASS "Q3 status is needs-measurement" "$heading"
else
  record FAIL "Q3 status is needs-measurement" "${heading:-no ### Q3 heading}"
fi

left=$(ls -A "$project")
if [ -z "$left" ]; then
  record PASS "Project root is still empty" "nothing written during the run"
else
  record FAIL "Project root is still empty" "found: $(printf '%s' "$left" | tr '\n' ' ')"
fi

echo
echo "Score: $passes passed, $fails failed"
cost_line

if [ "$fails" -gt 0 ]; then
  fail_keep
fi
cleanup_note
exit 0
