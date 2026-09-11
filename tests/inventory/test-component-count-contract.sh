#!/bin/bash
# test-component-count-contract.sh
# Binds the tree to every place a component count or component list is written by hand.
#
# Nine numbers and three lists across five files, none of them derived at read time:
#
#   README.md                             `| Hooks | N |`, `| Skills | N |`, `| Agents | N |`
#   README.md                             the `## Hooks` table -- one row per hook
#   CLAUDE.md                             `N skill directories`, `N agent definitions`
#   .opencode/README.md                   `all N user-facing Quiver skills`
#   .opencode/README.md                   the `#### Available skills` table
#   .opencode/README.md                   `Quiver provides N specialist agents`
#   .opencode/README.md                   the `### Agents` @name list
#   .claude/rules/agent-capability-rules.md  `registers all N agents`
#
# All of them drift silently. Nothing in a session reads any of these numbers, so the
# only symptom is a reader believing them. The .opencode skill sentence is the worked
# example: it was wrong by one before it was wrong by three, because the table 19 lines
# below it was edited twice and the sentence was not, and no test looked.
#
# The user-facing skill count is not a constant. It is the directory count minus the
# names `.claude/rules/readme-structure.md` excludes from user-facing docs, so Section 3
# derives it rather than pinning a number. Section 2 binds this file's copy of that
# exclusion list back to the rule text in both directions -- a name dropped here would
# otherwise shrink the expected count to match whatever the docs happen to say, which is
# the failure this test exists to catch, arriving through the test instead of the docs.
#
# readme-structure.md also carries a `| Skills | 16 |` inventory table. That one is a
# formatting example, not a count of this repo, and is deliberately not a site here.
#
# Each numeric site is asserted to appear exactly once. A reworded sentence leaves the
# grep testing nothing, and a second copy is a new drift partner no assertion covers.
#
# Each list is compared by name, not only by length. A length check alone stays green
# when one entry replaces another.
#
# Run directly: bash tests/inventory/test-component-count-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
RULES="$REPO_ROOT/.claude/rules/readme-structure.md"
CAPABILITY_RULES="$REPO_ROOT/.claude/rules/agent-capability-rules.md"
README="$REPO_ROOT/README.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
OPENCODE_README="$REPO_ROOT/.opencode/README.md"
SKILLS_DIR="$REPO_ROOT/skills"
AGENTS_DIR="$REPO_ROOT/agents"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

# The names readme-structure.md keeps out of user-facing docs. Section 2 holds this
# list to the rule text; it is restated here so the arithmetic below is readable.
EXCLUDED="code-navigation orchestrate-agents verification tdd visual-companion"
EXCLUDED_COUNT=5

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# Counts pattern occurrences, not matching lines. `grep -c` would read two copies on one
# line as one site. `grep -c .` on empty input prints 0 and exits 1; this file has no set -e.
count_matches() {
  grep -Eo "$2" "$1" 2>/dev/null | grep -c .
}

# Reads the single number out of a count sentence. Callers assert the site count first.
extract_number() {
  grep -Eo "$2" "$1" 2>/dev/null | head -1 | grep -Eo '[0-9]+' | head -1
}

echo ""
echo "=== 1. Preflight ==="
MISSING=0
for f in "$RULES" "$CAPABILITY_RULES" "$README" "$CLAUDE_MD" "$OPENCODE_README" "$HOOKS_JSON"; do
  if [ ! -f "$f" ]; then
    fail "missing ${f#"$REPO_ROOT"/}"
    MISSING=1
  fi
done
for d in "$SKILLS_DIR" "$AGENTS_DIR"; do
  if [ ! -d "$d" ]; then
    fail "missing ${d#"$REPO_ROOT"/} -- nothing to count"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit 1
fi
pass "every count site, both rule files, skills/, agents/ and hooks.json present"

echo ""
echo "=== 2. The exclusion list still matches readme-structure.md ==="

# The rule states the list inside parentheses after "internal reference skills".
# Reading it back is what stops this test from grading the docs against itself.
RULE_LIST="$(grep -iEo 'internal reference skills \([^)]*\)' "$RULES" \
  | head -1 | sed -e 's/.*(//' -e 's/)//' -e 's/,/ /g')"

