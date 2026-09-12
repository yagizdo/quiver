#!/bin/bash
# test-when-to-use-contract.sh
# Binds R10 in .claude/rules/skill-rules.md to the two things that depend on it:
#   the frontmatter of every skill under skills/, and the routing block that
#   hooks/scripts/session-start-auto-dispatch.sh builds out of that frontmatter.
#
# R10's failure mode is silent in both directions, which is why it needs a test at all.
# The hook reads the first `when-to-use:` line of the frontmatter and strips `"`, `<`
# and `>` from it. A multi-line YAML block scalar therefore parses to `|` (a routing
# entry reading `/plan: |`, which routes nothing) or to the empty string (the skill is
# dropped from the block entirely). Neither raises an error, neither is visible in a
# session, and the only symptom is a skill that stops auto-firing.
#
# The reverse direction matters more. The hook tells the model to invoke a matching skill
# *silently, before any other response*. R10 exempts three internal reference skills, which
# are read by other skills and never invoked at all; giving one a `when-to-use:` string
# wires a non-invocable skill into that path. So this test asserts the exempt skills carry
# no `when-to-use:` rather than treating the field as merely optional for them.
#
# Destructive operations are not exempt and are not kept out this way. They live inside a
# skill carrying `disable-model-invocation: true` behind an AskUserQuestion confirmation --
# `/handover --clear` and `/handover --clear-all` are the case -- and that skill keeps its
# `when-to-use:` under R10's format rules. What keeps the destructive path off the silent
# auto-invocation route is the hook dropping model-disabled skills from the block, which is
# the assertion in Section 4's disabled branch. That branch is gated on the field it filters
# on and so cannot assert its presence; the flag is pinned by name after the loop instead.
#
# A skill is therefore kept out of the routing block for one of two reasons, and they are
# not the same reason. An R10 exemption means the skill has no `when-to-use:` at all. A skill
# with `disable-model-invocation: true` still declares one -- it is slash-invocable and R10
# still governs the string's shape -- but the model cannot invoke it, so a routing entry
# for it instructs the model to do something impossible. Section 4 therefore asserts
# absence for both sets while Section 3 keeps holding the disabled ones to R10's format.
#
# Section 4 runs the real hook instead of re-deriving its parser here. A test that
# re-implements the consumer passes when the copy is right and the consumer is wrong,
# which is the case it exists to catch.
#
# Run directly: bash tests/skills/test-when-to-use-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
RULES="$REPO_ROOT/.claude/rules/skill-rules.md"
HOOK="$REPO_ROOT/hooks/scripts/session-start-auto-dispatch.sh"
SKILLS_DIR="$REPO_ROOT/skills"

# R10's exemptions, restated. Section 1 binds this list to the rule text so a name
# dropped from the rule cannot stay silently skipped here.
EXEMPT="code-navigation verification tdd"
EXEMPT_COUNT=3

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

is_exempt() {
  case " $EXEMPT " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# The frontmatter block only -- the first `---`-delimited section. Same window the hook
# reads, so a `when-to-use:` line in the body is invisible to both.
frontmatter() {
  awk 'BEGIN{c=0} /^---/{c++; if (c==2) exit; next} c==1 {print}' "$1"
}

# Frontmatter-scoped, same window the hook reads. Takes a skill file path, not a name.
is_disabled() {
  frontmatter "$1" | grep -Eq '^disable-model-invocation:[[:space:]]*true[[:space:]]*$'
}

echo ""
echo "=== 1. Preflight ==="
MISSING=0
for f in "$RULES" "$HOOK"; do
  if [ ! -f "$f" ]; then
    fail "missing ${f#"$REPO_ROOT"/}"
    MISSING=1
  fi
done
if [ ! -d "$SKILLS_DIR" ]; then
  fail "missing skills/ -- nothing to check"
  MISSING=1
fi
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit 1
fi
pass "rules file, routing hook and skills/ present"

echo ""
echo "=== 2. R10 still says what this test enforces ==="
R10_LINE="$(grep -F '**R10.' "$RULES" | head -1)"
if [ -n "$R10_LINE" ]; then
  pass "skill-rules.md carries an R10 rule"
else
  fail "skill-rules.md has no line starting the R10 rule -- this test enforces a rule that no longer exists, so either restore R10 or delete this test"
fi

if [ -n "$R10_LINE" ]; then
  case "$R10_LINE" in
    *'when-to-use:'*) pass "R10 is still the when-to-use rule" ;;
    *) fail "R10 no longer mentions 'when-to-use:' -- the rule was renumbered or repurposed and this test is now pointed at the wrong rule" ;;
  esac

  NAMED=0
  for name in $EXEMPT; do
    case "$R10_LINE" in
      *"$name"*) pass "R10 still exempts $name"; NAMED=$((NAMED + 1)) ;;
      *) fail "R10 no longer names $name as an exception, but this test still skips it -- either restore the name in R10, or give skills/$name/ a when-to-use: and drop the name from EXEMPT (lowering EXEMPT_COUNT to match)" ;;
    esac
  done

  # The loop above only checks the names EXEMPT still lists. Dropping a name from EXEMPT
  # removes its assertion instead of failing it, so pin the count too.
  if [ "$NAMED" -eq "$EXEMPT_COUNT" ]; then
    pass "all $EXEMPT_COUNT R10 exemptions are named in the rule text"
  else
    fail "R10 names $NAMED of the $EXEMPT_COUNT expected exemptions -- EXEMPT and EXEMPT_COUNT disagree with the rule, so update all three together"
  fi
fi

