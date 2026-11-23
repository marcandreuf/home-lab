#!/usr/bin/env bash

# vps-upgrade.sh - Upgrade a Docker VPS over SSH: stop containers, apt upgrade, reboot, start them again
#
# Usage:
#   ./vps-upgrade.sh <ssh-host>               Report what a run would do, change nothing (default)
#   ./vps-upgrade.sh <ssh-host> --check       Same as above
#   ./vps-upgrade.sh <ssh-host> --run         Stop containers, upgrade, reboot, start containers, check sites
#   ./vps-upgrade.sh <ssh-host> --start       Only start the containers again (recovery)
#   ./vps-upgrade.sh --help                   Show usage
#
# Options:
#   --yes, -y          With --run: skip the confirmation prompt
#   --no-reboot        With --run: upgrade and restart the containers, but do not reboot
#   --proxy a,b        Containers to stop last and start first (default: auto-detect)
#   --exclude a,b      Containers to leave alone: never stopped, never started
#
#
# WHY THIS EXISTS
#
#   A VPS that only runs websites in Docker needs one routine chore: take the
#   sites down for a few minutes, apt upgrade, reboot onto the new kernel and
#   bring everything back. Doing it by hand has one trap. Containers started
#   with `restart: unless-stopped` treat `docker stop` as a deliberate stop, so
#   they do NOT come back on their own after the reboot. This script records
#   what was running, and starts exactly that again afterwards.
#
#
# NOTHING HOST-SPECIFIC LIVES IN THIS REPO
#
#   <ssh-host> is anything ssh accepts. Use an alias from ~/.ssh/config, so the
#   address, port, user and key stay on your machine:
#
#     Host my-vps
#       HostName 203.0.113.10
#       Port 22
#       User ubuntu
#       IdentityFile ~/.ssh/my-vps-key
#       IdentitiesOnly yes
#
#   Container names are read from the host at run time. The edge proxy (any
#   container publishing host port 80 or 443, such as Traefik, Caddy or nginx)
#   is detected the same way, so a typical host needs no flags at all.
#
#
# WHAT IS LEFT ON EACH SIDE
#
#   Local:  ${XDG_STATE_HOME:-~/.local/state}/vps-upgrade/<ssh-host>/
#             containers.txt    what was running before the last --run
#             upgrade-*.log     the apt log of each run, copied back
#   Remote: nothing. The upgrade step is copied to /run/vps-upgrade (a tmpfs,
#           wiped by the reboot) and runs as the transient systemd unit
#           `vps-upgrade`, so a dropped SSH session cannot interrupt dpkg. Its
#           output goes to the journal: `journalctl -u vps-upgrade`.
#
#
# REQUIREMENTS ON THE HOST
#
#   A systemd distro with apt (Ubuntu, Debian), Docker, and passwordless sudo
#   for the SSH user. Every docker call goes through sudo, so the user does
#   not need to be in the docker group.
#
#
# IF IT STOPS HALFWAY
#
#   If apt fails, the host is not rebooted and the containers are started again
#   automatically. If this script itself dies after stopping the containers
#   (Ctrl-C, laptop asleep), the host carries on with the upgrade and reboot on
#   its own, and `--start` brings the containers back from the saved list.

set -euo pipefail

STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/vps-upgrade"
UNIT=vps-upgrade
RUN_DIR=/run/vps-upgrade
POLL_SECONDS=10
MAX_WAIT_SECONDS=2700      # upgrade + reboot, end to end
STOP_TIMEOUT=30            # seconds docker gives each container to exit
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)

usage() {
  cat <<EOF
vps-upgrade.sh - Upgrade a Docker VPS over SSH: stop containers, apt upgrade, reboot, start them again

Usage:
  $0 <ssh-host>               Report what a run would do, change nothing (default)
  $0 <ssh-host> --check       Same as above
  $0 <ssh-host> --run         Stop containers, upgrade, reboot, start containers, check sites
  $0 <ssh-host> --start       Only start the containers again (recovery)
  $0 --help                   Show usage

Options:
  --yes, -y          With --run: skip the confirmation prompt
  --no-reboot        With --run: upgrade and restart the containers, but do not reboot
  --proxy a,b        Containers to stop last and start first (default: auto-detect)
  --exclude a,b      Containers to leave alone: never stopped, never started

<ssh-host> is best an alias from ~/.ssh/config, so no address or key is typed
or stored anywhere else. State is kept locally in $STATE_ROOT/<ssh-host>/.
EOF
}

