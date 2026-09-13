#!/usr/bin/env bash
#
# Behavior eval for /review: does a fast review find three planted defects
# without reporting three deliberate false-positive baits?
#
# Costs real money. Not named test-*.sh on purpose -- tests/run-all.sh globs
# test-*.sh, so neither the local runner nor CI can pick this up by accident.
#
#   bash tests/eval/run-review-golden.sh [--keep]
#
# PORTING TO `claude plugin eval`
# ------------------------------
# `plugin eval` is early access and disabled for this account as of
# 2026-09-13 (running it prints "plugin eval is currently in early access").
# This harness is shaped to move onto it with no change of meaning:
#
#   tests/eval/review-golden/   ->  evals/review-golden/
#     build-fixture.sh          ->  the suite's fixture/setup step
#     expectations.txt          ->  regex graders; "+" is a match grader and
#                                   "-" is a not-match grader, one per line
#     the prompt at PROBE below ->  prompt.md
#
# The one piece that does not port verbatim is the "## Findings" extraction
# below. Graders match the whole transcript, so each ported regex needs the
# section scoping folded into it (or the eval asserts on the report file).
#
set -uo pipefail

keep=false
[ "${1:-}" = "--keep" ] && keep=true

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../.." && pwd -P)
expectations="$here/review-golden/expectations.txt"

tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)
fixture="$tmp/repo"

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

echo "Building fixture..."
bash "$here/review-golden/build-fixture.sh" "$fixture" || { echo "FIXTURE BUILD FAILED"; fail_keep; }
git -C "$fixture" checkout -q feature

cd "$fixture"

