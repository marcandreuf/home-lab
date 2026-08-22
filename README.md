# Home Lab Scripts

This repository contains a small collection of shell scripts I use to automate common tasks in my home lab and daily workflow, plus the Claude Code commands and skills I want on every VM.

## Purpose

These scripts help me:
- start, restart, or manage services and programs
- interact with network and remote-access tools
- simplify repetitive admin tasks around my home lab setup
- keep one copy of my Claude Code commands and skills across every machine I clone this repo onto

## Layout

- [`scripts/`](scripts/README.md) – every shell script, with a page explaining what each one is for and when to reach for it
- `commands/` – Claude Code slash commands
- `skills/` – Claude Code skills, one directory per skill ([skills/README.md](skills/README.md))
- [`UPSTREAM.md`](UPSTREAM.md) – how we track [mattpocock/skills](https://github.com/mattpocock/skills)

## Scripts

Full descriptions in [scripts/README.md](scripts/README.md).

| Script | What it does |
| ------ | ------------ |
| `morning-terminals.sh` | Opens the morning workspace as positioned terminal windows (X11 only; `--install` on a new machine) |
| `banner.sh` | Prints a word as a coloured ASCII-art banner |
| `install-claude.sh` | Wires `commands/` and `skills/` into `~/.claude` |
| `sync-upstream.sh` | Reports what changed upstream in mattpocock/skills since the last review |
| `connect-vnc.sh` | Connects to a remote VNC session over an SSH tunnel |
| `wol-proxmox.sh` | Sends a Wake-on-LAN packet to the Proxmox host |
| `restart-program.sh` | Kills a program by name and relaunches it |
| `zerotier-reset-identity.sh` | Regenerates a ZeroTier node identity and rejoins a network |

## Claude Code

On a new VM, clone this repo and run `./scripts/install-claude.sh`. That is the whole setup: it symlinks the commands and skills into `~/.claude`, so a later `git pull` here updates every one of them on that machine at once.

- `commands/` – slash commands, written to be portable: they resolve the repo they operate on at run time rather than hardcoding a path, so the same file works on every VM. A project needing different wiring keeps its own override in that project's `.claude/commands/`.
  - `start-of-day.md` – resume from the latest journal in `.claude/journals/` and verify the repo still matches it
  - `wrap-up.md` – checkpoint the session into a dated journal so the next day can start cold
- `skills/` – skills, one directory per skill. See [skills/README.md](skills/README.md).

### Working on this repo

`scripts/sync-upstream.sh` is only needed on the machine where I actually develop home-lab, not on the VMs that just consume it. It clones [mattpocock/skills](https://github.com/mattpocock/skills) as a sibling at `~/projects/mattpocock-skills` and reports what changed there since the commit recorded in [`UPSTREAM.md`](UPSTREAM.md), so skills get ported deliberately rather than merged. That clone is disposable and the script never writes to `skills/`.

`UPSTREAM.md` holds the rest: why adapted skills live here rather than in a fork, how a fork is still used for contributing back, which upstream commit was last reviewed, the ledger of what has been ported, and the survey of what is worth taking.

## Notes

These are personal automation scripts tailored to my environment and workflow. They may need adjustments depending on your own machine names, network setup, or service configuration.

Feel free to adapt them for your own setup.
