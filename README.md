# bpm-pizza-simcontainer

Prebuilt WSL development environment for the BPM Pizza Sim projects.

Ships with `bpm-pizza-ml` and `bpm-pizza-vibecoding` already cloned, both coding
agents installed and wired to OpenRouter, and a passwordless `robert` user.

| | |
|---|---|
| Base | Debian 13 (trixie) |
| User | `robert`, no password, passwordless sudo |
| Tools | git, jq, curl, wget, zip, unzip, ripgrep, build-essential, python3, Node 22 |
| Agents | `claude` -> `moonshotai/kimi-k3`, `codex` -> `z-ai/glm-5.2`, both via OpenRouter |
| Projects | `~/projects/bpm-pizza-ml`, `~/projects/bpm-pizza-vibecoding` |

## Install

One command in **PowerShell on Windows** — nothing to install first, no
execution policy change needed:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1))) user:password
```

Replace `user:password` with the credentials for the `.env` endpoint. Without
credentials the distro still comes up, just with an empty `.env`:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1))) -NoEnv
```

The command downloads the rootfs, imports it as a new WSL distro, fetches the
`.env`, and opens a shell. Prerequisite: WSL itself (`wsl --install`).

### Name the distro

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1))) user:password -Name pizza-sim-training
```

## Multiple instances side by side

Existing distros are never touched. Running the command twice auto-suffixes the
name: `pizza-sim`, `pizza-sim-2`, `pizza-sim-3`, ...

```powershell
wsl --list --verbose        # what exists
wsl -d pizza-sim            # enter
wsl --unregister pizza-sim  # throw away (irreversible)
```

Note: all distros share one WSL2 VM - same kernel, same network namespace.
Port 3000 in one instance blocks port 3000 in the others.

## Filling in the .env later

If the endpoint was not reachable, or the credentials changed:

```powershell
wsl -d pizza-sim -u root -- devbox-bootstrap user:password
wsl --terminate pizza-sim
```

## Build locally instead of downloading

```powershell
git clone https://github.com/BPMspaceUG/bpm-pizza-simcontainer.git
cd bpm-pizza-simcontainer
docker build -t pizza-sim .
docker export (docker create pizza-sim) -o rootfs.tar
.\scripts\create_pizzasim_env.ps1 -Rootfs .\rootfs.tar -NoEnv
```

## Layout

```
Dockerfile                        image definition
wsl.conf                          default user + systemd, baked into the image
files/bootstrap.sh                -> /usr/local/bin/devbox-bootstrap
files/codex-config.toml           -> ~/.codex/config.toml
files/profile.d/devbox.sh         -> /etc/profile.d/devbox.sh
scripts/create_pizzasim_env.ps1   Windows-side installer
.github/workflows/build.yml       build + export + publish release asset
```

## Implementation notes

`docker export` flattens the image and drops all image metadata - `ENV`, `CMD`,
`ENTRYPOINT` and `WORKDIR` do not survive the conversion to a WSL rootfs. That
is why every environment variable is set in `/etc/profile.d/devbox.sh` rather
than via `ENV` in the Dockerfile.

The `.env` is fetched at import time, not at build time, so the image itself
contains no credentials and the same artifact works for every user.

`create_pizzasim_env.ps1` carries no `#Requires` statement on purpose:
`[scriptblock]::Create()` rejects those, and the one-liner above depends on it.
