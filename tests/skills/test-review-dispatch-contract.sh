#!/bin/bash
# test-review-dispatch-contract.sh
# Guards the review dispatch contract:
#   producer  .claude/rules/review-agent-rules.md -- canonical ## Dispatch Gates table (Agent | Gate | Modes)
#   consumer  skills/review/SKILL.md              -- Step 2b prose restates every row for the prompt path
#
# The table lives in two places by construction. This test fails mechanically when a copy
# drifts, when an agent in dispatch scope has no canonical row, or when a canonical row names
# no agent file.
#
# It reads the real files. It never writes a fixture and greps it with a rule hardcoded here --
# that form passes whatever the fixture says, which is the opposite of a drift guard.
#
# Run directly: bash tests/skills/test-review-dispatch-contract.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RULES="$REPO_ROOT/.claude/rules/review-agent-rules.md"
SKILL="$REPO_ROOT/skills/review/SKILL.md"
AGENTS_DIR="$REPO_ROOT/agents"

# Dispatch scope: every file under agents/review/ plus the two cross-category paths
# skills/review/SKILL.md Step 2a adds by hand as Tier 2. Agents outside this set are
# not /quiver:review participants and carry no dispatch gate.
TIER2="agents/research/best-practices-researcher.md agents/research/project-context-analyst.md"

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# --- Preflight ---
echo ""
echo "=== 1. Preflight ==="
MISSING=0
if [ ! -f "$RULES" ]; then
  fail "missing $RULES -- the canonical ## Dispatch Gates table lives here."
  MISSING=1
fi
if [ ! -f "$SKILL" ]; then
  fail "missing $SKILL -- the prompt-path copy of the table lives here."
  MISSING=1
fi
if [ ! -d "$AGENTS_DIR/review" ]; then
  fail "missing $AGENTS_DIR/review -- cannot check for ungated agents."
  MISSING=1
fi
if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "================================"
  echo "Some tests FAILED."
  exit $EXIT
fi
pass "rules file, skill file, and agents/review/ all present"

# fm_count()'s single-occurrence discipline, ported. Both region extractors below stop
# at their first anchor, so a second copy of either one would be silently ignored and
# the wrong block validated. The rules-file count is anchored on ^## on purpose: the
# Scope paragraph cross-references the section by name, so an unanchored count is 2.
ANCHORS="$(grep -c '^## Dispatch Gates' "$RULES")"
if [ "$ANCHORS" -eq 1 ]; then
  pass "'## Dispatch Gates' appears exactly once as a heading in the rules file"
else
  fail "'## Dispatch Gates' appears $ANCHORS times as a heading in the rules file -- expected exactly 1"
fi

