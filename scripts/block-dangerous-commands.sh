#!/usr/bin/env bash

# block-dangerous-commands.sh - PreToolUse hook: refuse destructive commands
#
# Reads a Claude Code PreToolUse payload on stdin, pulls out the Bash command,
# and exits 2 if it matches a destructive pattern. Exit 2 is what tells Claude
# Code to block the call; the reason goes to stderr and the model reads it.
#
# Wire it up with `scripts/install-claude.sh`, which offers to add it to
# ~/.claude/settings.json as a machine-wide PreToolUse hook on Bash. The path
# written there points into this repo, so `git pull` updates the rules on that
# VM with nothing to re-install.
#
# Ported from mattpocock/skills misc/git-guardrails-claude-code and widened --
# upstream covers git only, which leaves out the case that prompted this
# (deleting a repo through `gh`). See docs/sdlc.md "Deviations".
#
# WHY A HOOK RATHER THAN A DENY RULE
#
# Claude Code permission rules match on a command PREFIX, so `Bash(gh api -X:*)`
# in a deny list catches `gh api -X DELETE ...` and misses
# `gh api repos/x -X DELETE`, `gh api -XDELETE ...`, and anything wrapped in
# `bash -c`. A hook receives the whole command string and can match anywhere in
# it. Deny rules stay as a second layer; this is the one that holds.
#
# WHAT THIS IS NOT
#
# Pattern matching over text, so it stops a careless command, not a determined
# one: base64, variable indirection, and anything that assembles a command at run
# time all go around it. Treat it as a guardrail, not a sandbox.
#
# Matching only at a command position (see CMD_POS below) is what keeps writing
# about these commands legal:
#
#   echo 'git push --force is what I would do'   <- allowed, it is an argument
#   cd /tmp && git push --force                  <- blocked, it is a command
#   bash -c 'gh api -X DELETE repos/x'           <- blocked, -c takes a command
#
# The residual gap is a wrapper this does not know about: a command reached
# through something other than `;` `&` `|` `(` `{` backtick `$(` `-c` `eval`
# `sudo` `nohup` `time` `xargs` is not seen as a command. Add to CMD_POS when one
# shows up.
#
# PLAIN `git push` IS NOT BLOCKED. It is ordinary work, and Claude Code already
# asks before running anything that is not on an allow list -- a prompt you can
# answer is better than a wall you have to edit a file to get past. Only the
# force variants are refused outright, because they rewrite remote history.
#
# THERE ARE TWO ANSWERS, NOT ONE. PATTERNS refuses (exit 2, no prompt offered).
# ASK_PATTERNS returns a "ask" permission decision, which routes the call to the
# normal approval prompt. The second tier is for commands that are destructive
# but sometimes correct, where refusing outright leaves no way through except
# editing this file. Refusals are checked first, so a command tripping both gets
# the stricter answer. Put a rule in ASK_PATTERNS only when a human looking at
# the command could reasonably say yes; everything else belongs in PATTERNS.
#
# ON FAILURE IT BLOCKS. If it cannot parse the payload it exits 2 rather than
# waving the command through -- a guardrail that fails open is not one.

set -uo pipefail

INPUT="$(cat)"

# jq is the normal path; python3 covers a VM that has not installed it. Both
# missing means we cannot read the command, so we refuse rather than guess.
if command -v jq >/dev/null 2>&1; then
  COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  COMMAND="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: pass' 2>/dev/null)"
else
  echo "BLOCKED: block-dangerous-commands.sh needs jq or python3 to read the command." >&2
  exit 2
fi

# An empty command is not a Bash call this hook has anything to say about.
[[ -z "$COMMAND" ]] && exit 0

# Every pattern below is anchored to a COMMAND POSITION: the start of a line, or
# just after something that begins a new command. Without this the hook matches a
# dangerous phrase anywhere in the line, so writing ABOUT one of these commands --
# quoting it in an echo, or in a heredoc that documents this very file -- gets
# refused. That happened on day one.
#
# The set below is what actually introduces a command:
#
#   ^          start of a line (a multi-line command gives one per line)
#   ; & |      separators, which covers && and || as single characters
#   ( { `      subshells, groups, and old-style substitution
#   $(         command substitution
#   -c         `bash -c`, `sh -c` -- the flag whose argument IS a command
#   eval       ditto, and the classic way round a text matcher
#   sudo nohup time xargs   wrappers that run the rest as a command
#
# A quote may follow any of those (`bash -c 'rm ...'`), so one optional quote is
# allowed before the pattern. A quote alone is NOT a command position, which is
# exactly what keeps `echo 'git push ...'` legal.
CMD_POS='(^|[;&|`({]|\$\(|\b(eval|sudo|nohup|time|xargs)[[:space:]]|-c[[:space:]])[[:space:]]*['"'"'"]?[[:space:]]*'

