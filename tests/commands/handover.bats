#!/usr/bin/env bats
# Tests for shell blocks in commands/handover.md

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../test_helper/mock_context'
  load '../test_helper/shell_extractor'

  setup_mock_project

  HANDOVER_MD="${MOCK_PROJECT_DIR}/commands/handover.md"
}

teardown() {
  teardown_mock_project
}

# ---------------------------------------------------------------------------
# Block 0: git status --short
# ---------------------------------------------------------------------------

@test "git status block executes" {
  mock_git "M  src/auth.js" ""
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$HANDOVER_MD" 0
  assert_success
  assert_output --partial "M  src/auth.js"
}

# ---------------------------------------------------------------------------
# Block 1: git diff --stat
# ---------------------------------------------------------------------------

@test "git diff block executes" {
  mock_git "" "src/auth.js | 5 +++--"
  cd "$MOCK_PROJECT_DIR"
  run run_shell_block "$HANDOVER_MD" 1
  assert_success
  assert_output --partial "src/auth.js | 5 +++--"
}
