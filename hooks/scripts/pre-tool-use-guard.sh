#!/usr/bin/env bash
# PreToolUse hook -- classifies a Bash command before it runs.
#
# Three outcomes:
#   deny    the three irreversible-and-never-legitimate forms. Refused outright.
#   ask     recoverable but destructive. The user gets a prompt naming what would be lost.
#   silence everything else. No output, exit 0, and the call proceeds untouched.
#
# This is an accident brake, not a security boundary. See the Known Gotchas entry in CLAUDE.md.
#
# set -u only, deliberately. set -e would turn any internal hiccup into a nonzero exit on the
# path of every single Bash call in the session, which is a far worse failure than a missed
# classification. Every exit below is an explicit exit 0.
#
# set -f is on because classification word-splits each segment with an unquoted expansion. Without
# it, a target like * would glob against the hook's own working directory before it was ever read.

set -uf

INPUT="$(cat)"

# The payload shape is recorded under ## Spike Results in
# .claude/plans/2026-08-20-destructive-command-guard-plan.md: tool_name is top-level, and the
# command string is at tool_input.command. sed matches both flat, because "command" is the only
# key by that name in a PreToolUse payload.
json_field() {
  printf '%s' "$INPUT" \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
    | head -n 1
}

TOOL_NAME="$(json_field tool_name)"
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# The command arrives JSON-escaped, and [^"]* stops at the first embedded quote. That truncation
# is intentional and load-bearing: `echo "rm -rf /"` arrives as "echo \"rm -rf /\"" and truncates
# to `echo \`, whose first word is echo, so it classifies silent for the right reason.
COMMAND="$(json_field command)"
if [ -z "$COMMAND" ]; then
  exit 0
fi

# The static half of every reason is authored ASCII with no double quote and no backslash, so
# this printf is the whole JSON encoder. But reasons interpolate a target path lifted from the
# command, and a path can carry either character -- `rm -rf "my dir"` truncates to a lone
# backslash at extraction time. Dropping both is enough, because they are the only two characters
# a JSON string literal cannot hold raw, and a mangled path in a prompt is better than a hook
# whose output the CLI cannot parse.
emit() {
  REASON="$(printf '%s' "$2" | tr -d '"\\')"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$REASON"
  exit 0
}

# --- Segmentation -------------------------------------------------------------------------
#
# Split on the shell separators, then classify each segment by its FIRST WORD. That first-word
# anchoring is the entire false-positive defense: `grep -rn "rm -rf /" docs/` is one segment whose
# first word is grep, so it never matches, and that command is one this repository's own
# documentation work runs. `foo $(rm -rf /)` splits at the paren and yields a segment whose first
# word is rm, so nesting is still covered.
#
# Splitting also breaks quoted strings that contain a separator: `echo "a;b"` yields two segments.
# The second one's first word is not a command name, so it classifies silent. Harmless, not fixed.
SEGMENTS="$(printf '%s\n' "$COMMAND" | tr ';&|()`' '\n\n\n\n\n\n')"

# Directories a build regenerates. Deleting one costs a rebuild, not work, so these stay silent --
# otherwise the guard prompts on the single most common legitimate rm -rf and gets muted wholesale.
SAFE_TARGETS=" node_modules dist build .next target __pycache__ .pytest_cache .venv DerivedData coverage "

# Strip a trailing slash then a leading ./ so build/, ./build, and ./build/ all reduce to build.
normalize_target() {
  NORM="${1%/}"
  NORM="${NORM#./}"
  printf '%s' "$NORM"
}

is_safe_target() {
  case "$SAFE_TARGETS" in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Targets that must never be the argument of a recursive force delete.
is_catastrophic_target() {
  case "$1" in
    /|'~'|'~/'|'$HOME'|'$HOME/'|'${HOME}'|'${HOME}/') return 0 ;;
    *) return 1 ;;
  esac
}

# Deny wins over ask no matter which segment each was found in, so a deny exits inside the loop
# while an ask is only recorded and emitted after every segment has been read.
ASK_REASON=""

# First ask wins. A command with two destructive segments only needs one prompt, and the first
# one read is the one the user reaches first when the command runs.
set_ask() {
  if [ -z "$ASK_REASON" ]; then
    ASK_REASON="$1"
  fi
}

