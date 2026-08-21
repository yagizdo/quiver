#!/bin/bash
# test-capability-profile-contract.sh
# Guards the agent capability contract:
#   producer  .claude/rules/agent-capability-rules.md -- canonical disallowedTools strings + assignments
#   consumer  agents/**/*.md                          -- each agent restates its profile's string verbatim
#   consumer  workflows/*.js                          -- no maxTurns (CP8), no tools allowlist (CP3) in agent options
#
# The string lives in two places by construction. This test fails mechanically when a copy drifts,
# when an agent is missing from the Assignments table, or when a table row has no agent file.
#
# It reads the real files. It never writes a fixture and greps it with a rule hardcoded here --
# that form passes whatever the fixture says, which is the opposite of a drift guard.
#
# Run directly: bash tests/agents/test-capability-profile-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RULES="$REPO_ROOT/.claude/rules/agent-capability-rules.md"
AGENTS_DIR="$REPO_ROOT/agents"
WORKFLOWS_DIR="$REPO_ROOT/workflows"

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# --- Preflight ---
echo ""
echo "=== 1. Preflight ==="
if [ ! -f "$RULES" ]; then
  fail "missing $RULES -- cannot check the contract."
  exit $EXIT
fi
if [ ! -d "$AGENTS_DIR" ]; then
  fail "missing $AGENTS_DIR -- cannot check the contract."
  exit $EXIT
fi
pass "rules file and agents directory present"

# Extract a frontmatter field, bounded to the block between the first two --- delimiters.
fm() {
  awk -v key="$2" '
    BEGIN { c = 0 }
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      print
      exit
    }' "$1"
}

# Count how many times a key appears inside the frontmatter block.
# YAML resolves duplicates last-wins; fm() reads only the first, so a file
# carrying both a canonical and a weakened value would otherwise pass.
fm_count() {
  awk -v key="$2" '
    BEGIN { c = 0; n = 0 }
    /^---[[:space:]]*$/ { c++; if (c == 2) exit; next }
    c == 1 && index($0, key ":") == 1 { n++ }
    END { print n + 0 }' "$1"
}

# Strip surrounding quotes, collapse whitespace around commas, trim ends.
norm() {
  printf '%s' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//" \
          -e 's/[[:space:]]*,[[:space:]]*/, /g' \
          -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Canonical disallowedTools for a profile, read from the ## Profiles section.
canonical() {
  awk -v p="$1" '
    /^## Profiles/ { s = 1; next }
    /^## / { s = 0 }
    s && $0 ~ ("^\\| `" p "` \\|") {
      if (match($0, /\|[^|]*\|[[:space:]]*`[^`]*`/)) {
        line = $0
        sub(/^\|[^|]*\|[[:space:]]*`/, "", line)
        sub(/`.*$/, "", line)
        print line
        exit
      }
    }' "$RULES"
}

# Assigned profile and effort for an agent, read from the ## Assignments section.
assigned() {
  awk -v a="$1" -v col="$2" '
    /^## Assignments/ { s = 1; next }
    /^## / { s = 0 }
    s && $0 ~ ("^\\| `" a "` \\|") {
      n = split($0, f, "|")
      v = f[col + 1]
      gsub(/[` ]/, "", v)
      print v
      exit
    }' "$RULES"
}

