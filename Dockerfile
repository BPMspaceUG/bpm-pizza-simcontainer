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
# bubblewrap is what Codex uses for sandboxing; without it Codex warns on every
# start. xxd is used by the audio test to check the mp3 header.
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        jq \
        xxd \
        zip \
        unzip \
        gnupg \
        sudo \
        less \
        nano \
        ripgrep \
        bubblewrap \
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
# System files and the three simbox commands:
#   update-simbox      .env, apt, agents, repos, then the tests
#   configure-simbox   fetch the .env and rewrite the agent configs
#   test-simbox        the acceptance tests
#
# ~/.codex/config.toml is not copied here - configure-simbox generates it,
# because the gateway base URL is only known once the .env is in place.
# -----------------------------------------------------------------------------
COPY wsl.conf /etc/wsl.conf
COPY files/profile.d/devbox.sh /etc/profile.d/simbox.sh
COPY files/bootstrap.sh /usr/local/bin/configure-simbox
COPY files/update.sh /usr/local/bin/update-simbox

RUN chmod 0644 /etc/profile.d/simbox.sh \
    && chmod 0755 /usr/local/bin/configure-simbox /usr/local/bin/update-simbox

# -----------------------------------------------------------------------------
# Acceptance tests in ~/tests, next to ~/projects.
# -----------------------------------------------------------------------------
COPY --chown=${USERNAME}:${USERNAME} files/tests /home/${USERNAME}/tests
RUN chmod 0755 /home/${USERNAME}/tests/*.sh \
    && ln -sf /home/${USERNAME}/tests/run-all.sh /usr/local/bin/test-simbox

# -----------------------------------------------------------------------------
# Project checkouts under ~/projects - this is the layout the recorded
# exercise videos show, so it stays.
#
# No error suppression here: if a clone fails there is no point in producing
# an image at all.
#
# Shallow on purpose: the datasets make full history expensive, and the rootfs
# has to stay under the 2 GB release asset limit.
# -----------------------------------------------------------------------------
USER ${USERNAME}
WORKDIR /home/${USERNAME}

RUN mkdir -p projects .codex .claude \
    && git clone --depth 1 https://github.com/BPMspaceUG/bpm-pizza-ml.git         projects/bpm-pizza-ml \
    && git clone --depth 1 https://github.com/BPMspaceUG/bpm-pizza-vibecoding.git projects/bpm-pizza-vibecoding

# Verify both checkouts really landed before anything else depends on them.
RUN test -d projects/bpm-pizza-ml/.git \
    && test -d projects/bpm-pizza-vibecoding/.git \
    && test -f projects/bpm-pizza-ml/check_environment.py

# Only the chmod may fail harmlessly - a repo without .sh files is fine.
RUN chmod +x projects/bpm-pizza-ml/*.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# Exercise environment: PyTorch venv inside bpm-pizza-ml
#
# The exercises expect exactly this:
#     cd bpm-pizza-ml && source .venv/bin/activate && python3 check_environment.py
#
# CPU-only wheels on purpose - the CUDA build is several GB and useless on
# a training laptop.
# -----------------------------------------------------------------------------
WORKDIR /home/${USERNAME}/projects/bpm-pizza-ml

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
