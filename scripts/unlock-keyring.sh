#!/bin/bash

# unlock-keyring.sh: Make the GNOME keyring unlockable on a headless/VNC session,
# then optionally open Seahorse to unlock it.
#
# Usage:
#   ./unlock-keyring.sh            # fix the session, report state, exit
#   ./unlock-keyring.sh --seahorse # fix the session, then launch Seahorse
#   ./unlock-keyring.sh --check    # report state only, change nothing
#
# Environment Variables:
#   DISPLAY   - X display to use (default: :1.0, the usual VNC display here)
#
# The problem this solves
#
# On a VNC/headless box there is no full desktop session, so nothing exports
# DISPLAY into the D-Bus activation environment. gnome-keyring-daemon runs with
# --components=pkcs11,secrets and has no prompter of its own: the password
# window is a separate binary, /usr/libexec/gcr-prompter, that D-Bus starts on
# demand. Started without DISPLAY it has nowhere to draw, dies immediately, and
# whoever asked for the unlock waits for a window that never appears.
#
# Symptoms this produces, all of them silent:
#   - Seahorse opens but the Unlock button does nothing, or hangs.
#   - glab fails with: failed to unlock correct collection
#     '/org/freedesktop/secrets/collection/login'
#   - secret-tool and anything else using libsecret hang or fail the same way.
#
# Note: running gcr-prompter by hand does NOT fix it. It exits when idle by
# design, because it is meant to be D-Bus activated. The fix is to give D-Bus
# the DISPLAY so it can start the prompter itself.
#
# Making it permanent
#
# This lasts for the life of the session bus. To stop doing it by hand, put
#   dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
# in the startup of the graphical session (e.g. ~/.vnc/xstartup), which is what
# a full desktop environment does and what is missing here.

set -u

DISPLAY_VALUE="${DISPLAY:-:1.0}"
BUS="unix:path=/run/user/$(id -u)/bus"
MODE="fix"

case "${1:-}" in
    --check)    MODE="check" ;;
    --seahorse) MODE="seahorse" ;;
    --help|-h)  sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")         ;;
    *)          echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

export DBUS_SESSION_BUS_ADDRESS="$BUS"
export DISPLAY="$DISPLAY_VALUE"

echo "bus:     $BUS"
echo "display: $DISPLAY_VALUE"

# 1. The secrets service must be there at all. Note gnome-keyring-daemon's
#    process name is truncated to 15 chars, so a full-name pgrep never matches:
#    use a short pattern or pgrep -af.
if pgrep -af gnome-keyring > /dev/null 2>&1; then
    echo "daemon:  gnome-keyring-daemon running"
else
    echo "daemon:  NOT RUNNING. Nothing below will help; start your session's keyring daemon first." >&2
    exit 1
fi

locked_state() {
    busctl --user call org.freedesktop.secrets \
        /org/freedesktop/secrets/collection/login \
        org.freedesktop.DBus.Properties Get ss \
        org.freedesktop.Secret.Collection Locked 2>/dev/null | awk '{print $3}'
}

echo "locked:  $(locked_state)"

if [ "$MODE" = "check" ]; then
    if gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.ListActivatableNames 2>/dev/null |
        grep -q "org.gnome.keyring.SystemPrompter"; then
        echo "prompter: activatable by name"
    else
        echo "prompter: NOT activatable, the D-Bus service file is missing" >&2
    fi
    exit 0
fi

# 2. The actual fix: hand DISPLAY (and XAUTHORITY when there is one) to D-Bus and
#    to systemd --user, so the services they start inherit them.
VARS="DISPLAY"
[ -n "${XAUTHORITY:-}" ] && VARS="$VARS XAUTHORITY"

if dbus-update-activation-environment --systemd $VARS 2>/dev/null; then
    echo "env:     $VARS pushed to the D-Bus and systemd activation environments"
elif gdbus call --session --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.UpdateActivationEnvironment \
    "{'DISPLAY': '$DISPLAY_VALUE'}" > /dev/null 2>&1; then
    echo "env:     DISPLAY pushed to the D-Bus activation environment (systemd form unavailable)"
else
    echo "env:     FAILED to update the activation environment" >&2
    exit 1
fi

# 3. Prove it: ask D-Bus to start the prompter and see whether it answers.
if gdbus call --session --dest org.gnome.keyring.SystemPrompter \
    --object-path /org/gnome/keyring/Prompter \
    --method org.freedesktop.DBus.Peer.Ping > /dev/null 2>&1; then
    echo "prompter: started by D-Bus and answering"
else
    echo "prompter: did not come up. Check that $DISPLAY_VALUE is the right display." >&2
    exit 1
fi

if [ "$MODE" = "seahorse" ]; then
    echo
    echo "Opening Seahorse. Click the Login keyring and unlock it."
    exec seahorse
fi

echo
echo "Ready. Unlock it either way:"
echo "  - open Seahorse and unlock the Login keyring, or"
echo "  - just run the command that needs it (glab, secret-tool) and answer the window."