die() { echo "vps-upgrade: $*" >&2; exit 1; }
say() { printf '== %s\n' "$*"; }
# rsh never reads stdin (-n), so it cannot swallow a list being piped through a
# function that calls it. rsh_in is the one variant that feeds stdin to the host.
rsh()    { ssh -n "${SSH_OPTS[@]}" "$HOST" "$@"; }
rsh_in() { ssh "${SSH_OPTS[@]}" "$HOST" "$@"; }
in_list() { local x=$1 i; shift; for i in "$@"; do [[ $i == "$x" ]] && return 0; done; return 1; }

# ---------------------------------------------------------------- arguments

HOST="" MODE=check YES=0 REBOOT=1 PROXY_OVERRIDE="" EXCLUDE_CSV=""
while (($#)); do
  case $1 in
    -h|--help)  usage; exit 0 ;;
    --check)    MODE=check ;;
    --run)      MODE=run ;;
    --start)    MODE=start ;;
    -y|--yes)   YES=1 ;;
    --no-reboot) REBOOT=0 ;;
    --proxy)    PROXY_OVERRIDE=${2:?--proxy needs a comma-separated list}; shift ;;
    --exclude)  EXCLUDE_CSV=${2:?--exclude needs a comma-separated list}; shift ;;
    -*)         die "unknown option: $1 (see --help)" ;;
    *)          [[ -z $HOST ]] || die "only one host per run (got '$HOST' and '$1')"; HOST=$1 ;;
  esac
  shift
done
[[ -n $HOST ]] || { usage; exit 1; }

STATE_DIR="$STATE_ROOT/${HOST//[^A-Za-z0-9._-]/_}"
SAVED_LIST="$STATE_DIR/containers.txt"
IFS=',' read -r -a EXCLUDES <<<"$EXCLUDE_CSV"

# ---------------------------------------------------------------- host facts

# One SSH round trip that reports everything the plan needs, as KEY=value lines.
gather() {
  rsh_in 'bash -s' <<'EOF'
set -u
sudo -n true 2>/dev/null || { echo "ERR=passwordless sudo is not available for $(whoami)"; exit 0; }
command -v apt-get >/dev/null || { echo "ERR=apt-get not found (only apt-based hosts are supported)"; exit 0; }
echo "KERNEL=$(uname -r)"
echo "OS=$(. /etc/os-release; echo "$PRETTY_NAME")"
echo "BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)"
[ -f /var/run/reboot-required ] && echo "REBOOT_REQUIRED=yes" || echo "REBOOT_REQUIRED=no"
echo "UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c /)"
echo "UNIT_ACTIVE=$(systemctl is-active vps-upgrade 2>/dev/null)"
sudo docker info >/dev/null 2>&1 || { echo "ERR=docker is not running or not installed"; exit 0; }
echo "DOCKER=$(sudo docker version --format '{{.Server.Version}}')"
ids=$(sudo docker ps -aq)
[ -z "$ids" ] || sudo docker inspect --format \
  'C={{.Name}}|{{.State.Status}}|{{.HostConfig.RestartPolicy.Name}}|{{json .HostConfig.PortBindings}}' $ids
EOF
}

fact() { sed -n "s/^$1=//p" <<<"$INFO" | head -1; }

