#!/usr/bin/env bash

# statusline.sh - Claude Code status line: context tokens, rate limits, git branch
#
# Claude Code pipes this script a JSON blob of session data on stdin and prints
# whatever it writes to stdout in a row above the footer. It runs on every
# assistant message (debounced 300ms), so it has to be fast and it has to be
# quiet when data is missing.
#
# Usage:
#   ./statusline.sh < session.json     Render one line from a JSON blob
#   ./statusline.sh --demo             Render a sample line, no stdin needed
#   ./statusline.sh --help             Show usage
#
# Wire it up with `install-claude.sh`, which writes a statusLine block into
# ~/.claude/settings.json pointing at this file, so a `git pull` updates the
# status line on that VM with nothing to re-install.
#
# OUTPUT
#
#   Opus | home-lab | main* | XXX-- 34% 68k/200k | 5h 23% 1h47m | 7d 41%
#
#   model      .model.display_name
#   dir        basename of .workspace.current_dir
#   branch     current git branch, with * when tracked files are dirty
#   context    a short bar, .context_window.used_percentage, and the token
#              counts as used/total against the real context window size
#              (200k, or 1M on an extended-context model)
#   5h         .rate_limits.five_hour: percent of the rolling 5-hour window
#              used, and a countdown to when it resets
#   7d         .rate_limits.seven_day: percent of the weekly cap used
#
# EVERY SEGMENT IS OPTIONAL. Each one renders only when its data is there:
#
#   - `rate_limits` exists only for Claude.ai Pro and Max subscribers, and only
#     after the first API response of a session. Claude Code also drops each
#     window from the JSON once that window's resets_at has passed. On a metered
#     API key the object never appears at all, and the 5h and 7d segments simply
#     do not render.
#   - `context_window.used_percentage` is null early in a session, and
#     `current_usage` goes null again after /compact until the next API call.
#   - The branch segment is absent outside a git repo.
#
# WIDTH
#
# Claude Code cannot be read with `tput cols` here, because it captures stdout
# rather than handing the script a terminal. It exports COLUMNS instead. When the
# assembled line would not fit, segments are dropped by priority (7d first, then
# model, dir, branch, 5h) and the context segment sheds its token counts before
# the bar itself shrinks. The bar is deliberately short so the rest fits on one
# line at a normal terminal width.
#
# NO `set -e`. A status line that exits early prints nothing, which reads as a
# broken terminal rather than a missing number. Failures are handled per call and
# degrade to a shorter line.
#
# DEPENDENCIES: jq when present (~3ms), else python3 (~17ms). Both read the same
# fixed-order record, so the rest of the script does not know which one ran.

set -uo pipefail

BAR_WIDTH="${STATUSLINE_BAR_WIDTH:-5}"
GIT_CACHE_TTL="${STATUSLINE_GIT_TTL:-5}"

usage() {
    sed -n '3,17p' "$0" | cut -c3-
    exit "${1:-0}"
}

DEMO='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$PWD"'"},
"context_window":{"used_percentage":34,"total_input_tokens":68000,
"total_output_tokens":1200,"context_window_size":200000},
"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":RESET5},
"seven_day":{"used_percentage":41.2,"resets_at":RESET7}},
"session_id":"demo-session"}'

demo=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --demo) demo=1; shift ;;
        --help|-h) usage 0 ;;
        *) echo "statusline.sh: unknown option $1" >&2; usage 1 ;;
    esac
done

# ------------------------------------------------------------------ colours --
# Disabled when NO_COLOR is set, which is the convention terminals and test
# harnesses both understand.
if [ -n "${NO_COLOR:-}" ]; then
    DIM=''; RESET=''; CYAN=''; GREEN=''; YELLOW=''; RED=''; BLUE=''
else
    DIM=$'\033[2m'; RESET=$'\033[0m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[34m'
fi

