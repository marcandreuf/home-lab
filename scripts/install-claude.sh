#!/usr/bin/env bash

# install-claude.sh - Wire this repo's Claude commands and skills into Claude Code
#
# Usage:
#   ./install-claude.sh                       Install into ~/.claude
#   ./install-claude.sh --check               Report what is installed, change nothing
#   ./install-claude.sh --uninstall           Remove links that point into this repo
#   ./install-claude.sh --help                Show usage
#
# Everything in commands/ and skills/ is symlinked into ~/.claude, so a
# `git pull` in this repo updates every command and skill on that machine at
# once. Re-run after adding, renaming, or removing one.
#
# THE INSTALL IS ALWAYS GLOBAL. There is no per-repo install, by design. One
# machine-wide set that a single `git pull` updates is the only arrangement that
# stays honest: a repo-local copy of all 27 entries is a fork that drifts
# silently, and in a repo that commits .claude/settings.json it gets swept into
# git as a duplicate of this one. A session is scoped to one repo (docs/sdlc.md,
# "One repo per session") -- that is about where a session RUNS, not about
# giving each repo its own copy of the tooling.
#
# The commands do not need a per-repo variant to begin with: they resolve the
# repo they operate on at run time (`git rev-parse --show-toplevel`), so one
# file behaves correctly in every repo on the machine. Changing how a command
# works is an edit in this repo followed by `git pull` on each VM -- the symlink
# means there is nothing to re-install. `--force` is there for the one case that
# needs it: a real file sitting where the symlink belongs.
#
# Existing real files are never overwritten. They are reported and skipped, so
# a hand-written command in ~/.claude/commands survives this script. Pass
# --force to replace them.
#
# GLOBAL GIT RULES (opt-in)
#
# A global install also offers to write two rules into the global git ignore
# file, which is what actually keeps journals and local settings out of every
# repo on the machine -- the commands only instruct the model, and a per-repo
# .gitignore has to be remembered for each new clone. The script asks before
# touching anything, appends only rules that are missing, and never rewrites
# an existing line. Answer up front with --git-rules / --no-git-rules; when
# stdin is not a terminal the step is skipped rather than assumed.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

action=install
force=0
CLAUDE_DIR="$HOME/.claude"
git_rules=ask            # ask | yes | no

# The rules the global install offers to add. Journals are never committed in
# any repo, and settings.local.json is the file that is supposed to die with
# the VM; both are per-repo decisions today, which means one forgotten clone
# undoes them.
GIT_IGNORE_RULES=(
  '**/.claude/journals/'
  '**/.claude/settings.local.json'
)

