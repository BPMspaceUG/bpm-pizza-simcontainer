#!/usr/bin/env bash
# Gateway reachable, key present, .env complete.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="00-preconditions"
header "gateway settings and .env"

# The .env itself, before anything that depends on it: a missing file must name
# itself, not surface later as an unset variable (#3).
[ -s "$HOME/.env" ] || fail "no ~/.env - this machine was never configured" \
    "Run: sudo simbox-configure"

require_gateway

entries=$(grep -c '=' "$HOME/.env" 2>/dev/null || echo 0)
printf '  gateway : %s\n' "$LITELLM_PIZZA_URL"
printf '  key     : %s...\n' "$(printf '%s' "$LITELLM_PIZZA_KEY" | head -c 12)"
printf '  .env    : %s entries\n' "$entries"

case "$LITELLM_PIZZA_KEY" in
    *\ *) fail "LITELLM_PIZZA_KEY contains a space" \
               "Quote the value in the .env, otherwise it is cut off at the space." ;;
esac

code=$(curl -s -o /dev/null -w '%{http_code}' \
       -H "Authorization: Bearer $LITELLM_PIZZA_KEY" \
       "$LITELLM_PIZZA_URL/models")

case "$code" in
    200) ;;
    401|403) fail "gateway rejected the key (HTTP $code)" ;;
    000)     fail "gateway not reachable at $LITELLM_PIZZA_URL" ;;
    *)       fail "unexpected response from the gateway (HTTP $code)" ;;
esac

for var in CLAUDE_MODEL CODEX_MODEL; do
    if [ -z "$(eval printf '%s' "\${${var}:-}")" ]; then
        note "$var not set in .env - the image default is used"
    fi
done

pass "gateway answers, key accepted"
