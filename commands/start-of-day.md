---
description: Resume work from the last session by reading the latest journal in .claude/journals/ and verifying current state
argument-hint: "[date or slug, e.g. 2026-05-13 or feature-x — optional, defaults to most recent]"
allowed-tools: Bash(ls:*), Bash(git log:*), Bash(git status:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git diff:*), Bash(date:*), Bash(test:*), Bash(find:*), Bash(stat:*), Bash(pwd:*), Read, AskUserQuestion
---

## Configuration

**REPO_PATH** — the absolute path to the project repo this command operates on.

> Set this once per machine/account. If left as `auto`, the command will detect it at run time via `git rev-parse --show-toplevel` from the current working directory.

```
REPO_PATH = auto
```

**JOURNAL_DIR** is derived as `${REPO_PATH}/.claude/journals/`. Journals are checked into `.claude/journals/` so they travel with the repo — add the dir to `.gitignore` if you don't want them committed.

---

You are briefing the user at the start of a new working day. The goal is to make resumption frictionless: read the most recent session journal in `${JOURNAL_DIR}`, verify the repo is still in the state that journal described, surface the concrete next step, and let the user choose how to begin.

## Your task

1. Resolve `${REPO_PATH}` and `${JOURNAL_DIR}` per the Configuration block above.
2. Find and read the latest session journal in `${JOURNAL_DIR}`.
3. Verify the current state of the repo at `${REPO_PATH}` matches what the journal said (flag any drift).
4. If the journal's "Next session: start here" references specific files in the repo, read just enough of those files to have context ready.
5. Produce a short, structured resumption briefing.
6. Ask the user how they want to start.

Do **not** take any action beyond reading and briefing — no commits, no branch switches, no edits.

## Argument

`$ARGUMENTS` optionally narrows which journal to load:
- A date prefix like `2026-05-13` → load the most recent journal from that date.
- A topic slug like `feature-x` → load the most recent journal matching that slug.
- Empty → load the most recently modified `YYYY-MM-DD-*.md` in `${JOURNAL_DIR}`.

If multiple journals share the same most-recent date (e.g., morning + evening), read both in chronological order — the latest supersedes earlier ones, but earlier may contain referenced context.

## Steps

1. **Resolve paths.**
   - If `REPO_PATH = auto`: run `git rev-parse --show-toplevel` from the current directory. If that fails (not in a git repo), tell the user to set `REPO_PATH` explicitly in this file and stop.
   - Set `JOURNAL_DIR = ${REPO_PATH}/.claude/journals`.
   - If `${JOURNAL_DIR}` does not exist, tell the user there are no journals yet and stop. Suggest running `/wrap-up` at the end of today's session.

2. **Locate the journal(s)** in `${JOURNAL_DIR}`:
   - `ls -lat ${JOURNAL_DIR}/*.md` to inspect by mtime.
   - Filter to files matching `YYYY-MM-DD-*.md`. If `$ARGUMENTS` is set, filter further by date or slug substring.
   - If no journal is found, tell the user and stop — there's nothing to resume from.

3. **Read the journal fully.** Extract:
   - **Where we left off:** branch, last commit, uncommitted state.
   - **Next session: start here:** the single concrete next action — THE critical field.
   - **Open threads:** unfinished items, parked decisions.
   - **References:** paths to other docs or code files the next step depends on.

4. **Verify current git state** in `${REPO_PATH}` (parallel where independent):
   - `git -C ${REPO_PATH} rev-parse --abbrev-ref HEAD` — current branch
   - `git -C ${REPO_PATH} log -1 --format="%h %s"` — last commit on branch
   - `git -C ${REPO_PATH} status --short` — uncommitted changes
   - `git -C ${REPO_PATH} log --since="<journal-date>" --oneline --no-merges` — any commits since the journal was written

5. **Detect drift** between journal and current state. Examples to flag:
   - Branch changed since the journal.
   - New commits landed on the branch (someone else merged work, or you committed after writing the journal).
   - Working tree now dirty when journal said clean (or vice versa).
   - Files named in "Next session: start here" no longer exist at the expected path.

6. **Read load-bearing references.** If "Next session: start here" names a specific file in the repo (e.g., `src/foo/bar.py:some_function()`):
   - Confirm the file exists.
   - Read the relevant section (the named function, or the first 80 lines if no line/function anchor) so you can answer follow-up questions immediately.
   - Do **not** dump the file content to the user — just hold it in context.
   - Skip other references unless they're directly load-bearing. Don't preload every linked doc.

7. **Produce the briefing** (template below). Keep it tight — the user will read it and decide. Don't paste the journal back; summarize.

8. **Ask the user how to start** via `AskUserQuestion`:
   - Question: `"How do you want to start the day?"`
   - Header: `"Start"`
   - Options (multiSelect: false):
     1. `"Proceed with the next step"` (Recommended) — description: `"Begin the concrete next action from the journal."`
     2. `"Pick from open threads"` — description: `"Show the open threads and let me choose which to tackle first."`
     3. `"Just brief me — I'll decide"` — description: `"Stop after the briefing; I'll direct the next move."`
   - The auto-provided "Other" lets the user redirect freely.

9. **Handle the answer:**
   - `"Proceed with the next step"` → State the first concrete action you'll take and **wait for the user's go-ahead** before editing files or running non-read commands. (Even with a clear next step, confirm before acting.)
   - `"Pick from open threads"` → List the open threads as numbered options; wait for the user to choose.
   - `"Just brief me — I'll decide"` → Stop. End with a one-line "Ready when you are."
   - "Other" with custom text → Follow the user's redirection.

## Briefing template (use this shape)

```
Resuming from: {journal-filename} ({journal-date})

Branch: {current branch} {⚠ flag if changed from journal}
Last commit: {short hash + subject}
Working tree: {clean | N files modified}
{Drift note, only if any: e.g., "⚠ N new commits on branch since journal was written" or "⚠ journal said clean, working tree is now dirty"}

Where we left off:
{1–2 sentences summarizing the journal's "Where we left off" + "What this session accomplished" — just enough to orient}

Next step (from journal):
{The "Next session: start here" content, verbatim or lightly trimmed. Be specific — keep file paths and function names.}

Open threads ({N}):
- {thread 1}
- {thread 2}
- {...}

(Omit "Open threads" if none.)
```

## Rules

- **Read-only briefing.** Do not edit, commit, switch branches, or run any send/post command during this step.
- **Don't paste the journal back.** Summarize. The user can re-read the file if they want.
- **Flag drift honestly.** If the repo state diverges from the journal, surface it — don't paper over it.
- **Don't invent context.** If the journal is thin on a section, say so rather than filling gaps from assumptions.
- **Don't preload every reference.** Only read files directly named in "Next session: start here." Skim the rest by path only.
- **If no journal exists**, tell the user plainly and stop. Suggest running `/wrap-up` at the end of today's session so tomorrow's start works.
- **Never run `git push`, `gh`, or any send/post command.**
- After the `AskUserQuestion`, even on "Proceed," confirm the first concrete action before editing files — match the scope of actions to what the user explicitly approves.

Now run the steps and produce the briefing.
