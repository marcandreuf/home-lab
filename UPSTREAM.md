# Upstream: mattpocock/skills

Skills in `skills/` come from [mattpocock/skills](https://github.com/mattpocock/skills)
(MIT). We work to that methodology as written, so skills get ported **faithfully**
rather than rewritten to taste: the skills are designed to compose, and local
edits to one quietly break the others that call it. The flow itself is summarised
in [docs/sdlc.md](docs/sdlc.md).

Any deliberate divergence is recorded in the Deviations section of
`docs/sdlc.md`, with a reason. Everything else is a straight copy.

Because we track alignment rather than taste, `sync-upstream.sh` matters **more**
here, not less: an upstream change to a skill we have ported is normally
something to take, not something to weigh. The ledger below is what tells a
deliberate divergence apart from a change we simply have not taken yet.

A fork is still useful for **contributing back**, and stays safe because it
never holds local edits. See `FORK_URL` below.

## Configuration

**UPSTREAM_DIR** is the local clone `sync-upstream.sh` reads from, on whichever
machine this repo is being worked on. It is disposable: `LAST_REVIEWED` below is
the only state that matters and it lives here, so deleting the clone and cloning
again loses nothing. `sync-upstream.sh` clones it when it is missing.

```
UPSTREAM_DIR = ~/projects/skills
```

**FORK_URL** is optional. Set it to a personal fork of `mattpocock/skills` to
contribute back. `sync-upstream.sh` then clones the fork as `origin` and adds
`mattpocock/skills` as a second remote, so pushes go to the fork while reads
still come from upstream. Leave it empty to clone upstream directly.

```
FORK_URL = https://github.com/marcandreuf/skills.git
```

Whether or not a fork is in play, `sync-upstream.sh` reads from whichever remote
actually points at `mattpocock/skills` rather than assuming `origin` does. In a
fork clone `origin` is the fork, and its `main` goes stale the moment upstream
pushes: reading it would report "up to date" while upstream had moved on.

The fork stays a **clean mirror**. Adapted skills live in `skills/` in this repo
and are never committed to it. That is what makes this fork safe while the one
ruled out above is not: the conflict problem only applies to a fork that holds
the adaptations.

There is no need to keep the fork's `main` in sync. Branch contributions off the
upstream remote's `main` directly, which is current by definition; GitHub accepts
the PR regardless of what the fork's own `main` is sitting at. `sync-upstream.sh`
prints the exact commands when `FORK_URL` is set.

**LAST_REVIEWED** is the upstream commit whose changes we have already looked
at. `sync-upstream.sh` diffs from here; `sync-upstream.sh --mark` moves it
forward once a review is done.

```
LAST_REVIEWED = 5b15a47f2d7150f545fbcacbfe381787fc0230dc
```

## Ported skills

Nothing ported yet. One row per skill once we start. "Changes" should normally
read "none": a straight copy is the default, and anything else needs a matching
entry in the Deviations section of [docs/sdlc.md](docs/sdlc.md).

| Skill | Upstream path | From commit | Changes |
| ----- | ------------- | ----------- | ------- |

## Survey, as of 5b15a47 (2026-08-21)

Upstream ships 25 promoted skills: 18 under `skills/engineering/`, 7 under
`skills/productivity/`, plus unpromoted `misc/` and `in-progress/` buckets.
Grouped by what it costs to take one:

### Standalone

No dependency on upstream's setup skill, its issue tracker, or its `CONTEXT.md`.

| Skill | Lines | Note |
| ----- | ----- | ---- |
| `grilling` | 56 | The interview primitive the rest of upstream builds on. `grill-me` is a 14-line user-invoked wrapper that just calls it. |
| `wizard` | 88 | Generates an interactive bash wizard for steps only a human can do: provisioning, credentials, third-party dashboards. Closest fit to what this repo already is. |
| `writing-for-agents` | 184 | How to write skills. Worth reading before adapting the others. |
| `resolving-merge-conflicts` | 28 | Self-contained. |
| `research` | 24 | Spawns a background research agent, writes findings to a cited Markdown file. |
| `prototype` | 231 | Throwaway prototype to answer one design question. |
| `handoff` | 32 | Overlaps `commands/wrap-up.md`. See below. |
| `to-questionnaire` | 108 | Turn a decision you cannot make alone into an async questionnaire. |
| `teach` | 424 | Multi-session teaching workspace. Large, and a different use case. |

### Standalone but assumes a `CONTEXT.md`

Upstream's shared-vocabulary doc. These work without one; porting means deciding
whether to keep those pointers or strip them.

`diagnosing-bugs` (276), `tdd` (212), `codebase-design` (309), `wait-what` (14).

`tdd` calls `codebase-design` for its module vocabulary: take both, or sever the
link when porting.

### Needs upstream's issue-tracker setup

`ask-matt`, `code-review`, `to-spec`, `to-tickets`, `triage` (536), `wayfinder`.
Each references `setup-matt-pocock-skills` and an issue tracker. Taking these
means adopting the spec/ticket/triage pipeline or rewriting them against
whatever we actually use.

Note `code-review` is only half-coupled: its **Standards** axis is free-standing,
its **Spec** axis reads the tracker.

### Not worth taking

- `setup-matt-pocock-skills` (419) configures a repo for the above pipeline.
- `implement` (30) orchestrates the pipeline.
- `improve-codebase-architecture` (265) depends on three other skills and emits an HTML report.
- `misc/migrate-to-shoehorn`, `misc/scaffold-exercises`, `in-progress/setup-ts-deep-modules`: TypeScript-specific, tied to upstream's own tooling.

### Worth a look, outside the promoted set

`misc/git-guardrails-claude-code` is a hook plus `scripts/block-dangerous-git.sh`
that blocks destructive git commands. A shell script and a hook, which is what
this repo mostly is.

## Overlap with what we already have

`handoff` and `commands/wrap-up.md` both compact a session, differently:

- `wrap-up` writes a dated journal to `.claude/journals/`, archives older ones,
  and is written for tomorrow-you starting cold. Pairs with `start-of-day`.
- `handoff` writes to the OS temp dir, is written for another agent picking up
  right now, and includes a "suggested skills" section.

Complementary. `handoff` is not an end-of-day command and does not replace
`wrap-up`.
