#!/usr/bin/env bash
# =============================================================================
# devbox-bootstrap
#
# Puts a .env in place and wires both coding agents to whatever gateway it
# describes.
#
# Expected keys (LiteLLM gateway, OpenAI-compatible):
#   LLM_PROXY_URL   e.g. https://litellm.aipizzasim.com/v1
#   LLM_PROXY_KEY   the participant-facing key; the real upstream key stays
#                   on the gateway and is never handed out
# Optional overrides:
#   CLAUDE_MODEL    model alias for Claude Code   (default: kimi-k3)
#   CODEX_MODEL     model alias for Codex CLI     (default: glm-5.2)
#   CODEX_WIRE_API  chat | responses              (default: chat)
#
# Sources for the .env, in order of precedence:
#   --stdin            read from standard input
#   --file PATH        copy from a path inside the distro
#   --url  URL         fetch from that URL (basic auth optional)
#   <user:password>    fetch from the default endpoint with basic auth
#
# Equivalent environment variables: DEVBOX_ENV_FILE, DEVBOX_ENV_URL,
# DEVBOX_BASICAUTH. The target account can be set with DEVBOX_USER or --user.
#
# Nothing here is fatal. Without a usable source an empty .env is written and
# the distro stays usable; rerun this script later to fill it in.
# =============================================================================
set -uo pipefail

DEFAULT_ENV_URL="https://www.aipizzasim.com/getenv"
DEFAULT_USER="roberto"

BASICAUTH="${DEVBOX_BASICAUTH:-}"
ENV_URL="${DEVBOX_ENV_URL:-}"
ENV_SRC="${DEVBOX_ENV_FILE:-}"
TARGET_USER="${DEVBOX_USER:-}"
FROM_STDIN=0

usage() {
    sed -n '3,32p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --stdin)    FROM_STDIN=1; shift ;;
        --file)     ENV_SRC="${2:-}"; shift 2 ;;
        --url)      ENV_URL="${2:-}"; shift 2 ;;
        --user)     TARGET_USER="${2:-}"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        --)         shift ;;
        *)          BASICAUTH="$1"; shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve the target account. This must never resolve to root: `wsl -u root -e`
# leaves SUDO_USER unset and USER set to root.
# ---------------------------------------------------------------------------
if [ -z "$TARGET_USER" ]; then
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        TARGET_USER="$SUDO_USER"
    elif [ "$(id -u)" -ne 0 ]; then
        TARGET_USER="$(id -un)"
    else
        TARGET_USER="$DEFAULT_USER"
    fi
fi

if ! getent passwd "$TARGET_USER" >/dev/null; then
    echo "!!! no such user: ${TARGET_USER}" >&2
    exit 2
fi

HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
ENV_FILE="${HOME_DIR}/.env"
TMP_FILE="${ENV_FILE}.tmp"

echo ">>> configuring for user ${TARGET_USER} (${HOME_DIR})"

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

if [ "$got_env" = "1" ] && ! looks_like_env "$TMP_FILE"; then
    echo "!!! the response does not look like an .env file:" >&2
    head -c 200 "$TMP_FILE" | sed 's/^/    /' >&2
    echo "" >&2
    echo "!!! check the URL - a static host often answers 404 pages with status 200" >&2
    got_env=0
fi

if [ "$got_env" = "1" ]; then
    mv "$TMP_FILE" "$ENV_FILE"
    echo ">>> .env written to ${ENV_FILE} ($(grep -c '=' "$ENV_FILE") entries)"
else
    rm -f "$TMP_FILE"
    [ -f "$ENV_FILE" ] || : > "$ENV_FILE"
    echo "!!! continuing with an empty ${ENV_FILE}" >&2
fi

chown "$TARGET_USER:$TARGET_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ---------------------------------------------------------------------------
# Read the gateway settings out of the .env
# ---------------------------------------------------------------------------
set -a
# shellcheck disable=SC1090
. "$ENV_FILE" 2>/dev/null || true
set +a

# OPENROUTER_* is accepted as a fallback for setups without the gateway.
PROXY_URL="${LLM_PROXY_URL:-}"
PROXY_KEY="${LLM_PROXY_KEY:-${OPENROUTER_API_KEY:-}}"
if [ -z "$PROXY_URL" ] && [ -n "${OPENROUTER_API_KEY:-}" ]; then
    PROXY_URL="https://openrouter.ai/api/v1"
fi

# Claude Code appends /v1/messages itself, so it needs the base without /v1.
ANTHROPIC_BASE="${PROXY_URL%/}"
ANTHROPIC_BASE="${ANTHROPIC_BASE%/v1}"

CLAUDE_MODEL_NAME="${CLAUDE_MODEL:-kimi-k3}"
CODEX_MODEL_NAME="${CODEX_MODEL:-glm-5.2}"
CODEX_WIRE="${CODEX_WIRE_API:-chat}"

# ---------------------------------------------------------------------------
# Claude Code -> gateway (Anthropic-compatible /v1/messages)
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/.claude"
cat > "${HOME_DIR}/.claude/settings.json" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "${ANTHROPIC_BASE}",
    "ANTHROPIC_AUTH_TOKEN": "${PROXY_KEY}",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "${CLAUDE_MODEL_NAME}",
    "ANTHROPIC_SMALL_FAST_MODEL": "${CLAUDE_MODEL_NAME}"
  },
  "hasCompletedOnboarding": true
}
EOF

# ---------------------------------------------------------------------------
# Codex CLI -> gateway (OpenAI-compatible)
# Written here rather than baked into the image, because the base URL only
# becomes known once the .env is in place.
# ---------------------------------------------------------------------------
mkdir -p "${HOME_DIR}/.codex"
cat > "${HOME_DIR}/.codex/config.toml" <<EOF
## Generated by devbox-bootstrap - edit ~/.env and rerun to change this.

model_provider = "gateway"
model = "${CODEX_MODEL_NAME}"
model_reasoning_effort = "high"

[model_providers.gateway]
name = "LLM gateway"
base_url = "${PROXY_URL}"
env_key = "LLM_PROXY_KEY"
wire_api = "${CODEX_WIRE}"
EOF

chown -R "$TARGET_USER:$TARGET_USER" "${HOME_DIR}/.claude" "${HOME_DIR}/.codex"

echo ">>> bootstrap complete"
if [ -n "$PROXY_KEY" ] && [ -n "$PROXY_URL" ]; then
    echo "    gateway : ${PROXY_URL}"
    echo "    claude  -> ${CLAUDE_MODEL_NAME}"
    echo "    codex   -> ${CODEX_MODEL_NAME} (${CODEX_WIRE})"
    exit 0
else
    echo "    NOTE: LLM_PROXY_URL / LLM_PROXY_KEY missing in ${ENV_FILE}."
    echo "    The agents will not authenticate. Retry with a valid .env."
    exit 3
fi
