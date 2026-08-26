#!/bin/bash
# test-design-flag-contract.sh
# Guards the two run flags the design pipeline carries, each of which lives in two files
# by construction:
#   producer  skills/design/SKILL.md       -- Step 0.5 defines --auto and --no-commit,
#             Step 8 acts on --no-commit, Step 10 forwards both
#   consumer  skills/design-build/SKILL.md -- Phase 1 parses both, every prompt site ahead
#             of it carries an auto-mode branch, and Phase 3d honors the commit override
#
# The promise the flag makes is negative: after /design Step 8, an auto run asks nothing.
# A prompt site added to /design-build without an auto branch breaks that promise silently
# -- the run stalls waiting on a human who walked away. So the flag token is read out of
# the producer's forwarding line rather than pinned here, and every AskUserQuestion call
# site in the consumer is checked for a guard rather than counted.
#
# Run directly: bash tests/skills/test-design-flag-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXIT=0

DESIGN="$REPO_ROOT/skills/design/SKILL.md"
BUILD="$REPO_ROOT/skills/design-build/SKILL.md"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# assert_in <file> <pattern> <label>
# The -- guards patterns that start with a dash.
assert_in() {
  if grep -q -- "$2" "$1"; then
    pass "$3"
  else
    fail "$3"
  fi
}

echo "=== 1. /design declares and documents the flag ==="

assert_in "$DESIGN" '^argument-hint:.*--auto' "argument-hint advertises the flag"
assert_in "$DESIGN" '^## Step 0.5 -- Arguments$' "Step 0.5 exists to parse arguments"
assert_in "$DESIGN" 'It does not remove the questions that decide what gets built' \
  "Step 0.5 states the plan-time Q&A survives auto mode"
assert_in "$DESIGN" 'Strip it before Step 3 resolves a target' \
  "the flag is stripped before node-ID resolution"

echo "=== 2. /design forwards the flag it defines ==="

# The forwarded token is read from the live forwarding line, not pinned, so a rename on the
# producer side has to reach the consumer or this fails.
FLAG="$(grep -o '/design-build {plan path} [^ ]*' "$DESIGN" | head -1 | awk '{print $NF}')"

if [ -n "$FLAG" ]; then
  pass "Step 10 carries a forwarding line ($FLAG)"
else
  fail "Step 10 carries a forwarding line"
  FLAG="--auto"
fi

assert_in "$DESIGN" 'In auto mode, skip the question below' \
  "the auto path skips Step 10's handoff question"
assert_in "$DESIGN" 'Pass no `'"$FLAG"'`' \
  "the interactive Build-it-now button does not forward $FLAG"

echo "=== 3. /design-build accepts the forwarded flag ==="

assert_in "$BUILD" '^argument-hint:.*'"$FLAG" "argument-hint advertises $FLAG"
assert_in "$BUILD" '`'"$FLAG"'` anywhere in `\$ARGUMENTS` sets \*\*auto mode\*\*' \
  "Phase 1 parses $FLAG into auto mode"
assert_in "$BUILD" 'Strip it before resolving a path' \
  "the flag is stripped before plan-path resolution"
assert_in "$BUILD" 'never lowers a bar, it only stops asking' \
  "auto mode is documented as changing no measurement or gate"
assert_in "$BUILD" 'sits on an `Otherwise` line' \
  "the prompt-site convention this test enforces is stated in the skill"

echo "=== 4. every prompt site in /design-build is guarded ==="

# The instruction body only. Anti-Patterns and Test Plan mention AskUserQuestion to forbid
# and to verify it; neither is a call site.
BODY="$(mktemp)"
MENTIONS="$(mktemp)"
trap 'rm -f "$BODY" "$MENTIONS"' EXIT
awk '/^# Instructions/{f=1} /^## Anti-Patterns/{f=0} f' "$BUILD" > "$BODY"

# Match `AskUserQuestion` anywhere in the body rather than on a verb phrase. Phrase
# matching defaults a new call site to invisible -- the test passes green on exactly the
# drift it exists to catch. Matching the tool name defaults it to checked instead, and
# the three body lines that name the tool without calling it are exempted by name.
grep -n 'AskUserQuestion' "$BODY" > "$MENTIONS"

