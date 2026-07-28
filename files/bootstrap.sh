#!/usr/bin/env bash
# =============================================================================
# devbox-bootstrap
#
# Puts a .env in place and wires both coding agents to whatever gateway it
# describes.
#
# Called without arguments it refreshes the .env from wherever it came from
# last, so updating a changed file on the CDN is just:
#
#     sudo devbox-bootstrap
#
# Expected keys (LiteLLM gateway, OpenAI-compatible):
#   LLM_PROXY_URL   e.g. https://litellm.aipizzasim.com/v1
#   LLM_PROXY_KEY   the participant-facing key; the real upstream key stays
#                   on the gateway and is never handed out
# Optional:
#   ENV_SELF_URL    where this very file lives. Set it and the machines will
#                   follow the file if it ever moves to a different URL.
#   CLAUDE_MODEL    model alias for Claude Code
#   CODEX_MODEL     model alias for Codex CLI
#   CODEX_WIRE_API  responses | chat              (default: responses)
#   CLAUDE_THEME    dark | light | dark-ansi ...  (default: dark)
#
# Model aliases must match what the gateway actually serves. List them with:
#   curl -s -H "Authorization: Bearer $LLM_PROXY_KEY" $LLM_PROXY_URL/models \
#     | jq -r '.data[].id'
#
# Sources, in order of precedence:
#   --stdin            read from standard input
#   --file PATH        copy from a path inside the distro
#   --url  URL         fetch from that URL (basic auth optional)
#   <user:password>    fetch from the default endpoint with basic auth
#   (nothing)          ENV_SELF_URL from the current .env, else the URL
#                      remembered from the last successful run
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
STATE_DIR="/etc/devbox"
STATE_FILE="${STATE_DIR}/env-source"

# Verified against the gateway on 2026-07-27. The bare names kimi-k3 and
# glm-5.2 do not exist there; every alias carries the openrouter/ prefix.
DEFAULT_CLAUDE_MODEL="openrouter/moonshotai/kimi-k2.5"
DEFAULT_CODEX_MODEL="openrouter/z-ai/glm-5.1"

BASICAUTH="${DEVBOX_BASICAUTH:-}"
ENV_URL="${DEVBOX_ENV_URL:-}"
ENV_SRC="${DEVBOX_ENV_FILE:-}"
TARGET_USER="${DEVBOX_USER:-}"
FROM_STDIN=0
EXPLICIT_SOURCE=0

usage() {
    sed -n '3,41p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --stdin)    FROM_STDIN=1; EXPLICIT_SOURCE=1; shift ;;
        --file)     ENV_SRC="${2:-}"; EXPLICIT_SOURCE=1; shift 2 ;;
        --url)      ENV_URL="${2:-}"; EXPLICIT_SOURCE=1; shift 2 ;;
        --user)     TARGET_USER="${2:-}"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        --)         shift ;;
        *)          BASICAUTH="$1"; EXPLICIT_SOURCE=1; shift ;;
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

# ---------------------------------------------------------------------------
# No source given: fall back to where the .env came from before.
# ENV_SELF_URL inside the file wins, so moving the file to a new URL only has
# to be announced once, in the old file.
# ---------------------------------------------------------------------------
if [ "$EXPLICIT_SOURCE" = "0" ]; then
    remembered=""
    if [ -s "$ENV_FILE" ]; then
        remembered=$(grep -m1 '^[[:space:]]*ENV_SELF_URL=' "$ENV_FILE" 2>/dev/null \
                     | cut -d= -f2- | tr -d '"'"'"' \r')
    fi
    if [ -z "$remembered" ] && [ -r "$STATE_FILE" ]; then
        remembered=$(head -n1 "$STATE_FILE" 2>/dev/null | tr -d ' \r')
    fi
    if [ -n "$remembered" ]; then
        ENV_URL="$remembered"
        echo ">>> no source given - refreshing from the remembered URL"
    fi
fi

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
used_url=""

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
        echo "!!! fetch failed (curl exit $rc) - endpoint down or wrong URL" >&2
    elif [ ! -s "$TMP_FILE" ]; then
        echo "!!! endpoint returned an empty body" >&2
    else
        got_env=1
        used_url="$ENV_URL"
    fi

else
    echo ">>> no .env source given and none remembered - skipping"
    echo "    Provide one once with:  sudo devbox-bootstrap --url <url>"
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
    # Remember the URL so a later bare run can refresh without arguments.
    if [ -n "$used_url" ] && [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$STATE_DIR" 2>/dev/null \
            && printf '%s\n' "$used_url" > "$STATE_FILE" 2>/dev/null \
            && chmod 0644 "$STATE_FILE" 2>/dev/null
    fi
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

CLAUDE_MODEL_NAME="${CLAUDE_MODEL:-$DEFAULT_CLAUDE_MODEL}"
CODEX_MODEL_NAME="${CODEX_MODEL:-$DEFAULT_CODEX_MODEL}"
# Codex rejects wire_api = "chat" outright since the chat protocol was
# retired, so "responses" is the only workable default.
CODEX_WIRE="${CODEX_WIRE_API:-responses}"
CLAUDE_THEME_NAME="${CLAUDE_THEME:-dark}"

# If the file names its own location, that becomes the new remembered source.
if [ -n "${ENV_SELF_URL:-}" ] && [ "$(id -u)" -eq 0 ]; then
    mkdir -p "$STATE_DIR" 2>/dev/null \
        && printf '%s\n' "$ENV_SELF_URL" > "$STATE_FILE" 2>/dev/null \
        && chmod 0644 "$STATE_FILE" 2>/dev/null
fi

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
  }
}
EOF

# The first-run wizard (theme picker, tips) is driven by ~/.claude.json, not by
# settings.json. Pre-seed it so participants land straight in the prompt.
CLAUDE_JSON="${HOME_DIR}/.claude.json"
if [ -s "$CLAUDE_JSON" ] && jq -e . "$CLAUDE_JSON" >/dev/null 2>&1; then
    _tmp="$(mktemp)"
    jq --arg t "$CLAUDE_THEME_NAME" \
       '. + {hasCompletedOnboarding: true, theme: $t, hasUsedBackslashReturn: true}' \
       "$CLAUDE_JSON" > "$_tmp" && mv "$_tmp" "$CLAUDE_JSON"
    rm -f "$_tmp"
else
    cat > "$CLAUDE_JSON" <<EOF
{
  "hasCompletedOnboarding": true,
  "theme": "${CLAUDE_THEME_NAME}",
  "hasUsedBackslashReturn": true
}
EOF
fi

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

chown "$TARGET_USER:$TARGET_USER" "$CLAUDE_JSON"
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
