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
# GUARDRAILS HOOK (opt-in)
#
# A global install also offers to wire scripts/block-dangerous-commands.sh into
# ~/.claude/settings.json as a PreToolUse hook on Bash, so destructive commands
# are refused before they run. The settings entry points at this repo, so a
# `git pull` updates the rules with nothing to re-install. Answer up front with
# --hooks / --no-hooks.
#
# STATUS LINE (opt-in)
#
# A global install also offers to wire scripts/statusline.sh into
# ~/.claude/settings.json as the statusLine command, which puts a live token
# counter in the row above the footer: context window used, the rolling 5-hour
# limit with a countdown to its reset, the weekly cap, and the git branch. Like
# the hook, the settings entry points at this repo, so a `git pull` updates it
# with nothing to re-install. Answer up front with --statusline / --no-statusline.
#
# An existing statusLine that points somewhere else is someone's own status line
# and is reported and left alone, the same way a real file at a symlink path is.
# --force replaces it.
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
git_rules=ask            # ask | yes | no   (overwritten below if flags given)
hooks=ask                # ask | yes | no
statusline=ask           # ask | yes | no
CLAUDE_DIR="$HOME/.claude"
HOOK_SCRIPT_NAME=block-dangerous-commands.sh
STATUSLINE_SCRIPT_NAME=statusline.sh
# The countdown to the 5-hour reset ticks in minutes, so re-running once a
# minute keeps it honest. Claude Code also re-runs on every assistant message
# and the moment a rate-limit window reaches its resets_at, which is what makes
# a shorter interval pointless here: it would only add git calls.
STATUSLINE_REFRESH=60
ASK_RULES=('Bash(git push:*)')
# The rules the global install offers to add. Journals are never committed in
# any repo, and settings.local.json is the file that is supposed to die with
# the VM; both are per-repo decisions today, which means one forgotten clone
# undoes them.
GIT_IGNORE_RULES=(
  '**/.claude/journals/'
  '**/.claude/settings.local.json'
)

# Prose shown to the user is written one paragraph per line and folded here, at
# the real terminal width and only on spaces. Hard-wrapping it in the source puts
# a break mid-sentence at every width except the one it was written for. Defined
# before usage() because arg parsing calls both.
say() {
  local width
  width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
  [[ "$width" =~ ^[0-9]+$ ]] || width=80
  (( width > 100 )) && width=100
  (( width < 40 )) && width=40
  printf '%s\n' "$*" | fold -s -w "$width"
}

usage() {
  cat <<EOF
install-claude.sh - Wire this repo's Claude commands and skills into Claude Code

Usage:
  $0               Install into ~/.claude (always global -- see below)
  $0 --check       Report what is installed, change nothing
  $0 --uninstall   Remove links that point into this repo
  $0 --help        Show usage

Options:
  --force         Replace existing real files instead of skipping them.
  --git-rules     Add the global git ignore rules without asking.
  --no-git-rules  Leave the global git ignore file alone without asking.
  --hooks         Install the guardrails hook without asking.
  --no-hooks      Leave ~/.claude/settings.json alone without asking.
  --statusline    Install the token-counter status line without asking.
  --no-statusline Leave the statusLine setting alone without asking.

Examples:
  $0               every repo on this VM gets the commands
  $0 --check       what is wired up right now
  $0 --git-rules   unattended install, git rules included

EOF
  say "There is no per-repo install. One machine-wide set, updated by \`git pull\` here: the commands resolve the repo they operate on at run time, so the same file is correct everywhere. To change how one behaves, edit it in this repo."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|--project=*|-p|--workspace|--workspace=*|-w|--copy)
      # Removed, not renamed. Installing every command and skill into a single
      # repo produced a silent fork of this one, and now that private repos
      # commit .claude/settings.json it would be committed alongside it.
      echo "$1: per-repo installs were removed; the install is always global" >&2
      echo >&2
      say "Run \`$0\` with no arguments. The commands resolve the repo they operate on at run time, so one machine-wide set is correct in every repo; to change how one behaves, edit it in this repo and git pull." >&2
      exit 1 ;;
    --check)        action=check;     shift ;;
    --uninstall)    action=uninstall; shift ;;
    --force)        force=1;          shift ;;
    --git-rules)    git_rules=yes;    shift ;;
    --no-git-rules) git_rules=no;     shift ;;
    --hooks)        hooks=yes;        shift ;;
    --no-hooks)     hooks=no;         shift ;;
    --statusline)    statusline=yes;  shift ;;
    --no-statusline) statusline=no;   shift ;;
    --help|-h)      usage; exit 0 ;;
    *)              echo "unknown option: $1" >&2; echo; usage; exit 1 ;;
  esac
