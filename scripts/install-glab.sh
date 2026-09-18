#!/usr/bin/env bash

# install-glab.sh - Install the GitLab CLI, and check it can store a token safely
#
# Usage:
#   ./install-glab.sh              Report status, install nothing (default)
#   ./install-glab.sh --check      Same as above
#   ./install-glab.sh --install    Install or update glab, then report
#   ./install-glab.sh --help       Show usage
#
#
# WHY THIS EXISTS
#
#   The engineering skills can track issues in GitLab instead of GitHub, and
#   every one of those operations shells out to `glab`. Nothing else in this
#   repo installs it, and it is not in apt: it ships as a release tarball from
#   the project's own GitLab, the same shape as the lazydocker download in
#   morning-terminals.sh.
#
#
# THE KEYRING MATTERS MORE THAN THE BINARY
#
#   By default glab stores the token in the OS keyring -- the Secret Service on
#   Linux. When no keyring is reachable it does not fail and does not ask: it
#   writes the token in PLAINTEXT to ~/.config/glab-cli/config.yml. A machine
#   whose desktop sits on a different D-Bus session bus than the keyring gets a
#   plaintext credential and no warning at all.
#
#   That is the quiet half of the two-bus problem, so --check probes the Secret
#   Service rather than stopping at "the binary is installed". If it reports the
#   keyring unreachable, fix that BEFORE authenticating. See the Troubleshooting
#   section of scripts/README.md and scripts/vnc-xstartup.
#
#   Credentials already written as plaintext are not stuck there: running
#   `glab auth login` again, once a keyring is reachable, moves them into it.
#
#
# AUTHENTICATING IS A HUMAN STEP
#
#   `glab auth login` is interactive -- a browser flow, or a token pasted in --
#   so this script never attempts it. It reports whether it has been done and
#   where the credential ended up, and prints the command to run.

GLAB_PROJECT="gitlab-org%2Fcli"          # URL-encoded path, for the API
GLAB_BIN_DIR="$HOME/.local/bin"
GLAB_CONFIG="$HOME/.config/glab-cli/config.yml"

usage() {
  cat <<EOF
install-glab.sh - Install the GitLab CLI, and check it can store a token safely

Usage:
  $0              Report status, install nothing (default)
  $0 --check      Same as above
  $0 --install    Install or update glab, then report
  $0 --help       Show usage

The check covers three things, in the order they can fail:
  1. is glab installed, and on your PATH
  2. is the Secret Service reachable -- without it glab stores the token in
     plaintext, silently
  3. is glab authenticated, and did the credential land in the keyring

See the comment header in this file for why the middle one matters most.
EOF
}

# Map uname to the architecture strings the release assets use.
glab_arch() {
  case "$(uname -m)" in
    x86_64)         echo amd64 ;;
    aarch64|arm64)  echo arm64 ;;
    armv7l|armv6l)  echo armv6 ;;
    i686|i386)      echo 386 ;;
    *)              return 1 ;;
  esac
}

# Ask the project for its newest tag rather than pinning one here, so this does
# not go stale in the script. Tags are "v1.2.3"; the asset names drop the "v".
glab_latest_version() {
  curl -fsSL "https://gitlab.com/api/v4/projects/$GLAB_PROJECT/releases/permalink/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name":"v\([^"]*\)".*/\1/p'
}

# True when $1 is a bus name with a current owner on this shell's session bus.
# The timeouts matter: a wrong bus does not answer, it hangs, which is the
# failure being diagnosed.
dbus_name_has_owner() {
  command -v dbus-send &>/dev/null || return 2
  timeout 5 dbus-send --session --reply-timeout=2000 --print-reply \
    --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner "string:$1" 2>/dev/null \
    | grep -q "boolean true"
}

