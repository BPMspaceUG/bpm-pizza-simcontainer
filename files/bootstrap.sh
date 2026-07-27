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

# A static host answering 200 with an HTML 404 page is the classic silent
# failure here: curl is happy, the .env is garbage. Reject that.
looks_like_env() {
    local f="$1"
    [ -s "$f" ] || return 1
    if head -c 512 "$f" | grep -qiE '<!doctype html|<html|<head|<body'; then
        return 1
    fi
    grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$f"
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
    rc=$?

    if [ $rc -ne 0 ]; then
        echo "!!! fetch failed (curl exit $rc) - endpoint down or wrong credentials" >&2
    elif [ ! -s "$TMP_FILE" ]; then
        echo "!!! endpoint returned an empty body" >&2
    else
        got_env=1
    fi

else
    echo ">>> no .env source given - skipping"
fi

# Reject anything that clearly is not an env file, whatever the source.
if [ "$got_env" = "1" ] && ! looks_like_env "$TMP_FILE"; then
    echo "!!! the response does not look like an .env file:" >&2
    head -c 200 "$TMP_FILE" | sed 's/^/    /' >&2
    echo "" >&2
    echo "!!! check the URL - a static host often answers 404 pages with status 200" >&2
    got_env=0
fi

if [ "$got_env" = "1" ]; then
    mv "$TMP_FILE" "$ENV_FILE"
    echo ">>> .env in place at ${ENV_FILE} ($(grep -c '=' "$ENV_FILE") entries)"
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
    exit 0
else
    echo "    NOTE: no OPENROUTER_API_KEY in ${ENV_FILE} - the agents will not authenticate."
    echo "    Retry with:  sudo devbox-bootstrap --url <url>"
    # Non-zero so the caller can see it went wrong, but only after everything
    # else has been written - the distro stays usable either way.
    exit 3
fi
