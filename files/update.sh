#!/usr/bin/env bash
# =============================================================================
# simbox-update
#
# NOT part of the normal setup. After importing the image the machine is
# already in the state the exercises were tested and recorded against - run
# simbox-test and you are done.
#
# This command exists for the case where a trainer knowingly wants to leave
# that state: a bugfix that has not been released yet, a security update, an
# agent version with a fix they need. It is a decision, not a routine.
#
# Steps:
#   0. refresh ~/.env from the CDN
#   1. Debian packages
#   2. Claude Code
#   3. Codex CLI
#   4. the acceptance tests
#
# The exercise repos are NOT touched. They are pinned to the release tags the
# image was built from; moving them needs --repos-latest and says so loudly.
#
# Usage:
#   simbox-update               steps 0-4
#   simbox-update --check       report what is outdated, change nothing
#   simbox-update --env         only refresh the .env
#   simbox-update --agents      only claude + codex
#   simbox-update --system      only apt
#   simbox-update --test        only the acceptance tests
#   simbox-update --repos-latest   move both repos off their pinned tag
#
# Exit code 0 means everything applied and every test passed.
# =============================================================================
set -uo pipefail

MODE="all"
RUN_TEST=1

case "${1:-}" in
    --check)        MODE="check" ;;
    --env)          MODE="env";     RUN_TEST=0 ;;
    --agents)       MODE="agents";  RUN_TEST=0 ;;
    --system)       MODE="system";  RUN_TEST=0 ;;
    --repos-latest) MODE="repos";   RUN_TEST=0 ;;
    --test)         MODE="test" ;;
    --no-test)      MODE="all";     RUN_TEST=0 ;;
    -h|--help) sed -n '3,33p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "")             MODE="all" ;;
    *)              echo "unknown option: $1" >&2; exit 2 ;;
esac

PROJECTS="${HOME}/projects"
TESTS="${HOME}/tests"
STATE_FILE="/etc/simbox/env-source"
PINNED_FILE="/etc/simbox/pinned-refs"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'

hr()   { printf '%s\n' "----------------------------------------------------------"; }
step() { printf '\n%s\n' "${BOLD}$1${OFF}"; hr; }

pinned_ref() {   # pinned_ref <repo-name>
    [ -r "$PINNED_FILE" ] || return 1
    grep -m1 "^$1=" "$PINNED_FILE" 2>/dev/null | cut -d= -f2-
}

current_ref() {  # current_ref <path>
    git -C "$1" describe --tags --exact-match 2>/dev/null \
        || git -C "$1" rev-parse --short HEAD 2>/dev/null
}

show_versions() {
    step "installed"
    printf '  %-14s %s\n' "claude"  "$(claude --version 2>/dev/null || echo 'not found')"
    printf '  %-14s %s\n' "codex"   "$(codex --version 2>/dev/null || echo 'not found')"
    printf '  %-14s %s\n' "node"    "$(node --version 2>/dev/null)"
    printf '  %-14s %s\n' "python3" "$(python3 --version 2>/dev/null | cut -d' ' -f2)"
    if [ -x "${PROJECTS}/bpm-pizza-ml/.venv/bin/python" ]; then
        printf '  %-14s %s\n' "torch" \
            "$("${PROJECTS}/bpm-pizza-ml/.venv/bin/python" -c 'import torch;print(torch.__version__)' 2>/dev/null || echo '?')"
    fi
    printf '  %-14s %s\n' "debian"  "$(. /etc/os-release; echo "$VERSION")"
}

# --- 0. environment file ----------------------------------------------------
do_env() {
    step "0. refreshing .env"
    if sudo simbox-configure; then
        return 0
    fi
    printf '  %s\n' "could not refresh the .env."
    printf '  %s\n' "If this machine never had one, provide the URL once:"
    printf '  %s\n' "  sudo simbox-configure --url <cdn-url>"
    return 1
}

check_env() {
    step "0. environment file"
    local n
    n=$(
        [ -r "$HOME/.env" ] || { echo 0; exit; }
        # shellcheck disable=SC1091
        . "$HOME/.env" 2>/dev/null
        count=0
        while IFS= read -r key; do
            [ -n "${!key:-}" ] && count=$((count + 1))
        done < <(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$HOME/.env" 2>/dev/null \
                  | sed -E 's/^[[:space:]]*//; s/=$//')
        echo "$count"
    )
    printf '  %s entries in ~/.env\n' "$n"
    if [ -r "$STATE_FILE" ]; then
        printf '  source: %s\n' "$(head -n1 "$STATE_FILE")"
    else
        printf '  %s\n' "no source remembered - pass --url once"
    fi
}

# --- checks -----------------------------------------------------------------
check_system() {
    step "1. system packages"
    sudo apt-get update -qq 2>/dev/null
    local n
    n=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ')
    if [ "$n" -eq 0 ]; then
        echo "  up to date"
    else
        echo "  ${n} package(s) upgradable:"
        apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print "    " $2}' | head -20
    fi
}