# --- Every agent file conforms ---
# A profile that lost its canonical string is caught here, per agent assigned to it.
# A standalone profile-definition pass would need the profile names hardcoded a third
# time, after the ## Profiles and ## Assignments tables, and could not fail alone.
echo ""
echo "=== 2. Agent frontmatter matches its assigned profile ==="
agent_count=0
while IFS= read -r file; do
  agent_count=$((agent_count + 1))
  rel="${file#"$REPO_ROOT"/}"
  name="$(fm "$file" name)"
  name="$(norm "$name")"

  if [ -z "$name" ]; then
    fail "$rel: no 'name' field in frontmatter"
    continue
  fi

  profile="$(assigned "$name" 2)"
  effort_want="$(assigned "$name" 3)"
  if [ -z "$profile" ]; then
    fail "$rel: agent '$name' is not in the ## Assignments table"
    continue
  fi

  want="$(canonical "$profile")"
  if [ -z "$want" ]; then
    fail "$rel: assigned profile '$profile' is not defined in ## Profiles"
    continue
  fi

  got="$(norm "$(fm "$file" disallowedTools)")"
  if [ -z "$got" ]; then
    fail "$rel: no 'disallowedTools' field (expected profile '$profile')"
  elif [ "$got" = "$(norm "$want")" ]; then
    pass "$rel: $profile"
  else
    fail "$rel: disallowedTools drift -- want '$want', got '$got'"
  fi

  effort_got="$(norm "$(fm "$file" effort)")"
  if [ -z "$effort_got" ]; then
    fail "$rel: no 'effort' field (expected '$effort_want')"
  elif [ "$effort_got" != "$effort_want" ]; then
    fail "$rel: effort drift -- want '$effort_want', got '$effort_got'"
  fi

  case "$effort_got" in
    low|medium|high|xhigh|max|"") ;;
    *) fail "$rel: effort '$effort_got' is not a legal value" ;;
  esac

  for k in disallowedTools effort tools maxTurns; do
    if [ "$(fm_count "$file" "$k")" -gt 1 ]; then
      fail "$rel: '$k' appears more than once in frontmatter -- YAML takes the last, this test reads the first"
    fi
  done

  if [ -n "$(fm "$file" tools)" ]; then
    fail "$rel: sets 'tools' -- CP3 forbids allowlists on agents"
  fi
  if [ -n "$(fm "$file" maxTurns)" ]; then
    fail "$rel: sets 'maxTurns' -- CP8 bans it on synthesis-feeding agents"
  fi
  case "$(fm "$file" disallowedTools)" in
    *mcp__*) fail "$rel: disallowedTools contains an mcp__ pattern -- CP4 forbids it" ;;
  esac
done < <(find "$AGENTS_DIR" -name '*.md' -type f | sort)

if [ "$agent_count" -gt 0 ]; then
  pass "scanned $agent_count agent files"
else
  fail "no agent files found under $AGENTS_DIR"
fi

# --- Every table row has a file ---
echo ""
echo "=== 3. Assignments table has no orphan rows ==="
while IFS= read -r row; do
  [ -n "$row" ] || continue
  if find "$AGENTS_DIR" -name "$row.md" -type f | grep -q .; then
    pass "row '$row' has an agent file"
  else
    fail "row '$row' in ## Assignments has no matching file under agents/"
  fi
done < <(awk '
  /^## Assignments/ { s = 1; next }
  /^## / { s = 0 }
  s && /^\| `/ {
    n = split($0, f, "|")
    v = f[2]
    gsub(/[` ]/, "", v)
    print v
  }' "$RULES")

# --- Workflow scripts carry no per-call capability overrides ---
# CP3 and CP8 are agent-frontmatter rules, but a workflow script passes agent options
# in JavaScript, where the frontmatter checks above cannot see them. The grep is textual
# on purpose: a `maxTurns` inside a comment is still a `maxTurns` a reader will copy.
echo ""
echo "=== 4. Workflow scripts respect CP3 and CP8 ==="
workflow_count=0
if [ ! -d "$WORKFLOWS_DIR" ]; then
  pass "no workflows/ directory -- nothing to check"
else
  while IFS= read -r file; do
    workflow_count=$((workflow_count + 1))
    rel="${file#"$REPO_ROOT"/}"

    if grep -q 'maxTurns' "$file"; then
      fail "$rel: sets 'maxTurns' -- CP8 bans it on synthesis-feeding agents"
    else
      pass "$rel: no maxTurns"
    fi

    # Anchored on a non-identifier char so disallowedTools, allowedTools, and the like
    # are not read as an allowlist. The optional quote on each side is load-bearing:
    # quoted keys are the prevailing style in workflows/review-fanout.js, and a pattern
    # that only tolerates a bare key misses 'tools': and "tools": entirely. The leading
    # quote is optional rather than required so a bare key still matches, and the
    # anchor still rejects 'disallowedTools': because the character before "tools"
    # there is an identifier char, not the quote.
    if grep -qE '(^|[^[:alnum:]_$])['"'"'"]?tools['"'"'"]?[[:space:]]*:' "$file"; then
      fail "$rel: sets 'tools' -- CP3 forbids allowlists, use disallowedTools"
    else
      pass "$rel: no tools allowlist"
    fi
  done < <(find "$WORKFLOWS_DIR" -name '*.js' -type f | LC_ALL=C sort)

  if [ "$workflow_count" -eq 0 ]; then
    pass "workflows/ has no .js files -- nothing to check"
  else
    pass "scanned $workflow_count workflow files"
  fi
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
