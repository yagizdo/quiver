#!/usr/bin/env bats
# Tests for shell blocks in commands/delete-last-handover.md

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../test_helper/bats-file/load'
  load '../test_helper/mock_context'
  load '../test_helper/shell_extractor'

  setup_mock_project

  DELETE_LAST_MD="${MOCK_PROJECT_DIR}/commands/delete-last-handover.md"
}

teardown() {
  teardown_mock_project
}

# ---------------------------------------------------------------------------
# Block 0: delete last handover
# ---------------------------------------------------------------------------

@test "deletes the most recent file" {
  inject_handovers_aged 3
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$DELETE_LAST_MD" 0
  assert_success
  # The newest (03) should be deleted, 01 and 02 remain
  assert_file_not_exists "${MOCK_PROJECT_DIR}/.claude/handovers/2026-01-03_00-00-00.md"
  assert_file_exists "${MOCK_PROJECT_DIR}/.claude/handovers/2026-01-01_00-00-00.md"
  assert_file_exists "${MOCK_PROJECT_DIR}/.claude/handovers/2026-01-02_00-00-00.md"
}

@test "reports remaining count" {
  inject_handovers_aged 3
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$DELETE_LAST_MD" 0
  assert_success
  assert_output --partial "Remaining: 2"
}

@test "handles no files gracefully" {
  rm -f "${MOCK_PROJECT_DIR}/.claude/handovers/"*.md 2>/dev/null
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$DELETE_LAST_MD" 0
  assert_success
  assert_output --partial "No handover files found"
}
