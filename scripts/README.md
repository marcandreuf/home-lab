# Scripts

Every script takes `--help` or prints its usage when run with no arguments, and
each carries a full comment header. This page is the map: what each one is for
and when to reach for it. The header in the script is the reference.

Paths are resolved from the script's own location, so the repo can be cloned
anywhere and the scripts can be run from any working directory.

## Daily workflow

### `morning-terminals.sh`

Opens the morning workspace as gnome-terminal windows at fixed sizes and screen
positions (lazydocker, a banner, and Claude Code), then raises the Claude Code
window so it lands on top. X11 only, since it uses `xdotool` to place windows.

```sh
./scripts/morning-terminals.sh              # opens in ~/projects
./scripts/morning-terminals.sh foo          # opens in ~/projects/foo, banner "FOO"
./scripts/morning-terminals.sh --banner Memship
./scripts/morning-terminals.sh --install    # install missing requirements
./scripts/morning-terminals.sh --check      # report requirement status
```

A bare project name resolves under `~/projects`; anything with a slash is used
as the path itself, absolute or relative to `$HOME`. Run `--install` once on a
new machine: it installs `xdotool`, `gnome-terminal` and `toilet` from apt, and
fetches the `lazydocker` release binary, which is not packaged.

The window geometries are tuned to one screen size. On a different display,
re-tune them; the header explains how to read the current geometry out of
`xdotool`.

### `banner.sh`

Prints a word as a coloured ASCII-art banner via `toilet`, framed by horizontal
rules. Used by `morning-terminals.sh` for its banner window, and standalone for
labelling a terminal.

```sh
./scripts/banner.sh HOME-LAB
./scripts/banner.sh -c cyan -f mono12 -r '=' HOME-LAB
```

Needs `toilet` (`apt install toilet`). `toilet -I3` lists installed fonts.

## Claude Code

### `install-claude.sh`

Symlinks `../commands/` and `../skills/` into `~/.claude`, so every project on
the machine gets them and a later `git pull` here updates them all at once. This
is the whole setup on a new VM.

```sh
./scripts/install-claude.sh                        # global, into ~/.claude
./scripts/install-claude.sh --check                # what is wired up, change nothing
./scripts/install-claude.sh --uninstall            # remove links pointing into this repo
./scripts/install-claude.sh --workspace ~/projects/foo --copy
```

Existing real files are reported and skipped rather than overwritten, so a
hand-written command in `~/.claude/commands` survives; `--force` replaces them.
`--uninstall` only removes symlinks that resolve into this repo and leaves
anything else alone.

`--workspace PATH` installs into one project's `.claude/` instead of globally.
Add `--copy` there to get editable files that deliberately diverge from this
repo, which is the point of a project-local override; without it you get
symlinks that keep tracking this repo.

### `sync-upstream.sh`

Reports what changed in [mattpocock/skills](https://github.com/mattpocock/skills)
since the commit recorded in `../UPSTREAM.md`, so skills get ported deliberately
rather than merged. It never writes to `../skills/`.

```sh
./scripts/sync-upstream.sh              # changes since LAST_REVIEWED
./scripts/sync-upstream.sh --ported     # only skills we have already ported
./scripts/sync-upstream.sh --mark       # record upstream HEAD as reviewed
```

A maintainer tool, for the machine this repo is developed on. Other VMs clone
this repo, run `install-claude.sh`, and never need an upstream clone. Settings
live in [`../UPSTREAM.md`](../UPSTREAM.md), including the optional `FORK_URL`
for contributing back upstream.

## Home lab admin

### `connect-vnc.sh`

Connects to a remote VNC session over an SSH tunnel. By default it attaches to
the existing session, leaving running apps alone.

```sh
./scripts/connect-vnc.sh 192.168.1.100
./scripts/connect-vnc.sh 192.168.1.100 myuser 59004 5902 2
REMOTE_USER=myuser ./scripts/connect-vnc.sh 192.168.1.100
```

Defaults: user from `$REMOTE_USER` (else `user`), local port 59003, remote port
5901, display 1.

`--restart` restarts the VNC server on the remote host. That **kills every app
running in the session**, so it is for recovering a broken session (an auth
failure, say), not for routine connecting.

### `wol-proxmox.sh`

Sends a Wake-on-LAN magic packet to bring the Proxmox host up.

```sh
./scripts/wol-proxmox.sh 'aa:bb:cc:dd:ee:ff' '192.168.1.255'
```

Needs `wakeonlan`. To find the target's MAC, run `cat /sys/class/net/<iface>/address`
on it; for the broadcast address, `ip -4 addr show | grep brd`.

### `restart-program.sh`

Kills every process matching a name and relaunches it. Built for desktop
programs that wedge, like `conky`.

```sh
./scripts/restart-program.sh conky
./scripts/restart-program.sh conky --kill-only
```

It matches by name and kills with `SIGKILL`, no graceful shutdown, so check what
the name matches before running it on something that holds unsaved state.

### `zerotier-reset-identity.sh`

Deletes the ZeroTier identity files so the node generates a fresh ID, then
rejoins the given network. The fix for two machines cloned from one image that
ended up sharing a node ID.

```sh
sudo ./scripts/zerotier-reset-identity.sh <NETWORK_ID>
```

Needs root. The node gets a **new ID**, so it has to be re-authorized in the
ZeroTier controller before it can reach the network again.
