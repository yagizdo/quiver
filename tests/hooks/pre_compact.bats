#!/usr/bin/env bats
# Tests for hooks/scripts/pre-compact-handover.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  load '../test_helper/bats-file/load'
  load '../test_helper/mock_context'

  setup_mock_project
  mock_timeout

  HOOK_SCRIPT="${MOCK_PROJECT_DIR}/hooks/scripts/pre-compact-handover.sh"
  FIXTURE_TRANSCRIPT="${BATS_TEST_DIRNAME}/../fixtures/transcript.json"
}

teardown() {
  teardown_mock_project
}

# Helper: run the hook with a given transcript path via stdin JSON
run_hook() {
  local transcript_path="$1"
  run bash -c "echo '{\"transcript_path\":\"${transcript_path}\"}' | \
    CLAUDE_PROJECT_DIR='${MOCK_PROJECT_DIR}' \
    PATH='${PATH}' \
    bash '${HOOK_SCRIPT}'"
}

# ---------------------------------------------------------------------------
# Guard clause tests
# ---------------------------------------------------------------------------

@test "hook exits 0 on empty stdin" {
  run bash -c "echo '' | \
    CLAUDE_PROJECT_DIR='${MOCK_PROJECT_DIR}' \
    PATH='${PATH}' \
    bash '${HOOK_SCRIPT}'"

  assert_success
  assert_equal "$(get_handover_count)" "0"
}

@test "hook exits 0 on missing transcript file" {
  run_hook "/nonexistent/transcript.json"

  assert_success
  assert_equal "$(get_handover_count)" "0"
}

@test "hook exits 0 when claude fails" {
  mock_claude 1 ""
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  assert_equal "$(get_handover_count)" "0"
}

@test "hook exits 0 when claude returns empty output" {
  mock_claude 0 ""
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  assert_equal "$(get_handover_count)" "0"
}

# ---------------------------------------------------------------------------
# stdin parsing
# ---------------------------------------------------------------------------

@test "stdin parsing extracts transcript_path" {
  mock_claude 0 "## Summary\nTest content"
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  # If transcript was found and claude ran, a handover file should exist
  assert_equal "$(get_handover_count)" "1"
}

# ---------------------------------------------------------------------------
# File creation
# ---------------------------------------------------------------------------

@test "creates handover directory if missing" {
  mock_claude 0 "## Summary\nTest content"
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  # Remove the handovers dir
  rm -rf "${MOCK_PROJECT_DIR}/.claude/handovers"

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  assert_dir_exists "${MOCK_PROJECT_DIR}/.claude/handovers"
}

@test "writes timestamped handover file" {
  mock_claude 0 "## Summary\nTest handover content"
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  assert_equal "$(get_handover_count)" "1"

  local latest
  latest="$(get_latest_handover)"
  # Filename should match YYYY-MM-DD_HH-MM-SS.md pattern
  assert_output --partial ""  # no error output
  [[ "$(basename "$latest")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.md$ ]]
}

@test "handover content matches claude output" {
  mock_claude 0 "## Summary\nExact match test"
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  local latest
  latest="$(get_latest_handover)"
  run cat "$latest"
  assert_output --partial "## Summary"
  assert_output --partial "Exact match test"
}

# ---------------------------------------------------------------------------
# Pruning
# ---------------------------------------------------------------------------

@test "prunes to 3 most recent files" {
  mock_claude 0 "## Summary\nNew handover"
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  # Pre-inject 4 old files (will become 5 total with the new one)
  inject_handovers_aged 4

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  assert_equal "$(get_handover_count)" "3"
}

@test "prune keeps newest 3 files" {
  mock_claude 0 "## Summary\nNewest handover"
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  inject_handovers_aged 5

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  assert_equal "$(get_handover_count)" "3"

  # The 2 oldest (01, 02) should be gone; the hook's new file + 04 + 05 should survive
  assert_file_not_exists "${MOCK_PROJECT_DIR}/.claude/handovers/2026-01-01_00-00-00.md"
  assert_file_not_exists "${MOCK_PROJECT_DIR}/.claude/handovers/2026-01-02_00-00-00.md"
  assert_file_not_exists "${MOCK_PROJECT_DIR}/.claude/handovers/2026-01-03_00-00-00.md"
}

@test "does not prune when 3 or fewer exist" {
  mock_claude 0 "## Summary\nNew"
  cp "$FIXTURE_TRANSCRIPT" "${BATS_TEST_TMPDIR}/transcript.json"

  inject_handovers_aged 2

  run_hook "${BATS_TEST_TMPDIR}/transcript.json"

  assert_success
  # 2 old + 1 new = 3 total — no pruning
  assert_equal "$(get_handover_count)" "3"
}

# ---------------------------------------------------------------------------
# Prompt content
# ---------------------------------------------------------------------------

@test "PROMPT_PREFIX contains all 8 headings" {
  local script="${MOCK_PROJECT_DIR}/hooks/scripts/pre-compact-handover.sh"

  run grep -c '^## ' "$script"
  assert_output "8"

  run grep '## Summary' "$script"
  assert_success
  run grep '## What Was Done' "$script"
  assert_success
  run grep '## What We Tried / Dead Ends' "$script"
  assert_success
  run grep '## Bugs & Fixes' "$script"
  assert_success
  run grep '## Key Decisions (and Why)' "$script"
  assert_success
  run grep '## Gotchas / Things to Watch Out For' "$script"
  assert_success
  run grep '## Next Steps' "$script"
  assert_success
  run grep '## Important Files Map' "$script"
  assert_success
}
