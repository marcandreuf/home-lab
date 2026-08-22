#!/usr/bin/env bash

# sync-upstream.sh - Report what changed in mattpocock/skills since we last looked
#
# Usage:
#   ./sync-upstream.sh              Fetch upstream and report changes since LAST_REVIEWED
#   ./sync-upstream.sh --ported     Report only changes to skills we have ported
#   ./sync-upstream.sh --mark [SHA] Record SHA (default: upstream HEAD) as reviewed
#   ./sync-upstream.sh --help       Show usage
#
# We track mattpocock/skills by diff, not by merge. See UPSTREAM.md for why.
# This script never touches skills/: it tells you what moved upstream and leaves
# the decision of what to port, and how to adapt it, to you.
#
# This is a maintainer tool, for the machine you develop this repo on. It is not
# part of installing: other VMs clone this repo and run install-claude.sh, and
# never need an upstream clone at all.
#
# UPSTREAM_DIR and LAST_REVIEWED are read from UPSTREAM.md, which is also where
# the port ledger lives. The clone is disposable: LAST_REVIEWED lives in this
# repo, so deleting it and cloning again loses nothing.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LEDGER="$REPO/UPSTREAM.md"
UPSTREAM_URL="https://github.com/mattpocock/skills.git"

action=report
mark_sha=""

usage() {
  cat <<EOF
sync-upstream.sh - Report what changed in mattpocock/skills since we last looked

Usage:
  $0              Fetch upstream and report changes since LAST_REVIEWED
  $0 --ported     Report only changes to skills we have ported
  $0 --mark [SHA] Record SHA (default: upstream HEAD) as reviewed
  $0 --help       Show usage

Reads UPSTREAM_DIR and LAST_REVIEWED from UPSTREAM.md. Run --mark only after
actually reviewing the diff: it is the record of what you have seen.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ported)  action=ported; shift ;;
    --mark)
      action=mark; shift
      if [[ $# -gt 0 && "$1" != -* ]]; then mark_sha="$1"; shift; fi ;;
    --help|-h) usage; exit 0 ;;
    *)         echo "unknown option: $1" >&2; echo; usage; exit 1 ;;
  esac
done

[[ -f "$LEDGER" ]] || { echo "missing $LEDGER" >&2; exit 1; }

# Both settings live in fenced `KEY = VALUE` blocks in UPSTREAM.md, the same
# shape the commands in commands/ use for their own configuration.
read_setting() {
  local key="$1" value
  value="$(grep -m1 -E "^${key}[[:space:]]*=" "$LEDGER" | sed -E "s/^${key}[[:space:]]*=[[:space:]]*//")"
  echo "${value/#\~/$HOME}"
}

require_setting() {
  local value; value="$(read_setting "$1")"
  [[ -n "$value" ]] || { echo "$1 not set in $LEDGER" >&2; exit 1; }
  echo "$value"
}

UPSTREAM_DIR="$(require_setting UPSTREAM_DIR)"
LAST_REVIEWED="$(require_setting LAST_REVIEWED)"
FORK_URL="$(read_setting FORK_URL)"

if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then
  # With a fork, clone that and keep mattpocock as a second remote: `origin` is
  # where contributions get pushed, the upstream remote is what we read.
  if [[ -n "$FORK_URL" ]]; then
    echo "no clone at $UPSTREAM_DIR, cloning fork $FORK_URL"
    git clone "$FORK_URL" "$UPSTREAM_DIR"
    git -C "$UPSTREAM_DIR" remote add upstream "$UPSTREAM_URL"
    echo "added remote upstream -> $UPSTREAM_URL"
  else
    echo "no clone at $UPSTREAM_DIR, cloning $UPSTREAM_URL"
    git clone "$UPSTREAM_URL" "$UPSTREAM_DIR"
  fi
fi

# Find the remote that actually points at mattpocock/skills rather than assuming
# `origin` does. When the clone is a fork, `origin` is the fork, and its main
# goes stale the moment upstream pushes: reading it would report "up to date"
# while upstream had moved on.
remote=""
while read -r name url _; do
  [[ "$url" == *mattpocock/skills* ]] && { remote="$name"; break; }
done < <(git -C "$UPSTREAM_DIR" remote -v)

if [[ -z "$remote" ]]; then
  echo "no remote in $UPSTREAM_DIR points at mattpocock/skills" >&2
  echo "add one: git -C $UPSTREAM_DIR remote add upstream $UPSTREAM_URL" >&2
  exit 1
fi