usage() {
  cat <<EOF
install-claude.sh - Wire this repo's Claude commands and skills into Claude Code

Usage:
  $0               Install into ~/.claude (always global -- see below)
  $0 --check       Report what is installed, change nothing
  $0 --uninstall   Remove links that point into this repo
  $0 --help        Show usage

Options:
  --force        Replace existing real files instead of skipping them.
  --git-rules    Add the global git ignore rules without asking.
  --no-git-rules Leave the global git ignore file alone without asking.

Examples:
  $0               every repo on this VM gets the commands
  $0 --check       what is wired up right now
  $0 --git-rules   unattended install, git rules included

There is no per-repo install. One machine-wide set, updated by \`git pull\` here:
the commands resolve the repo they operate on at run time, so the same file is
correct everywhere. To change how one behaves, edit it in this repo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|--project=*|-p|--workspace|--workspace=*|-w|--copy)
      # Removed, not renamed. Installing every command and skill into a single
      # repo produced a silent fork of this one, and now that private repos
      # commit .claude/settings.json it would be committed alongside it.
      echo "$1: per-repo installs were removed; the install is always global" >&2
      echo >&2
      echo "run \`$0\` with no arguments. The commands resolve the repo they" >&2
      echo "operate on at run time, so one machine-wide set is correct in every" >&2
      echo "repo; to change how one behaves, edit it in this repo and git pull." >&2
      exit 1 ;;
    --check)        action=check;     shift ;;
    --uninstall)    action=uninstall; shift ;;
    --force)        force=1;          shift ;;
    --git-rules)    git_rules=yes;    shift ;;
    --no-git-rules) git_rules=no;     shift ;;
    --help|-h)      usage; exit 0 ;;
    *)              echo "unknown option: $1" >&2; echo; usage; exit 1 ;;
  esac
done

# ---------------------------------------------------------------- git rules --
#
# The commands tell the model not to commit a journal. Only git can enforce it,
# and only the global ignore file does so for repos that do not exist yet --
# which is the case a rebuilt VM is in.

GIT_RULES_MARKER='# home-lab: Claude Code working files, never committed'

# The file git actually consults: core.excludesFile when set, otherwise the XDG
# default. Appending to anything else writes a file git will never read.
git_ignore_file() {
  local configured
  configured="$(git config --global --get core.excludesFile 2>/dev/null || true)"
  if [[ -n "$configured" ]]; then
    echo "${configured/#\~/$HOME}"
  else
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
  fi
}

# Exact-line match. A commented-out or narrower variant is not the rule.
git_rule_present() {
  local file="$1" rule="$2"
  [[ -f "$file" ]] && grep -qxF -- "$rule" "$file"
}

git_rules_missing() {
  local file="$1" rule
  for rule in "${GIT_IGNORE_RULES[@]}"; do
    git_rule_present "$file" "$rule" || echo "$rule"
  done
}

# Append only what is absent, and never rewrite an existing line.
git_rules_apply() {
  local file="$1"; shift
  local missing=("$@") rule
  mkdir -p "$(dirname "$file")"
  # A file not ending in a newline would swallow the first rule onto its last line.
  if [[ -s "$file" && -n "$(tail -c 1 "$file")" ]]; then
    echo >> "$file"
  fi
  if ! git_rule_present "$file" "$GIT_RULES_MARKER"; then
    printf '%s\n' "$GIT_RULES_MARKER" >> "$file"
  fi
  for rule in "${missing[@]}"; do
    printf '%s\n' "$rule" >> "$file"
    echo "  added    $rule"
  done
  echo "written to $file"
}

# Offered on a global install only: a repo-local install says nothing about the
# other repos on the machine, which is the whole point of the rules.
git_rules_step() {
  local file missing=()
  file="$(git_ignore_file)"
  mapfile -t missing < <(git_rules_missing "$file")

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "global git rules: already in place ($file)"
    return 0
  fi

  case "$git_rules" in
    no)
      echo "global git rules: skipped (--no-git-rules); ${#missing[@]} rule(s) absent from $file"
      return 0 ;;
    ask)
      if [[ ! -t 0 ]]; then
        echo "global git rules: skipped (not a terminal); re-run with --git-rules to add them"
        return 0
      fi
      echo
      echo "Add these rules to your global git ignore ($file)?"
      local rule
      for rule in "${missing[@]}"; do echo "  $rule"; done
      echo "They keep journals and local Claude settings out of every repo on this"
      echo "machine, including repos not cloned yet. Nothing else is modified."
      local reply=""
      read -r -p "add them? [y/N] " reply || reply=""
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "left $file alone"; return 0 ;;
      esac ;;
  esac

  git_rules_apply "$file" "${missing[@]}"
}

# Collect what this repo has to offer. Commands are single .md files; skills are
# directories containing a SKILL.md, which is the unit Claude Code loads.
sources=()
collect() {
  local dest_name="$1"; shift
  local src
  for src in "$@"; do
    [[ -e "$src" ]] || continue
    sources+=("$dest_name/$(basename "$src")|$src")
  done
}

shopt -s nullglob
collect commands "$REPO"/commands/*.md
for skill in "$REPO"/skills/*/; do
  [[ -f "$skill/SKILL.md" ]] || continue
  collect skills "${skill%/}"
done
shopt -u nullglob

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "nothing to install: commands/ and skills/ are both empty" >&2
  exit 1
fi

# If the destination is itself a symlink back into this repo, per-entry links
# would be written into the working copy. Bail rather than pollute it.
guard_dest() {
  local dir="$1"
  [[ -L "$dir" ]] || return 0
  local resolved
  resolved="$(readlink -f "$dir")"
  case "$resolved" in
    "$REPO"|"$REPO"/*)
      echo "error: $dir is a symlink into this repo ($resolved)" >&2
      echo "remove it (rm \"$dir\") and re-run; this script will recreate it as a real dir" >&2
      exit 1 ;;
  esac
}

points_into_repo() {
  local path="$1" resolved
  [[ -L "$path" ]] || return 1
  resolved="$(readlink -f "$path")"
  case "$resolved" in "$REPO"|"$REPO"/*) return 0 ;; *) return 1 ;; esac
}

installed=0 skipped=0 removed=0

for entry in "${sources[@]}"; do
  rel="${entry%%|*}"
  src="${entry#*|}"
  dest="$CLAUDE_DIR/$rel"

  case "$action" in
    check)
      if points_into_repo "$dest"; then
        echo "  linked   $rel"
        installed=$((installed + 1))
      elif [[ -e "$dest" ]]; then
        echo "  FOREIGN  $rel (exists, not from this repo)"
        skipped=$((skipped + 1))
      else
        echo "  MISSING  $rel"
        skipped=$((skipped + 1))
      fi
      ;;

    uninstall)
      # Only ever remove links this script could have made. A real file at that
      # path is someone's own work and is left alone.
      if points_into_repo "$dest"; then
        rm "$dest"
        echo "removed $rel"
        removed=$((removed + 1))
      elif [[ -e "$dest" ]]; then
        echo "kept $rel (not a link into this repo)"
        skipped=$((skipped + 1))
      fi
      ;;

    install)
      guard_dest "$(dirname "$dest")"
      mkdir -p "$(dirname "$dest")"

      if [[ -e "$dest" ]] && ! points_into_repo "$dest"; then
        if [[ $force -eq 0 ]]; then
          echo "SKIP $rel: already exists and is not from this repo (--force to replace)" >&2
          skipped=$((skipped + 1))
          continue
        fi
        rm -rf "$dest"
      fi

      ln -sfn "$src" "$dest"
      echo "linked $rel -> ${src#$REPO/}"
      installed=$((installed + 1))
      ;;
  esac
done

echo
case "$action" in
  check)     echo "$installed installed, $skipped missing or foreign ($CLAUDE_DIR)" ;;
  uninstall) echo "$removed removed, $skipped kept ($CLAUDE_DIR)" ;;
  install)   echo "$installed installed, $skipped skipped ($CLAUDE_DIR)"
             echo "a \`git pull\` in $REPO now updates all of them" ;;
esac

# --uninstall leaves the git rules alone: they are a git preference the user
# opted into, not a link this script owns.
case "$action" in
  install) git_rules_step ;;
  check)
    git_ignore_path="$(git_ignore_file)"
    for rule in "${GIT_IGNORE_RULES[@]}"; do
      if git_rule_present "$git_ignore_path" "$rule"; then
        echo "  present  $rule"
      else
        echo "  ABSENT   $rule"
      fi
    done
    echo "global git rules ($git_ignore_path)" ;;
esac
