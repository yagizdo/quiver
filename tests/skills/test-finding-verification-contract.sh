#!/bin/bash
# test-finding-verification-contract.sh
# Guards the finding-verification contract between two files:
#   producer  agents/review/finding-verifier.md  -- returns one verdict heading per finding
#                                                    (### F<id> -- CONFIRMED | REFUTED |
#                                                    UNVERIFIABLE) and runs in its own worktree
#   consumer  skills/review/SKILL.md              -- Step 3.3 dispatches it, reads those
#                                                    headings, and writes the report lines
#                                                    `Verification: confirmed --`,
#                                                    `Verification: unverified --`, and the
#                                                    `refuted-by-verification` classification
# and binds the report lines to their two readers: skills/work/SKILL.md 4c (scope rule, and
# 4d skipping the verifier) and skills/report-check/SKILL.md (keeps the line on a rewrite).
#
# A verdict token renamed on one side and not the other raises no error: Step 3.3 finds no
# verdict it recognizes, every finding stays in the report unmarked, and that reads exactly
# like a review whose findings all held up. The report-line strings are read by the paid
# review eval and by /work. The worktree field is what keeps the verifier's scratch files
# and checkouts out of the user's tree. Every assertion reads the live files; no fixture is
# written.
#
# Run directly: bash tests/skills/test-finding-verification-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

AGENT="$REPO_ROOT/agents/review/finding-verifier.md"
REVIEW="$REPO_ROOT/skills/review/SKILL.md"
RA2_REF="$REPO_ROOT/agents/review/logic-reviewer.md"
WORK="$REPO_ROOT/skills/work/SKILL.md"
REPORT_CHECK="$REPO_ROOT/skills/report-check/SKILL.md"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <fixed string> <label>
assert_in() {
  if grep -qF -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

# --- 1. Preflight ---
echo ""
echo "=== 1. Preflight ==="
MISSING=0
for f in "$AGENT" "$REVIEW" "$RA2_REF" "$WORK" "$REPORT_CHECK"; do
  if [ -f "$f" ]; then
    pass "${f#$REPO_ROOT/} exists"
  else
    fail "missing ${f#$REPO_ROOT/}"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit 1
fi

# --- 2. Worktree isolation ---
# Bounded to the frontmatter block, so the field cannot be satisfied by prose in the body.
echo ""
echo "=== 2. The verifier runs in its own worktree ==="

ISO="$(awk '
  BEGIN { c = 0 }
  /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
  c == 1 && index($0, "isolation:") == 1 { sub("^isolation:[[:space:]]*", ""); print; exit }
' "$AGENT")"
if [ "$ISO" = "worktree" ]; then
  pass "frontmatter isolation: is worktree"
else
  fail "frontmatter isolation: is '$ISO', expected worktree -- without it the verifier's checkouts and scratch files land in the user's tree"
fi

# --- 3. Verdict tokens ---
# The producer writes them; Step 3.3 reads them. Both sides must carry each one.
echo ""
echo "=== 3. Both sides carry the verdict tokens ==="

for t in '-- CONFIRMED' '-- REFUTED' '-- UNVERIFIABLE'; do
  assert_in "$AGENT" "$t" "agent file carries '$t'"
  assert_in "$REVIEW" "$t" "review skill carries '$t'"
done

# --- 4. Report lines ---
echo ""
echo "=== 4. The review skill writes the report lines ==="

assert_in "$REVIEW" 'Verification: confirmed --' "review skill names 'Verification: confirmed --'"
assert_in "$REVIEW" 'Verification: unverified --' "review skill names 'Verification: unverified --'"
assert_in "$REVIEW" 'refuted-by-verification' "review skill names 'refuted-by-verification'"

# Exactly one heading: a second copy is two procedures for one step, a missing one leaves
# the Step 2b bullet pointing at nothing.
N="$(grep -cxF -- '## Step 3.3 -- Verify Findings' "$REVIEW")"
if [ "$N" = "1" ]; then
  pass "'## Step 3.3 -- Verify Findings' appears exactly once"
else
  fail "'## Step 3.3 -- Verify Findings' appears $N time(s), expected exactly once"
fi

# --- 5. The hypothetical-language ban ---
# The verifier carries the canonical text, hashed with the leading list number stripped,
# the same check the review agent rules prescribe for every copy.
echo ""
echo "=== 5. The verifier's hypothetical-language ban matches the canonical copy ==="

ra2_hash() {
  grep -F 'Hypothetical language is banned.' "$1" \
    | sed -E 's/^[[:space:]]*[0-9]+\. //' \
    | shasum -a 256 | cut -d' ' -f1
}
COUNT="$(grep -cF 'Hypothetical language is banned.' "$AGENT")"
if [ "$COUNT" != "1" ]; then
  fail "agent file carries the ban line $COUNT time(s), expected exactly once"
elif [ "$(ra2_hash "$AGENT")" = "$(ra2_hash "$RA2_REF")" ]; then
  pass "ban text in agents/review/finding-verifier.md hashes equal to agents/review/logic-reviewer.md"
else
  fail "ban text in agents/review/finding-verifier.md differs from agents/review/logic-reviewer.md"
fi

# --- 6. Report consumers ---
# /work 4c reads `Verification: confirmed` to decide scope, and 4d must skip the verifier;
# /report-check rewrites findings in a saved report and must keep their `Verification:` line.
# A rename here leaves /work fixing refuted or unchecked findings with no error.
echo ""
echo "=== 6. The report consumers carry the new lines ==="

assert_in "$WORK" 'Verification: confirmed' "work skill 4c names 'Verification: confirmed'"
assert_in "$WORK" 'skips `finding-verifier`' "work skill 4d skips finding-verifier"
assert_in "$REPORT_CHECK" 'Verification:' "report-check skill names the 'Verification:' line"

# --- 7. No caller gives the review flag as its reason ---
# /work, /design-build and /ship print the review command instead of running it. Their reason
# is that the review covers the finished branch, not the review skill's frontmatter flag: a
# sentence naming the flag turns false the day the flag is removed.
echo ""
echo "=== 7. Callers do not name the review skill's flag ==="

for d in work design-build ship; do
  HITS="$(grep -rnF 'disable-model-invocation' "$REPO_ROOT/skills/$d" 2>/dev/null)"
  if [ -z "$HITS" ]; then
    pass "skills/$d does not name disable-model-invocation"
  else
    fail "skills/$d names disable-model-invocation: ${HITS#$REPO_ROOT/}"
  fi
done

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
