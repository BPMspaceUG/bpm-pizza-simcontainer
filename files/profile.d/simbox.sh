# Loaded for every login shell.
# This replaces the Dockerfile ENV directives, which `docker export` discards.

export LANG=en_US.UTF-8
export EDITOR=nano
export PATH="$HOME/.local/bin:$PATH"

# Gateway settings and simulation credentials, placed by simbox-configure
if [ -f "$HOME/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.env"
    set +a
fi

# ---------------------------------------------------------------------------
# Claude Code -> LiteLLM gateway
#
# The gateway serves an Anthropic-compatible /v1/messages endpoint. Claude Code
# appends /v1/messages itself, so the trailing /v1 of LITELLM_PIZZA_URL is
# stripped. OPENROUTER_API_KEY is honoured as a fallback for setups without
# the gateway.
# ---------------------------------------------------------------------------
if [ -n "${LITELLM_PIZZA_URL:-}" ]; then
    _base="${LITELLM_PIZZA_URL%/}"
    export ANTHROPIC_BASE_URL="${_base%/v1}"
    export ANTHROPIC_AUTH_TOKEN="${LITELLM_PIZZA_KEY:-}"
    unset _base
elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
    export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
    export ANTHROPIC_AUTH_TOKEN="${OPENROUTER_API_KEY}"
fi

export ANTHROPIC_API_KEY=""          # must be explicitly empty
export ANTHROPIC_MODEL="${CLAUDE_MODEL:-openrouter/moonshotai/kimi-k2.5}"
export ANTHROPIC_SMALL_FAST_MODEL="${CLAUDE_MODEL:-openrouter/moonshotai/kimi-k2.5}"

# ---------------------------------------------------------------------------
# Codex CLI -> LiteLLM gateway
# ---------------------------------------------------------------------------
# The provider block lives in ~/.codex/config.toml and reads LITELLM_PIZZA_KEY,
# which the block above already exported from ~/.env.

_venv="$HOME/projects/bpm-pizza-ml/.venv"
[ -x "$_venv/bin/python3" ] && export PATH="$_venv/bin:$PATH"
unset _venv

# Start in the project directory - this is what the exercise videos show.
cd "$HOME/projects" 2>/dev/null || true
