#!/usr/bin/env bash
# =============================================================================
# devbox-update
#
# Shows or applies updates for everything that ages in this image:
# the Debian base, both coding agents, and the two project checkouts.
#
# Usage:
#   devbox-update --check     report what is outdated, change nothing
#   devbox-update             apply everything
#   devbox-update --agents    only claude + codex
#   devbox-update --system    only apt
#   devbox-update --repos     only git pull in ~/projects/*
# =============================================================================
set -uo pipefail

MODE="all"
case "${1:-}" in
    --check)   MODE="check" ;;
    --agents)  MODE="agents" ;;
    --system)  MODE="system" ;;
    --repos)   MODE="repos" ;;
    -h|--help) sed -n '3,15p' "$0" | sed 's/^# \?//'; exit 0 ;;
    "")        MODE="all" ;;
    *)         echo "unknown option: $1" >&2; exit 2 ;;
esac

PROJECTS="${HOME}/projects"

hr() { printf '%s\n' "----------------------------------------------------------"; }

show_versions() {
    hr
    echo "installed"
    hr
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

check_system() {
    hr
    echo "system packages"
    hr
    sudo apt-get update -qq 2>/dev/null
    local n
    n=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ')
    if [ "$n" -eq 0 ]; then
        echo "  up to date"
    else
        echo "  ${n} package(s) upgradable:"
        apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print "    " $2}' | head -20
        echo "  -> devbox-update --system"
    fi
}

check_agents() {
    hr
    echo "coding agents"
    hr
    local out
    out=$(npm -g outdated --parseable 2>/dev/null \
          | awk -F: '{print $4 " -> " $3}' \
          | grep -E 'claude-code|codex')
    if [ -z "$out" ]; then
        echo "  up to date"
    else
        echo "$out" | sed 's/^/  /'
        echo "  -> devbox-update --agents"
    fi
}

check_repos() {
    hr
    echo "project repos"
    hr
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
    echo "  -> devbox-update --repos"
}

do_system() {
    hr; echo "upgrading system packages"; hr
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
    sudo apt-get -y autoremove
    sudo apt-get clean
}

do_agents() {
    hr; echo "upgrading coding agents"; hr
    sudo npm install -g @anthropic-ai/claude-code@latest @openai/codex@latest
    sudo npm cache clean --force >/dev/null 2>&1
}

do_repos() {
    hr; echo "updating project repos"; hr
    local d
    for d in "$PROJECTS"/*/; do
        [ -d "${d}.git" ] || continue
        echo "  $(basename "$d")"
        # The clones are shallow, so keep the pull shallow as well.
        git -C "$d" pull --ff-only --depth 1 2>&1 | sed 's/^/    /'
    done
}

case "$MODE" in
    check)
        show_versions
        check_system
        check_agents
        check_repos
        ;;
    system) do_system; show_versions ;;
    agents) do_agents; show_versions ;;
    repos)  do_repos ;;
    all)
        do_system
        do_agents
        do_repos
        show_versions
        hr
        echo "Note: the PyTorch venv is left untouched on purpose - the"
        echo "exercises are pinned to the version baked into the image."
        ;;
esac
