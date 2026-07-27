#!/usr/bin/env bash
# =============================================================================
# devbox-bootstrap
#
# Puts a .env in place and materialises the agent configs from it.
#
# Sources, in order of precedence:
#   --stdin            read the .env from standard input
#   --file PATH        copy from a path inside the distro (e.g. /mnt/c/sim/.env)
#   --url  URL         fetch from that URL (basic auth optional)
#   <user:password>    fetch from the default endpoint with basic auth
#
# Equivalent environment variables: DEVBOX_ENV_FILE, DEVBOX_ENV_URL,
# DEVBOX_BASICAUTH.
#
# --url works with or without credentials: pass user:password as well if the
# endpoint is protected, leave it out if it is open.
#
# Nothing here is fatal. Without a usable source an empty .env is written and
# the distro stays usable; rerun this script later to fill it in.
#
# Usage:
#   devbox-bootstrap user:password
#   devbox-bootstrap --url https://example.com/path/pizza.env
#   devbox-bootstrap user:password --url https://staging.example.com/getenv
#   devbox-bootstrap --file /mnt/c/sim/pizza.env
#   cat pizza.env | devbox-bootstrap --stdin
# =============================================================================
set -uo pipefail

DEFAULT_ENV_URL="https://www.aipizzasim.com/getenv"

TARGET_USER="${SUDO_USER:-${USER:-robert}}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
ENV_FILE="${HOME_DIR}/.env"
TMP_FILE="${ENV_FILE}.tmp"

BASICAUTH="${DEVBOX_BASICAUTH:-}"
ENV_URL="${DEVBOX_ENV_URL:-}"
ENV_SRC="${DEVBOX_ENV_FILE:-}"
FROM_STDIN=0

usage() {
    sed -n '3,28p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --stdin)    FROM_STDIN=1; shift ;;
        --file)     ENV_SRC="${2:-}"; shift 2 ;;
        --url)      ENV_URL="${2:-}"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        --)         shift ;;
        *)          BASICAUTH="$1"; shift ;;
    esac
done

got_env=0

if [ "$FROM_STDIN" = "1" ]; then
    echo ">>> reading .env from stdin"
    if cat > "$TMP_FILE" && [ -s "$TMP_FILE" ]; then
        got_env=1
    else
        echo "!!! nothing arrived on stdin" >&2
    fi

elif [ -n "$ENV_SRC" ]; then
    echo ">>> copying .env from ${ENV_SRC}"
    if cp "$ENV_SRC" "$TMP_FILE" 2>/dev/null && [ -s "$TMP_FILE" ]; then
        got_env=1
    else
        echo "!!! could not read ${ENV_SRC}" >&2
    fi

elif [ -n "$ENV_URL" ] || [ -n "$BASICAUTH" ]; then
    # An explicit --url works on its own; without one we fall back to the
    # default endpoint, which does need credentials.
    [ -n "$ENV_URL" ] || ENV_URL="$DEFAULT_ENV_URL"

    echo ">>> fetching .env from ${ENV_URL}"
    if [ -n "$BASICAUTH" ]; then
        curl -fsSL --retry 2 --retry-delay 2 \
             -u "$BASICAUTH" -o "$TMP_FILE" "$ENV_URL"
    else
        curl -fsSL --retry 2 --retry-delay 2 \
             -o "$TMP_FILE" "$ENV_URL"
    fi

    if [ $? -eq 0 ] && [ -s "$TMP_FILE" ]; then
        got_env=1
    else
        echo "!!! fetch failed (endpoint down, wrong credentials, or empty response)" >&2
    fi

else
    echo ">>> no .env source given - skipping"
fi

if [ "$got_env" = "1" ]; then
    mv "$TMP_FILE" "$ENV_FILE"
    echo ">>> .env in place"
else
    rm -f "$TMP_FILE"
    [ -f "$ENV_FILE" ] || : > "$ENV_FILE"
    echo "!!! continuing with an empty .env" >&2
fi

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
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    echo "    claude -> moonshotai/kimi-k3  via OpenRouter"
    echo "    codex  -> z-ai/glm-5.2        via OpenRouter"
else
    echo "    NOTE: no OPENROUTER_API_KEY yet - the agents will not authenticate."
    echo "    Fill it in later with:  sudo devbox-bootstrap user:password"
fi

exit 0
