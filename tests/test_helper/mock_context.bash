#!/usr/bin/env bash
# mock_context.bash — Reusable setup/teardown and mock helpers for quiver-plugin tests.

# ---------------------------------------------------------------------------
# setup_mock_project
#   Creates a temp directory tree that mirrors the real plugin layout and sets
#   the environment variables the hook script and commands expect.
# ---------------------------------------------------------------------------
setup_mock_project() {
  MOCK_PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${MOCK_PROJECT_DIR}/.claude-plugin"
  mkdir -p "${MOCK_PROJECT_DIR}/.claude/handovers"
  mkdir -p "${MOCK_PROJECT_DIR}/commands"
  mkdir -p "${MOCK_PROJECT_DIR}/hooks/scripts"

  # Copy real plugin files into the mock tree
  PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."
  PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd)"

  cp "${PLUGIN_ROOT}/.claude-plugin/plugin.json" "${MOCK_PROJECT_DIR}/.claude-plugin/"
  cp "${PLUGIN_ROOT}/commands/"*.md "${MOCK_PROJECT_DIR}/commands/"
  cp "${PLUGIN_ROOT}/hooks/hooks.json" "${MOCK_PROJECT_DIR}/hooks/"
  cp "${PLUGIN_ROOT}/hooks/scripts/pre-compact-handover.sh" "${MOCK_PROJECT_DIR}/hooks/scripts/"

  export MOCK_PROJECT_DIR
  export CLAUDE_PROJECT_DIR="$MOCK_PROJECT_DIR"
  export CLAUDE_PLUGIN_ROOT="$MOCK_PROJECT_DIR"

  # Mock binary directory — prepend to PATH so stubs are found first
  MOCK_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$MOCK_BIN_DIR"
  export MOCK_BIN_DIR
  export PATH="${MOCK_BIN_DIR}:${PATH}"
}

# ---------------------------------------------------------------------------
# teardown_mock_project
#   Cleanup is automatic via $BATS_TEST_TMPDIR, but this resets env vars.
# ---------------------------------------------------------------------------
teardown_mock_project() {
  unset MOCK_PROJECT_DIR CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT MOCK_BIN_DIR
}

# ---------------------------------------------------------------------------
# inject_handover <name> <content>
#   Writes a fake handover file to .claude/handovers/<name>.md
# ---------------------------------------------------------------------------
inject_handover() {
  local name="$1"
  local content="$2"
  printf '%s\n' "$content" > "${MOCK_PROJECT_DIR}/.claude/handovers/${name}.md"
}

# ---------------------------------------------------------------------------
# inject_handovers_aged <count>
#   Creates <count> handover files with incrementing timestamps (oldest first).
# ---------------------------------------------------------------------------
inject_handovers_aged() {
  local count="$1"
  for i in $(seq 1 "$count"); do
    local ts
    ts=$(printf '2026-01-%02d_00-00-00' "$i")
    printf 'Handover %d\n' "$i" > "${MOCK_PROJECT_DIR}/.claude/handovers/${ts}.md"
  done
}

# ---------------------------------------------------------------------------
# mock_claude [exit_code] [output]
#   Creates a claude stub in MOCK_BIN_DIR that returns canned output.
# ---------------------------------------------------------------------------
mock_claude() {
  local exit_code="${1:-0}"
  local output="${2:-}"
  cat > "${MOCK_BIN_DIR}/claude" <<STUB
#!/usr/bin/env bash
# Consume all stdin (otherwise the caller may get SIGPIPE)
cat > /dev/null
printf '%b\\n' '$output'
exit $exit_code
STUB
  chmod +x "${MOCK_BIN_DIR}/claude"
}

# ---------------------------------------------------------------------------
# mock_git [status_output] [diff_output]
#   Creates a git stub that returns controlled output.
# ---------------------------------------------------------------------------
mock_git() {
  local status_output="${1:-}"
  local diff_output="${2:-}"
  cat > "${MOCK_BIN_DIR}/git" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"status --short"*|*"status -s"*)
    printf '%s\\n' '$status_output'
    ;;
  *"diff --stat"*)
    printf '%s\\n' '$diff_output'
    ;;
  *)
    printf ''
    ;;
esac
exit 0
STUB
  chmod +x "${MOCK_BIN_DIR}/git"
}

# ---------------------------------------------------------------------------
# mock_timeout
#   Creates a timeout stub that just executes the command (removes timeout behavior).
# ---------------------------------------------------------------------------
mock_timeout() {
  cat > "${MOCK_BIN_DIR}/timeout" <<'STUB'
#!/usr/bin/env bash
# Skip the timeout argument, execute the rest
shift  # skip duration
exec "$@"
STUB
  chmod +x "${MOCK_BIN_DIR}/timeout"
}

# ---------------------------------------------------------------------------
# get_handover_count
#   Returns count of .md files in mock handovers dir.
# ---------------------------------------------------------------------------
get_handover_count() {
  local count
  count=$(ls -1 "${MOCK_PROJECT_DIR}/.claude/handovers/"*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "$count"
}

# ---------------------------------------------------------------------------
# get_latest_handover
#   Returns path of most recent handover file (by name = by timestamp).
# ---------------------------------------------------------------------------
get_latest_handover() {
  ls -1r "${MOCK_PROJECT_DIR}/.claude/handovers/"*.md 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
# enable_dry_run
#   Sets DRY_RUN=1 and creates wrapper scripts that log instead of executing.
# ---------------------------------------------------------------------------
enable_dry_run() {
  export DRY_RUN=1

  cat > "${MOCK_BIN_DIR}/rm" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  # Skip flags
  [[ "$arg" == -* ]] && continue
  echo "[DRY-RUN] rm $arg" >> "${BATS_TEST_TMPDIR}/dry_run.log"
done
STUB
  chmod +x "${MOCK_BIN_DIR}/rm"
}
