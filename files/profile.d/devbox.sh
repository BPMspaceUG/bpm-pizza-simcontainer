# Loaded for every login shell.
# This replaces the Dockerfile ENV directives, which `docker export` discards.

export LANG=en_US.UTF-8
export EDITOR=nano
export PATH="$HOME/.local/bin:$PATH"

# Project secrets, placed by devbox-bootstrap
if [ -f "$HOME/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.env"
    set +a
fi

# ---------------------------------------------------------------------------
# Claude Code -> OpenRouter (Anthropic-compatible endpoint)
# ---------------------------------------------------------------------------
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
export ANTHROPIC_AUTH_TOKEN="${OPENROUTER_API_KEY:-}"
export ANTHROPIC_API_KEY=""          # must be explicitly empty
export ANTHROPIC_MODEL="moonshotai/kimi-k3"
export ANTHROPIC_SMALL_FAST_MODEL="moonshotai/kimi-k3"

# ---------------------------------------------------------------------------
# Codex CLI -> OpenRouter (see ~/.codex/config.toml for the provider block)
# ---------------------------------------------------------------------------
# OPENROUTER_API_KEY comes from ~/.env and is read via env_key in config.toml

# No cd: the login shell stays in $HOME, where the project repos live.
