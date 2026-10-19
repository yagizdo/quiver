#!/bin/bash
# test-git-log-fallback.sh
# Guards the fallback of every `git log` gather block in a skill.
#
# In a repository made with `git init` and no commit yet, every other gather block
# exits 0 -- rev-parse, branch, status, diff -- but `git log` exits 128 ("does not
# have any commits yet"). A git log block that falls back to NO_GIT therefore prints
# NO_GIT inside a real repository, and Step 0, which stops on any NO_GIT, reports
# "No git repository detected": /commit could not make a new project's first commit,
# and /ship treated the setup its own test plan describes as a directory with no git.
# Every git log block falls back to NO_COMMITS instead.
#
# /work is the one skill that reads the token, in two places. With no commit yet, its
# working branch does not resolve, so every worktree subagent's first step (switch to
# that branch) would come back BLOCKED. Phase 2.5 routes a NO_COMMITS run to the
# sequential path, and the second section pins that line so a renamed token cannot leave
# /work orchestrating. And `git checkout -b` on a default branch with no commit carries
# that state to the new branch, so the default branch never exists and a review against
# it stops on a missing base. Phase 2 makes an empty first commit first, and on a
# non-default branch creates the main branch the user picks from it; the third section
# pins that section, `--only`, which keeps staged files out of the commit, and `git branch`.
#
# Finding no git log block is a failure, not a pass. A reworded block form would
# otherwise leave this test asserting nothing.
#
# Run directly: bash tests/skills/test-git-log-fallback.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

EXIT=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

echo ""
echo "=== Every git log gather block falls back to NO_COMMITS ==="
BLOCKS="$(cd "$REPO_ROOT" && grep -rnoE '!`git log [^`]*`' skills --include='*.md')"
if [ -z "$BLOCKS" ]; then
  fail "no git log gather block found under skills/ -- the block form was reworded, and with no block this test asserts nothing"
else
  while IFS= read -r line; do
    case "$line" in
      *'|| echo "NO_COMMITS"`') pass "$line" ;;
      *) fail "$line -- falls back to something other than NO_COMMITS; in a repository with no commit yet, a NO_GIT here stops the skill as if git were missing" ;;
    esac
  done <<EOF
$BLOCKS
EOF
fi

echo ""
echo "=== /work runs a repository with no commit sequentially ==="
WORK="$REPO_ROOT/skills/work/SKILL.md"
if grep -E '^- \*\*No commit yet' "$WORK" | grep -q 'NO_COMMITS'; then
  pass "skills/work/SKILL.md Phase 2.5 has a 'No commit yet' line naming NO_COMMITS"
else
  fail "skills/work/SKILL.md has no '- **No commit yet' line naming NO_COMMITS -- a run in a repository with no commit would orchestrate, and every worktree subagent would come back BLOCKED"
fi

echo ""
echo "=== /work makes an empty first commit before branching off a default branch with none ==="
FIRST="$(sed -n '/^\*\*If the repository has no commit yet\*\*/,/^\*\*If already on a feature branch/p' "$WORK")"
for s in 'NO_COMMITS' 'git commit --allow-empty --only' 'git branch <name>'; do
  if printf '%s\n' "$FIRST" | grep -qF -- "$s"; then
    pass "skills/work/SKILL.md Phase 2 no-commit section names '$s'"
  else
    fail "skills/work/SKILL.md Phase 2 has no '**If the repository has no commit yet**' section naming '$s' -- the new branch would carry the commit-less state, the main branch would never exist, and the review against it would stop"
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