done

# ----------------------------------------------------------------- guardrails --
#
# A PreToolUse hook sees the whole command string, so it catches what a
# permission deny rule cannot: a dangerous flag in a late argument position, or
# a command wrapped in `bash -c`. The settings entry points at this repo, so the
# rules update with a `git pull`.
#
# It also adds `Bash(git push:*)` to permissions.ask. Plain `git push` is ordinary
# work, so the hook lets it through -- but "yes, and do not ask again" on a prompt
# writes an allow rule into settings.local.json, and from then on pushes would run
# unattended. An ask rule keeps the confirmation in place.

hook_path() { echo "$REPO/scripts/$HOOK_SCRIPT_NAME"; }

hook_present() {
  local settings="$1" hook="$2"
  [[ -f "$settings" ]] || return 1
  SETTINGS="$settings" HOOK="$hook" ASK="$(printf '%s\n' "${ASK_RULES[@]}")" python3 -c '
import json, os, sys
try:
    d = json.load(open(os.environ["SETTINGS"]))
except Exception:
    sys.exit(1)
want = os.environ["HOOK"]
hooked = any(want in str(h.get("command", ""))
             for g in d.get("hooks", {}).get("PreToolUse", [])
             for h in g.get("hooks", []))
asked = set(os.environ["ASK"].split("\n")) <= set(d.get("permissions", {}).get("ask", []))
sys.exit(0 if (hooked and asked) else 1)
' 2>/dev/null
}

# Merge into whatever is already in settings.json rather than writing the file
# fresh: it holds the user own preferences and this script does not own them.
hook_install() {
  local settings="$1" hook="$2"
  mkdir -p "$(dirname "$settings")"
  SETTINGS="$settings" HOOK="$hook" ASK="$(printf '%s\n' "${ASK_RULES[@]}")" python3 -c '
import json, os
path, hook = os.environ["SETTINGS"], os.environ["HOOK"]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception as e:
    raise SystemExit("cannot parse %s: %s; fix or move it and re-run" % (path, e))

pre = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
entry = {"type": "command", "command": hook}
if not any(hook in str(h.get("command", "")) for g in pre for h in g.get("hooks", [])):
    for group in pre:
        if group.get("matcher") == "Bash":
            group.setdefault("hooks", []).append(entry)
            break
    else:
        pre.append({"matcher": "Bash", "hooks": [entry]})
    print("  hooked   PreToolUse:Bash -> " + hook)

ask = data.setdefault("permissions", {}).setdefault("ask", [])
for rule in os.environ["ASK"].split("\n"):
    if rule and rule not in ask:
        ask.append(rule)
        print("  ask      " + rule)

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("written to " + path)
'
}

hook_step() {
  local settings="$CLAUDE_DIR/settings.json" hook
  hook="$(hook_path)"

  if [[ ! -x "$hook" ]]; then
    echo "guardrails hook: skipped, $hook is missing or not executable"
    return 0
  fi
  if hook_present "$settings" "$hook"; then
    echo "guardrails hook: already in place ($settings)"
    return 0
  fi

  case "$hooks" in
    no)
      echo "guardrails hook: skipped (--no-hooks)"
      return 0 ;;
    ask)
      if [[ ! -t 0 ]]; then
        echo "guardrails hook: skipped (not a terminal); re-run with --hooks to add it"
        return 0
      fi
      echo
      # Paths go on their own lines: say() folds on spaces, and a long path has
      # none, so folding it would break mid-path.
      echo "Install the guardrails hook?"
      echo "  hook      $hook"
      echo "  settings  $settings"
      echo "  event     PreToolUse on Bash"
      echo
      say "It refuses destructive commands before they run: force-push, hard reset, forced clean, history rewrites, GitHub repo and API writes, recursive delete of an absolute path, and the docker commands that drop images or volumes."
      echo
      say "A plain \`git push\` is NOT blocked. It is added to permissions.ask instead, so it asks you every time rather than ever becoming automatic."
      echo
      say "The full list, and the two things this cannot do, are in the header of the script above. Nothing else in your settings is touched."
      local reply=""
      read -r -p "install it? [y/N] " reply || reply=""
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "left $settings alone"; return 0 ;;
      esac ;;
  esac

  hook_install "$settings" "$hook"
}

# -------------------------------------------------------------- status line --
#
# The status line is the one thing offered here that is purely informational: it
# changes nothing about what Claude Code will do, it only shows what the session
# is already spending. It is still opt-in, because `statusLine` is a single key
# rather than a list, so installing it means taking over a setting the user may
# already have their own version of.

statusline_path() { echo "$REPO/scripts/$STATUSLINE_SCRIPT_NAME"; }

