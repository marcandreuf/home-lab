# Skills

One directory per skill, each containing a `SKILL.md`. `install-claude.sh`
symlinks every directory here that has one into `~/.claude/skills/`, so the
directory name is the skill name.

Skills adapted from [mattpocock/skills](https://github.com/mattpocock/skills)
carry a provenance footer naming the upstream path and the commit they came
from, and get a row in [../UPSTREAM.md](../UPSTREAM.md). Without that record, a
later `sync-upstream.sh` cannot tell an upstream rewording from a deliberate
local change. `sync-upstream.sh` finds ported skills by matching directory names
against upstream, so keep the name unless there is a reason to rename it, and
note the rename in the ledger when there is.

Nothing ported yet. `../UPSTREAM.md` holds the survey of what is worth taking.
