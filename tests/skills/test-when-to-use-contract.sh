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
# The reverse direction matters more. R10 exempts five skills, and two of them --
# delete-all-handovers and delete-last-handover -- delete user data. The hook tells the
# model to invoke a matching skill *silently, before any other response*. Giving either
# of those a `when-to-use:` string wires a destructive skill into that path. The
# exemption is what keeps them out of it, so this test asserts the exempt skills carry
# no `when-to-use:` rather than treating the field as merely optional for them.
#
# Section 3 runs the real hook instead of re-deriving its parser here. A test that
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
EXEMPT="code-navigation orchestrate-agents verification delete-all-handovers delete-last-handover"

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

  for name in $EXEMPT; do
    case "$R10_LINE" in
      *"$name"*) pass "R10 still exempts $name" ;;
      *) fail "R10 no longer names $name as an exception, but this test still skips it -- either add the field to skills/$name/ or drop it from the EXEMPT list here" ;;
    esac
  done
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
  else
    if [ "$PRESENT" -eq 1 ]; then
      pass "/$NAME has a non-empty routing entry"
    else
      fail "/$NAME has no non-empty routing entry -- the hook parsed its when-to-use to nothing, so the skill never auto-fires and nothing reports it"
    fi
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
