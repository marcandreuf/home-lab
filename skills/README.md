# Skills

One directory per skill, each containing a `SKILL.md`. `install-claude.sh`
symlinks every directory here that has one into `~/.claude/skills/`, so the
directory name is the skill name.

Skills from [mattpocock/skills](https://github.com/mattpocock/skills) are ported
**faithfully**, not rewritten to taste. They are designed to compose, so editing
one quietly breaks the others that call it. Any deliberate divergence goes in
the Deviations section of [../docs/sdlc.md](../docs/sdlc.md) with a reason.

Each ported skill gets a row in [../UPSTREAM.md](../UPSTREAM.md) recording the
commit it came from. `sync-upstream.sh` finds them by matching directory names
against upstream, so keep the upstream name.

Nothing ported yet. [../docs/sdlc.md](../docs/sdlc.md) is the methodology those
skills implement; `../UPSTREAM.md` holds the survey of what each one costs to
take.
