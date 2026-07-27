#!/usr/bin/env bash
# The PyTorch exercise environment, exactly as the exercises use it.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="05-exercise-env"
header "PyTorch venv in bpm-pizza-ml"

REPO="$HOME/projects/bpm-pizza-ml"

[ -d "$REPO/.git" ] || fail "$REPO is missing" \
    "The image is broken - re-import it."
[ -x "$REPO/.venv/bin/python" ] || fail "no venv in $REPO"

out=$(cd "$REPO" && ./.venv/bin/python check_environment.py 2>&1)
rc=$?
printf '%s\n' "$out" | sed 's/^/  /'

[ $rc -eq 0 ] || fail "check_environment.py exited with $rc"

printf '%s' "$out" | grep -qi 'ready to start\|all dependencies' \
    || fail "check_environment.py did not report a complete environment"

[ -d "$HOME/projects/bpm-pizza-vibecoding/.git" ] \
    || fail "bpm-pizza-vibecoding is missing"

pass "torch, data and both repos are in place"
