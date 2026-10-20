---
description: Capture the session into .claude/journals/ as a next-day resumption journal
argument-hint: "[topic-slug, e.g. feature-x — optional]"
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git status:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git show:*), Bash(git worktree list:*), Bash(date:*), Bash(ls:*), Bash(test:*), Bash(mkdir:*), Bash(mv:*), Bash(pwd:*), Read, Write, Edit
---

## Configuration

**REPO_PATH** — the absolute path to the project repo this command operates on. The *repository*, which is not always the directory the session is running in: open a git worktree and the two diverge.

> Set this once per machine/account. If left as `auto`, the command will detect it at run time from the current working directory: the path on the first `worktree ` line of `git worktree list --porcelain`, which git always prints for the main working tree. In a plain checkout that is the checkout itself, so `auto` resolves exactly as it always has.

```
REPO_PATH = auto
```

**WORKTREE_PATH** — the working tree this session is actually editing, from `git rev-parse --show-toplevel`. In a plain checkout it equals `REPO_PATH` and nothing below changes. In a linked worktree it does not, and the split is the point: the journal is **written to the repository** and **describes the worktree**. Read git state from `REPO_PATH` in a worktree session and you report whatever branch and dirty files some *other* session has checked out over there.

**JOURNAL_DIR** is derived as `${REPO_PATH}/.claude/journals/` — one stream per repository, shared by every worktree of it. Not per working tree: a worktree is removable and a journal is backed up by nothing, so a stream kept inside one is deleted with it, silently, exactly when a handover was the thing you wanted. Journals are **not** committed — `.gitignore` keeps `.claude/journals/` out of git in every repo, because a credential written in prose escapes the scans that catch one in code. They are local working notes: local-only, disposable, and backed up by nothing. Never treat a journal as version-controlled or as an archive — promote anything worth keeping into a commit, a doc or an issue.

---

You are checkpointing the current session so the next day's session can resume cold — no memory of this conversation — and pick up exactly where we left off.

## Your task

Write (or update) a session journal at `${JOURNAL_DIR}/{YYYY-MM-DD}-{topic-slug}.md` summarizing this session's important context. The doc must be **self-contained**: assume the next reader has zero memory of this conversation.

This is an internal checkpoint that captures decisions, file states, open threads, and the concrete next step.

## Argument

`$ARGUMENTS` is an optional topic slug for the filename (kebab-case, e.g., `feature-x`). If empty:
1. Infer the dominant topic from this session (the feature, area, or task most discussed).
2. Use a short kebab-case slug. Default to `session` only if no topic is identifiable.

When `WORKTREE_PATH` differs from `REPO_PATH`, other sessions may be writing into the same stream, and two that pick the same slug on the same date will append into one file (step 5). Slug after this worktree's topic or branch, and do not fall back to `session`.

## Steps

1. **Resolve paths.**
   - If `REPO_PATH = auto`: run `git worktree list --porcelain` from the current directory and take the path on the first `worktree ` line. If that fails (not in a git repo), tell the user to set `REPO_PATH` explicitly in this file and stop.
   - Set `WORKTREE_PATH` from `git rev-parse --show-toplevel`.
   - Set `JOURNAL_DIR = ${REPO_PATH}/.claude/journals`.
   - Ensure `${JOURNAL_DIR}` exists (`mkdir -p`).
   - If `WORKTREE_PATH` differs from `REPO_PATH`, this session is in a linked worktree: fill the **Worktree** line in the template, and name the journal path in the closing message so the user can see it landed in the repository rather than in the worktree.

2. **Compute date and filename.**
   - Date: today in `YYYY-MM-DD` format (use system date, do not invent).
   - Filename: `${JOURNAL_DIR}/{date}-{slug}.md`

3. **Gather git state** from `WORKTREE_PATH`, never from `REPO_PATH` — the journal describes the tree this session edited (parallel where independent):
   - `git -C ${WORKTREE_PATH} rev-parse --abbrev-ref HEAD` — current branch
   - `git -C ${WORKTREE_PATH} log --since="1 day ago" --oneline --no-merges` — today's commits
   - `git -C ${WORKTREE_PATH} status --short` — uncommitted state
   - `git -C ${WORKTREE_PATH} log -1 --format="%h %s"` — last commit on current branch

