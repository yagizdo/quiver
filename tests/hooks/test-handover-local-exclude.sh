#!/bin/bash
# test-handover-local-exclude.sh
# Runs hooks/scripts/pre-compact-handover.sh against throwaway repositories and
# asserts it applies the keep-local rule from skills/local-files/SKILL.md to
# .claude/handovers/: the directory is added to .git/info/exclude once, never
# twice, never when the project already tracks files there, and the hook still
# exits 0 outside a git repository.
#
# The hook pipes the transcript to `claude -p` through `timeout`. Both are
# replaced by stubs first on PATH, so no real model call is ever made: the
# `claude` stub prints a fixed note, and the `timeout` stub drops its duration
# and runs the rest (macOS ships no `timeout`). Global and system git config
# are switched off so a developer's own excludes file cannot pre-ignore the
# directory and turn an assertion green or red by accident.
#
# Run directly: bash tests/hooks/test-handover-local-exclude.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
HOOK="$REPO_ROOT/hooks/scripts/pre-compact-handover.sh"
EXIT=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

# One root made in this shell: new_dir runs inside $(...), a subshell, so any
# list it appended to would never reach the cleanup trap.
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/quiver-handover-test.XXXXXX")"
TMPROOT="$(cd "$TMPROOT" && pwd -P)"
trap 'rm -rf "$TMPROOT"' EXIT

new_dir() {
  mktemp -d "$TMPROOT/d.XXXXXX"
}

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

STUBS="$(new_dir)"
cat > "$STUBS/claude" <<'EOF'
#!/bin/bash
cat > /dev/null
echo "## Summary"
echo "stub handover"
EOF
cat > "$STUBS/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF
chmod +x "$STUBS/claude" "$STUBS/timeout"

TRANSCRIPT="$STUBS/transcript.jsonl"
echo '{"type":"user","message":"hello"}' > "$TRANSCRIPT"

# Runs the hook with the project dir set and the hook's cwd somewhere else, so a
# git call that reads the cwd instead of the project dir fails the assertions.
run_hook() {
  printf '{"transcript_path":"%s"}' "$TRANSCRIPT" \
    | (cd "$STUBS" && CLAUDE_PROJECT_DIR="$1" PATH="$STUBS:$PATH" GIT_CEILING_DIRECTORIES="$(dirname "$STUBS")" bash "$HOOK" >/dev/null 2>&1)
}

entry_count() {
  grep -cxF '.claude/handovers/' "$1/.git/info/exclude" 2>/dev/null
}

echo "Testing the PreCompact hook's keep-local step..."

echo ""
echo "=== 1. Untracked directory is added to .git/info/exclude once ==="

R1="$(new_dir)"
git -C "$R1" init -q
run_hook "$R1"
RC=$?
[ "$RC" -eq 0 ] && pass "first run exits 0" || fail "first run exits 0 (got $RC)"

N="$(entry_count "$R1")"
[ "$N" = "1" ] && pass "exclude file holds .claude/handovers/ once" \
  || fail "exclude file holds .claude/handovers/ once (got ${N:-0})"