# -------------------------------------------------------------- read stdin --
if [ "$demo" -eq 1 ]; then
    now=$(date +%s)
    input="${DEMO/RESET5/$((now + 6420))}"
    input="${input/RESET7/$((now + 300000))}"
else
    input=$(cat)
fi
[ -n "$input" ] || exit 0

# ------------------------------------------------------------ extract JSON --
#
# One invocation, one fixed-order record, so adding a field means touching both
# readers and the FIELDS list below and nothing else. Missing and null both come
# out as an empty line; jq's `//` passes 0 through, which matters because 0% used
# is a real value and must not be confused with absent.

read_with_jq() {
    jq -r '
      def s: if . == null then "" else tostring end;
      (.model.display_name                    | s),
      (.workspace.current_dir // .cwd         | s),
      (.context_window.used_percentage        | s),
      (.context_window.total_input_tokens     | s),
      (.context_window.total_output_tokens    | s),
      (.context_window.context_window_size    | s),
      (.rate_limits.five_hour.used_percentage | s),
      (.rate_limits.five_hour.resets_at       | s),
      (.rate_limits.seven_day.used_percentage | s),
      (.rate_limits.seven_day.resets_at       | s),
      (.session_id                            | s)
    ' 2>/dev/null
}

read_with_python() {
    python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
def g(*path):
    cur = d
    for key in path:
        if not isinstance(cur, dict):
            return ""
        cur = cur.get(key)
    return "" if cur is None else str(cur)
ws = d.get("workspace") or {}
print(g("model", "display_name"))
print(ws.get("current_dir") or d.get("cwd") or "")
for path in (("context_window", "used_percentage"),
             ("context_window", "total_input_tokens"),
             ("context_window", "total_output_tokens"),
             ("context_window", "context_window_size"),
             ("rate_limits", "five_hour", "used_percentage"),
             ("rate_limits", "five_hour", "resets_at"),
             ("rate_limits", "seven_day", "used_percentage"),
             ("rate_limits", "seven_day", "resets_at"),
             ("session_id",)):
    print(g(*path))
' 2>/dev/null
}

if command -v jq >/dev/null 2>&1; then
    record=$(printf '%s' "$input" | read_with_jq)
else
    record=$(printf '%s' "$input" | read_with_python)
fi
# A blob neither reader can parse is not worth a broken line.
[ -n "$record" ] || exit 0

mapfile -t F <<< "$record"
while [ "${#F[@]}" -lt 11 ]; do F+=(""); done

MODEL="${F[0]}"      CUR_DIR="${F[1]}"   USED_PCT="${F[2]}"
IN_TOK="${F[3]}"     OUT_TOK="${F[4]}"   CTX_SIZE="${F[5]}"
FIVE_PCT="${F[6]}"   FIVE_AT="${F[7]}"   SEVEN_PCT="${F[8]}"
SEVEN_AT="${F[9]}"   SESSION="${F[10]}"

# ------------------------------------------------------------------ format --

# Round a possibly-fractional percentage to a whole number, or nothing at all.
as_int() {
    case "$1" in
        ''|*[!0-9.eE+-]*) return 1 ;;
    esac
    printf '%.0f' "$1" 2>/dev/null
}

# 68000 -> 68k, 1000000 -> 1.0M. Token counts are only ever read at a glance, so
# three significant characters beat six exact digits on a crowded line.
human() {
    local n="$1"
    case "$n" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$n" -ge 1000000 ]; then
        printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
    elif [ "$n" -ge 1000 ]; then
        printf '%dk' $((n / 1000))
    else
        printf '%d' "$n"
    fi
}

bar() {
    local pct="$1" width="$2" filled i out=''
    filled=$(( (pct * width + 50) / 100 ))
    [ "$filled" -lt 0 ] && filled=0
    [ "$filled" -gt "$width" ] && filled="$width"
    for ((i = 0; i < filled; i++)); do out+='█'; done
    for ((i = filled; i < width; i++)); do out+='░'; done
    printf '%s' "$out"
}

