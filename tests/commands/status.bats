#!/usr/bin/env bats
# Tests for shell blocks in commands/status.md

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../test_helper/mock_context'
  load '../test_helper/shell_extractor'

  setup_mock_project

  STATUS_MD="${MOCK_PROJECT_DIR}/commands/status.md"
}

teardown() {
  teardown_mock_project
}

# ---------------------------------------------------------------------------
# Block 0: plugin name and version
# ---------------------------------------------------------------------------

@test "extracts plugin name and version" {
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 0
  assert_success
  assert_output "quiver v1.0.0"
}

# ---------------------------------------------------------------------------
# Block 1: handover count
# ---------------------------------------------------------------------------

@test "counts handover files correctly — 0 files" {
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 1
  assert_success
  assert_output "0"
}

@test "counts handover files correctly — 3 files" {
  inject_handovers_aged 3
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 1
  assert_success
  assert_output "3"
}

# ---------------------------------------------------------------------------
# Block 2: latest handover
# ---------------------------------------------------------------------------

@test "shows latest handover file" {
  inject_handovers_aged 3
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 2
  assert_success
  assert_output --partial "2026-01-03_00-00-00.md"
}

@test "shows empty when no handovers" {
  # The pipeline `ls ... | head -1 || echo "none"` returns empty because
  # head exits 0 even with no input, so the || branch never fires.
  rm -f "${MOCK_PROJECT_DIR}/.claude/handovers/"*.md 2>/dev/null
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 2
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# Block 3: PreCompact registration
# ---------------------------------------------------------------------------

@test "detects PreCompact registration" {
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 3
  assert_success
  assert_output "registered"
}

# ---------------------------------------------------------------------------
# Block 4: hook script executable check
# ---------------------------------------------------------------------------

@test "detects hook script is executable" {
  chmod +x "${MOCK_PROJECT_DIR}/hooks/scripts/pre-compact-handover.sh"
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 4
  assert_success
  assert_output "executable"
}

@test "detects missing hook script" {
  rm -f "${MOCK_PROJECT_DIR}/hooks/scripts/pre-compact-handover.sh"
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$STATUS_MD" 4
  assert_success
  assert_output "MISSING"
}
