# =============================================================================
# BPM Pizza Sim Container - WSL base image
#
# Built as a Docker image, then converted to a WSL distro via `docker export`.
# NOTE: `docker export` only keeps the filesystem. ENV / CMD / ENTRYPOINT /
# WORKDIR are dropped, so all environment setup lives in /etc/profile.d/.
# =============================================================================

FROM debian:trixie-slim

ARG USERNAME=roberto
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

RUN chmod 0644 /etc/profile.d/devbox.sh \
    && chmod 0755 /usr/local/bin/devbox-bootstrap

# -----------------------------------------------------------------------------
# Project checkouts - directly in $HOME, so `cd bpm-pizza-ml` works on login.
# Shallow on purpose: the datasets make full history expensive, and the rootfs
# has to stay under the 2 GB release asset limit.
# -----------------------------------------------------------------------------
USER ${USERNAME}
WORKDIR /home/${USERNAME}

RUN mkdir -p .codex .claude \
    && git clone --depth 1 https://github.com/BPMspaceUG/bpm-pizza-ml.git         bpm-pizza-ml \
    && git clone --depth 1 https://github.com/BPMspaceUG/bpm-pizza-vibecoding.git bpm-pizza-vibecoding \
    && chmod +x bpm-pizza-ml/*.sh || true

# -----------------------------------------------------------------------------
# Exercise environment: PyTorch venv inside bpm-pizza-ml
#
# The exercises expect exactly this:
#     cd bpm-pizza-ml && source .venv/bin/activate && python3 check_environment.py
#
# CPU-only wheels on purpose - the CUDA build is several GB and useless on
# a training laptop.
# -----------------------------------------------------------------------------
WORKDIR /home/${USERNAME}/bpm-pizza-ml

RUN python3 -m venv .venv \
    && .venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
    && .venv/bin/pip install --no-cache-dir \
         --index-url https://download.pytorch.org/whl/cpu \
         torch torchvision \
    && .venv/bin/pip install --no-cache-dir tqdm pillow \
    && find .venv -name '__pycache__' -type d -prune -exec rm -rf {} + \
    && find .venv -name '*.pyc' -delete

# Fail the build if the exercise environment is not actually usable,
# so a broken image never reaches the training room.
RUN .venv/bin/python check_environment.py

WORKDIR /home/${USERNAME}
USER root
