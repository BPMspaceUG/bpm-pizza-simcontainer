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

# Exercise content is pinned to release tags, not to a moving branch: the
# exercise videos are recorded against these. Bump them here when a new
# release is cut - that is a deliberate decision, never a side effect.
ARG ML_REF=v1.0.1
ARG VIBE_REF=v1.0.0
ARG PII_REF=v1.0.0

ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Base packages
#
# bubblewrap is what Codex uses for sandboxing; without it Codex warns on every
# start. xxd came in for the audio test that #3 removed; it stays as general
# developer tooling, not because a test needs it.
#
# debian:trixie-slim omits the process and network tooling a developer expects,
# so agents that inspect a running system come up empty-handed:
#   procps    ps, top, free, kill
#   psmisc    killall, pstree, fuser
#   iproute2  ip, ss
#   lsof      open files and listening sockets
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
        procps \
        psmisc \
        iproute2 \
        lsof \
        build-essential \
        python3 \
        python3-venv \
        python3-pip \
        openssh-client \
        locales \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen

# Fail the build if any of the tools an exercise might reach for is missing.
RUN for c in ps top free kill killall pstree fuser ip ss lsof \
             git curl wget jq xxd zip unzip rg nano less; do \
        command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; \
    done

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
#   simbox-test        the acceptance tests - the normal step after an import
#   simbox-configure   fetch the .env and rewrite the agent configs
#   simbox-update      deliberately leave the tested state, trainer decision
#
# ~/.codex/config.toml is not copied here - simbox-configure generates it,
# because the gateway base URL is only known once the .env is in place.
# -----------------------------------------------------------------------------
COPY wsl.conf /etc/wsl.conf
COPY files/profile.d/simbox.sh /etc/profile.d/simbox.sh
COPY files/bootstrap.sh /usr/local/bin/simbox-configure
COPY files/update.sh /usr/local/bin/simbox-update

RUN chmod 0644 /etc/profile.d/simbox.sh \
    && chmod 0755 /usr/local/bin/simbox-configure /usr/local/bin/simbox-update

# Record what this image was pinned to, so the tests and simbox-update can
# tell whether a checkout still matches the state the videos were made against.
RUN mkdir -p /etc/simbox \
    && printf 'bpm-pizza-ml=%s\nbpm-pizza-vibecoding=%s\nbpm-pizza-pII=%s\n' "${ML_REF}" "${VIBE_REF}" "${PII_REF}" \
       > /etc/simbox/pinned-refs \
    && chmod 0644 /etc/simbox/pinned-refs

# -----------------------------------------------------------------------------
# Acceptance tests in ~/tests, next to ~/projects.
# -----------------------------------------------------------------------------
COPY --chown=${USERNAME}:${USERNAME} files/tests /home/${USERNAME}/tests
RUN chmod 0755 /home/${USERNAME}/tests/*.sh \
    && ln -sf /home/${USERNAME}/tests/run-all.sh /usr/local/bin/simbox-test

# Fail the build if a command did not land where it is expected.
RUN test -x /usr/local/bin/simbox-configure \
    && test -x /usr/local/bin/simbox-update \
    && test -x /home/${USERNAME}/tests/run-all.sh \
    && test -f /etc/profile.d/simbox.sh \
    && test -f /etc/simbox/pinned-refs \
    && bash -n /usr/local/bin/simbox-configure \
    && bash -n /usr/local/bin/simbox-update \
    && bash -n /home/${USERNAME}/tests/run-all.sh

# -----------------------------------------------------------------------------
# Project checkouts under ~/projects, pinned to the release tags above.
#
# No error suppression here: if a clone fails, or a tag does not exist, there
# is no point in producing an image at all.
#
# Shallow on purpose: the datasets make full history expensive, and the rootfs
# has to stay under the 2 GB release asset limit.
# -----------------------------------------------------------------------------
USER ${USERNAME}
WORKDIR /home/${USERNAME}

RUN mkdir -p projects .codex .claude \
    && git clone --depth 1 --branch "${ML_REF}" \
         https://github.com/BPMspaceUG/bpm-pizza-ml.git         projects/bpm-pizza-ml \
    && git clone --depth 1 --branch "${VIBE_REF}" \
         https://github.com/BPMspaceUG/bpm-pizza-vibecoding.git projects/bpm-pizza-vibecoding \
    && git clone --depth 1 --branch "${PII_REF}" \
         https://github.com/BPMspaceUG/bpm-pizza-pII.git       projects/bpm-pizza-pII

# Verify both checkouts landed AND really sit on the requested tag.
#
# The skills block is asserted by presence, never by count: the exercise repo
# owns its skill set and may grow a fourth. A release that drops it entirely
# must break the build here rather than surface mid-exercise (#5).
RUN test -d projects/bpm-pizza-ml/.git \
    && test -d projects/bpm-pizza-vibecoding/.git \
    && test -d projects/bpm-pizza-pII/.git \
    && test -f projects/bpm-pizza-ml/check_environment.py \
    && [ -n "$(ls -1 projects/bpm-pizza-vibecoding/.claude/skills/*/SKILL.md 2>/dev/null)" ] \
    && [ "$(git -C projects/bpm-pizza-ml describe --tags --exact-match 2>/dev/null)" = "${ML_REF}" ] \
    && [ "$(git -C projects/bpm-pizza-vibecoding describe --tags --exact-match 2>/dev/null)" = "${VIBE_REF}" ] \
    && [ "$(git -C projects/bpm-pizza-pII describe --tags --exact-match 2>/dev/null)" = "${PII_REF}" ]

# Only the chmod may fail harmlessly - a repo without .sh files is fine.
RUN chmod +x projects/bpm-pizza-ml/*.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# Exercise environment: PyTorch venv inside bpm-pizza-ml
#
# The exercises expect exactly this:
#     cd bpm-pizza-ml && python3 check_environment.py
# (no `source .venv/bin/activate` needed - the login shell's profile.d puts
# the venv's bin/ on PATH already)
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