# Three answers, not two. "foreign" is the one that matters: a status line
# someone wrote themselves is their work, and gets the same treatment as a real
# file sitting where a symlink belongs.
statusline_state() {
  local settings="$1" script="$2"
  [[ -f "$settings" ]] || { echo absent; return 0; }
  SETTINGS="$settings" SCRIPT="$script" python3 -c '
import json, os, sys
try:
    d = json.load(open(os.environ["SETTINGS"]))
except Exception:
    print("absent"); sys.exit(0)
sl = d.get("statusLine")
if not isinstance(sl, dict) or not sl.get("command"):
    print("absent")
elif os.environ["SCRIPT"] in str(sl.get("command")):
    print("ours")
else:
    print("foreign")
' 2>/dev/null || echo absent
}

# Merge into whatever is already in settings.json rather than writing the file
# fresh: it holds the user's own preferences and this script does not own them.
statusline_install() {
  local settings="$1" script="$2" refresh="$3"
  mkdir -p "$(dirname "$settings")"
  SETTINGS="$settings" SCRIPT="$script" REFRESH="$refresh" python3 -c '
import json, os
path = os.environ["SETTINGS"]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception as e:
    raise SystemExit("cannot parse %s: %s; fix or move it and re-run" % (path, e))

data["statusLine"] = {
    "type": "command",
    "command": os.environ["SCRIPT"],
    "padding": 0,
    "refreshInterval": int(os.environ["REFRESH"]),
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("  statusLine  -> " + os.environ["SCRIPT"])
print("written to " + path)
'
}

statusline_step() {
  local settings="$CLAUDE_DIR/settings.json" script state
  script="$(statusline_path)"

  if [[ ! -x "$script" ]]; then
    echo "status line: skipped, $script is missing or not executable"
    return 0
  fi

  state="$(statusline_state "$settings" "$script")"
  if [[ "$state" == ours ]]; then
    echo "status line: already in place ($settings)"
    return 0
  fi
  if [[ "$state" == foreign && $force -eq 0 ]]; then
    echo "status line: skipped, $settings already has a statusLine of its own (--force to replace)"
    return 0
  fi

  case "$statusline" in
    no)
      echo "status line: skipped (--no-statusline)"
      return 0 ;;
    ask)
      if [[ ! -t 0 ]]; then
        echo "status line: skipped (not a terminal); re-run with --statusline to add it"
        return 0
      fi
      echo
      echo "Install the token counter status line?"
      echo "  script    $script"
      echo "  settings  $settings"
      echo
      say "It renders one row above the footer: the model, the directory, the git branch, a short bar with the context window used and the token counts, the rolling 5-hour limit with a countdown to its reset, and the weekly cap."
      echo
      say "Every segment hides itself when its data is absent, so on a metered API key, which has no subscription windows to report, it is just the context counter."
      echo
      # Render the real thing rather than describe it. A sample beats a sentence,
      # and it doubles as a check that the script runs on this machine at all.
      local sample=""
      sample="$(NO_COLOR=1 COLUMNS=76 "$script" --demo 2>/dev/null)" || sample=""
      if [[ -n "$sample" ]]; then
        echo "  $sample"
        echo
      fi
      local reply=""
      read -r -p "install it? [y/N] " reply || reply=""
      case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "left $settings alone"; return 0 ;;
      esac ;;
  esac

  statusline_install "$settings" "$script" "$STATUSLINE_REFRESH"
}

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
      say "Add these rules to your global git ignore ($file)?"
      local rule
      for rule in "${missing[@]}"; do echo "  $rule"; done
      echo
      say "They keep journals and local Claude settings out of every repo on this machine, including repos not cloned yet. Nothing else is modified."
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
  install) git_rules_step; hook_step; statusline_step ;;
  check)
    git_ignore_path="$(git_ignore_file)"
    for rule in "${GIT_IGNORE_RULES[@]}"; do
      if git_rule_present "$git_ignore_path" "$rule"; then
        echo "  present  $rule"
      else
        echo "  ABSENT   $rule"
      fi
    done
    echo "global git rules ($git_ignore_path)"
    if hook_present "$CLAUDE_DIR/settings.json" "$(hook_path)"; then
      echo "  present  guardrails hook + git push ask rule"
    else
      echo "  ABSENT   guardrails hook + git push ask rule"
    fi
    case "$(statusline_state "$CLAUDE_DIR/settings.json" "$(statusline_path)")" in
      ours)    echo "  present  token counter status line" ;;
      foreign) echo "  FOREIGN  status line (a statusLine not from this repo)" ;;
      *)       echo "  ABSENT   token counter status line" ;;
    esac ;;
esac
