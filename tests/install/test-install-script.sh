#!/bin/bash
# test-install-script.sh
# Validates install.sh: the symlink handler, idempotency, the refusal to clobber
# a real path, --uninstall, and the shape of the target table.
#
# Every scenario runs under a throwaway HOME from mktemp -d, so a failing
# assertion can never touch the developer's real ~/.config/opencode.
#
# Run directly: bash tests/install/test-install-script.sh

set -u

EXIT=0
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO_ROOT/install.sh"
TMPDIRS=""

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; EXIT=1; }

cleanup() {
  for d in $TMPDIRS; do
    [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT

# A fresh fake HOME. Registered for cleanup so an early failure still tidies up.
new_home() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/quiver-install-test.XXXXXX")"
  TMPDIRS="$TMPDIRS $d"
  printf '%s' "$d"
}

echo "Testing install.sh..."

# 0. Script exists and is executable
if [ -f "$SCRIPT" ]; then
  pass "install.sh exists at the repo root"
else
  fail "install.sh exists at the repo root"
  echo ""
  echo "Some install script tests failed."
  exit 1
fi

if [ -x "$SCRIPT" ]; then
  pass "install.sh is executable"
else
  fail "install.sh is executable"
fi

# --- Scenario 1: ~/.config/opencode exists, the symlink is created ---

H1="$(new_home)"
mkdir -p "$H1/.config/opencode"
OUT1="$(HOME="$H1" bash "$SCRIPT" 2>&1)"
RC1=$?
LINK1="$H1/.config/opencode/plugins/quiver.js"

if [ -L "$LINK1" ]; then
  pass "detected opencode: symlink created at ~/.config/opencode/plugins/quiver.js"
else
  fail "detected opencode: symlink created at ~/.config/opencode/plugins/quiver.js"
  echo "$OUT1" | sed 's/^/    /'
fi

if [ "$(readlink "$LINK1")" = "$REPO_ROOT/.opencode/plugins/quiver.js" ]; then
  pass "symlink points at the plugin file in this clone"
else
  fail "symlink points at the plugin file in this clone (got: $(readlink "$LINK1" 2>/dev/null))"
fi

if [ "$RC1" -eq 0 ]; then
  pass "install on a clean HOME exits 0"
else
  fail "install on a clean HOME exits 0 (got $RC1)"
fi

# The parent directory did not exist; the handler must create it rather than fail.
if [ -d "$H1/.config/opencode/plugins" ]; then
  pass "missing parent directory is created"
else
  fail "missing parent directory is created"
fi

# A native row prints its command and must never create anything on disk.
if echo "$OUT1" | grep -q "plugin marketplace add"; then
  pass "native target prints its command instead of running it"
else
  fail "native target prints its command instead of running it"
  echo "$OUT1" | sed 's/^/    /'
fi

# --- Scenario 2: run again, nothing changes, exit 0 ---

BEFORE2="$(readlink "$LINK1")"
OUT2="$(HOME="$H1" bash "$SCRIPT" 2>&1)"
RC2=$?

if [ "$RC2" -eq 0 ]; then
  pass "second run exits 0"
else
  fail "second run exits 0 (got $RC2)"
fi

if [ "$(readlink "$LINK1")" = "$BEFORE2" ]; then
  pass "second run leaves the symlink untouched"
else
  fail "second run leaves the symlink untouched"
fi

if echo "$OUT2" | grep -qi "already installed"; then
  pass "second run reports the target as already installed"
else
  fail "second run reports the target as already installed"
  echo "$OUT2" | sed 's/^/    /'
fi

# --- Scenario 3: a real directory sits at the destination ---

H3="$(new_home)"
mkdir -p "$H3/.config/opencode/plugins/quiver.js"
echo "user data" > "$H3/.config/opencode/plugins/quiver.js/keep-me.txt"
OUT3="$(HOME="$H3" bash "$SCRIPT" 2>&1)"
RC3=$?

if [ "$RC3" -ne 0 ]; then
  pass "a real directory at the destination makes the run exit nonzero"
else
  fail "a real directory at the destination makes the run exit nonzero"
fi

if [ -f "$H3/.config/opencode/plugins/quiver.js/keep-me.txt" ]; then
  pass "the real directory and its contents are left intact"
else
  fail "the real directory and its contents are left intact"
fi

if [ ! -L "$H3/.config/opencode/plugins/quiver.js" ]; then
  pass "the real directory was not replaced by a symlink"
else
  fail "the real directory was not replaced by a symlink"
fi

if echo "$OUT3" | grep -qi "skip"; then
  pass "the skipped target prints a reason"
else
  fail "the skipped target prints a reason"
  echo "$OUT3" | sed 's/^/    /'
fi

# --- Scenario 4: --uninstall removes our symlink and leaves a real path alone ---

H4="$(new_home)"
mkdir -p "$H4/.config/opencode"
HOME="$H4" bash "$SCRIPT" >/dev/null 2>&1
LINK4="$H4/.config/opencode/plugins/quiver.js"

OUT4="$(HOME="$H4" bash "$SCRIPT" --uninstall 2>&1)"
RC4=$?

if [ ! -e "$LINK4" ]; then
  pass "--uninstall removes the symlink that resolves into the repo"
else
  fail "--uninstall removes the symlink that resolves into the repo"
fi

if [ "$RC4" -eq 0 ]; then
  pass "--uninstall exits 0 when everything it found was its own"
else
  fail "--uninstall exits 0 when everything it found was its own (got $RC4)"
  echo "$OUT4" | sed 's/^/    /'
fi

# Now put something the script does not own at the same destination.
mkdir -p "$LINK4"
echo "not ours" > "$LINK4/keep-me.txt"

OUT4B="$(HOME="$H4" bash "$SCRIPT" --uninstall 2>&1)"
RC4B=$?

if [ -f "$LINK4/keep-me.txt" ]; then
  pass "--uninstall leaves a real directory alone"
else
  fail "--uninstall leaves a real directory alone"
fi

if [ "$RC4B" -ne 0 ]; then
  pass "--uninstall exits nonzero when it declines to remove something"
else
  fail "--uninstall exits nonzero when it declines to remove something"
  echo "$OUT4B" | sed 's/^/    /'
fi

# --- Scenario 5: every target row has exactly six columns ---

HELP="$(bash "$SCRIPT" --help 2>&1)"
RCH=$?

if [ "$RCH" -eq 0 ]; then
  pass "--help exits 0"
else
  fail "--help exits 0 (got $RCH)"
fi

ROWS="$(printf '%s\n' "$HELP" | awk -F'\t' 'NF > 1')"
ROW_COUNT="$(printf '%s' "$ROWS" | grep -c . )"
BAD_COUNT="$(printf '%s' "$ROWS" | awk -F'\t' 'NF != 6' | grep -c . )"

if [ "$ROW_COUNT" -ge 3 ]; then
  pass "--help prints the target table ($ROW_COUNT rows)"
else
  fail "--help prints the target table (found $ROW_COUNT rows, expected at least 3)"
fi

if [ "$BAD_COUNT" -eq 0 ]; then
  pass "every target row has exactly six tab-separated columns"
else
  fail "every target row has exactly six tab-separated columns ($BAD_COUNT bad rows)"
  printf '%s\n' "$ROWS" | awk -F'\t' 'NF != 6 { print "    " NF " cols: " $0 }'
fi

# --- Summary ---

if [ $EXIT -eq 0 ]; then
  echo ""
  echo "All install script tests passed."
else
  echo ""
  echo "Some install script tests failed."
fi

exit $EXIT
