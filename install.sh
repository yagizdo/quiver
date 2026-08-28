#!/usr/bin/env bash
# install.sh -- install Quiver into every AI coding CLI detected on this machine.
#
# Two kinds of target:
#
#   native  the runtime has its own plugin manager. The command is printed, never
#           run. Wrapping someone else's command surface means their next change
#           breaks this script and prints our error message instead of theirs.
#   link    the runtime has no plugin manager. A symlink points from its plugin
#           directory into this clone, so `git -C <clone> pull` updates that
#           runtime with no second update mechanism to write or document.
#
# A real file or directory is never removed or overwritten. A destination that is
# not a symlink into this clone is skipped and the run exits nonzero.
#
# Adding a runtime is one row in targets(). No other line of this script changes.
#
# Usage: ./install.sh [<id>|--uninstall|--help]

set -u

REPO_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
STATUS=0

# --- Target table ------------------------------------------------------------
#
# Six tab-separated columns: id kind detect src dest note
#
#   id      the argument that forces this target on its own.
#   kind    native or link.
#   detect  a path when it starts with ~ or /, tested with `test -e`; otherwise a
#           command name, tested with `command -v`. One case branch covers both.
#   src     repo-relative source for a link row, `.` for the repo root itself;
#           `-` for a native row.
#   dest    link destination for a link row; the command to print for a native row.
#   note    follow-up instruction, or `-` when there is none.
#
# The separator is a tab because the note column carries spaces and quotes.
# tests/install/test-install-script.sh asserts six columns per row, which is what
# catches an editor that turns these tabs into spaces.
#
# Cursor has no row, deliberately. It discovers skills by scanning a fixed list of
# roots that includes ~/.claude/plugins/, so a Claude Code install already surfaces
# Quiver there with nothing else to do. A Codex install does not: it lands in
# ~/.codex/plugins/, which is not on that list. A symlink under
# ~/.cursor/plugins/local/ is not picked up either: measured on Cursor 3.17.21,
# disabling the Claude Code install made Quiver disappear from Cursor while that
# symlink was still in place. Cursor's own plugin import covers a Cursor-only user.

targets() {
  cat <<'EOF'
claude	native	claude	-	/plugin marketplace add yagizdo/quiver	Then run: /plugin install quiver@quiver
codex	native	codex	-	codex plugin marketplace add yagizdo/quiver	Then run: codex plugin add quiver@quiver
opencode	link	~/.config/opencode	.opencode/plugins/quiver.js	~/.config/opencode/plugins/quiver.js	-
EOF
}

# --- Helpers -----------------------------------------------------------------

say() { printf '%-9s %s\n' "$1" "$2"; }
note_line() { [ "$1" = "-" ] || printf '%-9s %s\n' "" "-> $1"; }

# OpenCode resolves its global config dir as ${XDG_CONFIG_HOME:-$HOME/.config}/opencode,
# so a ~/.config/ prefix has to go through the XDG base or the link lands where nothing
# reads it. Both the detect and dest columns come through here, so one branch covers both.
expand_home() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/.config/"*) printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/${1#\~/.config/}" ;;
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

detected() {
  case "$1" in
    "~"*|/*) [ -e "$(expand_home "$1")" ] ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

src_path() {
  case "$1" in
    .) printf '%s' "$REPO_ROOT" ;;
    *) printf '%s' "$REPO_ROOT/$1" ;;
  esac
}

# A destination belongs to this script only when it is a symlink whose target sits
# inside this clone. Links are always written as absolute paths under REPO_ROOT,
# which `pwd -P` already resolved, so one level of readlink decides it.
# ponytail: plain readlink, not readlink -f -- BSD readlink had no -f before macOS
# 12.3, and a hand-made relative link failing this check refuses to be touched,
# which is the safe direction.
owns_link() {
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Handlers ----------------------------------------------------------------

install_link() {
  id="$1"
  src="$(src_path "$2")"
  dest="$(expand_home "$3")"

  if [ ! -e "$src" ]; then
    say "$id" "SKIP: source missing: $src"
    STATUS=1
    return 1
  fi

  if owns_link "$dest"; then
    say "$id" "already installed: $dest"
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    say "$id" "SKIP: $dest already exists and is not a Quiver symlink -- left untouched"
    STATUS=1
    return 1
  fi

  if ! mkdir -p "$(dirname "$dest")"; then
    say "$id" "SKIP: could not create $(dirname "$dest")"
    STATUS=1
    return 1
  fi

  if ! ln -s "$src" "$dest"; then
    say "$id" "SKIP: could not link $dest"
    STATUS=1
    return 1
  fi

  say "$id" "linked: $dest -> $src"
  return 0
}

remove_link() {
  id="$1"
  dest="$(expand_home "$2")"

  if owns_link "$dest"; then
    if rm -f "$dest"; then
      say "$id" "removed: $dest"
    else
      say "$id" "SKIP: could not remove $dest"
      STATUS=1
    fi
    return
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    say "$id" "SKIP: $dest is not a Quiver symlink -- left in place"
    STATUS=1
    return
  fi

  say "$id" "not installed"
}

# --- Main --------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: ./install.sh [<id>|--uninstall|--help]

  (no arguments)  install every runtime detected on this machine
  <id>            install one runtime by id, skipping detection
  --uninstall     remove only the symlinks that resolve into this clone
  --help          print this message

Targets (id, kind, detect, src, dest, note):
EOF
  targets
}

MODE=install
ONLY=""

if [ "$#" -gt 1 ]; then
  printf 'Too many arguments. Run ./install.sh --help\n' >&2
  exit 2
fi

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  --uninstall) MODE=uninstall ;;
  -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  *) ONLY="$1" ;;
esac

if [ "$MODE" = "uninstall" ]; then
  printf 'Uninstalling Quiver links pointing into %s\n\n' "$REPO_ROOT"
else
  printf 'Installing Quiver from %s\n\n' "$REPO_ROOT"
fi

MATCHED=0

while IFS=$'\t' read -r id kind detect src dest note; do
  [ -n "$id" ] || continue
  if [ -n "$ONLY" ] && [ "$ONLY" != "$id" ]; then
    continue
  fi
  MATCHED=1

  if [ "$MODE" = "uninstall" ]; then
    if [ "$kind" = "link" ]; then
      remove_link "$id" "$dest"
    else
      say "$id" "native install -- nothing to remove"
    fi
    continue
  fi

  # An explicit id forces the target; detection only gates the no-argument run.
  if [ -z "$ONLY" ] && ! detected "$detect"; then
    say "$id" "not detected -- skipped"
    continue
  fi

  if [ "$kind" = "link" ]; then
    if install_link "$id" "$src" "$dest"; then
      note_line "$note"
    fi
  else
    say "$id" "run: $dest"
    note_line "$note"
  fi
done < <(targets)

if [ "$MATCHED" -eq 0 ]; then
  printf 'Unknown target: %s. Run ./install.sh --help for the target list.\n' "$ONLY" >&2
  exit 2
fi

exit "$STATUS"
