#!/usr/bin/env bash
# Print a word as a coloured ASCII-art banner using toilet, framed by
# horizontal rules with a blank margin above and below.
#
# Usage: ./banner.sh [-f FONT] [-c COLOR] [-r CHAR] [-m N] WORD [WORD...]
#   -f FONT   toilet font (default: future).  toilet -I3 lists installed fonts.
#   -c COLOR  black red green yellow blue magenta cyan white (default: green)
#   -r CHAR   character the rules are drawn with (default: -)
#   -m N      blank lines above and below the frame (default: 1)

set -euo pipefail

font=future
color=green
rule_char='-'
margin=1

usage() {
    sed -n '2,10p' "$0" | cut -c3-
    exit "${1:-0}"
}

while getopts ':f:c:r:m:h' opt; do
    case "$opt" in
        f) font=$OPTARG ;;
        c) color=$OPTARG ;;
        r) rule_char=$OPTARG ;;
        m) margin=$OPTARG ;;
        h) usage 0 ;;
        :) echo "banner.sh: option -$OPTARG requires an argument" >&2; usage 1 ;;
        \?) echo "banner.sh: unknown option -$OPTARG" >&2; usage 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ "$#" -eq 0 ]; then
    echo "banner.sh: missing word to print" >&2
    usage 1
fi

case "$margin" in
    ''|*[!0-9]*) echo "banner.sh: -m expects a number, got '$margin'" >&2; exit 1 ;;
esac

command -v toilet >/dev/null 2>&1 || {
    echo "banner.sh: toilet is not installed (apt install toilet)" >&2
    exit 1
}

case "$color" in
    black)   code=30 ;;
    red)     code=31 ;;
    green)   code=32 ;;
    yellow)  code=33 ;;
    blue)    code=34 ;;
    magenta) code=35 ;;
    cyan)    code=36 ;;
    white)   code=37 ;;
    *) echo "banner.sh: unknown color '$color'" >&2; exit 1 ;;
esac

art=$(toilet -f "$font" -- "$*")

# Rule as wide as the widest line of the art. wc -L counts display columns, so
# the UTF-8 box-drawing fonts line up too.
width=$(printf '%s\n' "$art" | wc -L)
rule=$(printf "%*s" "$width" '' | tr ' ' "$rule_char")

blank=''
i=0
while [ "$i" -lt "$margin" ]; do
    blank="$blank"$'\n'
    i=$((i + 1))
done

# Only emit escape codes when stdout is a terminal, so piping stays clean.
if [ -t 1 ]; then
    printf '%s\033[%sm%s\n%s\n%s\033[0m\n%s' "$blank" "$code" "$rule" "$art" "$rule" "$blank"
else
    printf '%s%s\n%s\n%s\n%s' "$blank" "$rule" "$art" "$rule" "$blank"
fi