# Download the release tarball into ~/.local/bin. Nothing here needs sudo, which
# is why it goes under $HOME rather than /usr/local/bin.
install_glab() {
  local arch version url tmp found current

  arch=$(glab_arch) || {
    echo "no glab build for $(uname -m)" >&2
    return 1
  }

  version=$(glab_latest_version)
  if [[ -z "$version" ]]; then
    echo "could not read the latest glab version from gitlab.com" >&2
    return 1
  fi

  if current=$(command -v glab 2>/dev/null) && [[ "$("$current" --version 2>/dev/null)" == *"$version"* ]]; then
    echo "glab $version already installed: $current"
    return 0
  fi

  url="https://gitlab.com/api/v4/projects/$GLAB_PROJECT/packages/generic/glab/$version/glab_${version}_linux_${arch}.tar.gz"
  echo "installing glab $version to $GLAB_BIN_DIR"

  tmp=$(mktemp -d) || return 1
  if ! curl -fsSL "$url" | tar -xz -C "$tmp"; then
    echo "glab download failed ($url)" >&2
    rm -rf "$tmp"
    return 1
  fi

  # The tarball's layout has changed across releases, so locate the binary
  # rather than assuming it sits at a fixed path inside the archive.
  found=$(find "$tmp" -type f -name glab -perm -u+x 2>/dev/null | head -1)
  if [[ -z "$found" ]]; then
    echo "no glab binary inside the tarball" >&2
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$GLAB_BIN_DIR"
  install -m 755 "$found" "$GLAB_BIN_DIR/glab"
  rm -rf "$tmp"

  case ":$PATH:" in
    *":$GLAB_BIN_DIR:"*) ;;
    *) echo "note: $GLAB_BIN_DIR is not on your PATH" >&2 ;;
  esac
}

# Report on all three, in the order they can fail. Returns non-zero if something
# needs attention, so this is usable as a preflight.
check_glab() {
  local status=0 bin secrets_ok=0

  if bin=$(command -v glab 2>/dev/null); then
    echo "  ok       glab $("$bin" --version 2>/dev/null | head -1 | awk '{print $2}') ($bin)"
  elif [[ -x "$GLAB_BIN_DIR/glab" ]]; then
    echo "  PROBLEM  glab is installed at $GLAB_BIN_DIR/glab but not on your PATH" >&2
    return 1
  else
    echo "  MISSING  glab -- run: $0 --install" >&2
    return 1
  fi

  # The keyring check comes before the auth check on purpose: authenticating
  # without a reachable keyring is what writes the token out in plaintext.
  case "$(dbus_name_has_owner org.freedesktop.secrets; echo $?)" in
    0) echo "  ok       Secret Service reachable (glab will use the keyring)"
       secrets_ok=1 ;;
    2) echo "  absent   dbus-send not installed, cannot check the keyring"
       secrets_ok=1 ;;
    *) echo "  PROBLEM  no Secret Service on this session bus" >&2
       echo "           glab will store the token in PLAINTEXT without asking" >&2
       echo "           fix the bus first: see scripts/README.md, Troubleshooting" >&2
       status=1 ;;
  esac

  # Presence of a token key is enough; never print the value.
  if [[ -f "$GLAB_CONFIG" ]] && grep -qE "^[[:space:]]*token:[[:space:]]*[^[:space:]]" "$GLAB_CONFIG" 2>/dev/null; then
    echo "  PROBLEM  a plaintext token is stored in $GLAB_CONFIG" >&2
    echo "           re-run 'glab auth login' once the keyring is reachable to" >&2
    echo "           move it there, then remove the leftover value by hand" >&2
    status=1
  fi

  # Only ask glab about its own auth once the keyring is known to be reachable.
  # On the wrong bus this call does not fail, it hangs waiting for a reply that
  # never comes -- and it ignores SIGTERM, so plain `timeout` leaves the process
  # behind and only -s KILL actually ends it. Both halves verified the hard way.
  if [[ $secrets_ok -eq 1 ]]; then
    if timeout -s KILL 15 glab auth status &>/dev/null; then
      echo "  ok       glab is authenticated"
    else
      echo "  absent   glab is not authenticated -- run: glab auth login"
      echo "           add --hostname <host> for a self-hosted instance"
    fi
  else
    echo "  skipped  not asking glab about its auth: on this bus the call hangs" >&2
  fi

  return $status
}

action=check
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) action=install; shift ;;
    --check)   action=check;   shift ;;
    --help|-h) usage; exit 0 ;;
    *)         echo "unknown option: $1" >&2; echo; usage; exit 1 ;;
  esac
done

case "$action" in
  install)
    install_glab || exit 1
    echo
    echo "glab:"
    check_glab
    ;;
  check)
    echo "glab:"
    check_glab
    ;;
esac
