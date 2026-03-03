#!/usr/bin/env bats
# Tests for shell blocks in commands/delete-all-handovers.md

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../test_helper/mock_context'
  load '../test_helper/shell_extractor'

  setup_mock_project

  DELETE_ALL_MD="${MOCK_PROJECT_DIR}/commands/delete-all-handovers.md"
}

teardown() {
  teardown_mock_project
}

# ---------------------------------------------------------------------------
# Block 0: delete all handovers
# ---------------------------------------------------------------------------

@test "removes all handover files" {
  inject_handovers_aged 4
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$DELETE_ALL_MD" 0
  assert_success
  assert_equal "$(get_handover_count)" "0"
}

@test "reports count purged" {
  inject_handovers_aged 3
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$DELETE_ALL_MD" 0
  assert_success
  assert_output --partial "Purged 3 handover file(s)."
}

@test "handles empty directory" {
  rm -f "${MOCK_PROJECT_DIR}/.claude/handovers/"*.md 2>/dev/null
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$DELETE_ALL_MD" 0
  assert_success
  assert_output --partial "Purged 0 handover file(s)."
}
