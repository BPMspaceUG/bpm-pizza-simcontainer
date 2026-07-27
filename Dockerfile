# =============================================================================
# BPM Pizza Sim Container - WSL base image
#
# Built as a Docker image, then converted to a WSL distro via `docker export`.
# NOTE: `docker export` only keeps the filesystem. ENV / CMD / ENTRYPOINT /
# WORKDIR are dropped, so all environment setup lives in /etc/profile.d/.
# =============================================================================

FROM debian:trixie-slim

ARG USERNAME=robert
ARG NODE_MAJOR=22

ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Base packages
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        jq \
        zip \
        unzip \
        gnupg \
        sudo \
        less \
        nano \
        ripgrep \
        build-essential \
        python3 \
        python3-venv \
        python3-pip \
        openssh-client \
        locales \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen

# -----------------------------------------------------------------------------
# Node.js (required by both Claude Code and Codex CLI)
# -----------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Coding agents
# Not apt packages - both ship via npm.
# -----------------------------------------------------------------------------
RUN npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
    && npm cache clean --force

# -----------------------------------------------------------------------------
# User: passwordless login, passwordless sudo
# -----------------------------------------------------------------------------
RUN useradd -m -s /bin/bash -G sudo ${USERNAME} \
    && passwd -d ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${USERNAME} \
    && chmod 0440 /etc/sudoers.d/90-${USERNAME}

# -----------------------------------------------------------------------------
# System files (WSL config, shell environment, bootstrap helper)
# -----------------------------------------------------------------------------
COPY wsl.conf /etc/wsl.conf
COPY files/profile.d/devbox.sh /etc/profile.d/devbox.sh
COPY files/bootstrap.sh /usr/local/bin/devbox-bootstrap
COPY files/codex-config.toml /etc/skel/.codex/config.toml

RUN chmod 0644 /etc/profile.d/devbox.sh \
    && chmod 0755 /usr/local/bin/devbox-bootstrap

# -----------------------------------------------------------------------------
# Project checkouts
# -----------------------------------------------------------------------------
USER ${USERNAME}
WORKDIR /home/${USERNAME}

RUN mkdir -p projects .codex .claude \
    && cp /etc/skel/.codex/config.toml .codex/config.toml \
    && git clone --depth 1 https://github.com/BPMspaceUG/bpm-pizza-ml.git         projects/bpm-pizza-ml \
    && git clone --depth 1 https://github.com/BPMspaceUG/bpm-pizza-vibecoding.git projects/bpm-pizza-vibecoding

# Restore full history so the repos are actually usable for development
RUN git -C projects/bpm-pizza-ml         fetch --unshallow || true \
    && git -C projects/bpm-pizza-vibecoding fetch --unshallow || true

USER root
