#!/usr/bin/env bash
# Claude Code alone: proves /v1/messages and the CLAUDE_MODEL alias.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="01-claude"
header "Claude Code against the gateway"

require_gateway

out=$(claude -p "$QUESTION" 2>&1)
printf '%s\n' "$out" | sed 's/^/  /'

if printf '%s' "$out" | grep -qi 'no healthy deployments\|model not found\|BadRequestError'; then
    list_models_hint
    fail "the gateway does not know the configured model" \
         "Set CLAUDE_MODEL in the .env, then run: sudo simbox-configure"
fi

if printf '%s' "$out" | grep -qi 'API Error\|401\|403'; then
    fail "the gateway refused the request"
fi

check_answer "$out" || fail "the reply did not contain the token ${NONCE}"

pass "/v1/messages works, model alias resolves"
