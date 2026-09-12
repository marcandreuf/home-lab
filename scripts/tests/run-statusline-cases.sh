#!/usr/bin/env bash
#
# run-statusline-cases.sh - regression suite for scripts/statusline.sh
#
# Usage:
#   ./scripts/tests/run-statusline-cases.sh                 defaults, run from anywhere
#   ./scripts/tests/run-statusline-cases.sh SCRIPT CASES    explicit paths
#
# Feeds each case's JSON to the status line at a given terminal width and compares
# the rendered row with the expected one, exactly. Run it after touching a
# segment, the trim ladder, or either JSON reader.
#
# WHAT THESE CASES ARE REALLY FOR. Almost every field in the JSON is allowed to
# be absent or null, and the failure that matters is not a crash: it is a segment
# that renders "0%" as nothing, or "null%" as text, or keeps showing a rate-limit
# window Claude Code has already dropped. Half the cases below are absence cases,
# and `0 is not missing` is the one worth protecting hardest.
#
# Cases run with NO_COLOR=1 so the expectation is the layout rather than a row of
# escape bytes, and against a directory that is not a git repo so the branch
# segment cannot make the output depend on where the suite is run from.
#
# @NOW+N@ and @NOW-N@ in a case become epoch seconds N seconds from now, which is
# what a countdown or an already-expired window needs. A case is one line, so a
# tab separates the fields and cannot appear inside one.
#
# Both readers are exercised: the whole file runs once with jq on PATH and again
# with jq hidden, so the python3 fallback has to produce the identical row. A
# fallback that only runs on a VM without jq is a fallback nobody tests.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$HERE/../statusline.sh}"
CASES="${2:-$HERE/statusline-cases.tsv}"

if [[ ! -x "$SCRIPT" ]]; then
  echo "no status line to test at $SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$CASES" ]]; then
  echo "no cases at $CASES" >&2
  exit 1
fi

pass=0; fail=0

run_suite() {
  local label="$1" path_override="$2"
  local want cols json now out

  echo "  -- $label"
  while IFS=$'\t' read -r want cols json; do
    [[ -z "${json:-}" || "$want" == \#* ]] && continue

    now=$(date +%s)
    # Substitute every @NOW+N@ / @NOW-N@ with a real epoch.
    while [[ "$json" =~ @NOW([+-])([0-9]+)@ ]]; do
      local op="${BASH_REMATCH[1]}" n="${BASH_REMATCH[2]}" val
      if [[ "$op" == "+" ]]; then val=$((now + n)); else val=$((now - n)); fi
      json="${json/@NOW${op}${n}@/$val}"
    done
    # A case expecting nothing at all writes __EMPTY__, since a trailing tab and
    # an empty field are indistinguishable once read.
    [[ "$want" == "__EMPTY__" ]] && want=""

    out=$(printf '%s' "$json" | NO_COLOR=1 COLUMNS="$cols" PATH="$path_override" \
            bash "$SCRIPT" 2>/dev/null)

    if [[ "$out" == "$want" ]]; then
      pass=$((pass+1))
    else
      fail=$((fail+1))
      printf '  FAIL [%s] cols=%s\n        want: %s\n        got:  %s\n' \
        "$label" "$cols" "$want" "$out"
    fi
  done < "$CASES"
}

run_suite "jq reader" "$PATH"

# Hide jq by pointing PATH at a directory holding everything else the script
# needs. If jq is not installed here, this pass is the only pass.
if command -v jq >/dev/null 2>&1; then
  shim="$(mktemp -d)"
  trap 'rm -rf "$shim"' EXIT
  for bin in bash date git stat cat head tee sed cut python3 printf mktemp; do
    src="$(command -v "$bin" 2>/dev/null)" && ln -sf "$src" "$shim/$bin"
  done
  run_suite "python3 fallback (jq hidden)" "$shim"
else
  echo "  -- python3 fallback: jq is not installed, first pass already covered it"
fi

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
