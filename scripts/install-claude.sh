#!/usr/bin/env bash

# install-claude.sh - Wire this repo's Claude commands and skills into Claude Code
#
# Usage:
#   ./install-claude.sh                       Install globally into ~/.claude
#   ./install-claude.sh --workspace PATH      Install into PATH/.claude instead
#   ./install-claude.sh --check               Report what is installed, change nothing
#   ./install-claude.sh --uninstall           Remove links that point into this repo
#   ./install-claude.sh --help                Show usage
#
# Everything in commands/ and skills/ is symlinked into the target .claude
# directory, so a `git pull` in this repo updates every command and skill on
# that machine at once. Re-run after adding, renaming, or removing one.
#
# The global install is the one you want on a new VM: it makes the commands
# available in every project on that machine. --workspace is for a single
# project that needs its own wiring; pair it with --copy to get editable files
# that deliberately diverge from this repo (a project-local override), rather
# than symlinks that track it.
#
# Existing real files are never overwritten. They are reported and skipped, so
# a hand-written command in ~/.claude/commands survives this script. Pass
# --force to replace them.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

action=install
target=""
mode=link
force=0

usage() {
  cat <<EOF
install-claude.sh - Wire this repo's Claude commands and skills into Claude Code

Usage:
  $0                       Install globally into ~/.claude
  $0 --workspace PATH      Install into PATH/.claude instead
  $0 --check               Report what is installed, change nothing
  $0 --uninstall           Remove links that point into this repo
  $0 --help                Show usage

Options:
  --copy       Copy files instead of symlinking them. Only meaningful with
               --workspace, where the point is a project-local override that
               diverges from this repo.
  --force      Replace existing real files instead of skipping them.

Examples:
  $0                                    every project on this VM gets the commands
  $0 --check                            what is wired up right now
  $0 --workspace ~/projects/foo --copy  editable override just for foo
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace|-w)
      if [[ $# -lt 2 ]]; then
        echo "$1 needs a path" >&2; echo; usage; exit 1
      fi
      target="$2"; shift 2 ;;
    --workspace=*) target="${1#--workspace=}"; shift ;;
    --check)     action=check;     shift ;;
    --uninstall) action=uninstall; shift ;;
    --copy)      mode=copy;        shift ;;
    --force)     force=1;          shift ;;
    --help|-h)   usage; exit 0 ;;
    *)           echo "unknown option: $1" >&2; echo; usage; exit 1 ;;
  esac
done

if [[ -n "$target" ]]; then
  if [[ ! -d "$target" ]]; then
    echo "workspace does not exist: $target" >&2
    exit 1
  fi
  CLAUDE_DIR="$(cd "$target" && pwd)/.claude"
  scope="workspace $target"
else
  CLAUDE_DIR="$HOME/.claude"
  scope="global"
  if [[ "$mode" == copy ]]; then
    echo "--copy is only meaningful with --workspace" >&2
    echo "a global copy would stop tracking this repo, which is the whole point of installing" >&2
    exit 1
  fi
fi

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

      if [[ "$mode" == copy ]]; then
        rm -rf "$dest"
        cp -r "$src" "$dest"
        echo "copied $rel"
      else
        ln -sfn "$src" "$dest"
        echo "linked $rel -> ${src#$REPO/}"
      fi
      installed=$((installed + 1))
      ;;
  esac
done

echo
case "$action" in
  check)     echo "$scope: $installed installed, $skipped missing or foreign ($CLAUDE_DIR)" ;;
  uninstall) echo "$scope: $removed removed, $skipped kept ($CLAUDE_DIR)" ;;
  install)   echo "$scope: $installed installed, $skipped skipped ($CLAUDE_DIR)"
             [[ "$mode" == link ]] && echo "a \`git pull\` in $REPO now updates all of them" ;;
esac
