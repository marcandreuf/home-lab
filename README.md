# Home Lab Scripts

This repository contains a small collection of shell scripts I use to automate common tasks in my home lab and daily workflow.

## Purpose

These scripts help me:
- start, restart, or manage services and programs
- interact with network and remote-access tools
- simplify repetitive admin tasks around my home lab setup

## Included Scripts

- banner.sh – helper script for displaying a banner or status message
- connect-vnc.sh – connects to a VNC session
- morning-terminals.sh – opens the morning workspace as positioned terminal windows; takes the project directory to open Claude Code in, e.g. `./morning-terminals.sh foo` for `~/projects/foo` (X11 only; run with --install on a new machine)
- restart-program.sh – restarts a program or service
- wol-proxmox.sh – sends a Wake-on-LAN request for a Proxmox host
- zerotier-reset-identity.sh – resets a ZeroTier identity when needed

## Notes

These are personal automation scripts tailored to my environment and workflow. They may need adjustments depending on your own machine names, network setup, or service configuration.

Feel free to adapt them for your own setup.