# bypassPermissions is only acceptable because the working directory is the
# throwaway fixture. Refuse to run anywhere else.
cwd=$(pwd -P)
case "$cwd" in
  "$tmp"/*) : ;;
  *) echo "ABORT: cwd $cwd is not under the temp dir $tmp"; exit 1 ;;
esac

# Addressed as quiver:review, not /review. Claude Code ships a built-in
# code-review skill, and a bare /review resolves to that one: measured
# 2026-09-13, the run emitted ReportFindings-shaped output, wrote no report
# file, and spawned 0 subagents where quiver:review fans out to 5.
PROBE='/quiver:review --base main --output ./review-out'

# $1 is the attempt label; each attempt keeps its own JSON so a retry cannot
# erase the evidence from the attempt before it. run.json always points at the
# latest attempt.
run_claude() {
  attempt=$1
  shift
  raw="$tmp/run-$attempt.jsonl"
  if [ "$#" -gt 0 ]; then
    claude -p "$PROBE" \
      --plugin-dir "$repo_root" \
      --max-budget-usd 8 \
      --permission-mode bypassPermissions \
      --output-format stream-json --verbose \
      --append-system-prompt "$1" > "$raw"
  else
    claude -p "$PROBE" \
      --plugin-dir "$repo_root" \
      --max-budget-usd 8 \
      --permission-mode bypassPermissions \
      --output-format stream-json --verbose > "$raw"
  fi
  # The stream's final result event carries the same totals --output-format json
  # returns on its own. Pull it out so the grader reads one shape either way.
  grep '"type":"result"' "$raw" | tail -1 > "$tmp/run-$attempt.json"
  cp "$tmp/run-$attempt.json" "$tmp/run.json"
  cp "$raw" "$tmp/run.jsonl"
}

# What the run actually did, for the blocked path. A typed slash command is
# expanded into the prompt by the CLI -- it does not travel through the Skill
# tool -- so "did quiver:review run" is NOT answerable by looking for a Skill
# tool_use event. Measured 2026-09-13 against /work, /review and /design in a
# throwaway directory: none of the three produced one. What separates them is
# the work itself, so this prints the tools the run reached for; quiver:review
# opens with its own `!` git blocks, and the bundled reviewer does not.
run_evidence() {
  if [ ! -s "$1" ]; then
    echo "  (no stream captured)"
    return
  fi
  echo "  tools used: $(grep -o '"name":"[A-Za-z]*","input"' "$1" | sed 's/"name":"//; s/","input"//' | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
  if grep -q 'rev-parse --is-inside-work-tree' "$1"; then
    echo "  quiver:review's own git context block ran"
  else
    echo "  quiver:review's git context block never ran -- another skill handled the prompt"
  fi
}

find_report() {
  find "$fixture/review-out" -name 'review-*.md' -type f 2>/dev/null | sort | tail -1
}

echo "Running /review (fast mode, 5 agents)..."
run_claude 1
report=$(find_report)

if [ -z "$report" ]; then
  echo "No review-*.md produced. Retrying once with an explicit Skill-tool instruction..."
  run_claude 2 "Invoke the quiver:review skill through the Skill tool with the arguments given in the prompt, then stop."
  report=$(find_report)
fi

if [ -z "$report" ]; then
  echo
  echo "HARNESS BLOCKED: /review produced no report file on either attempt."
  echo "Per-attempt JSON kept: $tmp/run-1.json, $tmp/run-2.json (streams: run-N.jsonl)"
  echo "What the last attempt did:"
  run_evidence "$tmp/run.jsonl"
  echo "Evidence from the last attempt:"
  python3 - "$tmp/run.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as exc:
    print("  could not parse run.json:", exc)
    sys.exit(0)
for k in ("type", "subtype", "is_error", "num_turns", "duration_ms", "total_cost_usd"):
    if k in d:
        print("  %s: %s" % (k, d[k]))
stats = d.get("subagent_stats") or {}
if "spawned" in stats:
    print("  subagents spawned: %s (quiver:review fans out to 5; 0 means it never ran)" % stats["spawned"])
text = str(d.get("result", ""))
print("  result (first 2000 chars):")
print("  " + text[:2000].replace("\n", "\n  "))
PY
  fail_keep
fi

echo "Report: $report"

# Grade only inside "## Findings" -- a mention under "## Filtered Findings" or
# "## What's Working Well" counts neither for nor against.
findings="$tmp/findings.txt"
awk '/^## Findings[[:space:]]*$/{inside=1; next} inside && /^## /{exit} inside{print}' "$report" > "$findings"

if [ ! -s "$findings" ]; then
  echo "WARNING: '## Findings' section is empty or absent in the report."
fi

echo
printf '%-6s %-28s %s\n' "RESULT" "EXPECTATION" "EVIDENCE"
printf '%-6s %-28s %s\n' "------" "----------------------------" "--------"

fails=0
passes=0
while IFS= read -r line; do
  case "$line" in
    ''|'#'*) continue ;;
  esac
  sign=${line%% *}
  pattern=${line#* }
  case "$sign" in
    '+')
      hit=$(grep -Eim1 "$pattern" "$findings" || true)
      if [ -n "$hit" ]; then
        passes=$((passes + 1))
        printf '%-6s %-28s %s\n' "PASS" "+ $pattern" "$(echo "$hit" | cut -c1-90)"
      else
        fails=$((fails + 1))
        printf '%-6s %-28s %s\n' "FAIL" "+ $pattern" "not reported"
      fi
      ;;
    '-')
      hit=$(grep -Eim1 "$pattern" "$findings" || true)
      if [ -n "$hit" ]; then
        fails=$((fails + 1))
        printf '%-6s %-28s %s\n' "FAIL" "- $pattern" "false positive: $(echo "$hit" | cut -c1-72)"
      else
        passes=$((passes + 1))
        printf '%-6s %-28s %s\n' "PASS" "- $pattern" "not reported"
      fi
      ;;
    *)
      echo "SKIP  unparseable expectation: $line"
      ;;
  esac
done < "$expectations"

echo
echo "Score: $passes passed, $fails failed"
python3 - "$tmp/run.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
bits = []
if "total_cost_usd" in d:
    bits.append("$%.4f" % d["total_cost_usd"])
if "duration_ms" in d:
    bits.append("%.1fs" % (d["duration_ms"] / 1000.0))
if "num_turns" in d:
    bits.append("%s turns" % d["num_turns"])
u = d.get("usage") or {}
for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"):
    if k in u:
        bits.append("%s %s" % (k, u[k]))
if bits:
    print("Cost: " + ", ".join(bits))
PY
echo "Report: $report"

if [ "$fails" -gt 0 ]; then
  fail_keep
fi
cleanup_note
exit 0