# Each entry is "regex@@explanation" -- @@ rather than | because the regexes use
# | for alternation. Every regex must start with the command name, since CMD_POS
# is prepended to it. Keep the explanation specific: the model reads it and
# should be able to tell what to do instead.
PATTERNS=(
  # -- git, from upstream -------------------------------------------------
  'git[[:space:]]+push[[:space:]].*(--force|-f([[:space:]]|$))@@Force-pushing overwrites remote history and can destroy a teammate'"'"'s commits. A plain `git push` is fine and will ask the user first.'
  'git[[:space:]]+reset[[:space:]]+--hard@@Discards uncommitted work with no recovery. Use `git stash` or commit first.'
  'git[[:space:]]+clean[[:space:]]+-[a-z]*f@@Deletes untracked files permanently. Ask the user, or list them with `git clean -n` first.'
  # `git branch -D` moved to ASK_PATTERNS -- see the note there.
  'git[[:space:]]+(checkout|restore)[[:space:]]+\.@@Throws away every uncommitted change in the tree.'

  # -- git history rewrites -----------------------------------------------
  'git[[:space:]]+filter-branch@@Rewrites history across the whole repo.'
  'git[[:space:]]+reflog[[:space:]]+expire@@The reflog is the last way back from a bad reset. Do not expire it.'
  'git[[:space:]]+gc[[:space:]]+.*--prune@@Prunes unreachable objects, which is what recovery depends on.'
  'git[[:space:]]+update-ref[[:space:]]+-d@@Deletes a ref directly, bypassing every safety check git has.'

  # -- gh: the case that prompted widening upstream's list ----------------
  'gh[[:space:]]+repo[[:space:]]+(delete|archive|rename)@@Deletes, archives or renames a GitHub repo. The user does this themselves.'
  'gh[[:space:]]+(secret|release|run)[[:space:]]+delete@@Deletes a GitHub secret, release or run.'
  'gh[[:space:]]+api.*(-X|--method|--input|(^|[[:space:]])(-f|-F)[[:space:]]|--field|--raw-field)@@`gh api` with a write flag can delete a repo. Read-only `gh api` is fine.'

  # -- filesystem: absolute paths and $HOME only, so repo-local cleanup works
  'rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR])[a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME)@@Recursive force-delete of an absolute path. Relative paths inside the repo are fine.'

  # -- docker: volumes are where the databases live ------------------------
  'docker[[:space:]]+(system[[:space:]]+)?prune@@Prunes images, containers and networks across every project on this VM.'
  'docker[[:space:]]+volume[[:space:]]+rm@@Deletes a docker volume, which is where database data lives.'
  'docker[[:space:]]+compose[[:space:]]+down[[:space:]]+.*(-v|--volumes)@@`down -v` drops the volumes, taking the database with them.'
)

# ASK, not refuse. Same format as PATTERNS, different answer: instead of exiting
# 2 the hook returns a permission decision of "ask", which routes the call to
# Claude Code's ordinary approval prompt. The user sees the command and the
# reason and decides.
#
# This tier exists for commands that are destructive but sometimes correct, and
# where the safe alternative can refuse for reasons that are not about safety.
# `git branch -D` is the case that prompted it: `-d` rejects a branch whose
# commits are unreachable from HEAD, which includes every branch whose work
# landed by squash merge or rebase. The content shipped, the SHAs did not, and
# `-d` cannot tell that apart from genuinely unreviewed work. Refusing outright
# left no way through except editing this file -- the wall the header argues
# against. A prompt puts the judgement where it belongs, and keeps the case this
# is really guarding against (a branch whose work exists nowhere else) in front
# of a human rather than silently allowed.
ASK_PATTERNS=(
  'git[[:space:]]+branch[[:space:]]+-D@@Force-deletes a branch and any unmerged commits on it. `-d` is the safe form, but it also refuses branches whose work landed by squash merge or rebase, so `-D` is sometimes the only way through. Check that the work exists somewhere else first.'
)

# Claude Code reads a PreToolUse permission decision as JSON on stdout. Exit 2
# (the refusal path below) is the harder answer: no prompt is offered at all.
emit_ask() {
  local reason="$1" escaped
  if command -v jq >/dev/null 2>&1; then
    escaped="$(printf '%s' "$reason" | jq -Rs .)"
  else
    escaped="$(REASON="$reason" python3 -c 'import json,os;print(json.dumps(os.environ["REASON"]))')"
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$escaped"
  exit 0
}

# Refusals are checked first, so a command that trips both answers to the
# stricter one: `git branch -D x && rm -rf /` is refused, not merely asked.
for entry in "${PATTERNS[@]}"; do
  regex="${entry%%@@*}"
  reason="${entry#*@@}"
  if printf '%s' "$COMMAND" | grep -qE -- "$CMD_POS$regex"; then
    echo "BLOCKED by home-lab guardrails: $reason" >&2
    echo "Command: $COMMAND" >&2
    echo "The user has withheld this command. Do not try to work around it -- say what you wanted to run and why." >&2
    exit 2
  fi
done

for entry in "${ASK_PATTERNS[@]}"; do
  regex="${entry%%@@*}"
  reason="${entry#*@@}"
  if printf '%s' "$COMMAND" | grep -qE -- "$CMD_POS$regex"; then
    emit_ask "home-lab guardrails: $reason"
  fi
done

exit 0