# The exemption count is itself a tripwire. A stale pattern fails loudly (the line becomes
# a checked site with no Otherwise). A pattern that widens onto a real call site would
# fail silently, which this count is what catches.
EXEMPT_FOUND=$(grep -c -e 'sets \*\*auto mode\*\*' -e 'call site in this skill sits on' -e 'cancels any' "$MENTIONS")
if [ "$EXEMPT_FOUND" -ne 3 ]; then
  fail "expected 3 non-call-site AskUserQuestion mentions, found $EXEMPT_FOUND -- update the exemption list"
fi

SITES=0
UNGUARDED=0
while IFS=: read -r n line; do
  SITES=$((SITES + 1))
  # The convention: the call sits on an "Otherwise" line, with the auto branch above it.
  # Same-line is the strong check -- a proximity window alone passes a new unguarded prompt
  # that happens to land near an existing auto paragraph.
  if ! printf '%s' "$line" | grep -qi 'otherwise'; then
    fail "prompt site at body line $n is not on an Otherwise line: $line"
    UNGUARDED=$((UNGUARDED + 1))
    continue
  fi
  start=$((n - 20))
  [ "$start" -lt 1 ] && start=1
  if ! sed -n "${start},${n}p" "$BODY" | grep -qi 'auto mode'; then
    fail "prompt site at body line $n has no auto-mode branch within 20 lines"
    UNGUARDED=$((UNGUARDED + 1))
  fi
done < <(grep -v -e 'sets \*\*auto mode\*\*' -e 'call site in this skill sits on' -e 'cancels any' "$MENTIONS")

if [ "$SITES" -eq 0 ]; then
  fail "found no AskUserQuestion call sites -- the grep pattern has drifted"
elif [ "$UNGUARDED" -eq 0 ]; then
  pass "all $SITES prompt sites carry an auto-mode branch"
fi

echo "=== 5. the auto path stays bounded ==="

assert_in "$BUILD" 'The budget is never extended in auto mode' \
  "3c does not grant itself more attempts in auto mode"
assert_in "$BUILD" 'Invoke none of them' \
  "the Phase 4 auto handoff names follow-up skills without running them"

echo "=== 6. --no-commit is defined, forwarded, and honored ==="

assert_in "$DESIGN" '^argument-hint:.*--no-commit' "/design advertises --no-commit"
assert_in "$DESIGN" '`--no-commit` forces `commit_strategy: none` for this run' \
  "Step 0.5 defines what --no-commit does"
assert_in "$DESIGN" 'leave Question 1 out of the call entirely' \
  "Step 8 drops the commit question instead of asking it"
assert_in "$DESIGN" 'closes Question 1 before the call is composed' \
  "the skip rule is stated ahead of the question it skips"
assert_in "$DESIGN" "/design-build {plan path} $FLAG --no-commit" \
  "Step 10 forwards --no-commit alongside $FLAG"

assert_in "$BUILD" '^argument-hint:.*--no-commit' "/design-build advertises --no-commit"
assert_in "$BUILD" '`--no-commit` anywhere in `\$ARGUMENTS` forces `commit_strategy: none`' \
  "Phase 1 parses --no-commit"
assert_in "$BUILD" 'overrides it to `none`' "Phase 3d applies the override to the commit policy"
assert_in "$BUILD" 'never rewrites the plan' "the override is documented as run-scoped"
assert_in "$BUILD" "Don't\*\* write \`--no-commit\` into the plan" \
  "an anti-pattern forbids persisting the flag into the plan"

# The flags are independent. A skill that only handles them together strands
# /design-build <plan> --no-commit, which is the case the flag exists for.
for f in "$DESIGN" "$BUILD"; do
  assert_in "$f" 'independent' "$(basename "$(dirname "$f")") states the two flags are independent"
done

if [ "$EXIT" -eq 0 ]; then
  echo "PASS: design flag contract intact"
else
  echo "FAIL: design flag contract drifted"
fi
exit "$EXIT"