if [ -z "$RULE_LIST" ]; then
  fail "readme-structure.md no longer states an 'internal reference skills (...)' exclusion list -- this test derives the user-facing skill count from it"
else
  pass "readme-structure.md still states the exclusion list"
  if [ "$(printf '%s\n' $RULE_LIST | sort)" = "$(printf '%s\n' $EXCLUDED | sort)" ]; then
    pass "this test's EXCLUDED list matches the rule's, name for name"
  else
    fail "EXCLUDED here and the list in readme-structure.md disagree -- rule says [$(echo $RULE_LIST)], test says [$EXCLUDED]"
  fi
fi

# A name silently dropped from EXCLUDED removes an exclusion instead of failing one,
# exactly as EXEMPT_COUNT guards tests/skills/test-when-to-use-contract.sh.
ACTUAL_EXCLUDED_COUNT="$(printf '%s\n' $EXCLUDED | grep -c .)"
if [ "$ACTUAL_EXCLUDED_COUNT" -eq "$EXCLUDED_COUNT" ]; then
  pass "EXCLUDED still names $EXCLUDED_COUNT skills"
else
  fail "EXCLUDED names $ACTUAL_EXCLUDED_COUNT skills but EXCLUDED_COUNT says $EXCLUDED_COUNT -- a name was added or dropped without updating the pin"
fi

echo ""
echo "=== 3. What the tree actually holds ==="

ALL_SKILLS="$(cd "$SKILLS_DIR" && ls -d */ 2>/dev/null | sed 's#/##' | sort)"
SKILL_TOTAL="$(printf '%s\n' "$ALL_SKILLS" | grep -c .)"

ALL_AGENTS="$(cd "$AGENTS_DIR" && find . -name '*.md' 2>/dev/null | sed -e 's#.*/##' -e 's#\.md$##' | sort)"
AGENT_TOTAL="$(printf '%s\n' "$ALL_AGENTS" | grep -c .)"

# One row per registered hook command, which is what the README table lists.
HOOK_TOTAL="$(count_matches "$HOOKS_JSON" '"type"[[:space:]]*:[[:space:]]*"command"')"

for pair in "skills/:$SKILL_TOTAL" "agents/:$AGENT_TOTAL" "hooks.json:$HOOK_TOTAL"; do
  label="${pair%%:*}"; n="${pair##*:}"
  if [ "$n" -gt 0 ]; then
    pass "$label holds $n"
  else
    fail "$label holds nothing -- every count below would compare against zero"
  fi
done

# An exclusion naming a skill that no longer exists inflates the expected user-facing
# count by one and reads as a docs error at whichever site notices it first.
for name in $EXCLUDED; do
  if [ -d "$SKILLS_DIR/$name" ]; then
    pass "excluded skill $name is a real skill directory"
  else
    fail "readme-structure.md excludes $name but skills/$name/ does not exist -- the exclusion is stale and the expected user-facing count is one too low"
  fi
done

USER_FACING="$(printf '%s\n' "$ALL_SKILLS" | grep -vxF "$(printf '%s\n' $EXCLUDED)" | sort)"
USER_FACING_COUNT="$(printf '%s\n' "$USER_FACING" | grep -c .)"
pass "expecting $USER_FACING_COUNT user-facing skills ($SKILL_TOTAL directories minus $EXCLUDED_COUNT exclusions)"

echo ""
echo "=== 4. Every hand-written count says what the tree says ==="

check_site() {
  # $1 file, $2 label, $3 pattern, $4 expected
  n_sites="$(count_matches "$1" "$3")"
  if [ "$n_sites" -eq 0 ]; then
    fail "$2 no longer carries a count matching /$3/ -- the sentence was reworded and this assertion now tests nothing"
    return
  fi
  if [ "$n_sites" -eq 1 ]; then
    pass "$2 states its count exactly once"
  else
    fail "$2 carries $n_sites matching count sentences -- only the first is asserted, so the others drift unpinned"
  fi
  n="$(extract_number "$1" "$3")"
  if [ "$n" = "$4" ]; then
    pass "$2 says $n"
  else
    fail "$2 says $n but the tree has $4"
  fi
}