# Green while there is room, amber approaching the wall, red once the number is
# the thing you have to act on.
heat() {
    local pct="$1"
    if [ "$pct" -ge 80 ]; then printf '%s' "$RED"
    elif [ "$pct" -ge 50 ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"
    fi
}

# Epoch seconds -> "1h47m", "47m", "<1m". Empty once the window has passed, which
# is also when Claude Code stops sending it.
countdown() {
    local at="$1" now delta
    case "$at" in ''|*[!0-9]*) return 1 ;; esac
    now=$(date +%s)
    delta=$((at - now))
    [ "$delta" -le 0 ] && return 1
    if [ "$delta" -ge 3600 ]; then
        printf '%dh%02dm' $((delta / 3600)) $(((delta % 3600) / 60))
    elif [ "$delta" -ge 60 ]; then
        printf '%dm' $((delta / 60))
    else
        printf '<1m'
    fi
}

# Branch plus a dirty marker. `git status` is the one genuinely slow call here,
# so the answer is cached per session for a few seconds. The cache key is the
# session id rather than $$, which changes on every invocation and would mean the
# cache never hits.
git_segment() {
    local dir="$1" cache branch dirty=''
    [ -n "$dir" ] && [ -d "$dir" ] || return 1

    cache="${TMPDIR:-/tmp}/statusline-git-${SESSION:-nosession}"
    if [ -f "$cache" ]; then
        local age now mtime
        now=$(date +%s)
        mtime=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
        age=$((now - mtime))
        if [ "$age" -lt "$GIT_CACHE_TTL" ]; then
            cat "$cache"
            return 0
        fi
    fi

    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    [ -n "$branch" ] || return 1
    [ "$branch" = HEAD ] && branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    # --untracked-files=no keeps a directory full of build output from counting
    # as dirty, and makes the call materially cheaper in a large repo.
    if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null | head -c 1)" ]; then
        dirty='*'
    fi
    printf '%s%s' "$branch" "$dirty" | tee "$cache" 2>/dev/null
}

# ---------------------------------------------------------------- segments --
#
# Each segment is held twice: the coloured form that gets printed, and the plain
# form used to measure width. Measuring the coloured string would count the
# escape bytes and wrongly conclude the line does not fit.

PLAIN=() COLOR=() PRIO=()
add() { PLAIN+=("$1"); COLOR+=("$2"); PRIO+=("$3"); }

# model, priority 6
[ -n "$MODEL" ] && add "$MODEL" "${CYAN}${MODEL}${RESET}" 6

# directory, priority 5
if [ -n "$CUR_DIR" ]; then
    dir_name="${CUR_DIR##*/}"
    [ -n "$dir_name" ] && add "$dir_name" "${BLUE}${dir_name}${RESET}" 5
fi

# branch, priority 4
if branch_txt=$(git_segment "$CUR_DIR"); then
    add "$branch_txt" "${DIM}${branch_txt}${RESET}" 4
fi

# context window, priority 1: this is the token counter, it never gets dropped.
# It has a compact form (bar and percent only) used before the bar is shrunk.
CTX_PLAIN='' CTX_COLOR='' CTX_PLAIN_MIN='' CTX_COLOR_MIN=''
if pct=$(as_int "$USED_PCT"); then
    [ "$pct" -lt 0 ] && pct=0
    bar_txt=$(bar "$pct" "$BAR_WIDTH")
    col=$(heat "$pct")
    CTX_PLAIN_MIN="${bar_txt} ${pct}%"
    CTX_COLOR_MIN="${col}${bar_txt}${RESET} ${col}${pct}%${RESET}"
    CTX_PLAIN="$CTX_PLAIN_MIN"
    CTX_COLOR="$CTX_COLOR_MIN"
    # Total context first: 68k/200k reads as a fraction, and the denominator is
    # what tells you whether this is a 200k or a 1M session.
    if used=$(human "$IN_TOK") && total=$(human "$CTX_SIZE"); then
        CTX_PLAIN="${CTX_PLAIN_MIN} ${used}/${total}"
        CTX_COLOR="${CTX_COLOR_MIN} ${DIM}${used}/${total}${RESET}"
    fi
    add "$CTX_PLAIN" "$CTX_COLOR" 1
