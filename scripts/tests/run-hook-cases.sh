#!/usr/bin/env bash
#
# run-hook-cases.sh - regression suite for scripts/block-dangerous-commands.sh
#
# Usage:
#   ./scripts/tests/run-hook-cases.sh            both paths default, run from anywhere
#   ./scripts/tests/run-hook-cases.sh HOOK CASES explicit paths
#
# Feeds each case in hook-cases.tsv to the hook and compares its exit code with
# the expected one: 2 means refused, 0 means allowed. Run it after touching
# either the pattern list or CMD_POS -- the two halves pull against each other,
# and the failure that matters is a pattern quietly catching ordinary work.
#
# The cases live in a data file rather than in this script on purpose. They look
# like commands because they ARE commands, so a case written inline would be a
# command position in this file, and the hook would refuse the test run itself.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${1:-$HERE/../block-dangerous-commands.sh}"
CASES="${2:-$HERE/hook-cases.tsv}"

if [[ ! -x "$HOOK" ]]; then
  echo "no hook to test at $HOOK" >&2
  exit 1
fi
if [[ ! -f "$CASES" ]]; then
  echo "no cases at $CASES" >&2
  exit 1
fi
pass=0; fail=0

while IFS=$'\t' read -r want cmd; do
  [[ -z "$cmd" || "$want" == \#* ]] && continue
  payload="$(CMD="$cmd" python3 -c 'import json,os;print(json.dumps({"tool_input":{"command":os.environ["CMD"]}}))')"
  printf '%s' "$payload" | "$HOOK" >/dev/null 2>&1
  got=$?
  if [[ "$got" == "$want" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf '  FAIL want=%s got=%s  %s\n' "$want" "$got" "$cmd"
  fi
done < "$CASES"

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