check_agents() {
    step "2./3. coding agents"
    local out
    out=$(npm -g outdated --parseable 2>/dev/null \
          | awk -F: '{print $4 " -> " $3}' \
          | grep -E 'claude-code|codex')
    if [ -z "$out" ]; then
        echo "  up to date"
    else
        echo "$out" | sed 's/^/  /'
    fi
}

# Reports only. Whether to leave a pinned tag is a trainer decision.
check_repos() {
    step "exercise repos (pinned, not updated)"
    local d name pin cur latest
    for d in "$PROJECTS"/*/; do
        [ -d "${d}.git" ] || continue
        name=$(basename "$d")
        pin=$(pinned_ref "$name" || echo "?")
        cur=$(current_ref "$d")
        printf '  %-24s at %s (image pinned to %s)\n' "$name" "${cur:-?}" "$pin"

        git -C "$d" fetch --tags --quiet 2>/dev/null
        latest=$(git -C "$d" tag --sort=-v:refname 2>/dev/null | head -n1)
        if [ -n "$latest" ] && [ "$latest" != "$cur" ]; then
            printf '    %s newer release available: %s\n' "${YELLOW}note${OFF}" "$latest"
            printf '    a new image should be built from it, rather than moving this machine\n'
        fi
    done
}

# --- apply ------------------------------------------------------------------
do_system() {
    step "1. upgrading system packages"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
    sudo apt-get -y autoremove
    sudo apt-get clean
}

do_agents() {
    step "2./3. upgrading coding agents"
    sudo npm install -g @anthropic-ai/claude-code@latest @openai/codex@latest
    sudo npm cache clean --force >/dev/null 2>&1
}

do_repos_latest() {
    step "moving the exercise repos off their pinned tag"
    printf '%s This leaves the state the exercises were recorded against.\n' "${YELLOW}WARNING${OFF}"
    printf '        Videos and instructions may no longer match what participants see.\n\n'
    local d name branch
    for d in "$PROJECTS"/*/; do
        [ -d "${d}.git" ] || continue
        name=$(basename "$d")
        printf '  %s\n' "$name"
        branch=$(git -C "$d" remote show origin 2>/dev/null \
                 | sed -n 's/.*HEAD branch: //p')
        branch="${branch:-main}"
        git -C "$d" fetch --depth 1 origin "$branch" 2>&1 | sed 's/^/    /'
        git -C "$d" checkout -B "$branch" FETCH_HEAD 2>&1 | sed 's/^/    /'
    done
    printf '\n  Undo by re-importing the image.\n'
}

do_test() {
    step "4. acceptance tests"
    if [ ! -x "${TESTS}/run-all.sh" ]; then
        printf '  %s\n' "no tests in ${TESTS} - image predates them, re-import to get them"
        return 0
    fi
    "${TESTS}/run-all.sh"
}

# --- run --------------------------------------------------------------------
rc=0

case "$MODE" in
    check)
        show_versions
        check_env
        check_system
        check_agents
        check_repos
        printf '\n%s\n' "Apply steps 0-4 with:  simbox-update"
        ;;
    env)    do_env || rc=$? ;;
    system) do_system; show_versions ;;
    agents) do_agents; show_versions ;;
    repos)  do_repos_latest ;;
    test)   do_test || rc=$? ;;
    all)
        printf '%s simbox-update leaves the tested state of this image.\n' "${YELLOW}NOTE${OFF}"
        printf '     If the machine was just imported you do not need it - run simbox-test.\n'
        # A stale .env would make the tests fail for the wrong reason.
        do_env || rc=$?
        do_system
        do_agents
        show_versions
        check_repos
        printf '\n%s\n' "The PyTorch venv is left untouched on purpose - the exercises are"
        printf '%s\n'   "pinned to the version baked into the image."
        if [ "$RUN_TEST" = "1" ]; then
            do_test || rc=$?
        fi
        ;;
esac

if [ "$MODE" = "all" ] && [ "$RUN_TEST" = "1" ]; then
    printf '\n'
    hr
    if [ "$rc" -eq 0 ]; then
        printf '%s updates applied, all tests passed.\n' "${GREEN}READY${OFF}"
    else
        printf '%s something did not pass. Check the output above.\n' "${RED}NOT READY${OFF}"
        printf '      Re-importing the image restores the tested state.\n'
    fi
fi

exit $rc
