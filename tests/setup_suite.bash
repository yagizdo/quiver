#!/usr/bin/env bash
# setup_suite.bash — Suite-wide setup (bats convention).
# Loaded once before any test file runs.

setup_suite() {
  # Resolve the project root (two levels up from tests/)
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export PLUGIN_ROOT

  # Fixture directory
  FIXTURE_DIR="${BATS_TEST_DIRNAME}/fixtures"
  export FIXTURE_DIR
}