check_site "$README"            "README.md Hooks row"                 '^\| Hooks \| [0-9]+ \|'              "$HOOK_TOTAL"
check_site "$README"            "README.md Skills row"                '^\| Skills \| [0-9]+ \|'             "$SKILL_TOTAL"
check_site "$README"            "README.md Agents row"                '^\| Agents \| [0-9]+ \|'             "$AGENT_TOTAL"
check_site "$CLAUDE_MD"         "CLAUDE.md skills/ bullet"            '[0-9]+ skill directories'            "$SKILL_TOTAL"
check_site "$CLAUDE_MD"         "CLAUDE.md agents/ bullet"            '[0-9]+ agent definitions'            "$AGENT_TOTAL"
check_site "$OPENCODE_README"   ".opencode skill-list sentence"       'all [0-9]+ user-facing Quiver skills' "$USER_FACING_COUNT"
check_site "$OPENCODE_README"   ".opencode agents sentence"           'Quiver provides [0-9]+ specialist agents' "$AGENT_TOTAL"
check_site "$CAPABILITY_RULES"  "agent-capability-rules.md scope note" 'registers all [0-9]+ agents'        "$AGENT_TOTAL"

echo ""
echo "=== 5. Every hand-written list names what the tree names ==="

compare_list() {
  # $1 label, $2 actual list (newline-separated, sorted), $3 expected list, $4 empty-hint
  local n
  n="$(printf '%s\n' "$2" | grep -c .)"
  if [ "$n" -eq 0 ]; then
    fail "$1 came back empty -- $4"
    return
  fi
  if [ "$2" = "$3" ]; then
    pass "$1 names exactly the right $n entries"
    return
  fi
  ONLY_DOC="$(comm -23 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | tr '\n' ' ')"
  ONLY_TREE="$(comm -13 <(printf '%s\n' "$2") <(printf '%s\n' "$3") | tr '\n' ' ')"
  [ -n "$ONLY_DOC" ]  && fail "$1 lists entries the tree does not have: $ONLY_DOC"
  [ -n "$ONLY_TREE" ] && fail "$1 is missing entries the tree has: $ONLY_TREE"
}

# Rows between the heading and the next heading, first backticked token per row. The
# `| Skill | Purpose |` header and the `|---|` rule do not start with a backtick.
OPENCODE_SKILL_TABLE="$(awk '
  /^#### Available skills/ { f=1; next }
  f && /^#/ { exit }
  f && /^\| `/ { if (match($0, /`[a-z0-9-]+`/)) print substr($0, RSTART+1, RLENGTH-2) }
' "$OPENCODE_README" | sort)"
compare_list ".opencode Available skills table" "$OPENCODE_SKILL_TABLE" "$USER_FACING" \
  "the '#### Available skills' heading was renamed or the table removed, and the sentence above it is now pinned to nothing"

# Category bullets only. The intro sentence above them says "Invoke them with
# `@agentname`", and a whole-section sweep reads that placeholder as an agent.
OPENCODE_AGENT_LIST="$(awk '
  /^### Agents/ { f=1; next }
  f && /^###/ { exit }
  f && /^- \*\*/
' "$OPENCODE_README" | grep -Eo '@[a-z0-9-]+' | sed 's/^@//' | sort)"
compare_list ".opencode Agents @name list" "$OPENCODE_AGENT_LIST" "$ALL_AGENTS" \
  "the '### Agents' heading was renamed or the @name list removed"

README_HOOK_ROWS="$(awk '
  /^## Hooks/ { f=1; next }
  f && /^## / { exit }
  f && /^\| `/ { if (match($0, /`[a-z0-9-]+`/)) print substr($0, RSTART+1, RLENGTH-2) }
' "$README" | grep -c .)"
if [ "$README_HOOK_ROWS" -eq "$HOOK_TOTAL" ]; then
  pass "README.md's Hooks table has $README_HOOK_ROWS rows, one per registered hook"
else
  fail "README.md's Hooks table has $README_HOOK_ROWS rows but hooks.json registers $HOOK_TOTAL -- readme-structure.md requires every hook to be listed"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
