#!/usr/bin/env bash

# morning-terminals.sh - Open the morning workspace as positioned terminals
#
# Usage:
#   ./morning-terminals.sh [PROJECT] [BANNER...]   Open the terminals (default)
#   ./morning-terminals.sh --install [PROJECT]     Install missing requirements, then check
#   ./morning-terminals.sh --check [PROJECT]       Report requirement status, install nothing
#   ./morning-terminals.sh --help                  Show usage
#
# Opens one gnome-terminal window per tool at a fixed size and screen position,
# then raises the Claude Code window so it ends up on top.
#
# PROJECT selects the directory Claude Code starts in, so the same script works
# on every VM. A bare name is looked up under ~/projects (foo -> ~/projects/foo);
# anything containing a slash is used as the path itself, absolute or relative
# to $HOME (work/foo -> ~/work/foo). With no PROJECT the window opens in
# ~/projects itself, which is the right starting point when the VM has several
# and you have not picked one yet. BANNER is the text of the banner window and
# defaults to the directory name in upper case, so pass it when you want
# different wording or spacing.
#
#
# REQUIREMENTS
#
#   X11 session (required, cannot be installed)
#       Check with: echo "$XDG_SESSION_TYPE"   -> must print "x11"
#
#       This is the real constraint, not the packages below. Ubuntu Desktop
#       22.04+ defaults to GNOME on Wayland, where this script degrades badly
#       and SILENTLY:
#         - Wayland gives clients no way to place their own windows, so the
#           +X+Y offsets are ignored. Sizes still apply, so you get correctly
#           sized windows piled wherever the compositor puts them.
#         - xdotool is an X11 client and cannot see or activate native Wayland
#           windows, so focus_window just times out.
#       Fix: at the login screen, use the gear menu and pick "Ubuntu on Xorg".
#
#   xdotool (required, not installed by default)      --install handles this
#   gnome-terminal (required)                         --install handles this
#       Default on Ubuntu Desktop, but NOT on Xubuntu (xfce4-terminal) or
#       Kubuntu (konsole).
#
#   lazydocker (optional, only for the LazyDocker window)
#       Not packaged in apt; install from https://github.com/jesseduffield/lazydocker
#
#   Paths expected under $HOME
#       the PROJECT directory     working dir for the Claude Code window
#       ~/projects/home-lab/banner.sh   run by the Banner window
#       The banner is launched by a path relative to the terminal's starting
#       directory, which is $HOME.
#
#
# PORTING TO ANOTHER VM
#
#   Run `./morning-terminals.sh --install` first, then re-tune the geometries
#   below: they are specific to this display. "136x62" assumes a screen tall
#   enough for 62 rows at the current font size. On a smaller VM the window
#   manager clamps the window and the layout will not match. Re-measure with:
#       tput cols; tput lines        (in a maximized terminal)
#       xdotool getactivewindow getwindowgeometry --shell

APT_PACKAGES=(xdotool gnome-terminal)

# Where bare project names are looked up, and the fallback when no project is
# given at all.
PROJECTS_DIR="$HOME/projects"

# Set by resolve_project().
PROJECT_DIR=
PROJECT_NAME=
BANNER_TEXT=

usage() {
  local default_banner="${PROJECTS_DIR##*/}"
  default_banner="${default_banner^^}"

  cat <<EOF
morning-terminals.sh - Open the morning workspace as positioned terminals

Usage:
  $0 [PROJECT] [BANNER...]   Open the terminals (default)
  $0 --install [PROJECT]     Install missing requirements, then check
  $0 --check [PROJECT]       Report requirement status, install nothing
  $0 --help                  Show usage

PROJECT is the directory Claude Code starts in, defaulting to $PROJECTS_DIR
when omitted. A bare name resolves under $PROJECTS_DIR; a value with a slash
is the path itself, absolute or relative to \$HOME.
BANNER is the banner window's text (default: the directory name upper-cased).

Examples:
  $0                        $PROJECTS_DIR, banner "$default_banner"
  $0 foo                    $PROJECTS_DIR/foo, banner "FOO"
  $0 foo 'FOO BAR'          $PROJECTS_DIR/foo, banner "FOO BAR"
  $0 work/foo               ~/work/foo
  $0 /srv/foo               /srv/foo

See the comment header in this file for the full requirements list.
EOF
}

