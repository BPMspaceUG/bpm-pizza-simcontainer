#!/usr/bin/env bash
# Codex alone: proves /v1/responses and the CODEX_MODEL alias.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="02-codex"
header "Codex CLI against the gateway"

require_gateway

out=$(codex exec --skip-git-repo-check --sandbox read-only "$QUESTION" 2>&1)
printf '%s\n' "$out" | sed 's/^/  /'

# Expected and harmless: Codex has no metadata for gateway aliases.
if printf '%s' "$out" | grep -qi 'Model metadata for.*not found'; then
    note "missing model metadata is expected for a gateway alias"
fi

if printf '%s' "$out" | grep -qi 'no healthy deployments\|BadRequestError'; then
    list_models_hint
    fail "the gateway does not know the configured model" \
         "Set CODEX_MODEL in the .env, then rerun devbox-bootstrap."
fi

if printf '%s' "$out" | grep -qi 'wire_api\|is no longer supported'; then
    fail "Codex refused the config" \
         "wire_api must be \"responses\" - rerun devbox-bootstrap."
fi

if printf '%s' "$out" | grep -qi '404\|405\|not implemented'; then
    fail "the gateway does not serve /v1/responses" \
         "Enable the Responses API on LiteLLM - Codex no longer supports chat."
fi

check_answer "$out" || fail "unexpected answer - expected 391 and Zagreb"

pass "/v1/responses works, model alias resolves"
