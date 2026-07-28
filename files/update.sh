#!/usr/bin/env bash
# =============================================================================
# simbox-update
#
# The first command a trainer runs on a freshly reset lab machine. In order:
#
#   0. refresh ~/.env from the CDN
#   1. Debian packages
#   2. Claude Code
#   3. Codex CLI
#   4. git pull in ~/projects/*
#   5. the acceptance tests in ~/tests
#
# Usage:
#   simbox-update             all steps
#   simbox-update --check     report what is outdated, change nothing
#   simbox-update --no-test   steps 0-4 only
#   simbox-update --env       only refresh the .env
#   simbox-update --agents    only claude + codex
#   simbox-update --system    only apt
#   simbox-update --repos     only git pull
#   simbox-update --test      only the acceptance tests
#
# Exit code 0 means the machine is updated and every test passed.
# =============================================================================
set -uo pipefail

MODE="all"
RUN_TEST=1

case "${1:-}" in
    --check)   MODE="check" ;;
    --env)     MODE="env";     RUN_TEST=0 ;;
    --agents)  MODE="agents";  RUN_TEST=0 ;;
    --system)  MODE="system";  RUN_TEST=0 ;;
    --repos)   MODE="repos";   RUN_TEST=0 ;;
    --test)    MODE="test" ;;
    --no-test) MODE="all";     RUN_TEST=0 ;;
    -h|--help) sed -n '3,26p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "")        MODE="all" ;;
    *)         echo "unknown option: $1" >&2; exit 2 ;;
esac

PROJECTS="${HOME}/projects"
TESTS="${HOME}/tests"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; OFF=$'\033[0m'

hr()   { printf '%s\n' "----------------------------------------------------------"; }
step() { printf '\n%s\n' "${BOLD}$1${OFF}"; hr; }

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
    # A bare simbox-configure re-fetches from ENV_SELF_URL in the current file,
    # or from the URL remembered at install time.
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
    n=$(grep -c '=' "$HOME/.env" 2>/dev/null || echo 0)
    printf '  %s entries in ~/.env\n' "$n"
    if [ -r /etc/devbox/env-source ]; then
        printf '  source: %s\n' "$(head -n1 /etc/devbox/env-source)"
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

check_repos() {
    step "4. project repos"
    local d name behind
    for d in "$PROJECTS"/*/; do
        [ -d "${d}.git" ] || continue
        name=$(basename "$d")
        git -C "$d" fetch --quiet 2>/dev/null
        behind=$(git -C "$d" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
        if [ "$behind" = "0" ]; then
            printf '  %-24s up to date\n' "$name"
        else
            printf '  %-24s %s commit(s) behind\n' "$name" "$behind"
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

do_repos() {
    step "4. updating project repos"
    local d name
    for d in "$PROJECTS"/*/; do
        [ -d "${d}.git" ] || continue
        name=$(basename "$d")
        printf '  %s\n' "$name"
        # Shallow clones, so keep the fetch shallow as well.
        if ! git -C "$d" pull --ff-only --depth 1 2>&1 | sed 's/^/    /'; then
            printf '    %s\n' "not fast-forwardable - local changes? leaving it alone"
        fi
    done
}

do_test() {
    step "5. acceptance tests"
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
        printf '\n%s\n' "Apply everything with:  simbox-update"
        ;;
    env)    do_env || rc=$? ;;
    system) do_system; show_versions ;;
    agents) do_agents; show_versions ;;
    repos)  do_repos ;;
    test)   do_test || rc=$? ;;
    all)
        # A stale .env would make the tests fail for the wrong reason, so this
        # goes first. A failure here is not fatal - the rest still runs.
        do_env || rc=$?
        do_system
        do_agents
        do_repos
        show_versions
        printf '\n%s\n' "Note: the PyTorch venv is left untouched on purpose - the"
        printf '%s\n'   "exercises are pinned to the version baked into the image."
        if [ "$RUN_TEST" = "1" ]; then
            do_test || rc=$?
        fi
        ;;
esac

if [ "$MODE" = "all" ] && [ "$RUN_TEST" = "1" ]; then
    printf '\n'
    hr
    if [ "$rc" -eq 0 ]; then
        printf '%s the machine is updated and ready for the training.\n' "${GREEN}READY${OFF}"
    else
        printf '%s something did not pass. Check the output above.\n' "${RED}NOT READY${OFF}"
        printf '      Rerun a single test from %s for detail.\n' "$TESTS"
    fi
fi

exit $rc