# Turn the PROJECT argument into a directory, a name to match windows on, and
# the banner text. Remaining arguments are the banner text verbatim, so it can
# contain spaces without the caller quoting it.
resolve_project() {
  local project="${1:-}"
  shift || true

  case "$project" in
    "")  PROJECT_DIR="$PROJECTS_DIR" ;;
    /*)  PROJECT_DIR="$project" ;;
    */*) PROJECT_DIR="$HOME/$project" ;;
    *)   PROJECT_DIR="$PROJECTS_DIR/$project" ;;
  esac

  PROJECT_DIR="${PROJECT_DIR%/}"
  PROJECT_NAME="${PROJECT_DIR##*/}"

  if [[ $# -gt 0 ]]; then
    BANNER_TEXT="$*"
  else
    BANNER_TEXT="${PROJECT_NAME^^}"
  fi
}

# Print the session type, falling back to logind when the variable is not set
# (it is absent when the script runs outside a desktop login shell).
session_type() {
  if [[ -n "$XDG_SESSION_TYPE" ]]; then
    echo "$XDG_SESSION_TYPE"
  elif [[ -n "$XDG_SESSION_ID" ]]; then
    loginctl show-session "$XDG_SESSION_ID" -p Type --value 2>/dev/null
  fi
}

# Report on every requirement. Returns non-zero if something required is
# missing, so --check is usable as a preflight.
check_requirements() {
  local status=0 pkg type

  type=$(session_type)
  if [[ "$type" == "x11" ]]; then
    echo "  ok       X11 session"
  else
    echo "  PROBLEM  session type is '${type:-unknown}', not x11" >&2
    echo "           window positions and focus will not work; log in with" >&2
    echo "           'Ubuntu on Xorg' from the gear menu at the login screen" >&2
    status=1
  fi

  for pkg in "${APT_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
      echo "  ok       $pkg"
    else
      echo "  MISSING  $pkg -- run: $0 --install" >&2
      status=1
    fi
  done

  if command -v lazydocker &>/dev/null; then
    echo "  ok       lazydocker"
  else
    echo "  absent   lazydocker (optional; that window will exit immediately)"
    echo "           https://github.com/jesseduffield/lazydocker"
  fi

  local path
  for path in "$PROJECT_DIR" "$HOME/projects/home-lab/banner.sh"; do
    if [[ -e "$path" ]]; then
      echo "  ok       $path"
    else
      echo "  absent   $path (that window opens in \$HOME instead)"
    fi
  done

  return $status
}

# Install only what is actually missing, so re-running is cheap and safe.
install_requirements() {
  local pkg missing=()

  for pkg in "${APT_PACKAGES[@]}"; do
    dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "apt packages already installed: ${APT_PACKAGES[*]}"
  else
    echo "installing: ${missing[*]}"
    sudo apt-get update && sudo apt-get install -y "${missing[@]}" || {
      echo "apt install failed" >&2
      return 1
    }
  fi

  echo
  echo "requirements:"
  check_requirements
}

# Geometry must be COLSxROWS+X+Y (see `man gnome-terminal`).
# A malformed string is parsed inside gnome-terminal-server, which owns every
# terminal window on the desktop -- a bad value there can close all of them.
# So validate before launching.
launch() {
  local geometry="$1" title="$2" command="$3"

  if [[ ! "$geometry" =~ ^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$ ]]; then
    echo "skipping '$title': bad geometry '$geometry' (want COLSxROWS+X+Y)" >&2
    return 1
  fi

  gnome-terminal \
    --geometry="$geometry" \
    --title "$title" \
    -- bash -c "$command; exec bash" &

  # Stagger the launches so stacking order is deterministic rather than a race.
  sleep 0.4
}

# Raise and focus the first window whose title matches $1, once it shows up.
# Note: bash's PS1 overwrites --title with "user@host: dir", so match on the
# working directory rather than the title passed to launch().
focus_window() {
  local pattern="$1" tries=40 id name

  if ! command -v xdotool &>/dev/null; then
    echo "xdotool not installed, leaving window stacking to the WM" >&2
    echo "run: $0 --install" >&2
    return 1
  fi

  while (( tries-- > 0 )); do
    # Filter by title here rather than with `xdotool search --all --class
    # --name`, which matches nothing even when each criterion matches alone.
    while read -r id; do
      name=$(xdotool getwindowname "$id" 2>/dev/null)
      if [[ "$name" == *"$pattern"* ]] && xdotool windowactivate "$id" 2>/dev/null; then
        return 0
      fi
    done < <(xdotool search --class "Gnome-terminal" 2>/dev/null)

    sleep 0.25
  done

  echo "could not focus a terminal window matching '$pattern'" >&2
  return 1
}

open_terminals() {
  if ! command -v gnome-terminal &>/dev/null; then
    echo "gnome-terminal not installed -- run: $0 --install" >&2
    exit 1
  fi

  if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "$PROJECT_DIR does not exist -- the Claude Code window will stay in \$HOME" >&2
  fi

  # Lazydocker
  launch "88x47+0+0" "LazyDocker" "lazydocker"

  # Banner
  launch "35x7+0+1060" "Banner" \
    "./projects/home-lab/banner.sh $(printf '%q' "$BANNER_TEXT")"

  # Claude Code -- launched last and raised, so it ends up on top
  launch "113x57+400+0" "CC" "cd $(printf '%q' "$PROJECT_DIR") && claude"
  focus_window "$PROJECT_NAME"
}

action=open
case "${1:-}" in
  --install) action=install; shift ;;
  --check)   action=check;   shift ;;
  --help|-h) usage; exit 0 ;;
  -*)        echo "unknown option: $1" >&2; echo; usage; exit 1 ;;
esac

resolve_project "$@"

case "$action" in
  install) install_requirements ;;
  check)   echo "requirements:"; check_requirements ;;
  open)    open_terminals ;;
esac