git -C "$UPSTREAM_DIR" fetch --quiet "$remote"
head_sha="$(git -C "$UPSTREAM_DIR" rev-parse "$remote/main")"

if ! git -C "$UPSTREAM_DIR" cat-file -e "${LAST_REVIEWED}^{commit}" 2>/dev/null; then
  echo "LAST_REVIEWED ($LAST_REVIEWED) is not a commit in $UPSTREAM_DIR" >&2
  echo "the clone may be shallow, or the commit was rewritten upstream" >&2
  exit 1
fi

if [[ "$action" == mark ]]; then
  new_sha="${mark_sha:-$head_sha}"
  if ! git -C "$UPSTREAM_DIR" cat-file -e "${new_sha}^{commit}" 2>/dev/null; then
    echo "not a commit in $UPSTREAM_DIR: $new_sha" >&2
    exit 1
  fi
  new_sha="$(git -C "$UPSTREAM_DIR" rev-parse "$new_sha")"
  if [[ "$new_sha" == "$LAST_REVIEWED" ]]; then
    echo "already at $new_sha, nothing to mark"
    exit 0
  fi
  sed -i -E "s|^LAST_REVIEWED[[:space:]]*=.*|LAST_REVIEWED = $new_sha|" "$LEDGER"
  echo "LAST_REVIEWED: ${LAST_REVIEWED:0:8} -> ${new_sha:0:8}"
  echo "commit UPSTREAM.md to record the review"
  exit 0
fi

if [[ "$LAST_REVIEWED" == "$head_sha" ]]; then
  echo "up to date with upstream at ${head_sha:0:8}"
  exit 0
fi

range="$LAST_REVIEWED..$head_sha"
total="$(git -C "$UPSTREAM_DIR" rev-list --count "$range")"

echo "upstream ${LAST_REVIEWED:0:8} -> ${head_sha:0:8}  ($total commits, via $remote/main)"
echo

# Skills we have ported are exactly the directories in skills/. Matching them by
# name against upstream keeps this list correct without anyone maintaining it.
ported=()
shopt -s nullglob
for skill in "$REPO"/skills/*/; do
  [[ -f "$skill/SKILL.md" ]] && ported+=("$(basename "${skill%/}")")
done
shopt -u nullglob

if [[ ${#ported[@]} -gt 0 ]]; then
  echo "== changes to skills we have ported =="
  hits=0
  for name in "${ported[@]}"; do
    paths=()
    while IFS= read -r dir; do paths+=("$dir"); done < <(
      git -C "$UPSTREAM_DIR" ls-tree -d --name-only -r "$head_sha" |
        grep -E "(^|/)${name}$" || true
    )
    if [[ ${#paths[@]} -eq 0 ]]; then
      echo "  $name: no longer present upstream (renamed, moved, or deprecated)"
      hits=$((hits + 1))
      continue
    fi
    log="$(git -C "$UPSTREAM_DIR" log --oneline "$range" -- "${paths[@]}")"
    if [[ -n "$log" ]]; then
      echo "  $name:"
      echo "$log" | sed 's/^/    /'
      hits=$((hits + 1))
    fi
  done
  [[ $hits -eq 0 ]] && echo "  none"
  echo
elif [[ "$action" == ported ]]; then
  echo "nothing ported yet; skills/ is empty"
  exit 0
fi

[[ "$action" == ported ]] && exit 0

echo "== all changes under skills/ =="
skills_log="$(git -C "$UPSTREAM_DIR" log --oneline "$range" -- skills/)"
if [[ -n "$skills_log" ]]; then
  echo "$skills_log" | sed 's/^/  /'
else
  echo "  none (all $total commits were docs, tooling, or release machinery)"
fi
echo

echo "== skill dirs added or removed =="
git -C "$UPSTREAM_DIR" diff --name-status --diff-filter=AD "$range" -- '*/SKILL.md' |
  sed 's/^/  /' | grep . || echo "  none"
echo

cat <<EOF
next:
  read a change:   git -C $UPSTREAM_DIR show <sha>
  full diff:       git -C $UPSTREAM_DIR diff $range -- skills/
  once reviewed:   $0 --mark
EOF

if [[ -n "$FORK_URL" ]]; then
  # Branch from the upstream remote, not from the fork's main, which is only as
  # current as the last time it was synced. GitHub accepts the PR either way.
  cat <<EOF
  contribute:      git -C $UPSTREAM_DIR switch -c <branch> $remote/main
                   git -C $UPSTREAM_DIR push -u origin <branch>
EOF
fi