fi

# 5-hour rolling window, priority 3
if five=$(as_int "$FIVE_PCT"); then
    txt="5h ${five}%"
    if left=$(countdown "$FIVE_AT"); then txt="${txt} ${left}"; fi
    col=$(heat "$five")
    add "$txt" "${col}${txt}${RESET}" 3
fi

# weekly cap, priority 7: the first thing dropped on a narrow terminal, because
# it is the number you pace days by, not the one you act on mid-session.
if seven=$(as_int "$SEVEN_PCT"); then
    txt="7d ${seven}%"
    col=$(heat "$seven")
    add "$txt" "${col}${txt}${RESET}" 7
fi

[ "${#PLAIN[@]}" -gt 0 ] || exit 0

# ---------------------------------------------------------------- assemble --

SEP=' | '
SEP_COLOR="${DIM} | ${RESET}"

join_width() {
    local skip="$1" i total=0 count=0
    for i in "${!PLAIN[@]}"; do
        [ -n "$skip" ] && [ "${PRIO[$i]}" -ge "$skip" ] && continue
        total=$((total + ${#PLAIN[$i]}))
        count=$((count + 1))
    done
    [ "$count" -gt 1 ] && total=$((total + (count - 1) * ${#SEP}))
    printf '%d' "$total"
}

emit() {
    local skip="$1" i out='' first=1
    for i in "${!PLAIN[@]}"; do
        [ -n "$skip" ] && [ "${PRIO[$i]}" -ge "$skip" ] && continue
        if [ "$first" -eq 1 ]; then first=0; else out+="$SEP_COLOR"; fi
        out+="${COLOR[$i]}"
    done
    printf '%s\n' "$out"
}

WIDTH="${COLUMNS:-0}"
case "$WIDTH" in ''|*[!0-9]*) WIDTH=0 ;; esac
# Claude Code pads the row a little; leave a margin rather than risk a wrap.
[ "$WIDTH" -gt 4 ] && WIDTH=$((WIDTH - 2))

if [ "$WIDTH" -le 0 ] || [ "$(join_width '')" -le "$WIDTH" ]; then
    emit ''
    exit 0
fi

# Too wide. Drop the chrome from the least useful inward: 7d, model, dir, branch.
# The ladder stops there, above the 5-hour window: losing that window is worse
# than losing the token counts, so the compact retry below gets its turn first.
for cut in 7 6 5 4; do
    if [ "$(join_width "$cut")" -le "$WIDTH" ]; then
        emit "$cut"
        exit 0
    fi
done

# Still over. Shed the token counts and try the whole ladder again: a bar and a
# percentage plus the 5-hour window beats full token counts and nothing else,
# because the counts are the part the percentage already summarises.
if [ -n "$CTX_PLAIN_MIN" ] && [ "$CTX_PLAIN" != "$CTX_PLAIN_MIN" ]; then
    for i in "${!PLAIN[@]}"; do
        if [ "${PRIO[$i]}" -eq 1 ]; then
            PLAIN[$i]="$CTX_PLAIN_MIN"
            COLOR[$i]="$CTX_COLOR_MIN"
        fi
    done
    if [ "$(join_width '')" -le "$WIDTH" ]; then
        emit ''
        exit 0
    fi
    for cut in 7 6 5 4; do
        if [ "$(join_width "$cut")" -le "$WIDTH" ]; then
            emit "$cut"
            exit 0
        fi
    done
fi

# Nothing fits but the counter itself. Print it anyway: a truncated number is
# still the number, and an empty row reads as a broken terminal.
emit 3
