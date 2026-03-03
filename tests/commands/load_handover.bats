#!/usr/bin/env bats
# Tests for shell blocks in commands/load-handover.md

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../test_helper/mock_context'
  load '../test_helper/shell_extractor'

  setup_mock_project

  LOAD_MD="${MOCK_PROJECT_DIR}/commands/load-handover.md"
  SAMPLE_HANDOVER="${BATS_TEST_DIRNAME}/../fixtures/handover_sample.md"
}

teardown() {
  teardown_mock_project
}

# ---------------------------------------------------------------------------
# Block 0: load latest handover content
# ---------------------------------------------------------------------------

@test "loads latest handover content" {
  cp "$SAMPLE_HANDOVER" "${MOCK_PROJECT_DIR}/.claude/handovers/2026-01-01_00-00-00.md"
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$LOAD_MD" 0
  assert_success
  assert_output --partial "## Summary"
  assert_output --partial "Fixed login validation bug"
}

@test "handles empty handovers directory" {
  rm -f "${MOCK_PROJECT_DIR}/.claude/handovers/"*.md 2>/dev/null
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$LOAD_MD" 0
  assert_success
  assert_output --partial "No handover files found"
}

@test "picks newest file by timestamp" {
  inject_handover "2026-01-01_00-00-00" "Old handover"
  inject_handover "2026-01-02_00-00-00" "Middle handover"
  inject_handover "2026-01-03_00-00-00" "Newest handover"
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$LOAD_MD" 0
  assert_success
  assert_output --partial "Newest handover"
}
