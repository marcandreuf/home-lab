# Scripts

Every script takes `--help` or prints its usage when run with no arguments, and each carries a full comment header. This page is the map: what each one is for and when to reach for it. The header in the script is the reference.

Paths are resolved from the script's own location, so the repo can be cloned anywhere and the scripts can be run from any working directory.

## Daily workflow

### `morning-terminals.sh`

Opens the morning terminal layout as gnome-terminal windows at fixed sizes and positions (lazydocker, a banner, and Claude Code), then raises the Claude Code window so it lands on top. X11 only, since it uses `xdotool` to place windows.

```sh
./scripts/morning-terminals.sh              # opens in ~/projects — a picker, not a session
./scripts/morning-terminals.sh foo          # opens in ~/projects/foo, banner "FOO"
./scripts/morning-terminals.sh --banner Memship
./scripts/morning-terminals.sh --install    # install missing requirements
./scripts/morning-terminals.sh --check      # report requirement status
```

A bare project name resolves under `~/projects`; anything with a slash is used as the path itself, absolute or relative to `$HOME`. Pass one repo: a session is scoped to a single repo root ([One repo per session](../docs/sdlc.md#one-repo-per-session)), so the bare `~/projects` default is where you pick one, not where you work. Run `--install` once on a new machine: it installs `xdotool`, `gnome-terminal` and `toilet` from apt, and fetches the `lazydocker` release binary, which is not packaged.

The window geometries are tuned to one screen size. On a different display, re-tune them; the header explains how to read the current geometry out of `xdotool`.

If it opens no windows and ends with `could not focus the Claude Code window`, see [Troubleshooting](#troubleshooting): the shell is on a different D-Bus session bus than the desktop.

### `banner.sh`

Prints a word as a coloured ASCII-art banner via `toilet`, framed by horizontal rules. Used by `morning-terminals.sh` for its banner window, and standalone for labelling a terminal.

```sh
./scripts/banner.sh HOME-LAB
./scripts/banner.sh -c cyan -f mono12 -r '=' HOME-LAB
```

Needs `toilet` (`apt install toilet`). `toilet -I3` lists installed fonts.

## Claude Code

### `install-claude.sh`

Symlinks `../commands/` and `../skills/` into `~/.claude`, so every project on the machine gets them and a later `git pull` here updates them all at once. This is the whole setup on a new VM.

```sh
./scripts/install-claude.sh                        # into ~/.claude
./scripts/install-claude.sh --check                # what is wired up, change nothing
./scripts/install-claude.sh --uninstall            # remove links pointing into this repo
```

Existing real files are reported and skipped rather than overwritten, so a hand-written command in `~/.claude/commands` survives; `--force` replaces them. `--uninstall` only removes symlinks that resolve into this repo and leaves anything else alone.

**The install is always global — there is no per-repo install.** The commands are written to resolve the repo they operate on at run time, so one machine-wide set is already correct in every repo; a repo-local copy would add nothing but a fork that drifts, and in a repo that commits `.claude/settings.json` it would be a fork that gets committed. To change how a command behaves, edit it here and `git pull` on each VM — the symlink means there is nothing to re-install.

That is separate from a session being scoped to one repo ([One repo per session](../docs/sdlc.md#one-repo-per-session)): that rule is about where a session *runs*, not about each repo owning a copy of the tooling.

`--project`, `--workspace` and `--copy` are still recognised and exit with that explanation rather than doing something surprising.

A global install then **offers** three machine-wide changes, each asked for separately and each skippable. First, the guardrails hook in `~/.claude/settings.json` (`--hooks` / `--no-hooks`), described above. Second, the token counter status line in the same file (`--statusline` / `--no-statusline`), described below: the prompt renders a live sample line rather than describing one, which doubles as a check that the script runs on this machine. An existing `statusLine` pointing somewhere else is reported and left alone, the same way a real file at a symlink path is, and `--force` replaces it. Third, two rules in the global git ignore file (`--git-rules` / `--no-git-rules`):

```
**/.claude/journals/
**/.claude/settings.local.json
```

The commands only instruct the model not to commit a journal; these rules are what actually stop `git add -A`, in every repo on the machine including ones not cloned yet — which is exactly the state a rebuilt VM is in. The script asks first, appends only the rules that are absent, never rewrites an existing line, and writes to the file git really consults (`core.excludesFile` when set, the XDG default otherwise). Answer up front with `--git-rules` or `--no-git-rules`; when stdin is not a terminal it skips rather than assuming. `--check` reports each rule as present or absent, and `--uninstall` leaves them alone — they are a git preference you opted into, not a link this script owns.

### `block-dangerous-commands.sh`

A `PreToolUse` hook: Claude Code pipes it the pending Bash command as JSON, and it exits 2 to refuse anything destructive. `install-claude.sh` offers to wire it into `~/.claude/settings.json`, machine-wide, pointing at this file so a `git pull` updates the rules.

Blocked: `git push --force` / `-f` / `--force-with-lease`, `reset --hard`, `clean -f`, `branch -D`, `checkout .` / `restore .`, history rewrites (`filter-branch`, `reflog expire`, `gc --prune`, `update-ref -d`), `gh repo delete/archive/rename`, `gh api` with a write flag, `rm -rf` on an absolute path or `$HOME`, and `docker prune` / `volume rm` / `compose down -v`.

**Plain `git push` is not blocked** — it is ordinary development work, and a wall you have to edit a file to get past is the wrong tool for something you do daily. It gets a confirmation instead: `install-claude.sh` adds `Bash(git push:*)` to `permissions.ask` in `~/.claude/settings.json`, so Claude Code asks every time. The ask rule matters because answering "yes, and don't ask again" to a plain prompt writes an allow rule into `settings.local.json`, and pushes would silently become automatic from then on. Only the force variants are refused outright, since they overwrite remote history.

The point of a hook rather than a `deny` rule in `settings.json` is that permission rules match a command *prefix*, so `Bash(gh api -X:*)` catches `gh api -X DELETE repos/x` and misses `gh api repos/x -X DELETE`, `gh api -XDELETE ...`, and anything inside `bash -c`. A hook is handed the whole string.

Patterns match only at a **command position**: the start of a line, or straight after `;`, `&`, `|`, `(`, `{`, a backtick, `$(`, or one of the wrappers whose argument is itself a command (`-c`, `eval`, `sudo`, `nohup`, `time`, `xargs`). One optional quote may follow, which is what catches `bash -c 'gh api -X DELETE ...'`. A quote on its own is not a command position, so writing *about* one of these commands is fine — `echo 'git push --force is what I would do'` runs, and so does a heredoc documenting this very file. The first version matched anywhere in the line and refused its own documentation on day one.

It still matches text, so a command assembled at run time — base64, variable indirection — goes around it. A guardrail, not a sandbox. The other gap is a wrapper not in that list; add it to `CMD_POS` when one turns up.

`tests/run-hook-cases.sh` is the regression suite: 98 cases pairing each refusal with the ordinary command it could be confused with. Run it after touching the patterns or `CMD_POS`.

Ported from upstream's `misc/git-guardrails-claude-code` and widened past git; see the Deviations section of [../docs/sdlc.md](../docs/sdlc.md).

### `statusline.sh`

The Claude Code status line: a token counter in the row above the footer. Claude Code pipes it the session's JSON on stdin and prints whatever it writes. `install-claude.sh` offers to wire it into `~/.claude/settings.json`, machine-wide, pointing at this file so a `git pull` updates it.

```
Opus | home-lab | main* | ██░░░ 34% 68k/200k | 5h 24% 1h47m | 7d 41%
```

Left to right: the model, the directory, the git branch with `*` when tracked files are dirty, a short bar with the percentage of the context window used and the token counts against the real window size (200k, or 1M on an extended-context model), the rolling 5-hour limit with a countdown to its reset, and the weekly cap.

```sh
./scripts/statusline.sh --demo             # render a sample line
echo "$json" | ./scripts/statusline.sh     # render from a session blob
```

**Every segment is optional, and that is the whole difficulty.** `rate_limits` exists only for Claude.ai Pro and Max subscribers, only after the first API response of a session, and Claude Code drops each window from the JSON once that window's `resets_at` has passed. On a metered API key it never appears at all and the `5h` and `7d` segments simply do not render. `used_percentage` is null early in a session and again after `/compact`. The branch is absent outside a repo. So the script renders what it has and stays quiet about the rest, and `0%` is carefully not treated as missing: it is a real reading and has to show.

The bar is deliberately short, five characters, so everything else fits on one line. When it still would not fit, segments drop by priority: `7d` first, then the model, the directory, the branch. Below that the context segment sheds its token counts rather than lose the 5-hour window, because the percentage already summarises the counts while nothing else reports the window you are actually spending. The terminal width comes from `COLUMNS`, which Claude Code exports; `tput cols` cannot work here, because Claude Code captures the script's output instead of handing it a terminal.

`jq` reads the JSON when it is installed, about 3ms, and `python3` does when it is not, about 17ms. Both produce the same fixed-order record, so nothing downstream knows which one ran, and the test suite runs the whole file twice, once with `jq` hidden, so the fallback is not a code path that only ever executes on a VM nobody tests.

Tuning, all optional: `STATUSLINE_BAR_WIDTH` (default 5), `STATUSLINE_GIT_TTL` (default 5 seconds), and `NO_COLOR` to drop the ANSI colours. `git status` is the one genuinely slow call, so its result is cached per session for a few seconds, keyed on the session id rather than `$$`, which changes on every invocation and would mean the cache never hits.

The script does not use `set -e`. A status line that exits early prints an empty row, which reads as a broken terminal rather than a missing number, so failures degrade to a shorter line instead.

`tests/run-statusline-cases.sh` is the regression suite: 21 cases, run against both readers. Most of them are absence cases, since that is where the bugs are.

### `sync-upstream.sh`

Reports what changed in [mattpocock/skills](https://github.com/mattpocock/skills) since the commit recorded in `../UPSTREAM.md`, so skills get ported deliberately rather than merged. It never writes to `../skills/`.

```sh
./scripts/sync-upstream.sh              # changes since LAST_REVIEWED
./scripts/sync-upstream.sh --ported     # only skills we have already ported
./scripts/sync-upstream.sh --mark       # record upstream HEAD as reviewed
```

A maintainer tool, for the machine this repo is developed on. Other VMs clone this repo, run `install-claude.sh`, and never need an upstream clone. Settings live in [`../UPSTREAM.md`](../UPSTREAM.md), including the optional `FORK_URL` for contributing back upstream.

### `install-glab.sh`

Installs the [GitLab CLI](https://gitlab.com/gitlab-org/cli) and checks it can store a token safely. The engineering skills can track issues in GitLab instead of GitHub, and every one of those operations shells out to `glab`; nothing else here installs it, and it is not in apt.

```sh
./scripts/install-glab.sh              # report status, install nothing (default)
./scripts/install-glab.sh --install    # install or update, then report
```

**The keyring matters more than the binary.** By default `glab` stores the token in the OS keyring — the Secret Service on Linux. When no keyring is reachable it does not fail and does not ask: it writes the token in **plaintext** to `~/.config/glab-cli/config.yml`. On a machine whose desktop is on a different D-Bus bus than the keyring, that happens silently. So the check probes the Secret Service, warns if a plaintext token is already sitting in the config, and reports auth last — the order in which these things actually fail.

Authenticating stays a human step (`glab auth login` is interactive, and takes `--hostname` for a self-hosted instance). Credentials already written as plaintext are not stuck: re-running `glab auth login` with a reachable keyring moves them into it.

Fix the bus **before** authenticating — see [Troubleshooting](#troubleshooting) and [`vnc-xstartup`](#vnc-xstartup). On the wrong bus `glab` does not error, it hangs, and it ignores `SIGTERM`, so it takes `kill -9`. The check knows this and skips the auth probe rather than hanging with it.

## Home lab admin

### `connect-vnc.sh`

Connects to a remote VNC session over an SSH tunnel. By default it attaches to the existing session, leaving running apps alone.

```sh
./scripts/connect-vnc.sh 192.168.1.100
./scripts/connect-vnc.sh 192.168.1.100 myuser 59004 5902 2
REMOTE_USER=myuser ./scripts/connect-vnc.sh 192.168.1.100
```

Defaults: user from `$REMOTE_USER` (else `user`), local port 59003, remote port 5901, display 1.

`--restart` restarts the VNC server on the remote host. That **kills every app running in the session**, so it is for recovering a broken session (an auth failure, say), not for routine connecting.

After connecting it warns if the remote session is running its own D-Bus bus — the condition behind [issue #5](https://github.com/marcandreuf/home-lab/issues/5), where credential tools cannot reach the keyring and terminals can fail to open ([Troubleshooting](#troubleshooting)). `vnc-xstartup` below is the fix; the warning is non-fatal, since a desktop with an unreachable keyring still works.

### `vnc-xstartup`

A drop-in replacement for `~/.vnc/xstartup` that keeps the VNC desktop on **one** D-Bus session bus. Not a script you run — a file you install on the machine that *runs* the VNC server, not the one you connect from.

**`loginctl enable-linger` is a prerequisite, not an optional extra.** Without it `/run/user/<uid>` exists only while the user has a login session, so a desktop pointed at the systemd bus would lose that bus on every SSH disconnect — worse than the problem being fixed, since the VNC session is meant to outlive the connection.

```sh
ssh <user>@<host>
loginctl enable-linger "$(id -un)"
loginctl show-user "$(id -un)" -p Linger --value     # must print: yes

install -m 755 scripts/vnc-xstartup ~/.vnc/xstartup
vncserver -kill :1 && vncserver :1 -localhost no     # kills everything in the session
```

The stock `xstartup` unsets `DBUS_SESSION_BUS_ADDRESS` and runs `dbus-launch`, giving the desktop a private bus while the Secret Service sits on the systemd one. Credential tools then either hang or — silently, which is worse — write secrets to their config file in plaintext. This version uses the systemd bus when it exists and keeps `dbus-launch` as a fallback, so the desktop can never end up with no bus at all.

It also runs `dbus-update-activation-environment --systemd DISPLAY XAUTHORITY`. That line is not optional: on the systemd bus, GUI services are activated by `systemd --user`, which has its own environment, so without `DISPLAY` there a terminal fails to open with `Cannot open display:`. Setting `DISPLAY` in your shell does not help — systemd is the process that needs it.

Verify with `./scripts/morning-terminals.sh --check` on the VM, which reports both halves.

### `wol-proxmox.sh`

Sends a Wake-on-LAN magic packet to bring the Proxmox host up.

```sh
./scripts/wol-proxmox.sh 'aa:bb:cc:dd:ee:ff' '192.168.1.255'
```

Needs `wakeonlan`. To find the target's MAC, run `cat /sys/class/net/<iface>/address` on it; for the broadcast address, `ip -4 addr show | grep brd`.

### `restart-program.sh`

Kills every process matching a name and relaunches it. Built for desktop programs that wedge, like `conky`.

```sh
./scripts/restart-program.sh conky
./scripts/restart-program.sh conky --kill-only
```

It matches by name and kills with `SIGKILL`, no graceful shutdown, so check what the name matches before running it on something that holds unsaved state.

### `zerotier-reset-identity.sh`

Deletes the ZeroTier identity files so the node generates a fresh ID, then rejoins the given network. The fix for two machines cloned from one image that ended up sharing a node ID.

```sh
sudo ./scripts/zerotier-reset-identity.sh <NETWORK_ID>
```

Needs root. The node gets a **new ID**, so it has to be re-authorized in the ZeroTier controller before it can reach the network again.

## Troubleshooting

### `morning-terminals.sh` opens no windows, then `could not focus the Claude Code window`

The tell-tale is that the D-Bus errors arrive back at the prompt *after* the
script has already exited, up to 25 seconds later:

```
# Failed to use specified server: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown:
#   The name :1.NN was not provided by any .service files
# Falling back to default server.                                          (x3)
could not focus the Claude Code window
# Error constructing proxy for org.gnome.Terminal:/org/gnome/Terminal/Factory0:
#   Error calling StartServiceByName for org.gnome.Terminal: Timeout was reached
```

**Cause: the shell and the desktop are on two different D-Bus session buses.**

A VNC session started from `~/.vnc/xstartup` runs `dbus-launch`, so it gets a
private bus at `/tmp/dbus-XXXXXXXX`. Meanwhile `systemd --user` runs its own at
`/run/user/$(id -u)/bus`, and that is the one holding the Secret Service. Export
`DBUS_SESSION_BUS_ADDRESS` from a shell rc file to reach the keyring and the
shell moves off the bus its own windows live on. `gnome-terminal` then asks a
bus that has never heard of the server owning this window, falls back to
activating a new one, and that activation fails — leaving `morning-terminals.sh`
with no window to focus and no error it can see.

This is the keyring problem in
[issue #5](https://github.com/marcandreuf/home-lab/issues/5) seen from the other
side: the workaround for one is the cause of the other.

**Confirm it:**

```sh
./scripts/morning-terminals.sh --check     # names both halves if they are wrong
```

Or by hand — the server named by `GNOME_TERMINAL_SERVICE` owns the window you
are typing in, so the bus you are on should know it:

```sh
dbus-send --session --print-reply --dest=org.freedesktop.DBus \
  /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
  "string:$GNOME_TERMINAL_SERVICE"        # boolean false => wrong bus
```

**Fix: scope the export to the command that needs it.** Replace a blanket
`export DBUS_SESSION_BUS_ADDRESS=...` in `~/.zshrc` or `~/.bashrc` with a
wrapper, so the credential tool reaches the keyring while everything else stays
on the session's own bus:

```sh
# <tool> is whichever CLI stores its credentials in the Secret Service
<tool>() {
  local bus="/run/user/$(id -u)/bus"
  if [ -S "$bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" command <tool> "$@"
  else
    command <tool> "$@"
  fi
}
```

To recover the shell you are already in without closing its windows — the
address is the one the running `gnome-terminal-server` is using, read from its
own environment:

```sh
unset GNOME_TERMINAL_SERVICE GNOME_TERMINAL_SCREEN
export DBUS_SESSION_BUS_ADDRESS="$(tr '\0' '\n' < /proc/$(pgrep -f gnome-terminal-server | head -1)/environ \
  | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
```

Do **not** kill `gnome-terminal-server` to clear the state: it owns every
terminal window on the desktop, including the one running the fix.

### Activating `gnome-terminal-server` fails with `Cannot open display:`

```
systemctl --user status gnome-terminal-server.service
  gnome-terminal-server[NNNN]: Failed to parse arguments: Cannot open display:
```

D-Bus activation of the terminal server goes through `systemd --user`, which
inherits *its* environment, not the client's. A VNC session started by hand
never tells it which display to open, so activation dies instantly and the
client waits out the full D-Bus timeout. Having `DISPLAY` set in your shell does
not help; systemd is the one that needs it.

```sh
systemctl --user show-environment | grep DISPLAY       # empty => this is your problem
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
systemctl --user reset-failed gnome-terminal-server.service
```

Put the `dbus-update-activation-environment` line in `~/.vnc/xstartup` to make
it survive the next login. It is a prerequisite for any fix that moves the VNC
desktop onto the systemd bus, since every GUI app then activates through
`systemd --user` too.
