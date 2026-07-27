#!/usr/bin/env bash
# =============================================================================
# devbox-bootstrap
#
# Runs after `wsl --import`. Fetches the .env from the protected endpoint and
# materialises the agent configs from it.
#
# Missing or unreachable credentials are NOT fatal: the distro stays usable,
# an empty .env is written, and the agents are configured but unauthenticated.
# Rerun this script later to fill it in.
#
# Usage:  devbox-bootstrap <user:password>
#         devbox-bootstrap            (reads DEVBOX_BASICAUTH, or skips fetch)
# =============================================================================
set -uo pipefail

ENV_URL="https://www.aipizzasim.com/getenv"
TARGET_USER="${SUDO_USER:-${USER:-robert}}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
ENV_FILE="${HOME_DIR}/.env"

BASICAUTH="${1:-${DEVBOX_BASICAUTH:-}}"

fetch_ok=0

if [ -z "$BASICAUTH" ]; then
    echo ">>> no credentials given - skipping .env fetch"
else
    echo ">>> fetching .env from ${ENV_URL}"
    # credentials go in via stdin so they never appear in the process list
    if printf '%s' "$BASICAUTH" \
        | curl -fsSL --retry 2 --retry-delay 2 \
               --config <(echo 'user = "@-"') \
               -o "$ENV_FILE.tmp" "$ENV_URL" 2>/dev/null \
       || curl -fsSL --retry 2 --retry-delay 2 \
               -u "$BASICAUTH" -o "$ENV_FILE.tmp" "$ENV_URL"
    then
        mv "$ENV_FILE.tmp" "$ENV_FILE"
        fetch_ok=1
        echo ">>> .env retrieved"
    else
        rm -f "$ENV_FILE.tmp"
        echo "!!! could not fetch .env (endpoint down, or wrong credentials)" >&2
        echo "!!! continuing with an empty .env" >&2
    fi
fi

[ -f "$ENV_FILE" ] || : > "$ENV_FILE"
chown "$TARGET_USER:$TARGET_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ---------------------------------------------------------------------------
# Read the OpenRouter key out of the .env, if there is one
# ---------------------------------------------------------------------------
set -a
# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null || true
set +a

# ---------------------------------------------------------------------------
# Claude Code -> OpenRouter, backed by Kimi K3
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/.claude"
cat > "${HOME_DIR}/.claude/settings.json" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://openrouter.ai/api",
    "ANTHROPIC_AUTH_TOKEN": "${OPENROUTER_API_KEY:-}",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "moonshotai/kimi-k3",
    "ANTHROPIC_SMALL_FAST_MODEL": "moonshotai/kimi-k3"
  },
  "hasCompletedOnboarding": true
}
EOF

# ---------------------------------------------------------------------------
# Codex CLI -> OpenRouter, backed by GLM 5.2
# config.toml ships in the image and reads OPENROUTER_API_KEY from the env
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/.codex"
if [ ! -f "${HOME_DIR}/.codex/config.toml" ]; then
    cp /etc/skel/.codex/config.toml "${HOME_DIR}/.codex/config.toml"
fi

chown -R "$TARGET_USER:$TARGET_USER" "${HOME_DIR}/.claude" "${HOME_DIR}/.codex"

echo ">>> bootstrap complete"
if [ "$fetch_ok" = "1" ] && [ -n "${OPENROUTER_API_KEY:-}" ]; then
    echo "    claude -> moonshotai/kimi-k3  via OpenRouter"
    echo "    codex  -> z-ai/glm-5.2        via OpenRouter"
else
    echo "    NOTE: no OPENROUTER_API_KEY yet - the agents will not authenticate."
    echo "    Fill it in later with:  sudo devbox-bootstrap user:password"
fi

exit 0