echo ""
echo "=== 3. Frontmatter shape, per skill ==="
CHECKED=0
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  dir="$(basename "$(dirname "$skill_file")")"
  rel="skills/$dir/SKILL.md"
  FM="$(frontmatter "$skill_file")"
  LINE="$(printf '%s\n' "$FM" | grep '^when-to-use:' | head -1)"
  CHECKED=$((CHECKED + 1))

  if is_exempt "$dir"; then
    if [ -z "$LINE" ]; then
      pass "$rel is exempt and carries no when-to-use (stays out of the auto-dispatch block)"
    else
      fail "$rel is an R10 exception but declares when-to-use -- the SessionStart hook would tell the model to invoke it silently before responding, which is exactly what the exemption prevents"
    fi
    continue
  fi

  if [ -z "$LINE" ]; then
    fail "$rel has no when-to-use: in its frontmatter -- the hook skips the skill entirely and it never auto-fires"
    continue
  fi

  # Exactly two double quotes, closing one at end of line. A block scalar (`|`, `>`),
  # an unquoted value, or a value continued onto a second line all fail here.
  if printf '%s\n' "$LINE" | grep -Eq '^when-to-use: "[^"]*"$'; then
    pass "$rel when-to-use is a single-line double-quoted string"
  else
    fail "$rel when-to-use is not a single-line double-quoted string -- got: $LINE"
    continue
  fi

  VALUE="$(printf '%s\n' "$LINE" | sed -E 's/^when-to-use: "(.*)"$/\1/')"
  NAME="$(printf '%s\n' "$FM" | sed -n 's/^name:[[:space:]]*//p' | head -1)"

  if [ -z "$NAME" ]; then
    fail "$rel has no name: in its frontmatter -- the hook builds the routing entry from it and drops the skill without one"
    continue
  fi

  case "$VALUE" in
    *"/$NAME"*) pass "$rel when-to-use anchors on /$NAME" ;;
    *) fail "$rel when-to-use never names /$NAME -- the routing entry has no slash-command anchor for the model to match on" ;;
  esac

  # Delimited, not merely bracketed. A bare "'[^']+'" needs only two apostrophes with a
  # character between them, so prose contractions and possessives ("user's ... don't")
  # satisfy it while carrying no quoted utterance at all. Requiring a word boundary before
  # the opening quote and a boundary or terminator after the closing one keeps '/commit'
  # and 'stage and commit this' matching and rejects the contraction case.
  if printf '%s\n' "$VALUE" | grep -Eq "(^|[[:space:]])'[^']+'([[:space:],.]|$)"; then
    pass "$rel when-to-use quotes at least one user utterance"
  else
    fail "$rel when-to-use quotes no user utterance -- R10 requires at least one concrete phrase a user would actually type"
  fi
done

if [ "$CHECKED" -eq 0 ]; then
  fail "no skills/*/SKILL.md found -- this test asserted nothing"
else
  pass "checked $CHECKED skill files"
fi

echo ""
echo "=== 4. The routing hook emits what the frontmatter promises ==="
ROUTING="$(bash "$HOOK" 2>/dev/null)"
DISABLED_SEEN=0

if printf '%s\n' "$ROUTING" | grep -Fq '<quiver-auto-dispatch>'; then
  pass "hook emits a routing block"
else
  fail "hook emitted no <quiver-auto-dispatch> block -- it exits 0 on every failure path, so a broken hook is indistinguishable from a session with no skills"
fi

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  dir="$(basename "$(dirname "$skill_file")")"
  NAME="$(frontmatter "$skill_file" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  [ -n "$NAME" ] || continue

  # Colon-space anchored: a bare "/design" prefix would also match "/design-build".
  if printf '%s\n' "$ROUTING" | grep -Eq "^/$NAME: .+"; then
    PRESENT=1
  else
    PRESENT=0
  fi

  if is_exempt "$dir"; then
    if [ "$PRESENT" -eq 0 ]; then
      pass "/$NAME is absent from the routing block, as its exemption requires"
    else
      fail "/$NAME is exempt but appears in the routing block -- it is now wired into silent auto-invocation"
    fi
  elif is_disabled "$skill_file"; then
    DISABLED_SEEN=$((DISABLED_SEEN + 1))
    if [ "$PRESENT" -eq 0 ]; then
      pass "/$NAME sets disable-model-invocation and is absent from the routing block"
    else
      fail "/$NAME sets disable-model-invocation: true but appears in the routing block -- the block tells the model to invoke a skill the model is not allowed to invoke"
    fi
  else
    if [ "$PRESENT" -eq 1 ]; then
      pass "/$NAME has a non-empty routing entry"
    else
      fail "/$NAME has no non-empty routing entry -- the hook parsed its when-to-use to nothing, so the skill never auto-fires and nothing reports it"
    fi
  fi
done

# Without this the disabled branch is vacuous: drop the filter from the hook AND the
# field from every skill and the loop above still reports nothing but passes.
if [ "$DISABLED_SEEN" -eq 0 ]; then
  fail "no skill outside the EXEMPT list carries disable-model-invocation: true -- the filter assertion above tested nothing, so either a skill lost the field or this branch is dead"
else
  pass "checked $DISABLED_SEEN disable-model-invocation skill(s) for absence"
fi

# /handover carries delete flags (--clear, --clear-all). It is not R10-exempt and declares a
# when-to-use, so `disable-model-invocation: true` is the only thing keeping it out of the
# block. The branch above cannot assert the field's presence -- it is gated on it.
if is_disabled "$SKILLS_DIR/handover/SKILL.md"; then
  pass "handover still sets disable-model-invocation: true, keeping --clear/--clear-all out of the routing block"
else
  fail "skills/handover/SKILL.md lost disable-model-invocation: true -- it declares a when-to-use, so the routing hook now tells the model to invoke a skill carrying --clear and --clear-all silently before responding"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