load_facts() {
  INFO=$(gather) || die "cannot reach $HOST over ssh (try: ssh $HOST)"
  local err; err=$(fact ERR)
  [[ -z $err ]] || die "$HOST: $err"

  ALL=() RUNNING=() DETECTED_PROXIES=()
  declare -gA POLICY=()
  local name state policy ports
  while IFS='|' read -r name state policy ports; do
    name=${name#/}
    ALL+=("$name"); POLICY[$name]=$policy
    [[ $state == running ]] && RUNNING+=("$name")
    grep -qE '"HostPort":"(80|443)"' <<<"$ports" && DETECTED_PROXIES+=("$name")
  done < <(sed -n 's/^C=//p' <<<"$INFO")

  if [[ -n $PROXY_OVERRIDE ]]; then IFS=',' read -r -a PROXIES <<<"$PROXY_OVERRIDE"
  else PROXIES=("${DETECTED_PROXIES[@]}"); fi
}

role_of() { in_list "$1" "${PROXIES[@]}" && echo proxy || echo app; }

# Running containers minus the excluded ones, as "role name" lines: apps first,
# then proxies, which is the stop order.
targets_ordered() {
  local c lines=""
  for c in "${RUNNING[@]}"; do
    in_list "$c" "${EXCLUDES[@]}" || lines+="$(role_of "$c") $c"$'\n'
  done
  awk '$1=="app"' <<<"$lines"; awk '$1=="proxy"' <<<"$lines"
}

print_summary() {
  local c tag
  printf '  %-11s %s (%s)\n' Host "$HOST" "$(fact OS)"
  printf '  %-11s %s, reboot required: %s\n' Kernel "$(fact KERNEL)" "$(fact REBOOT_REQUIRED)"
  printf '  %-11s %s upgradable (as of the host'"'"'s last apt update)\n' Packages "$(fact UPGRADABLE)"
  printf '  %-11s %s\n' Docker "$(fact DOCKER)"
  printf '  %-11s %d total, %d running\n' Containers "${#ALL[@]}" "${#RUNNING[@]}"
  for c in "${ALL[@]}"; do
    if in_list "$c" "${EXCLUDES[@]}"; then tag="excluded (left alone)"
    elif ! in_list "$c" "${RUNNING[@]}"; then tag="not running (left alone)"
    elif in_list "$c" "${PROXIES[@]}"; then tag="proxy: stopped last, started first"
    else tag="stop, then start after the upgrade"; fi
    printf '    %-50s %-16s %s\n' "$c" "${POLICY[$c]}" "$tag"
  done
  [[ -n $PROXY_OVERRIDE || ${#DETECTED_PROXIES[@]} -gt 0 ]] ||
    echo "  (no container publishes port 80/443; pass --proxy if one should go last/first)"
}

# ---------------------------------------------------------------- remote upgrade step

# Runs on the host as root, as a transient systemd unit. Reports progress through
# $RUN_DIR/status, which the local side polls. $1 is 1 to reboot, 0 not to.
read -r -d '' STAGE <<'EOF' || true
set -u
S=/run/vps-upgrade/status
status() { echo "$*" > "$S"; echo "== $(date -Is) $*"; }
apt_() {
  DEBIAN_FRONTEND=noninteractive apt-get -y -o DPkg::Lock::Timeout=600 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}
status "apt-get update"     ; apt_ update                  || { status "failed: apt-get update"; exit 1; }
status "apt-get upgrade"    ; apt_ upgrade --with-new-pkgs || { status "failed: apt-get upgrade"; exit 1; }
status "apt-get autoremove" ; apt_ autoremove --purge      || { status "failed: apt-get autoremove"; exit 1; }
echo "kernels installed:"; ls /boot/vmlinuz-*
if [ "${1:-1}" = 1 ]; then status "rebooting"; systemctl reboot; else status "done"; fi
EOF

# Prints the host's clock at launch, so the log fetch reads only this run's journal
# lines. Any status left by an earlier --no-reboot run is cleared first, or the
# poll would read its "done" and stop before this run has begun.
launch_stage() {
  rsh_in "sudo rm -rf $RUN_DIR && sudo install -d -m 700 $RUN_DIR && sudo tee $RUN_DIR/stage.sh >/dev/null &&
       date +%s && sudo systemd-run --unit=$UNIT --collect --quiet /bin/bash $RUN_DIR/stage.sh $REBOOT" <<<"$STAGE"
}

cleanup_remote() {   # only matters without a reboot; /run is wiped by one
  rsh "sudo rm -rf $RUN_DIR" 2>/dev/null || true
}

# Poll until the host reboots (boot id changes), the step finishes, or it fails.
# Sets STAGE_RESULT to rebooted, done or failed.
wait_for_stage() {
  local deadline=$(( $(date +%s) + MAX_WAIT_SECONDS )) last="" out bid st act down=0
  while :; do
    (( $(date +%s) < deadline )) || die "timed out after $((MAX_WAIT_SECONDS / 60)) min waiting for $HOST"
    if out=$(rsh "cat /proc/sys/kernel/random/boot_id; sudo cat $RUN_DIR/status 2>/dev/null || echo starting
                  systemctl is-active $UNIT 2>/dev/null || true" 2>/dev/null); then
      bid=$(sed -n 1p <<<"$out"); st=$(sed -n 2p <<<"$out"); act=$(sed -n 3p <<<"$out")
      if [[ $bid != "$BOOT_ID" ]]; then say "$HOST is back up after the reboot"; STAGE_RESULT=rebooted; return; fi
      down=0
      [[ $st == "$last" ]] || { say "$st"; last=$st; }
      case $st in
        failed:*) STAGE_RESULT=failed; return ;;
        done)     STAGE_RESULT=done; return ;;
        rebooting) ;;
        *) [[ $act == active || $act == activating ]] ||
             { say "the upgrade unit stopped without reporting a result"; STAGE_RESULT=failed; return; } ;;
      esac
    elif ((!down)); then
      say "$HOST is unreachable (rebooting)"; down=1
    fi
    sleep "$POLL_SECONDS"
  done
}

# Copy the step's journal output back. -b -1 is the boot it ran in, if it rebooted.
fetch_log() {
  local boot=$1 log="$STATE_DIR/upgrade-$(date +%Y%m%d-%H%M%S).log"
  if rsh "sudo journalctl -u $UNIT -o cat --no-pager -b $boot --since @$LAUNCH_EPOCH" >"$log" 2>/dev/null && [[ -s $log ]]; then
    say "apt log saved to $log"
  else
    rm -f "$log"; say "could not read the journal for this run (on the host: journalctl -u $UNIT)"
  fi
  LOG_FILE=$log
}

# ---------------------------------------------------------------- containers

wait_for_docker() {
  local i
  for i in $(seq 1 30); do rsh 'sudo docker info >/dev/null 2>&1' && return; sleep 4; done
  die "docker did not come up on $HOST"
}

# Start "role name" lines from stdin: proxies first, then apps. Missing ones are skipped.
start_list() {
  local lines role name proxies=() apps=()
  lines=$(cat)
  while read -r role name; do
    [[ -n $name ]] || continue
    in_list "$name" "${ALL[@]}" || { echo "  skipping $name: no longer exists"; continue; }
    if [[ $role == proxy ]]; then proxies+=("$name"); else apps+=("$name"); fi
  done <<<"$lines"
  ((${#proxies[@]})) && { say "starting proxy: ${proxies[*]}"; rsh sudo docker start "${proxies[@]}" >/dev/null; }
  ((${#apps[@]}))    && { say "starting ${#apps[@]} containers"; rsh sudo docker start "${apps[@]}" >/dev/null; }
  STARTED=("${proxies[@]}" "${apps[@]}")
}

check_running() {
  local bad=0 name st
  sleep 5
  say "container status"
  for name in "${STARTED[@]}"; do
    st=$(rsh sudo docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo missing)
    printf '    %-50s %s\n' "$name" "$st"
    [[ $st == running ]] || bad=1
  done
  return $bad
}

# For Traefik setups: request every Host(`...`) router rule over HTTPS from here.
check_sites() {
  ((${#STARTED[@]})) || return 0
  local hosts h code bad=0
  hosts=$(rsh "sudo docker inspect --format '{{range \$k, \$v := .Config.Labels}}{{\$k}}={{\$v}}{{println}}{{end}}' ${STARTED[*]}" |
          grep -E '^traefik\.http\.routers\.[^=]+\.rule=' | grep -oE 'Host\([^)]*\)' |
          grep -oE '`[^`]+`' | tr -d '`' | sort -u) || true
  [[ -n $hosts ]] || { say "no Traefik Host rules found; skipping the site check"; return 0; }
  say "site check (HTTPS from this machine)"
  while read -r h; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$h/" || true)
    printf '    %-55s %s\n' "$h" "$code"
    [[ $code =~ ^[23] ]] || bad=1
  done <<<"$hosts"
  return $bad
}

bring_back() {   # stdin: "role name" lines
  wait_for_docker
  start_list
  local ok=0
  check_running || { ok=1; echo "  some containers are not running: ssh $HOST sudo docker logs <name>" >&2; }
  check_sites   || { ok=1; echo "  some sites did not answer 2xx/3xx; they may still be warming up" >&2; }
  return $ok
}

# ---------------------------------------------------------------- modes

confirm() {
  ((YES)) && return
  [[ -t 0 ]] || die "not a terminal; pass --yes to run without the prompt"
  local ans
  read -r -p "Stop these containers and upgrade $HOST$( ((REBOOT)) && echo ', then reboot' )? [y/N] " ans
  [[ $ans =~ ^[Yy]$ ]] || { echo "Nothing changed."; exit 0; }
}

do_check() {
  load_facts
  print_summary
  [[ $(fact UNIT_ACTIVE) != active ]] || echo "  NOTE: an upgrade is running on this host right now"
  echo
  echo "Nothing changed. Run with --run to do it."
}

do_start() {
  load_facts
  if [[ -f $SAVED_LIST ]]; then
    say "starting the containers saved by the last run ($SAVED_LIST)"
    bring_back <"$SAVED_LIST"
  else
    say "no saved list for $HOST; starting every container that is not excluded"
    local c
    for c in "${ALL[@]}"; do in_list "$c" "${EXCLUDES[@]}" || printf '%s %s\n' "$(role_of "$c")" "$c"; done | bring_back
  fi
}

do_run() {
  load_facts
  [[ $(fact UNIT_ACTIVE) != active ]] || die "an upgrade is already running on $HOST (ssh $HOST systemctl status $UNIT)"
  print_summary
  echo
  confirm

  local kernel_before docker_before t0 targets stop_apps=() stop_proxies=() role name
  kernel_before=$(fact KERNEL); docker_before=$(fact DOCKER); BOOT_ID=$(fact BOOT_ID)
  targets=$(targets_ordered)
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$targets" | sed '/^$/d' >"$SAVED_LIST"
  while read -r role name; do
    [[ -n $name ]] || continue
    if [[ $role == proxy ]]; then stop_proxies+=("$name"); else stop_apps+=("$name"); fi
  done <<<"$targets"

  t0=$(date +%s)
  trap 'echo >&2; echo "vps-upgrade: interrupted. Containers on $HOST may be stopped; the host continues the upgrade on its own. Bring them back with: $0 $HOST --start" >&2' EXIT
  ((${#stop_apps[@]}))    && { say "stopping ${#stop_apps[@]} containers"; rsh sudo docker stop -t "$STOP_TIMEOUT" "${stop_apps[@]}" >/dev/null; }
  ((${#stop_proxies[@]})) && { say "stopping proxy: ${stop_proxies[*]}"; rsh sudo docker stop -t "$STOP_TIMEOUT" "${stop_proxies[@]}" >/dev/null; }

  say "starting the upgrade on $HOST (unit $UNIT)"
  LAUNCH_EPOCH=$(launch_stage) || die "could not start the upgrade unit on $HOST"
  wait_for_stage
  case $STAGE_RESULT in
    rebooted) fetch_log -1 ;;
    *)        fetch_log 0; cleanup_remote ;;
  esac
  if [[ $STAGE_RESULT == failed ]]; then
    [[ -f ${LOG_FILE:-} ]] && { echo "  last lines of the log:"; tail -n 15 "$LOG_FILE" | sed 's/^/    /'; }
    say "upgrade failed; the host was not rebooted. Starting the containers again."
  fi

  load_facts     # fresh container list and versions after the reboot
  local rc=0
  bring_back <"$SAVED_LIST" || rc=1
  trap - EXIT

  echo
  say "summary"
  printf '    %-9s %s -> %s\n' kernel "$kernel_before" "$(fact KERNEL)"
  printf '    %-9s %s -> %s\n' docker "$docker_before" "$(fact DOCKER)"
  printf '    %-9s %s\n' downtime "$(( ($(date +%s) - t0) / 60 )) min $(( ($(date +%s) - t0) % 60 )) s"
  printf '    %-9s %s left upgradable, reboot required: %s\n' packages "$(fact UPGRADABLE)" "$(fact REBOOT_REQUIRED)"
  [[ $STAGE_RESULT != failed ]] || rc=1
  return $rc
}

case $MODE in
  check) do_check ;;
  start) do_start ;;
  run)   do_run ;;
esac
