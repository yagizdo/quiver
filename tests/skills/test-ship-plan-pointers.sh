#!/bin/bash
# test-ship-plan-pointers.sh
# Guards every skill step that /ship reads at runtime by name:
#   pointer   skills/ship/SKILL.md    -- names each section as `skills/<name>/SKILL.md` Step <N>
#   target    skills/<name>/SKILL.md  -- carries that section as a "## Step <N> -- " heading
#
# Ship does not restate another skill's formats, inline checks, or dispatch blocks. It
# names the step that holds each one and tells the model to read that section when it gets
# there. The pointer is the whole interface. A step that is renamed or renumbered with no
# matching edit in ship leaves ship naming a section that does not exist, and the model
# then improvises the format or skips the check with NO error anywhere. This test is the
# only thing that catches that. Every skill ship points into is covered, not only /plan.
#
# The step number is extracted as [0-9]+(\.[0-9]+)?, so a sentence ending "Step 6." yields 6.
# The heading match is literal and keeps the trailing " -- ", so Step 6 is not satisfied by
# "## Step 6.5 -- ".
#
# Finding no pointer is a failure, not a pass. A reworded pointer form would otherwise leave
# this test asserting nothing. Section 0 runs the rule over a fixture it must reject, so a
# rule that stopped matching pointers into other skills cannot pass the real file forever.
#
# Override, for running the rule against a fixture:
#   SHIP_FILE  default skills/ship/SKILL.md
# A relative value resolves from the repo root, so the test runs from any directory. The
# named skill files always resolve from the repo root.
#
# Run directly: bash tests/skills/test-ship-plan-pointers.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

resolve() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$REPO_ROOT/$1" ;;
  esac
}

SHIP="$(resolve "${SHIP_FILE:-skills/ship/SKILL.md}")"
SHIP_REL="${SHIP#"$REPO_ROOT"/}"

POINTER_RE='`skills/[a-z0-9-]+/SKILL\.md` Step [0-9]+(\.[0-9]+)?'

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

finish() {
  echo ""
  echo "================================"
  if [ $EXIT -eq 0 ]; then
    echo "All tests passed."
  else
    echo "Some tests FAILED."
  fi
  exit $EXIT
}

# --- Self-check ---
# The rule runs once over a fixture it must reject: one valid /plan pointer and one
# /brainstorm pointer to a step that file does not have. A rule that stopped reading
# pointers into other skills would pass the real file forever. The nested run sets
# SHIP_POINTERS_SELFCHECK so it does not recurse.
if [ -z "${SHIP_POINTERS_SELFCHECK:-}" ]; then
  echo ""
  echo "=== 0. The rule rejects a dangling pointer into another skill ==="
  FIXTURE="$(mktemp)"
  trap 'rm -f "$FIXTURE"' EXIT
  printf '%s\n' 'Write the plan by `skills/plan/SKILL.md` Step 5.' 'Write the spec by `skills/brainstorm/SKILL.md` Step 6.' > "$FIXTURE"
  OUT="$(SHIP_POINTERS_SELFCHECK=1 SHIP_FILE="$FIXTURE" bash "$0" 2>&1)"
  CODE=$?
  if [ "$CODE" -ne 0 ] && printf '%s\n' "$OUT" | grep -qF 'FAIL: skills/brainstorm/SKILL.md Step 6 -- '; then
    pass "a fixture naming \`skills/brainstorm/SKILL.md\` Step 6 fails with that pointer named"
  else
    fail "a fixture naming \`skills/brainstorm/SKILL.md\` Step 6, which that file does not have, exited $CODE without a FAIL line for it -- the rule no longer checks pointers into skills other than /plan"
  fi
fi

# --- Preflight ---
echo ""
echo "=== 1. Preflight ==="
if [ ! -f "$SHIP" ]; then
  fail "missing $SHIP -- the ship skill whose step pointers this test checks."
  finish
fi
pass "ship file present"

# --- Extraction ---
# One "<ship line> <skill file> <step>" triple per pointer, so a dangling step can name
# every ship line that points at it.
echo ""
echo "=== 2. Ship names skill steps ==="
POINTERS="$(grep -noE "$POINTER_RE" "$SHIP" | sed -E 's/^([0-9]+):`([^`]+)` Step /\1 \2 /')"
TARGETS="$(printf '%s\n' "$POINTERS" | awk 'NF == 3 { print $2, $3 }' | sort -u | sort -k1,1 -k2,2n)"
if [ -z "$TARGETS" ]; then
  fail "$SHIP_REL has no \`skills/<name>/SKILL.md\` Step <N> pointer -- the pointer form was reworded or removed, and with no pointer this test asserts nothing"
  finish
fi
pass "$SHIP_REL names $(printf '%s\n' "$TARGETS" | awk '{ printf "%s%s Step %s", sep, $1, $2; sep = ", " }')"

# --- Targets ---
# Every step is checked, so one run names every dangling pointer instead of the first.
echo ""
echo "=== 3. Every named step exists in its skill ==="
while read -r F N; do
  WHERE="$(printf '%s\n' "$POINTERS" | awk -v f="$F" -v n="$N" -v s="$SHIP_REL" '$2 == f && $3 "" == n "" { printf "%s%s:%s", sep, s, $1; sep = ", " }')"
  if [ ! -f "$REPO_ROOT/$F" ]; then
    fail "$F Step $N -- $F does not exist, named at $WHERE; ship tells the model to read a file that is not there"
  elif awk -v h="## Step $N -- " 'index($0, h) == 1 { found = 1 } END { exit found ? 0 : 1 }' "$REPO_ROOT/$F"; then
    pass "$F Step $N -- has a line starting '## Step $N -- '"
  else
    fail "$F Step $N -- $F has no line starting '## Step $N -- ', named at $WHERE; ship tells the model to read a section that does not exist, and the model improvises in its place"
  fi
done <<EOF2
$TARGETS
EOF2

finish
