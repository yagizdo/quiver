#!/bin/bash
# test-ship-plan-pointers.sh
# Guards every /plan step that /ship reads at runtime by name:
#   pointer   skills/ship/SKILL.md  -- names each section as `skills/plan/SKILL.md` Step <N>
#   target    skills/plan/SKILL.md  -- carries that section as a "## Step <N> -- " heading
#
# Ship does not restate /plan's plan format, its inline checks, or its dispatch blocks. It
# names the step that holds each one and tells the model to read that section when it gets
# there. The pointer is the whole interface. A /plan step that is renamed or renumbered with
# no matching edit in ship leaves ship naming a section that does not exist, and the model
# then improvises the format or skips the check with NO error anywhere. This test is the
# only thing that catches that.
#
# The step number is extracted as [0-9]+(\.[0-9]+)?, so a sentence ending "Step 6." yields 6.
# The heading match is literal and keeps the trailing " -- ", so Step 6 is not satisfied by
# "## Step 6.5 -- ".
#
# Finding no pointer is a failure, not a pass. A reworded pointer form would otherwise leave
# this test asserting nothing.
#
# Overrides, for running the rule against a fixture:
#   SHIP_FILE  default skills/ship/SKILL.md
#   PLAN_FILE  default skills/plan/SKILL.md
# A relative value resolves from the repo root, so the test runs from any directory.
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
PLAN="$(resolve "${PLAN_FILE:-skills/plan/SKILL.md}")"
SHIP_REL="${SHIP#"$REPO_ROOT"/}"
PLAN_REL="${PLAN#"$REPO_ROOT"/}"

POINTER_RE='`skills/plan/SKILL\.md` Step [0-9]+(\.[0-9]+)?'

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

# --- Preflight ---
# A missing plan file would report every step as dangling, which reads as a renamed step
# rather than as a moved file.
echo ""
echo "=== 1. Preflight ==="
MISSING=0
if [ ! -f "$SHIP" ]; then
  fail "missing $SHIP -- the ship skill whose /plan pointers this test checks."
  MISSING=1
fi
if [ ! -f "$PLAN" ]; then
  fail "missing $PLAN -- the /plan skill whose step headings the pointers name."
  MISSING=1
fi
if [ "$MISSING" -ne 0 ]; then
  finish
fi
pass "ship and plan files present"

# --- Extraction ---
# One "<ship line> <step>" pair per pointer, so a dangling step can name every ship line
# that points at it.
echo ""
echo "=== 2. Ship names /plan steps ==="
POINTERS="$(grep -noE "$POINTER_RE" "$SHIP" | sed -E 's/^([0-9]+):.* Step /\1 /')"
STEPS="$(printf '%s\n' "$POINTERS" | awk 'NF == 2 { print $2 }' | sort -u | sort -t. -k1,1n -k2,2n)"
if [ -z "$STEPS" ]; then
  fail "$SHIP_REL has no \`skills/plan/SKILL.md\` Step <N> pointer -- the pointer form was reworded or removed, and with no pointer this test asserts nothing"
  finish
fi
pass "$SHIP_REL names Steps $(printf '%s\n' "$STEPS" | paste -sd, - | sed 's/,/, /g')"

# --- Targets ---
# Every step is checked, so one run names every dangling pointer instead of the first.
echo ""
echo "=== 3. Every named step exists in /plan ==="
for N in $STEPS; do
  if awk -v h="## Step $N -- " 'index($0, h) == 1 { found = 1 } END { exit found ? 0 : 1 }' "$PLAN"; then
    pass "Step $N -- $PLAN_REL has a line starting '## Step $N -- '"
  else
    WHERE="$(printf '%s\n' "$POINTERS" | awk -v n="$N" -v f="$SHIP_REL" '$2 "" == n "" { printf "%s%s:%s", sep, f, $1; sep = ", " }')"
    fail "Step $N -- $PLAN_REL has no line starting '## Step $N -- ', named at $WHERE; ship tells the model to read a section that does not exist, and the model improvises in its place"
  fi
done

finish
