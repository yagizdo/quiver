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
# Two audiences for the reason strings: an ask reason is rendered in the confirmation prompt and
# is read by the user, while a deny reason is sent to Claude instead, because the call is
# cancelled and never reaches a prompt. Both are written as plain prose, which reads correctly
# either way, but an edit that assumes only a human sees these is wrong for the deny tier.
#
# set -u only, deliberately. set -e would turn any internal hiccup into a nonzero exit on the
# path of every single Bash call in the session, which is a far worse failure than a missed
# classification. Every exit below is an explicit exit 0.
#
# set -f is on because classification word-splits each segment with an unquoted expansion. Without
# it, a target like * would glob against the hook's own working directory before it was ever read.

set -uf

INPUT="$(cat)"

# The command arrives as a JSON string literal, so its quotes, backslashes, newlines and tabs are
# all escaped. Field extraction below captures with [^"]*, which would stop dead at the first
# escaped quote and discard the rest of the command -- and nothing downstream would ever see a
# newline, because a multi-line command is carrying the two characters \ n rather than a line
# break. Mask each escape to a control character first, extract, then decode the masks back.
#
# \\ is masked first, on purpose. Doing it last would let a literal backslash-n typed in the
# command (\\n in the payload) be read as an encoded newline and split a segment that is not one.
#
# The mask script is built with printf so the control characters are literal bytes. Writing them
# as \001 inside a sed replacement is not portable -- both GNU and BSD sed read a leading
# backslash-digit there as a backreference.
SED_MASK="$(printf 's/\\\\\\\\/\001/g; s/\\\\"/\002/g; s/\\\\n/\003/g; s/\\\\t/\004/g')"
MASKED="$(printf '%s' "$INPUT" | sed "$SED_MASK")"

# The payload shape is recorded under ## Spike Results in
# .claude/plans/2026-08-20-destructive-command-guard-plan.md: tool_name is top-level, and the
# command string is at tool_input.command. sed matches both flat, because "command" is the only
# key by that name in a PreToolUse payload.
json_field() {
  printf '%s' "$MASKED" \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
    | head -n 1
}

unmask() {
  printf '%s' "$1" | tr '\001\002\003\004' '\\"\n\t'
}

TOOL_NAME="$(json_field tool_name)"
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND_MASKED="$(json_field command)"
if [ -z "$COMMAND_MASKED" ]; then
  exit 0
fi

# A double-quoted span that contains a newline is a block of text being printed or written, not an
# argument list -- `echo "note:<newline>rm -rf / is bad"` is a sentence about a command, and once
# newlines segment, line two of it looks exactly like the command it describes. Drop those spans.
#
# Single-line quoted spans are kept, because a target needs its quotes: `rm -rf "$HOME"` must
# still resolve to $HOME. This is why the drop runs before unmask -- afterwards a quote written by
# the command and a quote wrapping a target are the same byte.
SED_DROP_TEXT_BLOCK="$(printf 's/\002[^\002]*\003[^\002]*\002//g')"
COMMAND="$(unmask "$(printf '%s' "$COMMAND_MASKED" | sed "$SED_DROP_TEXT_BLOCK")")"
if [ -z "$COMMAND" ]; then
  exit 0
fi

# The static half of every reason is authored ASCII with no double quote and no backslash, so
# this printf is the whole JSON encoder. But reasons interpolate a target path lifted from the
# command, and a decoded path can now carry a real quote, a real backslash, or a control
# character -- `rm -rf "my dir"` yields the target "my dir" with its quotes intact. Those are the
# characters a JSON string literal cannot hold raw, and a mangled path in a prompt is better than
# a hook whose output the CLI cannot parse.
emit() {
  REASON="$(printf '%s' "$2" | tr -d '"\\' | tr -d '\001-\037')"
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
# A newline is a shell separator too, and the decode above turned every encoded one back into a
# real line break, so the read loop below splits on it with no help from tr.
#
# Splitting also breaks quoted strings that contain a separator: `echo "a;b"` yields two segments.
# The second one's first word is not a command name, so it classifies silent. Harmless, not fixed.
#
# A heredoc body is data being written, not commands being run: `cat <<EOF > notes.md` followed
# by a line reading `rm -rf /` is a documentation edit. Before newlines segmented, that body was
# invisible; now the first-word anchoring cannot tell it apart from a real command, and a wrong
# deny is the one decision a user cannot override. So classification stops at the first heredoc
# or herestring opener.
#
# The cost is a miss, never a wrong answer: anything destructive that follows a heredoc in the
# same command goes unclassified. Anything before it still classifies, so `rm -rf / && cat <<EOF`
# is still denied.
case "$COMMAND" in
  *'<<'*) COMMAND="${COMMAND%%<<*}" ;;
esac

SEGMENTS="$(printf '%s\n' "$COMMAND" | tr ';&|()`' '\n\n\n\n\n\n')"

# Directories a build regenerates. Deleting one costs a rebuild, not work, so these stay silent --
# otherwise the guard prompts on the single most common legitimate rm -rf and gets muted wholesale.
SAFE_TARGETS=" node_modules dist build .next target __pycache__ .pytest_cache .venv DerivedData coverage "

