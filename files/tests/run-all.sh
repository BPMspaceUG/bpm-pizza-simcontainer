#!/usr/bin/env bash
# =============================================================================
# ~/tests/run-all.sh   (linked as simbox-test)
#
# Acceptance checklist for a freshly reset lab machine. Run it right after
# importing the image, before the training starts.
#
#   simbox-test          run everything
#   simbox-test 01 05    run only the tests whose number matches
#   simbox-test --list   show what exists
#
# Exit code 0 means the machine is ready.
# =============================================================================
set -uo pipefail
# readlink so this also works through the /usr/local/bin/simbox-test symlink.
cd "$(dirname "$(readlink -f "$0")")"

GREEN=$'\033[32m'; RED=$'\033[31m'; BOLD=$'\033[1m'; OFF=$'\033[0m'

mapfile -t ALL < <(ls -1 [0-9][0-9]-*.sh 2>/dev/null | sort)

if [ "${1:-}" = "--list" ]; then
    printf '%s\n' "${ALL[@]}"
    exit 0
fi

if [ $# -gt 0 ]; then
    SELECTED=()
    for want in "$@"; do
        for t in "${ALL[@]}"; do
            case "$t" in "${want}"*) SELECTED+=("$t") ;; esac
        done
    done
else
    SELECTED=("${ALL[@]}")
fi

[ ${#SELECTED[@]} -gt 0 ] || { echo "no matching tests"; exit 2; }

declare -a FAILED=()
started=$(date +%s)

for t in "${SELECTED[@]}"; do
    printf '\n'
    if bash "$t"; then
        :
    else
        FAILED+=("$t")
        # Everything downstream depends on the gateway; stop early if it is out.
        case "$t" in 00-*) echo "aborting - nothing else can pass without the gateway"; break ;; esac
    fi
done

elapsed=$(( $(date +%s) - started ))

printf '\n%s\n' "${BOLD}=========================================================${OFF}"
if [ ${#FAILED[@]} -eq 0 ]; then
    printf '%s %s test(s) in %ss - the machine is ready.\n' \
        "${GREEN}ALL PASSED${OFF}" "${#SELECTED[@]}" "$elapsed"
    exit 0
fi

printf '%s %s of %s test(s) failed in %ss:\n' \
    "${RED}FAILURES${OFF}" "${#FAILED[@]}" "${#SELECTED[@]}" "$elapsed"
printf '  %s\n' "${FAILED[@]}"
printf '\nRerun a single test for detail, e.g.  ~/tests/%s\n' "${FAILED[0]}"
exit 1
