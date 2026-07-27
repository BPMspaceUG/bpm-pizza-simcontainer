#!/usr/bin/env bash
# =============================================================================
# devbox-bootstrap
#
# Runs once after `wsl --import`. Fetches the .env from the protected endpoint
# and materialises the agent configs from it.
#
# Usage:  devbox-bootstrap <user:password>
#         devbox-bootstrap            (reads DEVBOX_BASICAUTH from environment)
# =============================================================================
set -euo pipefail

ENV_URL="https://www.aipizzasim.com/getenv"
TARGET_USER="${SUDO_USER:-${USER:-robert}}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
ENV_FILE="${HOME_DIR}/.env"
STAMP="${HOME_DIR}/.devbox-bootstrapped"

BASICAUTH="${1:-${DEVBOX_BASICAUTH:-}}"

if [ -z "$BASICAUTH" ]; then
    echo "usage: devbox-bootstrap <user:password>" >&2
    exit 2
fi

echo ">>> fetching .env from ${ENV_URL}"
curl -fsSL --retry 3 --retry-delay 2 \
     -u "$BASICAUTH" \
     -o "$ENV_FILE" \
     "$ENV_URL"

chown "$TARGET_USER:$TARGET_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ---------------------------------------------------------------------------
# Read the OpenRouter key out of the freshly fetched .env
# ---------------------------------------------------------------------------
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo "!!! OPENROUTER_API_KEY not present in .env - agents will not authenticate" >&2
fi

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
# config.toml ships in the image; it reads OPENROUTER_API_KEY from the env
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/.codex"
if [ ! -f "${HOME_DIR}/.codex/config.toml" ]; then
    cp /etc/skel/.codex/config.toml "${HOME_DIR}/.codex/config.toml"
fi

chown -R "$TARGET_USER:$TARGET_USER" "${HOME_DIR}/.claude" "${HOME_DIR}/.codex"

date -Iseconds > "$STAMP"
chown "$TARGET_USER:$TARGET_USER" "$STAMP"

echo ">>> bootstrap complete"
echo "    claude -> moonshotai/kimi-k3  via OpenRouter"
echo "    codex  -> z-ai/glm-5.2        via OpenRouter"
