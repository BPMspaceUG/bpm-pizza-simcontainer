#!/usr/bin/env bash
# The PyTorch exercise environment, exactly as the exercises use it, plus a
# check that both checkouts still sit on the release tags this image was
# built from.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="05-exercise-env"
header "PyTorch venv and pinned exercise repos"

REPO="$HOME/projects/bpm-pizza-ml"
PINNED_FILE="/etc/simbox/pinned-refs"

[ -d "$REPO/.git" ] || fail "$REPO is missing" \
    "The image is broken - re-import it."
[ -x "$REPO/.venv/bin/python" ] || fail "no venv in $REPO"

# --- the data the exercises train on ----------------------------------------
# Existence and non-empty only. The dataset versions under data/ belong to the
# exercise repo and will churn; asserting deep paths would break this image on
# a legitimate data/v3 (#3).
for d in data test_images; do
    [ -d "$REPO/$d" ] && [ -n "$(ls -A "$REPO/$d" 2>/dev/null)" ] \
        || fail "$REPO/$d is missing or empty" \
               "The image is broken - re-import it."
    printf '  required: bpm-pizza-ml/%s\n' "$d"
done
printf '  data    : %s\n' "$(ls -1 "$REPO/data" 2>/dev/null | tr '\n' ' ')"
[ -d "$HOME/projects/bpm-pizza-vibecoding/.git" ] \
    || fail "bpm-pizza-vibecoding is missing"

# --- the skills block exercise 4 relies on ----------------------------------
# Presence, not count: the exercise repo owns its skill set and may add more.
# The names are printed so a trainer can eyeball them; only "at least one"
# is a pass condition.
#
# NUL-delimited throughout: a skill directory containing a space must count as
# one skill, not two.
SKILLDIR="$HOME/projects/bpm-pizza-vibecoding/.claude/skills"
printf '  required: bpm-pizza-vibecoding/.claude/skills\n'
mapfile -d '' -t SKILLPATHS < <(find "$SKILLDIR" -mindepth 2 -maxdepth 2 \
                                -name SKILL.md -printf '%h\0' 2>/dev/null | sort -z)
[ ${#SKILLPATHS[@]} -gt 0 ] || fail "no skills in $SKILLDIR" \
    "The checkout predates the skills or the image is broken - re-import it."
for s in "${SKILLPATHS[@]}"; do
    printf '  skill   : %s\n' "$(basename "$s")"
done

# --- the environment the exercises rely on ----------------------------------
out=$(cd "$REPO" && ./.venv/bin/python check_environment.py 2>&1)
rc=$?
printf '%s\n' "$out" | sed 's/^/  /'

[ $rc -eq 0 ] || fail "check_environment.py exited with $rc"

printf '%s' "$out" | grep -qi 'ready to start\|all dependencies' \
    || fail "check_environment.py did not report a complete environment"

# --- still on the pinned release? -------------------------------------------
# Not fatal: a trainer may have moved a repo on purpose with
# `simbox-update --repos-latest`. But it must be visible, because the
# recorded videos were made against the pinned tag.
if [ -r "$PINNED_FILE" ]; then
    drifted=0
    for d in "$HOME"/projects/*/; do
        [ -d "${d}.git" ] || continue
        name=$(basename "$d")
        pin=$(grep -m1 "^${name}=" "$PINNED_FILE" 2>/dev/null | cut -d= -f2-)
        [ -n "$pin" ] || continue
        cur=$(git -C "$d" describe --tags --exact-match 2>/dev/null \
              || git -C "$d" rev-parse --short HEAD 2>/dev/null)
        if [ "$cur" = "$pin" ]; then
            printf '  %-24s %s\n' "$name" "$pin"
        else
            printf '  %-24s %s (image pinned to %s)\n' "$name" "${cur:-?}" "$pin"
            drifted=1
        fi
    done
    if [ "$drifted" = "1" ]; then
        note "a checkout has moved off its pinned release - the exercise videos may not match"
        note "re-import the image to get back to the tested state"
    fi
else
    note "no ${PINNED_FILE} - image predates release pinning"
fi

pass "torch, data, both repos and the vibecoding skills are in place"
