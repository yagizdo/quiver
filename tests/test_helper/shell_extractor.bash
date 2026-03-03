#!/usr/bin/env bash
# shell_extractor.bash — Extract !`...` inline shell blocks from command Markdown files.

# ---------------------------------------------------------------------------
# extract_shell_blocks <markdown_file>
#   Prints each !`...` shell block on its own line (in order of appearance).
# ---------------------------------------------------------------------------
extract_shell_blocks() {
  local file="$1"
  # Match !`...` patterns — non-greedy, single line.
  # sed extracts content between !` and `
  sed -n "s/.*!\`\([^\`]*\)\`.*/\1/p" "$file"
}

# ---------------------------------------------------------------------------
# extract_shell_block <markdown_file> <index>
#   Returns the Nth shell block (0-indexed).
# ---------------------------------------------------------------------------
extract_shell_block() {
  local file="$1"
  local index="$2"
  local line_num=$((index + 1))
  extract_shell_blocks "$file" | sed -n "${line_num}p"
}

# ---------------------------------------------------------------------------
# run_shell_block <markdown_file> <index>
#   Extracts and executes the Nth shell block in current env.
#   Output goes to stdout; caller captures with $().
# ---------------------------------------------------------------------------
run_shell_block() {
  local file="$1"
  local index="$2"
  local cmd
  cmd="$(extract_shell_block "$file" "$index")"
  if [[ -z "$cmd" ]]; then
    echo "ERROR: no shell block at index $index in $file" >&2
    return 1
  fi
  eval "$cmd"
}
