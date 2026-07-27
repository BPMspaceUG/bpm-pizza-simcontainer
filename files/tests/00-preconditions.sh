#!/usr/bin/env bash
# Gateway reachable, key present, .env complete.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="00-preconditions"
header "gateway settings and .env"

require_gateway

entries=$(grep -c '=' "$HOME/.env" 2>/dev/null || echo 0)
printf '  gateway : %s\n' "$LLM_PROXY_URL"
printf '  key     : %s...\n' "$(printf '%s' "$LLM_PROXY_KEY" | head -c 12)"
printf '  .env    : %s entries\n' "$entries"

case "$LLM_PROXY_KEY" in
    *\ *) fail "LLM_PROXY_KEY contains a space" \
               "Quote the value in the .env, otherwise it is cut off at the space." ;;
esac

code=$(curl -s -o /dev/null -w '%{http_code}' \
       -H "Authorization: Bearer $LLM_PROXY_KEY" \
       "$LLM_PROXY_URL/models")

case "$code" in
    200) ;;
    401|403) fail "gateway rejected the key (HTTP $code)" ;;
    000)     fail "gateway not reachable at $LLM_PROXY_URL" ;;
    *)       fail "unexpected response from the gateway (HTTP $code)" ;;
esac

for var in CLAUDE_MODEL CODEX_MODEL; do
    if [ -z "$(eval printf '%s' "\${${var}:-}")" ]; then
        note "$var not set in .env - the image default is used"
    fi
done

pass "gateway answers, key accepted"