if ls "$R1"/.claude/handovers/*.md >/dev/null 2>&1; then
  pass "a handover file was written through the stub"
else
  fail "a handover file was written through the stub"
fi

if git -C "$R1" check-ignore -q .claude/handovers/x; then
  pass "git check-ignore reports the directory ignored"
else
  fail "git check-ignore reports the directory ignored"
fi

echo ""
echo "=== 2. A second run adds nothing ==="

run_hook "$R1"
RC=$?
[ "$RC" -eq 0 ] && pass "second run exits 0" || fail "second run exits 0 (got $RC)"
N="$(entry_count "$R1")"
[ "$N" = "1" ] && pass "exclude file still holds the entry once" \
  || fail "exclude file still holds the entry once (got ${N:-0})"

echo ""
echo "=== 3. A tracked handover directory gains no entry ==="

R3="$(new_dir)"
git -C "$R3" init -q
mkdir -p "$R3/.claude/handovers"
echo "kept" > "$R3/.claude/handovers/keep.md"
git -C "$R3" add .claude/handovers/keep.md
git -C "$R3" -c user.name=t -c user.email=t@example.com commit -qm init
run_hook "$R3"
RC=$?
[ "$RC" -eq 0 ] && pass "tracked-directory run exits 0" || fail "tracked-directory run exits 0 (got $RC)"
N="$(entry_count "$R3")"
[ "${N:-0}" = "0" ] && pass "exclude file gains no entry" \
  || fail "exclude file gains no entry (got $N)"

echo ""
echo "=== 4. The user's last line is not joined to the entry ==="

R4="$(new_dir)"
git -C "$R4" init -q
printf '*.log' > "$R4/.git/info/exclude"
run_hook "$R4"
RC=$?
[ "$RC" -eq 0 ] && pass "no-trailing-newline run exits 0" || fail "no-trailing-newline run exits 0 (got $RC)"
if grep -qxF '*.log' "$R4/.git/info/exclude" && [ "$(entry_count "$R4")" = "1" ]; then
  pass "existing line kept intact and entry on its own line"
else
  fail "existing line kept intact and entry on its own line"
  sed 's/^/    /' "$R4/.git/info/exclude"
fi

echo ""
echo "=== 5. A project dir below the repo top gets an entry that matches ==="

# Exclude patterns are relative to the repo top. An entry written without the
# project's prefix never matches, so every later compaction would append again.
R6="$(new_dir)"
git -C "$R6" init -q
mkdir -p "$R6/app"
run_hook "$R6/app"
run_hook "$R6/app"
N="$(grep -cxF 'app/.claude/handovers/' "$R6/.git/info/exclude" 2>/dev/null)"
[ "$N" = "1" ] && pass "exclude file holds app/.claude/handovers/ once after two runs" \
  || fail "exclude file holds app/.claude/handovers/ once after two runs (got ${N:-0})"

echo ""
echo "=== 6. A .gitignore negation of the directory still gets one entry ==="

# .gitignore outranks .git/info/exclude, so check-ignore keeps reporting the
# directory as not ignored after the entry is in. Only the exact-line check
# stops the hook from appending again on every compaction.
R7="$(new_dir)"
git -C "$R7" init -q
printf '.claude/*\n!.claude/handovers/\n' > "$R7/.gitignore"
run_hook "$R7"
run_hook "$R7"
RC=$?
[ "$RC" -eq 0 ] && pass "negation run exits 0" || fail "negation run exits 0 (got $RC)"
N="$(entry_count "$R7")"
[ "$N" = "1" ] && pass "exclude file holds the entry once after two runs" \
  || fail "exclude file holds the entry once after two runs (got ${N:-0})"

echo ""
echo "=== 7. A symlinked .claude gains no entry ==="

# check-ignore exits 128 ("beyond a symbolic link") here. That is an error, not
# "not ignored", so the hook must not append.
R8="$(new_dir)"
git -C "$R8" init -q
ln -s "$(new_dir)" "$R8/.claude"
run_hook "$R8"
run_hook "$R8"
RC=$?
[ "$RC" -eq 0 ] && pass "symlink run exits 0" || fail "symlink run exits 0 (got $RC)"
N="$(entry_count "$R8")"
[ "${N:-0}" = "0" ] && pass "exclude file gains no entry" \
  || fail "exclude file gains no entry (got $N)"

echo ""
echo "=== 8. Outside a git repository the hook exits 0 ==="

R5="$(new_dir)"
run_hook "$R5"
RC=$?
[ "$RC" -eq 0 ] && pass "non-repo run exits 0" || fail "non-repo run exits 0 (got $RC)"
[ ! -e "$R5/.git" ] && pass "no .git created" || fail "no .git created"

echo ""
echo "================================"
if [ $EXIT -eq 0 ]; then
  echo "All tests passed."
else
  echo "Some tests FAILED."
fi
exit $EXIT
