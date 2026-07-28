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
    [ -n "${LITELLM_PIZZA_URL:-}" ] || fail "LITELLM_PIZZA_URL is not set" \
        "Run: sudo simbox-configure"
    [ -n "${LITELLM_PIZZA_KEY:-}" ] || fail "LITELLM_PIZZA_KEY is not set" \
        "Run: sudo simbox-configure"
}

# ---------------------------------------------------------------------------
# The connectivity probe.
#
# A fresh random token per run. Only a model that actually generated a reply
# can return it - no cache, no error page, no stale output can.
#
# Deliberately NOT an arithmetic question: that measures whether the model can
# do maths, not whether the pipeline works. Kimi K2.5 gets 17*23 wrong, which
# would have failed this test on a perfectly healthy gateway.
# ---------------------------------------------------------------------------
NONCE="PIZZA-$(tr -dc 'A-Z0-9' < /dev/urandom | head -c 10)"
QUESTION="Antworte ausschliesslich mit dieser Zeichenkette, ohne jeden Zusatz: ${NONCE}"

check_answer() {
    printf '%s' "$1" | grep -qF "$NONCE"
}

list_models_hint() {
    printf '%s\n' \
      "List the aliases the gateway really serves with:" \
      "  curl -s -H \"Authorization: Bearer \$LITELLM_PIZZA_KEY\" \$LITELLM_PIZZA_URL/models | jq -r '.data[].id'"
}