# Reduce a target to its comparable form: strip a surrounding quote pair, then one trailing slash,
# then one leading ./ -- so "build/", ./build and build all reduce to build, and "$HOME" reduces
# to $HOME. Quotes come first because they sit outside the slash.
#
# Writes NORM_TARGET rather than echoing a value. The rm branch calls this once per target, and a
# subshell fork per target put a 1000-target delete past the 5s timeout in hooks/hooks.json.
normalize_target() {
  NORM_TARGET="$1"
  case "$NORM_TARGET" in
    \"*\") NORM_TARGET="${NORM_TARGET#\"}"; NORM_TARGET="${NORM_TARGET%\"}" ;;
    \'*\') NORM_TARGET="${NORM_TARGET#\'}"; NORM_TARGET="${NORM_TARGET%\'}" ;;
  esac
  # A bare / is exempt: stripping its trailing slash would leave nothing to compare.
  case "$NORM_TARGET" in
    /) : ;;
    */) NORM_TARGET="${NORM_TARGET%/}" ;;
  esac
  NORM_TARGET="${NORM_TARGET#./}"
}

is_safe_target() {
  case "$SAFE_TARGETS" in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Targets that must never be the argument of a recursive force delete. The /* spellings are here
# because `rm -rf /*` is the canonical accidental form and erases exactly what `rm -rf /` does.
# The trailing-slash spellings (~/, $HOME/) are absent on purpose: normalize_target already
# reduced them.
is_catastrophic_target() {
  case "$1" in
    /|'/*'|'~'|'~/*'|'$HOME'|'$HOME/*'|'${HOME}'|'${HOME}/*') return 0 ;;
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
    # sudo's own options sit between sudo and the real command: sudo -E rm, sudo -u root rm. Skip
    # them, and skip the value of the short options that take one, so the real command lands in $1.
    # A --long value spelling (as opposed to --long=value) leaves the value as the first word,
    # which costs a missed prompt and never a wrong one.
    while [ $# -gt 0 ]; do
      case "$1" in
        -[CDghpRrTtUu])
          shift
          if [ $# -gt 0 ]; then
            shift
          fi
          ;;
        -*) shift ;;
        *) break ;;
      esac
    done
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
        normalize_target "$TARGET"
        if is_catastrophic_target "$NORM_TARGET"; then
          emit deny "Refusing a recursive force delete of $NORM_TARGET. This erases the whole filesystem or the whole home directory and nothing recovers it."
        fi
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
    # option before the subcommand (git -C path status) is handled nowhere, so `git -C dir reset
    # --hard` classifies silent. That shape is written by hand often enough that the concession is
    # a real gap -- tests/hooks/test-destructive-guard.sh uses `git -C` itself -- and it stands
    # only because getting it wrong costs a missed prompt, never a wrong one.
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
        # -f alone only removes untracked files git already knows are untracked; adding d reaches
        # directories. Both bits accumulate across arguments, because `git clean -f -d` is the
        # spelling git's own hint text prints, and --force is the long form of the same bit.
        CLEAN_F=0
        CLEAN_D=0
        for ARG in "$@"; do
          case "$ARG" in
            --force) CLEAN_F=1 ;;
            # Every other long flag, --dry-run included, must not reach the letter test below.
            --*) : ;;
            -*)
              case "$ARG" in *f*) CLEAN_F=1 ;; esac
              case "$ARG" in *d*) CLEAN_D=1 ;; esac
              ;;
          esac
        done
        if [ "$CLEAN_F" -eq 1 ] && [ "$CLEAN_D" -eq 1 ]; then
          set_ask "This deletes every untracked file and directory here, including ones git has never seen. They are in no commit and no stash, so nothing recovers them."
        fi
        ;;
      checkout|restore)
        for ARG in "$@"; do
          if [ "$ARG" = "." ]; then
            set_ask "This overwrites every uncommitted change in the working tree with the committed version. Those edits were never committed, so nothing recovers them."
          fi
        done
        ;;
      branch)
        # -D is the shorthand for --delete --force. Both bits accumulate, so -d -f and
        # --delete --force reach the same prompt as -D.
        BRANCH_DELETE=0
        BRANCH_FORCE=0
        for ARG in "$@"; do
          case "$ARG" in
            --delete) BRANCH_DELETE=1 ;;
            --force) BRANCH_FORCE=1 ;;
            --*) : ;;
            -*)
              case "$ARG" in *D*) BRANCH_DELETE=1; BRANCH_FORCE=1 ;; esac
              case "$ARG" in *d*) BRANCH_DELETE=1 ;; esac
              case "$ARG" in *f*) BRANCH_FORCE=1 ;; esac
              ;;
          esac
        done
        if [ "$BRANCH_DELETE" -eq 1 ] && [ "$BRANCH_FORCE" -eq 1 ]; then
          set_ask "This force-deletes the branch whether or not its commits are merged anywhere. Any commit only reachable from it becomes unreachable."
        fi
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
