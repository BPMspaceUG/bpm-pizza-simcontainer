#!/usr/bin/env bash
# Shared helpers for the acceptance tests in ~/tests.
# Sourced, not executed.

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'

TEST_NAME="${TEST_NAME:-$(basename "$0" .sh)}"

header() {
    printf '%s\n' "${BOLD}== ${TEST_NAME}${OFF} - $1"
}

pass() {
    printf '%s\n' "${GREEN}PASS${OFF} ${TEST_NAME}${1:+ - $1}"
    exit 0
}

fail() {
    printf '%s\n' "${RED}FAIL${OFF} ${TEST_NAME} - $1" >&2
    [ -n "${2:-}" ] && printf '     %s\n' "$2" >&2
    exit 1
}

note() {
    printf '%s\n' "${YELLOW}note${OFF} $1"
}

# Load ~/.env so the tests work even when the login shell was not restarted.
load_env() {
    if [ -s "$HOME/.env" ]; then
        set -a
        # shellcheck disable=SC1091
        . "$HOME/.env"
        set +a
    fi
}

require_gateway() {
    load_env
    [ -n "${LLM_PROXY_URL:-}" ] || fail "LLM_PROXY_URL is not set" \
        "Run: sudo simbox-configure"
    [ -n "${LLM_PROXY_KEY:-}" ] || fail "LLM_PROXY_KEY is not set" \
        "Run: sudo simbox-configure"
}

# Both single-agent tests ask the same question: a multiplication no cache or
# error page can produce, plus a fact, so a wrong model is obvious too.
QUESTION="Rechne 17*23 und nenne die Hauptstadt von Kroatien."

check_answer() {
    local out="$1"
    printf '%s' "$out" | grep -q '391' || return 1
    printf '%s' "$out" | grep -qi 'zagreb' || return 1
    return 0
}

list_models_hint() {
    printf '%s\n' \
      "List the aliases the gateway really serves with:" \
      "  curl -s -H \"Authorization: Bearer \$LLM_PROXY_KEY\" \$LLM_PROXY_URL/models | jq -r '.data[].id'"
}