while IFS= read -r SEGMENT; do
  # Unquoted on purpose: this is the word split. set -f above makes it safe.
  # shellcheck disable=SC2086
  set -- $SEGMENT
  if [ $# -eq 0 ]; then
    continue
  fi
  if [ "$1" = "sudo" ]; then
    shift
    if [ $# -eq 0 ]; then
      continue
    fi
  fi

  FIRST_WORD="$1"
  shift

  if [ "$FIRST_WORD" = "rm" ]; then
    HAS_R=0
    HAS_F=0
    TARGETS=""
    for ARG in "$@"; do
      case "$ARG" in
        --recursive) HAS_R=1 ;;
        --force) HAS_F=1 ;;
        --*) : ;;
        -*)
          # A flag cluster: -rf, -fr, -rfv, and -r -f spread across separate arguments.
          case "$ARG" in *[rR]*) HAS_R=1 ;; esac
          case "$ARG" in *f*) HAS_F=1 ;; esac
          ;;
        *) TARGETS="$TARGETS $ARG" ;;
      esac
    done

    if [ "$HAS_R" -eq 1 ] && [ "$HAS_F" -eq 1 ]; then
      UNSAFE=""
      # shellcheck disable=SC2086
      for TARGET in $TARGETS; do
        if is_catastrophic_target "$TARGET"; then
          emit deny "Refusing a recursive force delete of $TARGET. This erases the whole filesystem or the whole home directory and nothing recovers it."
        fi
        NORM_TARGET="$(normalize_target "$TARGET")"
        if ! is_safe_target "$NORM_TARGET"; then
          UNSAFE="$UNSAFE $NORM_TARGET"
        fi
      done
      if [ -n "$UNSAFE" ]; then
        set_ask "This deletes$UNSAFE and everything under it. rm does not use the trash, so nothing here comes back."
      fi
    fi

  elif [ "$FIRST_WORD" = "git" ]; then
    # The subcommand is taken as the first argument, not the first non-flag argument. A global
    # option before the subcommand (git -C path status) is rare enough in agent-written commands
    # that handling it would cost more than it buys, and getting it wrong only ever costs a
    # missed prompt, never a wrong one.
    GIT_SUB="${1:-}"
    if [ $# -gt 0 ]; then
      shift
    fi

    case "$GIT_SUB" in
      push)
        for ARG in "$@"; do
          case "$ARG" in
            --force|-f|--force-with-lease|--force-with-lease=*|--force-if-includes)
              set_ask "This overwrites the remote branch history. Any commits on the remote that are not in your local branch are lost, for everyone using that branch, not only for you."
              ;;
          esac
        done
        ;;
      reset)
        for ARG in "$@"; do
          case "$ARG" in
            --hard)
              set_ask "This throws away every uncommitted change in the working tree and the index. Those changes were never committed, so no git command brings them back."
              ;;
          esac
        done
        ;;
      clean)
        for ARG in "$@"; do
          case "$ARG" in
            --*) : ;;
            -*f*)
              # A cluster carrying both f and d, so -fd, -fdx, -df. -f alone only removes
              # untracked files git already knows are untracked; adding d reaches directories.
              case "$ARG" in
                *d*)
                  set_ask "This deletes every untracked file and directory here, including ones git has never seen. They are in no commit and no stash, so nothing recovers them."
                  ;;
              esac
              ;;
          esac
        done
        ;;
      checkout|restore)
        for ARG in "$@"; do
          if [ "$ARG" = "." ]; then
            set_ask "This overwrites every uncommitted change in the working tree with the committed version. Those edits were never committed, so nothing recovers them."
          fi
        done
        ;;
      branch)
        for ARG in "$@"; do
          case "$ARG" in
            --*) : ;;
            -*D*)
              set_ask "This force-deletes the branch whether or not its commits are merged anywhere. Any commit only reachable from it becomes unreachable."
              ;;
          esac
        done
        ;;
    esac
  fi
done <<EOF
$SEGMENTS
EOF

if [ -n "$ASK_REASON" ]; then
  emit ask "$ASK_REASON"
fi

exit 0