4. **Mine the session** for:
   - What got accomplished (concrete deliverables: files created, commands built, docs drafted, decisions made).
   - Decisions made and **why** (the reasoning, not just the outcome — future-you needs to judge edge cases).
   - Files touched/created in the repo. List paths.
   - Open threads — unfinished items, blocked questions, work parked mid-task.
   - The single most concrete next step.

5. **Check if the target file already exists.**
   - If new: write the file with the template below.
   - If exists: read it, then append a new `## Update at HH:MM` section at the end (today's local time) capturing only the deltas since the previous entry. Do not rewrite earlier sections.

6. **Write/update the file.** Use the template below exactly.

7. **Archive older session journals.** After writing today's file:
   - Ensure `${JOURNAL_DIR}/archived/` exists (`mkdir -p`).
   - Move every file in `${JOURNAL_DIR}/` matching `YYYY-MM-DD-*.md` whose date prefix is **strictly older than today** into `${JOURNAL_DIR}/archived/`.
   - **Do not touch:**
     - Today's journal(s) — any file whose date prefix equals today's date.
     - Non-dated files in the journal dir — these are reference material, not session journals.
     - Anything already inside `${JOURNAL_DIR}/archived/`.
   - **Directory name is `archived/` (past tense), not `archive/`** — be consistent across runs; do not create a parallel directory.
   - If a destination file already exists in `archived/`, skip that move and note it in the closing message — don't overwrite.
   - If there are zero files to archive, no-op silently.

8. **Output to the user:** one short paragraph naming the file path written and listing the key takeaways (3-bullet max). If any files were archived in step 7, append a short trailing line: `Archived N older journals to ${JOURNAL_DIR}/archived/.` Do not paste the full file content back.

## Template (for new files)

```markdown
# {topic-title-cased} — session {YYYY-MM-DD}

Self-contained checkpoint for resuming this work the next day. Assume the next session has no memory of this conversation.

## Where we left off

- **Branch:** {current branch}
- **Worktree:** {WORKTREE_PATH — include this line only when it differs from the repo path, and say which repo it is a worktree of; omit it entirely in a plain checkout}
- **Last commit:** {short hash + subject, or "no commits in this session"}
- **Uncommitted state:** {summary of git status, or "clean working tree"}

## What this session accomplished

- {high-signal bullet — what shipped, what got built, what got decided}
- {...}

## Decisions made

- **{decision}** — {why: the reasoning the user gave or the constraint that drove it}
- {...}

## Files created or changed

- `{path}` — {one-line role}
- {...}

## Open threads

- {unfinished item or blocked question}
- {...}

## Next session: start here

{ONE concrete sentence describing the exact first action when resuming. Be specific — name the file, command, or decision. Example: "Edit `src/auth/session.py:refresh_token()` to add a 30-second leeway on expiry checks, then update the unit test in `tests/auth/test_session.py`."}

## References

- {file path or external link the next session will need}
- {...}
```

## Template (for appending — existing file)

```markdown

## Update at {HH:MM}

**Deltas since previous entry:**

- {what changed since the last wrap-up today}
- {...}

**Updated next-session-start:** {revised concrete next step, if changed}
```

## Rules

- **Self-contained.** Do not write "as discussed earlier" or "continuing from above" — the next reader has no context. Spell things out.
- **Capture WHY, not just WHAT.** Decisions without reasoning rot fast.
- **Be specific in "Next session: start here".** A vague next step ("continue feature work") is useless; a specific one ("edit `src/auth/session.py` line ~45 to add leeway in `refresh_token()`") is gold.
- **Do not paste large code blocks** — reference paths and line ranges instead. The next session can read the files.
- **Scrub secrets before writing.** Journals are prose, so a credential in one reads as "password `hunter2`", not `KEY=value`, and a keyword grep will miss it. Never write a token, password, or key literal into a journal: name where the value lives instead.
- **Leave other sessions' journals alone.** One repository's stream can hold several files dated today, written by sessions in other worktrees of it. Step 7 only archives strictly older dates, so they are already safe from the sweep — do not rename, merge or archive them either, and never append your deltas to a file another session wrote. Append only to a file whose slug is this session's own.
- **Do not commit the journal.** `.claude/journals/` is gitignored in every repo by policy. Leave the file untracked; do not offer to add it, and do not suggest un-ignoring the directory.
- **Do not run `git push`, `gh`, or any send/post command.**
- One short closing paragraph to the user after writing — not the full doc.

Now run the steps and write the wrap-up.
