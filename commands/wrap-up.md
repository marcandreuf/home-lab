---
description: Capture the session into .claude/journals/ as a next-day resumption journal
argument-hint: "[topic-slug, e.g. feature-x — optional]"
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git status:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git show:*), Bash(date:*), Bash(ls:*), Bash(test:*), Bash(mkdir:*), Bash(mv:*), Bash(pwd:*), Read, Write, Edit
---

## Configuration

**REPO_PATH** — the absolute path to the project repo this command operates on.

> Set this once per machine/account. If left as `auto`, the command will detect it at run time via `git rev-parse --show-toplevel` from the current working directory.

```
REPO_PATH = auto
```

**JOURNAL_DIR** is derived as `${REPO_PATH}/.claude/journals/`. Journals are checked into `.claude/journals/` so they travel with the repo — add the dir to `.gitignore` if you don't want them committed.

---

You are checkpointing the current session so the next day's session can resume cold — no memory of this conversation — and pick up exactly where we left off.

## Your task

Write (or update) a session journal at `${JOURNAL_DIR}/{YYYY-MM-DD}-{topic-slug}.md` summarizing this session's important context. The doc must be **self-contained**: assume the next reader has zero memory of this conversation.

This is an internal checkpoint that captures decisions, file states, open threads, and the concrete next step.

## Argument

`$ARGUMENTS` is an optional topic slug for the filename (kebab-case, e.g., `feature-x`). If empty:
1. Infer the dominant topic from this session (the feature, area, or task most discussed).
2. Use a short kebab-case slug. Default to `session` only if no topic is identifiable.

## Steps

1. **Resolve paths.**
   - If `REPO_PATH = auto`: run `git rev-parse --show-toplevel` from the current directory. If that fails (not in a git repo), tell the user to set `REPO_PATH` explicitly in this file and stop.
   - Set `JOURNAL_DIR = ${REPO_PATH}/.claude/journals`.
   - Ensure `${JOURNAL_DIR}` exists (`mkdir -p`).

2. **Compute date and filename.**
   - Date: today in `YYYY-MM-DD` format (use system date, do not invent).
   - Filename: `${JOURNAL_DIR}/{date}-{slug}.md`

3. **Gather git state** (parallel where independent):
   - `git -C ${REPO_PATH} rev-parse --abbrev-ref HEAD` — current branch
   - `git -C ${REPO_PATH} log --since="1 day ago" --oneline --no-merges` — today's commits
   - `git -C ${REPO_PATH} status --short` — uncommitted state
   - `git -C ${REPO_PATH} log -1 --format="%h %s"` — last commit on current branch

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
- **Do not commit** the wrap-up file unless the user explicitly asks — leave it as an untracked file (or gitignored) by default.
- **Do not run `git push`, `gh`, or any send/post command.**
- One short closing paragraph to the user after writing — not the full doc.

Now run the steps and write the wrap-up.
