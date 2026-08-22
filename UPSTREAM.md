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

One row per ported skill. "Changes" should normally read "none": a straight copy
is the default, and anything else needs a matching entry in the Deviations
section of [docs/sdlc.md](docs/sdlc.md).

We port by **cluster**, not skill by skill, so that every skill a ported skill
calls is present. The set below is the per-repo precondition plus everything in
the main flow from idea up to (not including) `/implement`, with its feeders.

| Skill | Upstream path | From commit | Changes |
| ----- | ------------- | ------------ | ------- |
| `setup-matt-pocock-skills` | `skills/engineering/setup-matt-pocock-skills/` | `5b15a47` | none |
| `grilling` | `skills/productivity/grilling/` | `5b15a47` | none |
| `grill-me` | `skills/productivity/grill-me/` | `5b15a47` | none |
| `grill-with-docs` | `skills/engineering/grill-with-docs/` | `5b15a47` | none |
| `domain-modeling` | `skills/engineering/domain-modeling/` | `5b15a47` | none |
| `to-spec` | `skills/engineering/to-spec/` | `5b15a47` | none |
| `to-tickets` | `skills/engineering/to-tickets/` | `5b15a47` | none |
| `wayfinder` | `skills/engineering/wayfinder/` | `5b15a47` | none |
| `research` | `skills/engineering/research/` | `5b15a47` | none |
| `prototype` | `skills/engineering/prototype/` | `5b15a47` | none |
| `to-questionnaire` | `skills/productivity/to-questionnaire/` | `5b15a47` | none |
| `handoff` | `skills/productivity/handoff/` | `5b15a47` | none |

Every row omits upstream's `agents/openai.yaml`; that is repo-wide and recorded
once in Deviations rather than repeated per row.

Ported files are kept **byte-identical** to upstream, which is what makes
`diff -r` against the clone a reliable drift check. Nothing local goes inside a
ported skill, including provenance notes: this table is the record.

Every Skill-tool call made by a skill above resolves to another skill above.
Check that still holds before adding a row: a skill whose dependency is missing
fails at the step that calls it.

### Deliberately not ported yet

The build half of the flow, and the pieces off it:

| Skill | What it is | Why not yet |
| ----- | ---------- | ----------- |
| `implement`, `tdd`, `code-review` | The build half: spec or issues to committed code | The natural next cluster. `implement` drives the other two |
| `triage` | On-ramp for issues we did not create | Needs its triage-label vocabulary, and `setup-matt-pocock-skills` skips that section entirely while `triage` is absent. Porting it means re-running setup on any repo already configured |
| `diagnosing-bugs` | On-ramp for a hard bug | Standalone. Take it when there is a bug worth the discipline |
| `improve-codebase-architecture`, `codebase-design` | Codebase health, and the deep-module vocabulary | Health work, not definition or build |
| `ask-matt` | Router over every user-invoked skill | A router that names skills we do not have is a router that lies. Port it when the set stops moving |
| `resolving-merge-conflicts`, `wizard`, `teach`, `wait-what`, `writing-for-agents` | Standalone utilities | Take individually as the need shows up; nothing depends on them |

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
