#!/bin/bash
# test-shell-block-syntax.sh
# Guards every skill body against an inline shell block Claude Code executes by accident.
#
# The loader scans a SKILL.md body for a "!" immediately followed by a backtick-delimited
# span and runs that span through the shell BEFORE any step logic. Markdown nesting does
# not protect it -- a double-backtick inline code span wrapped around an example is
# invisible to that scanner. So a sentence written to document the syntax executes it.
#
# That is not hypothetical. skills/design-fix/SKILL.md shipped in v1.24.0 carrying
#   - This skill carries no `` !`...` `` shell blocks on purpose.
# and loading /quiver:design-fix aborted before Step 0 with
#   Shell command failed for pattern "!`...`": (eval):1: command not found: ...
# /quiver:design failed identically, because it routes into the same file.
#
# The rule, applied per line after stripping the safe prose form `!`:
#   one occurrence, whitespace-only prefix   -> a real shell block, allowed
#   one occurrence, anything else before it  -> prose that runs, failure
#   two or more occurrences on one line      -> failure
# The last clause is what makes the exemption occurrence-scoped instead of line-scoped.
# A line-scoped filter (strip the line when the safe form appears anywhere on it) stays
# green on a line carrying both forms while its unsafe half still runs. The dense
# prose-about-shell-blocks lines -- skills/review/SKILL.md:252, skills/handover/SKILL.md:389
# -- are exactly where that mixed shape would first appear.
#
# Section 3 runs the same rule over four inline inputs and asserts it accepts two and
# rejects two. Without it a rule that stopped matching anything would report a clean tree
# forever, which is the failure mode this whole file exists to prevent.
#
# Known limit: the rule keys on what precedes the pattern, and the loader does not care
# about column. A prose sentence beginning at column 0 with the pattern executes and passes
# here. Ordinary markdown rewrapping can produce that -- the design-fix bullet above already
# wraps across four lines. No grep separates that case from the real blocks that
# legitimately start a line, so it is documented rather than guarded.
#
# Scope is skills/ only. The pattern appears nowhere under agents/ or hooks/, and neither
# is read by the skill loader that produced the bug.
#
# Run directly: bash tests/skills/test-shell-block-syntax.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS="$REPO_ROOT/skills"

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# The detector. Used against the real tree in section 2 and against known inputs in
# section 3, so the thing under test and the thing proven to work are one string.
AWK_PROG='
{
  line = $0
  gsub(/`!`/, "", line)
  n = gsub(/!`/, "&", line)
  if (n == 0) next
  i = index(line, "!`")
  prefix = substr(line, 1, i - 1)
  if (n > 1 || prefix ~ /[^ \t]/) print FILENAME ":" FNR ": " $0
}
'

# --- Preflight ---
# A scan that finds no files passes on nothing. A skills/ rename would otherwise leave
# this test green forever while guarding an empty set.
echo ""
echo "=== 1. Preflight ==="
if [ ! -d "$SKILLS" ]; then
  fail "missing $SKILLS -- there is nothing to scan"
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit $EXIT
fi
COUNT="$(find "$SKILLS" -name '*.md' | wc -l | tr -d ' ')"
if [ "$COUNT" -gt 0 ]; then
  pass "$COUNT markdown files under skills/ to scan"
else
  fail "no markdown files under $SKILLS -- the scan below would assert nothing"
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit $EXIT
fi

# --- The tree ---
echo ""
echo "=== 2. Inline shell-block syntax in skill bodies ==="
HITS="$(find "$SKILLS" -name '*.md' -exec awk "$AWK_PROG" {} +)"
if [ -z "$HITS" ]; then
  pass "no skill body carries the shell-block pattern in a form the loader runs by accident"
else
  fail "these lines are executed by the shell when the skill loads:"
  echo "$HITS" | sed 's/^/      /'
  echo "      Write the mention as \`!\` instead -- the form skills/handover/SKILL.md:389"
  echo "      and skills/ship/SKILL.md:787 already use -- or move the example out of the body."
fi

# --- The detector ---
# Two inputs the rule must accept and two it must reject. The second rejection is the
# mixed line: safe form and executable form on one line, the shape a line-scoped filter
# lets through.
echo ""
echo "=== 3. Detector self-check ==="

check() {
  DESC="$1"
  WANT="$2"
  INPUT="$3"
  GOT="$(printf '%s\n' "$INPUT" | awk "$AWK_PROG")"
  if [ "$WANT" = "flag" ] && [ -n "$GOT" ]; then
    pass "rejects $DESC"
  elif [ "$WANT" = "allow" ] && [ -z "$GOT" ]; then
    pass "accepts $DESC"
  elif [ "$WANT" = "flag" ]; then
    fail "does not reject $DESC -- the rule no longer catches the bug it was written for"
  else
    fail "rejects $DESC -- a real shell block or a safe prose mention would fail the tree"
  fi
}

check "a real shell block at column 0"      allow '!`git status --short 2>/dev/null || echo "NO_GIT"`'
check "a safe prose mention"                allow '- Every `!` block in this repo runs git.'
check "the shipped design-fix line"          flag '- This skill carries no `` !`...` `` shell blocks on purpose. It creates no'
check "a line carrying both forms"           flag '- Every `!` block runs git. Do not write !`date` here.'

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