# --- Shared normalizers ---
# Prepended to every extractor so the three copies are compared as token sets rather
# than as authored text. Reordering a cell is not a gate change; adding or dropping a
# class is. Defined once here because three separate copies of a normalizer is the
# same drift problem this test exists to catch.
AWK_NORM='
function listnorm(raw, ordstr,   n, ord, m, t, i, j, out, seen) {
  gsub(/`/, "", raw)
  gsub(/[[:space:]]/, "", raw)
  n = split(ordstr, ord, ",")
  m = split(raw, t, ",")
  out = ""
  for (i = 1; i <= n; i++) {
    for (j = 1; j <= m; j++) {
      if (t[j] == ord[i]) {
        if (out == "") out = ord[i]; else out = out ", " ord[i]
        seen[j] = 1
        break
      }
    }
  }
  for (j = 1; j <= m; j++) {
    if (t[j] != "" && !(j in seen)) {
      if (out == "") out = t[j]; else out = out ", " t[j]
    }
  }
  return out
}
function classnorm(raw) {
  return listnorm(raw, "SCRIPT,CODE,CONFIG-APP,CONFIG-MANIFEST,PROMPT,DOCS")
}
function modenorm(raw,   v) {
  # The canonical Modes cell spells "joins no fan-out" as --; the script spells the
  # same thing as an empty mode list. Both normalize to the empty string.
  v = listnorm(raw, "fast,deep")
  if (v == "--") v = ""
  return v
}
function trim(s) {
  gsub(/^[[:space:]]+/, "", s)
  gsub(/[[:space:]]+$/, "", s)
  return s
}
'

# --- Extraction A: the canonical table ---
# Entry is anchored on ^## Dispatch Gates and any other ^## clears the flag, the same
# region shape tests/agents/test-capability-profile-contract.sh uses for ## Profiles.
# Rows are matched on a backticked first cell, which excludes the header and the rule.
canonical_norm() {
  awk "$AWK_NORM"'
    /^## Dispatch Gates/ { s = 1; next }
    /^## / { s = 0 }
    s && /^\| `/ {
      n = split($0, f, "|")
      if (n < 5) next
      a = trim(f[2]); gsub(/`/, "", a)
      print a "\t" classnorm(f[3]) "\t" modenorm(f[4])
    }' "$RULES"
}

# --- Extraction B: the Step 2b gate prose ---
# The region is anchored on its two literal boundary headings. Exiting on any ^###
# instead would close the region at "### Review depth dispatch", three lines in and
# before a single agent bullet, and both directions of section 3 would then compare
# empty sets and pass.
#
# Rows are matched on the bullet form the gate prose actually uses -- "- **" followed
# immediately by a backticked agent name. A bare backtick scan would also collect
# SCRIPT, CODE, CONFIG-APP, $ARGUMENTS, --with-codex, wc -l, command -v codex and
# quiver:{name}. The "- **Future agents**:" bullet has no backtick after "- **" and is
# excluded by the same anchor, as are the args-payload bullets, which open with a
# backticked field name rather than with "**".
#
# The class list is read only from the gate clause: the span running from the word
# "contains" to the first "." after it. Two bullets name classes outside that span and
# mean the negation of a gate by them -- security-audit's "Skip when all files are
# PROMPT, DOCS, or CONFIG-MANIFEST" and best-practices-researcher's "Configuration
# files (both CONFIG-APP and CONFIG-MANIFEST) do not trigger this agent". Collecting
# every class token in the bullet reads the second one as SCRIPT, CODE, CONFIG-APP and
# passes it against a canonical SCRIPT, CODE, which is the false pass this test exists
# to prevent.
#
# A gate clause that names no class at all is a PRECONDITION: codex-code-reviewer's
# bullet contains the word "contains" but its three conditions read state no manifest
# carries. That mapping is not a special case for one agent -- a class-gated bullet
# that lost every class token also lands here, and then fails against its canonical
# class list, which is the intended loud failure.
#
# Each agent is stated twice in the region, once in the fast block and once in the deep
# block. Identical (agent, gate) pairs are deduped; a disagreeing pair survives as a
# second row and section 3 reports it.
#
# The enclosing block is the ONLY place the prose encodes an agent's modes, so it is
# tracked and emitted as a third field. Dropping it is not a cosmetic loss: deleting an
# agent's fast-mode bullet leaves the canonical table and the script both saying
# "fast, deep" while the prompt path -- the path every non-Claude CLI takes -- silently
# reviews with one agent fewer, which is the failure direction Step 2b itself calls
# unrecoverable. Section 2 compares modes for the script copy; this must be symmetric.
#
# report-checker and senior-reviewer sit in the deep block but carry a canonical Modes
# cell of --, because they join no fan-out. A NEVER gate therefore maps to the empty mode
# list here, the same normalization modenorm() applies to -- on the canonical side.
skill_norm() {
  awk "$AWK_NORM"'
    index($0, "### 2b -- Conditional Dispatch") == 1 { s = 1; next }
    index($0, "### Adding future agents") == 1 { s = 0 }
    s && index($0, "**If `review_mode = fast`:**") == 1 { blk = "fast"; next }
    s && index($0, "### Deep mode dispatch rules") == 1 { blk = "deep"; next }
    s && /^- \*\*`/ {
      line = $0
      name = line
      sub(/^- \*\*`/, "", name)
      sub(/`.*$/, "", name)

      if (index(line, "Never dispatched") > 0) {
        gate = "NEVER"
      } else if (index(line, "Always dispatched") > 0) {
        gate = "UNCONDITIONAL"
      } else if (match(line, /contains/)) {
        clause = substr(line, RSTART)
        p = index(clause, ".")
        if (p > 0) clause = substr(clause, 1, p)
        gate = ""
        if (index(clause, "`SCRIPT`") > 0) gate = gate "SCRIPT,"
        if (index(clause, "`CODE`") > 0) gate = gate "CODE,"
        if (index(clause, "`CONFIG-APP`") > 0) gate = gate "CONFIG-APP,"
        sub(/,$/, "", gate)
        if (gate == "") gate = "PRECONDITION"
      } else {
        gate = "UNPARSED"
      }

      key = name "\t" classnorm(gate)
      if (!(key in blocks)) { border[++bn] = key; blocks[key] = "" }
      if (blk != "" && index(blocks[key], blk) == 0) blocks[key] = blocks[key] blk ","
    }
    END {
      for (bi = 1; bi <= bn; bi++) {
        key = border[bi]
        split(key, kf, "\t")
        m = ""
        if (kf[2] != "NEVER") m = modenorm(blocks[key])
        print key "\t" m
      }
    }' "$SKILL"
}

CANON_NORM="$(canonical_norm)"
SKILL_ROWS="$(skill_norm)"

# --- Canonical table vs the Step 2b prose ---
# The class comparison is the load-bearing half. The prose is the only path any
# non-Claude CLI ever takes, so widening one agent's gate there and nowhere else is
# the divergence that matters most, and the one an agent-set-only comparison cannot
# see. The mode comparison exists for the same reason: an agent dropped from the
# fast block reviews nothing on the prompt path while the canonical table still
# claims it runs.
echo ""
echo "=== 2. Canonical table matches Step 2b prose in skills/review/SKILL.md ==="
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    "OK "*) pass "${line#OK }" ;;
    *) fail "$line" ;;
  esac
done < <(awk -F'\t' '
  $1 == "" { next }
  NR == FNR { cg[$1] = $2; cm[$1] = $3; corder[++cn] = $1; next }
  {
    if ($1 in pg) { pdup[$1] = 1 } else { pg[$1] = $2; pm[$1] = $3; porder[++pn] = $1 }
  }
  END {
    if (cn == 0) { print "no rows extracted from ## Dispatch Gates -- the table or its heading moved"; }
    if (pn == 0) { print "no agent bullets extracted from the Step 2b region -- check the two boundary headings and the bullet form"; }
    for (i = 1; i <= cn; i++) {
      a = corder[i]
      if (!(a in pg)) {
        print "`" a "`: canonical row is not gated anywhere in the Step 2b region"
        continue
      }
      if (a in pdup) {
        print "`" a "`: Step 2b states two different class lists for this agent"
        continue
      }
      if (cg[a] != pg[a]) {
        print "`" a "`: gate drift -- rules say [" cg[a] "], Step 2b prose says [" pg[a] "]"
        continue
      }
      if (cm[a] != pm[a]) {
        print "`" a "`: modes drift -- rules say [" cm[a] "], Step 2b prose says [" pm[a] "]"
        continue
      }
      print "OK `" a "`: gate [" cg[a] "], modes [" cm[a] "]"
    }
    for (i = 1; i <= pn; i++) {
      a = porder[i]
      if (!(a in cg)) print "`" a "`: gated in Step 2b but has no row in ## Dispatch Gates"
    }
    if (cn > 0 && pn > 0) print "OK compared " cn " canonical rows against " pn " Step 2b bullets"
  }' <(printf '%s\n' "$CANON_NORM") <(printf '%s\n' "$SKILL_ROWS"))

# --- No ungated agent ---
# Both directions, mirroring the orphan check in the capability verifier: an agent in
# dispatch scope with no row is dispatched on every diff at runtime, and a row naming
# no agent file is a gate for something that no longer exists.
echo ""
echo "=== 3. Every agent in dispatch scope has a canonical row ==="

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

norm() {
  printf '%s' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

scope_files() {
  find "$AGENTS_DIR/review" -name '*.md' -type f | LC_ALL=C sort
  for rel in $TIER2; do
    echo "$REPO_ROOT/$rel"
  done
}

SCOPE_FILES="$(scope_files)"

scope_count=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  scope_count=$((scope_count + 1))
  rel="${file#"$REPO_ROOT"/}"

  if [ ! -f "$file" ]; then
    fail "$rel: listed in dispatch scope but the file does not exist"
    continue
  fi

  name="$(norm "$(fm "$file" name)")"
  if [ -z "$name" ]; then
    fail "$rel: no 'name' field in frontmatter -- cannot resolve a dispatch gate"
    continue
  fi

  gate="$(printf '%s\n' "$CANON_NORM" | awk -F'\t' -v a="$name" '$1 == a { print $2; exit }')"
  if [ -z "$gate" ]; then
    fail "$rel: agent '$name' has no row in ## Dispatch Gates -- it would be dispatched on every diff"
  else
    pass "$rel: $gate"
  fi
done < <(printf '%s\n' "$SCOPE_FILES")

if [ "$scope_count" -gt 0 ]; then
  pass "scanned $scope_count agents in dispatch scope"
else
  fail "no agent files in dispatch scope -- the glob matched nothing"
fi

row_count=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  row_count=$((row_count + 1))
  if printf '%s\n' "$SCOPE_FILES" | grep -q "/$row\.md\$"; then
    pass "row \`$row\` has an agent file in dispatch scope"
  else
    fail "row \`$row\` in ## Dispatch Gates has no agent file in dispatch scope"
  fi
done < <(printf '%s\n' "$CANON_NORM" | awk -F'\t' '$1 != "" { print $1 }')

if [ "$row_count" -eq 0 ]; then
  fail "no rows in ## Dispatch Gates -- nothing to resolve against agents/"
fi

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
