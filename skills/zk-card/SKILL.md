---
name: zk-card
description: Create or revise a Zettelkasten card, then run a link review the user selects from. Use when writing a new zettel card, editing an existing one, or reviewing which cards one should link to.
---

# ZK Card

Write a card into a Zettelkasten repo and settle its links deliberately. The repo owns
the card format; this skill owns the procedure around it.

A Zettelkasten link is a claim about meaning, so the **annotation** beside the `[[ID]]`
is the content and the id is just the address. Links are therefore chosen, never
generated in bulk: a graph where everything touches everything says less than a sparse
one where each edge earns its sentence.

## 1. Read the repo's conventions

Before writing anything, read the repo's own card-format document (commonly
`ZK-FRONTMATTER-CONVENTIONS.md` at the root) and its `CLAUDE.md` if present. They are
the source of truth for frontmatter fields, the id scheme, the filename pattern, the
link syntax, and any lint rules the user's editor enforces. Follow them over any
assumption carried in here.

The usual layout: an **active** folder (`zettel/`) where new cards land, and an
**archive** folder (`zettelkasten/`) of older cards kept as a frozen record.

## 2. Take the id from the clock

```
date +%Y%m%d%H%M%S
```

Use that output verbatim. An id composed by hand looks valid, collides silently, and
nothing downstream catches it. Reuse the same timestamp for the `date:` field.

## 3. Draft the card

New card: write it to the active folder under the repo's filename pattern.
Existing card: read it in full first, and keep edits additive — amend and date rather
than rewriting, so the record of how the thinking moved survives.

Keep one idea per card. A draft growing several unrelated sections is two cards.

## 4. Review the links

This is the step the skill exists for. Both directions are in scope:

- **Outbound**: cards this card should point to.
- **Inbound**: cards that should gain a bullet pointing back here.

**Cast a wide net** first, to reach the corpus cheaply:

- shared `keywords:` entries in frontmatter, **weighted by rarity**
- two-hop neighbours: cards linked from the cards this one already links
- full-text matches on the card's distinctive terms

Rarity does the work that a stoplist would otherwise have to. A tag carried by a large
share of the corpus is close to noise; a tag shared by two or three cards is nearly an
identifier. Weighting by it drops format tags (`living-document`, `draft`, `wip`) on
their own, in any repo, with nothing to configure or keep current.

**Then judge by relation, not by similarity.** Lexical overlap finds cards on the same
subject, which is a weak proxy for a link worth writing: two cards can share every term
and stand in no relation, while the strongest edge in a Zettelkasten often crosses
subjects entirely.

Learn the vocabulary from the repo rather than importing one. Read a sample of the
existing `* [[ID]] Title (annotation)` bullets: the annotations record the relations
this author actually writes. Expect verbs over topics — _corrects_, _supersedes_,
_supplies evidence for_, _gates_, _resolves an open question in_, _is the case that_.

Now test each survivor by asking which named relation holds, and **drop the candidate
when none does**, however similar it looked. Two consequences worth expecting:

- Hub cards (dashboards, indexes, checklists) win every similarity contest because they
  touch everything, and carry the least meaning per edge. The relation test is what
  rejects them.
- A card that shares almost no vocabulary can be the strongest link on the list, when it
  corrects the method the new card rests on or resolves the question it opens.

**Then read the survivors in full.** A shortlist of eight cards you have actually opened
beats thirty you pattern-matched. Rank what remains; state how many candidates you
dropped so the user can ask for more.

**Propose, with the annotation drafted.** Name the relation and the sentence is most of
the way written. The user is approving sentences, not ids:

```
1.  ->  [[20240115093000]] Retry Budgets in Queue Consumers
        "the mechanism this card measures"

2.  <-  [[20231102141500]] Backpressure Notes
        would gain: "[[20240220100000]] Load Shedding Tradeoffs (the case this one deferred)"
```

Number every row, mark direction with `->` (outbound) and `<-` (inbound), and write
each inbound proposal from the *target* card's point of view. Then **wait**. Nothing
is written to any file until the user answers with the numbers they want, and "none"
is a complete answer.

**Guards:**

- Archive cards may be linked **to**; leave their files untouched. The archive is frozen.
- Propose additions. When an existing link looks stale, say so and leave it in place: removing one is a history edit and the user's call.
- An inbound link edits somebody else's card. That is why it is proposed rather than applied.

## 5. Apply and validate

Write only the selected links, then run the repo's validator (commonly
`./scripts/validate-zettel.sh`). It catches mistyped ids as broken wikilinks.

Done when every reported failure is either fixed or shown to predate this session:
re-run it against `git stash` or compare with the pre-edit state rather than assuming.
Report the card's path, the links applied in each direction, and the validator's result.
