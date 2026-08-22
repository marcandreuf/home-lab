# The development flow

The SDLC we work to, taken from [mattpocock/skills](https://github.com/mattpocock/skills).
We follow it as written rather than inventing our own variant, so the skills
compose the way they were designed to. Deviations get recorded here with a
reason; see [Deviations](#deviations).

Summarised from upstream at `5b15a47` (2026-08-21). The sources, if you need
more depth than this page:

| Upstream file | What it holds |
| ------------- | ------------- |
| `skills/engineering/ask-matt/SKILL.md` | The flow itself. The fullest statement of the methodology anywhere in that repo |
| `skills/engineering/ask-matt/PHASE-BOUNDARIES.md` | The ordered decision tree for context boundaries |
| `CONTEXT.md` | The glossary the skills speak in |
| `skills/engineering/setup-matt-pocock-skills/` | Per-repo config: issue tracker, triage labels, domain doc layout |
| `docs/engineering/`, `docs/productivity/` | One human-facing page per skill |

Read them in `~/projects/skills`, our fork of that repo (see
[../UPSTREAM.md](../UPSTREAM.md)).

## What we actually have

All 25 of upstream's promoted skills, so every command named on this page is
installed. `/ask-matt` is the router over them: ask it when you cannot remember
which skill fits, and it will place your situation on the flow below.

We took the promoted set whole rather than cherry-picking, because these skills
call each other and `/ask-matt` routes over all of them: a partial port gives
you skills that fail at a step and a router that points at things that are not
there. [../UPSTREAM.md](../UPSTREAM.md) has the full list and the two checks
that keep it honest.

Having a skill installed is not a commitment to use it. Most work only touches
the main flow.

## The main flow: idea to ship

The route most work travels.

```
  /research ──┐                  ┌── /to-questionnaire
  (facts)     │                  │   (someone else's head)
              ▼                  ▼
   ┌─────────────────────────────────────────┐
   │ 1. /grill-with-docs   in a repo         │  ← writes CONTEXT.md + ADRs
   │    /grill-me          no repo, stateless│
   └────────────────────┬────────────────────┘
                        │
       2. needs a runnable answer?
              yes ──→  /handoff → /prototype → /handoff back ──┐
              no  ─────────────────────────────────────────────┤
                        │                                      │
       3. multi-session build?                                 │
              yes ──→  /to-spec → /to-tickets ──┐              │
                                                │              │
              no  ────────────────────────────┐ │              │
                                              ▼ ▼ ◄────────────┘
                                         /implement     (per issue,
                                              │          /clear between)
                                    drives /tdd internally
                                              ▼
                                        /code-review
                                              ▼
                                           commit
```

**1. Sharpen the idea.** `/grill-with-docs` when there is a working directory:
it runs the same interview as `/grill-me` but is stateful, leaving a paper trail
in `CONTEXT.md` and ADRs. `/grill-me` is the stateless one, for when there is no
repo underneath (a plan, a design, a piece of writing).

**2. Can every question be settled in conversation?** If one needs a runnable
answer (a state model, business logic, a UI you have to see), detour through
`/prototype`. A prototype lives in its own directory, so `/handoff` bridges both
directions: out to a fresh session, then back with what was learned.

**3. Is this a multi-session build?**

- **Yes**: `/to-spec` turns the thread into a spec, `/to-tickets` splits it into
  tracer-bullet issues, each declaring its blocking edges. Then `/implement` per
  issue, clearing context between each.
- **No**: `/implement` right there in the same window.

Either way `/implement` drives `/tdd` internally, one red-green slice at a time,
and closes by running `/code-review` over the diff before committing. Both are
reachable on their own: `/tdd` when you want to build a behaviour test-first
without a spec, `/code-review` to review a branch or PR against a fixed point.

## On-ramps

Situations that generate work, then merge onto the main flow.

**Bugs and requests piling up** → `/triage`. Moves issues through the triage
roles and produces agent-ready issues that `/implement` picks up later.

> Triage is only for issues **you did not create**: bug reports, incoming
> feature requests, anything that arrives raw. Issues from `/to-tickets` are
> already agent-ready. Do not triage them.

**Something is broken** → `/diagnosing-bugs`. For the hard ones: the bug that
resists a first glance, the intermittent flake, the regression between two
known-good states. It refuses to theorise until it has a tight feedback loop
(one command that already goes red on *this* bug), then fixes with a regression
test. Its post-mortem hands off to `/improve-codebase-architecture` when the real
finding is that there is no good seam to lock the bug down.

**A huge, foggy effort**, greenfield or a feature too big for one session →
`/wayfinder`. It charts a shared map of **decision tickets** and resolves them
one at a time, producing **decisions, not deliverables**, until the way is clear.
Then it hands off: merge onto the main flow at `/to-spec`, which collapses the
map's linked decisions into something buildable.

> `/wayfinder` never builds, and going straight from a map to `/implement`
> throws the linked detail away. Save it for the effort you genuinely cannot
> hold in one session; it is slower and denser than `/grill-with-docs`.

## Codebase health

`/improve-codebase-architecture` is upkeep rather than feature work: run it in a
spare moment and it surveys for **deepening opportunities**. Picking one
*generates an idea*, which re-enters the main flow at `/grill-with-docs`. It is
the survey that finds candidates; `/codebase-design` is the bench you design the
chosen one on.

## Vocabulary underneath

Two model-invoked references that run beneath the other skills, each the single
source of truth for its vocabulary. Reach for them when the **words**, not the
process, are the problem.

- **`/domain-modeling`**: the project's *domain* language. Challenge a fuzzy
  term, resolve an overloaded word, record a hard-to-reverse decision as an ADR.
  The active discipline `/grill-with-docs` drives to keep `CONTEXT.md` clean.
- **`/codebase-design`**: the deep-module vocabulary (module, interface, depth,
  seam, adapter, leverage, locality) for a module's *shape*. `/tdd` and
  `/improve-codebase-architecture` both speak it.

## Context hygiene

The rule that is easiest to break by accident:

> Keep steps 1 to 3 in **one unbroken context window**. Do not compact or clear
> until after `/to-tickets`, so the grilling, the spec and the issues all build
> on the same thinking.

Each `/implement` then starts fresh from its issue. Every issue is
self-contained, which is what makes the previous one's context disposable.

The bound on this is the **smart zone**, roughly 150k tokens on current models,
within which the model still reasons sharply. If a session approaches it before
`/to-tickets`, do not push on degraded: `/compact` at the nearest phase boundary.

### Phase boundaries

A **phase** is a chunk of work inside a session (the grilling, the
implementation, the QA). At a boundary there are five options, and upstream is
clear that choosing between them is the fuzziest decision in the whole method:

| Option | When |
| ------ | ---- |
| **Continue** | Stay put. Costs nothing, loses nothing. Rule it out first |
| **`/clear`** | Nothing here matters to what is next |
| **`/handoff`** | Narrow: a new harness, a new directory, a colleague, or forking a side task mid-phase. What it buys is portability |
| **Subagent** | A tightly-scoped task in its own window, reporting back |
| **`/compact`** | The default, but at the bottom of the tree rather than the first reach |

Make the call **at** a boundary. Mid-phase, continue or split the rest into
subagents. The ordered tree and the reasoning live in upstream's
`ask-matt/PHASE-BOUNDARIES.md`.

## Vocabulary

Upstream's `CONTEXT.md` defines these, and the skills use them precisely. The
issue/ticket distinction in particular is load-bearing.

**Issue tracker** — the tool hosting a repo's issues: GitHub Issues, Linear, or
a local `.scratch/` markdown convention. `/to-tickets`, `/to-spec` and `/triage`
all read and write through it.
*Avoid*: backlog, backlog manager, issue host.

**Issue** — a single tracked unit of work inside an issue tracker: a bug, task,
spec, or slice produced by `/to-tickets`.
*Avoid*: "ticket", except in the two cases below.

**Decision ticket** — a `/wayfinder` unit: a child issue of a `wayfinder:map`
holding a **question** whose resolution is a decision, not a slice of a build to
execute. The "decision" qualifier is what keeps it distinct from an
implementation issue.

**Triage role** — a canonical state-machine label carried by an issue during
triage. One at a time. The five roles:

| Role | Meaning |
| ---- | ------- |
| `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | Fully specified, ready for an AFK agent |
| `ready-for-human` | Requires human implementation |
| `wontfix` | Will not be actioned |

> The skill named `to-tickets` is inconsistent with this glossary, which says to
> avoid "ticket" for a unit of work. It produces **issues**. Read the skill name
> as a legacy label, not as a second concept.

## Our issue tracker

**GitHub Issues, using the `gh` CLI.** Units of work in a repo are GitHub issues.

The alternative upstream ships is a local markdown convention under `.scratch/`
(one directory per feature, one file per issue, a `Status:` line for triage
state, a `Blocked by: NN, NN` line for edges). It needs no GitHub at all, and is
worth reaching for in a repo that has no remote. The choice is per repo, made by
`/setup-matt-pocock-skills`, not a global setting.

What GitHub gives that the local convention does not is **native issue
dependencies**: `/to-tickets` writes blocking edges as real links, so any issue
whose blockers are closed can be picked up. `/wayfinder` uses the same mechanism
for its map, with the map as a parent issue and decision tickets as sub-issues.

## Domain docs

Before exploring a codebase, the engineering skills read:

- `CONTEXT.md` at the repo root, or `CONTEXT-MAP.md` if the repo has several
  contexts, which points at one `CONTEXT.md` per context
- `docs/adr/` for decisions touching the area being worked in

If these do not exist, the skills **proceed silently**. They are not scaffolded
upfront: `/domain-modeling` creates them lazily, when a term or a decision
actually gets resolved. Do not pre-create them.

Output that names a domain concept uses the glossary's term, not a synonym the
glossary says to avoid. Output that contradicts an ADR says so explicitly rather
than silently overriding it.

## Per-repo setup

`/setup-matt-pocock-skills` runs **once per repo**, before the first engineering
flow. It configures the issue tracker, the triage label vocabulary, and the
domain doc layout that the other skills assume.

This is a precondition, not a step in the flow. A repo that has not had it run
will have the engineering skills guessing at things they should have been told.

## Deviations

Anything we change from upstream goes here with the reason, so a later
`sync-upstream.sh` diff can tell a deliberate divergence from a change we simply
have not taken yet.

**`agents/openai.yaml` is not ported.** Repo-wide, every skill. Upstream ships
one per skill holding Codex picker metadata (`interface.display_name`,
`interface.short_description`) and, for user-invoked skills, the
`policy.allow_implicit_invocation: false` that pairs with
`disable-model-invocation` in the frontmatter. We run Claude Code, which reads
the frontmatter and ignores that file. Porting it would carry a second copy of
the invocation setting that nothing here enforces, so the two could silently
drift apart.

Revisit if we ever run Codex: the file is required there, and upstream's rule is
that a skill is user-invoked in both harnesses or neither.
