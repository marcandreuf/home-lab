#!/usr/bin/env bash

# morning-terminals.sh - Open the morning workspace as positioned terminals
#
# Usage:
#   ./morning-terminals.sh [--banner TEXT] [PROJECT] [BANNER...]
#                                                  Open the terminals (default)
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
# different wording or spacing. Because the positional BANNER only follows a
# PROJECT, use --banner TEXT to set it while keeping the default project
# directory -- that is the case where the directory name ("projects") says
# nothing about which VM you are looking at.
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
#   toilet (required by banner.sh, not installed by default)
#                                                     --install handles this
#       Without it the Banner window prints an error and exits.
#
#   lazydocker (optional, only for the LazyDocker window)
#       Not packaged in apt, so --install downloads the release binary from
#       https://github.com/jesseduffield/lazydocker into ~/.local/bin, which
#       has to be on your PATH for the window to find it.
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

APT_PACKAGES=(xdotool gnome-terminal toilet)

# lazydocker ships as a GitHub release tarball rather than an apt package.
LAZYDOCKER_REPO="jesseduffield/lazydocker"
LAZYDOCKER_BIN_DIR="$HOME/.local/bin"

# Where bare project names are looked up, and the fallback when no project is
# given at all.
PROJECTS_DIR="$HOME/projects"

# Set by resolve_project().
PROJECT_DIR=
PROJECT_NAME=
BANNER_TEXT=

# Set by the option loop at the bottom; consumed by resolve_project().
banner_override=
banner_set=0

usage() {
  local default_banner="${PROJECTS_DIR##*/}"
  default_banner="${default_banner^^}"

  cat <<EOF
morning-terminals.sh - Open the morning workspace as positioned terminals

Usage:
  $0 [--banner TEXT] [PROJECT] [BANNER...]
                             Open the terminals (default)
  $0 --install [PROJECT]     Install missing requirements, then check
  $0 --check [PROJECT]       Report requirement status, install nothing
  $0 --help                  Show usage

PROJECT is the directory Claude Code starts in, defaulting to $PROJECTS_DIR
when omitted. A bare name resolves under $PROJECTS_DIR; a value with a slash
is the path itself, absolute or relative to \$HOME.
BANNER is the banner window's text (default: the directory name upper-cased).
--banner TEXT sets the same thing without a PROJECT in front of it, which is
the only way to word the banner while keeping the default project directory.

Examples:
  $0                        $PROJECTS_DIR, banner "$default_banner"
  $0 --banner Memship       $PROJECTS_DIR, banner "Memship"
  $0 foo                    $PROJECTS_DIR/foo, banner "FOO"
  $0 foo 'FOO BAR'          $PROJECTS_DIR/foo, banner "FOO BAR"
  $0 work/foo               ~/work/foo
  $0 /srv/foo               /srv/foo

See the comment header in this file for the full requirements list.
EOF
}

# Turn the PROJECT argument into a directory, a name to match windows on, and
# the banner text. Remaining arguments are the banner text verbatim, so it can
# contain spaces without the caller quoting it. --banner wins over both, so it
# can override the default without naming a project.
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

  if [[ $banner_set -eq 1 ]]; then
    BANNER_TEXT="$banner_override"
  elif [[ $# -gt 0 ]]; then
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
    echo "           run: $0 --install"
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

# Download the lazydocker release binary into ~/.local/bin. Nothing here needs
# sudo, which is why it goes under $HOME rather than /usr/local/bin.
install_lazydocker() {
  # Check the install path as well as PATH: when ~/.local/bin is not on PATH
  # the first test misses a binary this script itself put there, and we would
  # re-download it on every run (and hit ETXTBSY if a LazyDocker window has it
  # open).
  if command -v lazydocker &>/dev/null; then
    echo "lazydocker already installed: $(command -v lazydocker)"
    return 0
  elif [[ -x "$LAZYDOCKER_BIN_DIR/lazydocker" ]]; then
    echo "lazydocker already installed: $LAZYDOCKER_BIN_DIR/lazydocker"
    echo "note: $LAZYDOCKER_BIN_DIR is not on your PATH" >&2
    return 0
  fi

  local arch asset version tmp
  case "$(uname -m)" in
    x86_64)         arch=x86_64 ;;
    aarch64|arm64)  arch=arm64 ;;
    armv7l|armv6l)  arch=armv6 ;;
    *) echo "no lazydocker build for $(uname -m); skipping" >&2; return 1 ;;
  esac

  # The API reports the newest tag, so this does not go stale in the script.
  version=$(curl -fsSL "https://api.github.com/repos/$LAZYDOCKER_REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
  if [[ -z "$version" ]]; then
    echo "could not read the latest lazydocker version; skipping" >&2
    return 1
  fi

  asset="lazydocker_${version}_Linux_${arch}.tar.gz"
  echo "installing lazydocker $version to $LAZYDOCKER_BIN_DIR"

  tmp=$(mktemp -d) || return 1
  # Unpack only the binary; the tarball also carries a README and LICENSE.
  if curl -fsSL "https://github.com/$LAZYDOCKER_REPO/releases/download/v$version/$asset" \
       | tar -xz -C "$tmp" lazydocker; then
    mkdir -p "$LAZYDOCKER_BIN_DIR"
    install -m 755 "$tmp/lazydocker" "$LAZYDOCKER_BIN_DIR/lazydocker"
  else
    echo "lazydocker download failed ($asset)" >&2
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"

  case ":$PATH:" in
    *":$LAZYDOCKER_BIN_DIR:"*) ;;
    *) echo "note: $LAZYDOCKER_BIN_DIR is not on your PATH" >&2 ;;
  esac
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

  # A failure here is not fatal: only the LazyDocker window depends on it.
  echo
  install_lazydocker || true

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
  launch "88x34+0+0" "LazyDocker" "lazydocker"

  # Banner
  launch "35x7+0+1060" "Banner" \
    "./projects/home-lab/banner.sh $(printf '%q' "$BANNER_TEXT")"

  # Claude Code -- launched last and raised, so it ends up on top
  launch "145x40+400+0" "CC" "cd $(printf '%q' "$PROJECT_DIR") && claude"
  focus_window "$PROJECT_NAME"
}

# A loop rather than a single case, so --banner can be combined with the other
# options and does not have to come first.
action=open
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)  action=install; shift ;;
    --check)    action=check;   shift ;;
    --banner|-b)
      if [[ $# -lt 2 ]]; then
        echo "$1 needs a value" >&2; echo; usage; exit 1
      fi
      banner_override="$2"; banner_set=1; shift 2 ;;
    --banner=*) banner_override="${1#--banner=}"; banner_set=1; shift ;;
    --help|-h)  usage; exit 0 ;;
    --)         shift; break ;;
    -*)         echo "unknown option: $1" >&2; echo; usage; exit 1 ;;
    *)          break ;;
  esac
done

resolve_project "$@"

case "$action" in
  install) install_requirements ;;
  check)   echo "requirements:"; check_requirements ;;
  open)    open_terminals ;;
esac
