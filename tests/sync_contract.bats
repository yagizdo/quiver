#!/usr/bin/env bats
# Tests for SYNC contract between commands/handover.md and hooks/scripts/pre-compact-handover.sh

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
  PLUGIN_ROOT="$(cd "$PLUGIN_ROOT" && pwd)"

  HANDOVER_CMD="${PLUGIN_ROOT}/commands/handover.md"
  HOOK_SCRIPT="${PLUGIN_ROOT}/hooks/scripts/pre-compact-handover.sh"
}

@test "handover.md and pre-compact-handover.sh have identical section headings" {
  # Extract headings from commands/handover.md (## lines in the instruction block)
  local headings_cmd
  headings_cmd="$(grep '^## ' "$HANDOVER_CMD" | grep -v '## Save to Disk' | grep -v '## Git Status' | grep -v '## Git Diff' | grep -v '## Plugin Info' | grep -v '## Handovers' | grep -v '## Available Commands' | grep -v '## Hook Status' | head -8)"

  # Extract headings from hook script PROMPT_PREFIX
  local headings_hook
  headings_hook="$(grep '^## ' "$HOOK_SCRIPT")"

  assert_equal "$headings_cmd" "$headings_hook"
}

@test "SYNC comment in handover.md references hook script" {
  run grep 'SYNC:' "$HANDOVER_CMD"
  assert_success
  assert_output --partial "hooks/scripts/pre-compact-handover.sh"
}

@test "SYNC comment in hook script references handover.md" {
  run grep 'SYNC:' "$HOOK_SCRIPT"
  assert_success
  assert_output --partial "commands/handover.md"
}
