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

## Install (Windows)

One-time - put the launcher somewhere on your PATH:

```powershell
mkdir $env:LOCALAPPDATA\bin -Force
curl.exe -L -o $env:LOCALAPPDATA\bin\create_debian.ps1 `
  https://github.com/BPMspaceUG/bpm-pizza-simcontainer/releases/latest/download/create_debian.ps1
[Environment]::SetEnvironmentVariable(
  "Path", "$env:Path;$env:LOCALAPPDATA\bin", "User")
```

Then, in a fresh shell:

```powershell
create_debian user:password
```

That downloads the rootfs, imports it as a new WSL distro, pulls the `.env` from
`https://www.aipizzasim.com/getenv` using the credentials you passed, and opens
a shell.

## Multiple instances side by side

Existing distros are never touched. A second call auto-suffixes the name:

```powershell
create_debian user:password                           # -> pizza-sim
create_debian user:password                           # -> pizza-sim-2
create_debian user:password -Name pizza-sim-training   # -> explicit name
```

```powershell
wsl --list --verbose        # what exists
wsl -d pizza-sim            # enter
wsl --unregister pizza-sim  # throw away (irreversible)
```

Note: all distros share one WSL2 VM - same kernel, same network namespace.
Port 3000 in one instance blocks port 3000 in the others.

## Re-running the bootstrap

If credentials were wrong or the `.env` changed:

```powershell
wsl -d pizza-sim -u root -- devbox-bootstrap user:password
wsl --terminate pizza-sim
```

## Build locally instead of downloading

```powershell
docker build -t pizza-sim .
docker export (docker create pizza-sim) -o rootfs.tar
wsl --import pizza-sim-local $env:LOCALAPPDATA\WSL\pizza-sim-local rootfs.tar
wsl -d pizza-sim-local -u root -- devbox-bootstrap user:password
```

## Layout

```
Dockerfile                      image definition
wsl.conf                        default user + systemd, baked into the image
files/bootstrap.sh              -> /usr/local/bin/devbox-bootstrap
files/codex-config.toml         -> ~/.codex/config.toml
files/profile.d/devbox.sh       -> /etc/profile.d/devbox.sh
scripts/create_debian.ps1       Windows-side installer
.github/workflows/build.yml     build + export + publish release asset
```

## Implementation notes

`docker export` flattens the image and drops all image metadata - `ENV`, `CMD`,
`ENTRYPOINT` and `WORKDIR` do not survive the conversion to a WSL rootfs. That
is why every environment variable is set in `/etc/profile.d/devbox.sh` rather
than via `ENV` in the Dockerfile.

The `.env` is fetched at import time, not at build time, so the image itself
contains no credentials and the same artifact works for every user.
