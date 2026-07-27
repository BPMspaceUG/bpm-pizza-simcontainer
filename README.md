# bpm-pizza-simcontainer

Prebuilt WSL development environment for the BPM Pizza Sim training.

One command on a Windows machine produces a ready Linux distro: both project
repos cloned, a working PyTorch environment for the exercises, both coding
agents installed and pointed at OpenRouter, and a passwordless user.

Nothing needs to be installed on the Windows side except WSL itself.

---

## Contents of the image

| | |
|---|---|
| Base | Debian 13 (trixie) |
| User | `robert` — no password, passwordless `sudo` |
| CLI tools | git, curl, wget, jq, zip, unzip, ripgrep, nano, less, build-essential, openssh-client |
| Runtimes | Python 3 (system), Node.js 22 |
| Agents | `claude` (Claude Code), `codex` (Codex CLI) — both routed through OpenRouter |
| ML env | `~/projects/bpm-pizza-ml/.venv` with torch, torchvision, tqdm, Pillow (CPU wheels) |
| Projects | `~/projects/bpm-pizza-ml`, `~/projects/bpm-pizza-vibecoding` |
| Login dir | `~/projects` |

---

## Install

Run this in **PowerShell on Windows** — not inside WSL. No prior download, no
`Set-ExecutionPolicy`, no admin rights:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1))) user:password
```

`irm` pulls the script as text, `[scriptblock]::Create()` turns it into an
executable block, `&` runs it and passes the arguments through. Because the
script never touches disk as a file, the execution policy does not apply.

The plain `irm ... | iex` form cannot take parameters — hence the scriptblock.

Prerequisite on the target machine: WSL (`wsl --install`). If it is missing,
the script stops with a clear message instead of a cryptic error.

### What it does

1. Downloads `pizza-sim-rootfs.tar.gz` from the latest GitHub release
   (cached in `%TEMP%` — delete it to force a fresh download)
2. Picks a free distro name and imports the rootfs into `%LOCALAPPDATA%\WSL\<name>`
3. Runs `devbox-bootstrap` inside the new distro to place the `.env`
4. Restarts the distro so `/etc/wsl.conf` takes effect, then opens a shell

---

## Where the `.env` comes from

The `.env` is never baked into the image. It is placed at import time, so the
same artifact works for every participant and contains no credentials.

Four sources, evaluated in this order:

| Option | Behaviour |
|---|---|
| `-EnvFile C:\sim\pizza.env` | Local file on Windows, piped in. No network request, no credentials needed. |
| `-EnvUrl https://... user:password` | Fetch from an alternate endpoint instead of the default |
| `user:password` | Fetch from the default endpoint (`https://www.aipizzasim.com/getenv`) |
| `-NoEnv` | Skip entirely — the distro comes up with an empty `.env` |

If no option is given, the script asks once. Pressing Enter skips.

A missing or unreachable source is never fatal: an empty `.env` is written, the
distro stays usable, and the agents simply have no key yet.

### Examples

```powershell
$s = "https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1"

& ([scriptblock]::Create((irm $s))) user:password
& ([scriptblock]::Create((irm $s))) -EnvFile C:\sim\pizza.env
& ([scriptblock]::Create((irm $s))) user:password -EnvUrl https://staging.example.com/getenv
& ([scriptblock]::Create((irm $s))) -NoEnv -Name pizza-sim-test
```

### From inside the distro

`devbox-bootstrap` does the same thing and can be rerun at any time — after the
endpoint comes online, after credentials change, or to swap in a different
`.env` mid-session:

```bash
sudo devbox-bootstrap user:password
sudo devbox-bootstrap user:password --url https://staging.example.com/getenv
sudo devbox-bootstrap --file /mnt/c/sim/pizza.env
cat pizza.env | sudo devbox-bootstrap --stdin
```

`--file` accepts any path *inside* the distro, so `/mnt/c/...` reaches the whole
Windows drive without involving PowerShell at all.

Equivalent environment variables for scripted use: `DEVBOX_ENV_FILE`,
`DEVBOX_ENV_URL`, `DEVBOX_BASICAUTH`.

After rerunning the bootstrap, restart the distro so the new environment is
picked up:

```powershell
wsl --terminate pizza-sim
```

---

## The exercise environment

The exercises at <https://www.aipizzasim.com/exercises/1> expect a virtualenv
inside `bpm-pizza-ml`. It is prebuilt in the image, so the session start works
exactly as written on the exercise page:

```bash
cd bpm-pizza-ml
source .venv/bin/activate
python3 check_environment.py
```

Expected final line:

```
All dependencies and data are present. You are ready to start.
```

The login shell already lands in `~/projects`, so `cd bpm-pizza-ml` works
straight away.

`check_environment.py` also runs during the image build. If torch, torchvision,
tqdm, Pillow or any dataset were missing, the build fails — a broken image never
reaches the training room.

**CPU wheels on purpose.** torch is installed from
`https://download.pytorch.org/whl/cpu`. The CUDA build is several gigabytes and
useless on a training laptop; the rootfs also has to stay under the 2 GB GitHub
release asset limit.

The clones are shallow (`--depth 1`) for the same reason. If full history is
needed:

```bash
git -C ~/projects/bpm-pizza-ml fetch --unshallow
```

---

## Coding agents

Both agents are installed globally via npm and configured against OpenRouter.
They read `OPENROUTER_API_KEY` from `~/.env`.

| Agent | Model | Config |
|---|---|---|
| `claude` | `moonshotai/kimi-k3` | `~/.claude/settings.json` + `/etc/profile.d/devbox.sh` |
| `codex` | `z-ai/glm-5.2` | `~/.codex/config.toml` |

Claude Code talks to OpenRouter's Anthropic-compatible endpoint
(`https://openrouter.ai/api`), so no local proxy is needed. `ANTHROPIC_API_KEY`
is deliberately set to an empty string — a leftover value there overrides the
auth token.

Codex uses a custom provider block with `wire_api = "responses"`. That is
mandatory since OpenAI removed the `chat` wire protocol, and the block has to
live in the user-level `~/.codex/config.toml`; Codex ignores it in a
project-local one.

Both configs are rewritten by `devbox-bootstrap` whenever it runs.

---

## Several instances side by side

Existing distros are never touched. Running the command twice auto-suffixes the
name: `pizza-sim`, `pizza-sim-2`, `pizza-sim-3`, …

```powershell
wsl --list --verbose        # what exists
wsl -d pizza-sim            # enter
wsl -d pizza-sim -u root    # enter as root
wsl --terminate pizza-sim   # stop
wsl --unregister pizza-sim  # delete, irreversible
```

Use `-Name` to choose explicitly, `-Force` to replace an existing distro of the
same name.

**What is shared and what is not:**

| | |
|---|---|
| Filesystem, packages, users, home | separate — each distro has its own `ext4.vhdx` |
| Kernel, RAM, the VM itself | shared — all distros run in one WSL2 VM |
| Network and `localhost` | shared — port 3000 in one distro blocks it in the others |
| `/mnt/c` | shared — same Windows drive |

The network namespace is the usual surprise when running two instances at once.

Throwing an instance away and starting over takes about two minutes:
`wsl --unregister`, then the install command again.

---

## Rebuilding the image

CI lives in `.github/workflows/build.yml`. It builds the Docker image, pushes it
to GHCR, converts it to a WSL rootfs and publishes it as the `rootfs-latest`
release.

**Only one build runs at a time.** A `concurrency` group with
`cancel-in-progress: true` cancels the running build when a newer push arrives,
instead of stacking parallel runs.

**Not every commit builds.** `paths-ignore` covers `**.md`, `scripts/**`,
`.github/**`, `.gitattributes`, `.gitignore` and `LICENSE` — none of which change
the rootfs. Use **Actions → Build WSL rootfs → Run workflow** to rebuild anyway,
for example to refresh the `create_pizzasim_env.ps1` attached to the release.

A weekly cron rebuild keeps apt packages, npm globals and the repo checkouts
current.

The install one-liner reads the script from `raw.githubusercontent.com/.../main/`,
not from the release asset — script changes are live immediately and do not
depend on a build.

### Build locally

```powershell
git clone https://github.com/BPMspaceUG/bpm-pizza-simcontainer.git
cd bpm-pizza-simcontainer
docker build -t pizza-sim .
docker export (docker create pizza-sim) -o rootfs.tar
.\scripts\create_pizzasim_env.ps1 -Rootfs .\rootfs.tar -NoEnv
```

This needs Docker on the Windows machine — exactly what the release path avoids.

---

## Layout

```
Dockerfile                        image definition
wsl.conf                          default user + systemd, baked into the image
files/bootstrap.sh                -> /usr/local/bin/devbox-bootstrap
files/codex-config.toml           -> ~/.codex/config.toml
files/profile.d/devbox.sh         -> /etc/profile.d/devbox.sh
scripts/create_pizzasim_env.ps1   Windows-side installer
.github/workflows/build.yml       build, export, publish release asset
```

---

## Troubleshooting

**`download failed`** — no release published yet, or the build is still running.
Check Actions, or build locally with `-Rootfs`.

**Agents report authentication errors** — `~/.env` has no `OPENROUTER_API_KEY`.
Rerun `sudo devbox-bootstrap` with a working source, then `wsl --terminate`.

**`check_environment.py` reports missing data** — the datasets come from the
`bpm-pizza-ml` checkout. If they are absent, the image is stale; rebuild via
Run workflow.

**Cached rootfs** — the tarball is kept in `%TEMP%\pizza-sim-rootfs.tar.gz` and
reused. Delete it to pull a newer release.

**Port already in use across distros** — expected, see the sharing table above.

---

## Implementation notes

`docker export` flattens the image and discards all image metadata. `ENV`,
`CMD`, `ENTRYPOINT` and `WORKDIR` do not survive the conversion to a WSL rootfs.
That is why every environment variable is set in `/etc/profile.d/devbox.sh`
rather than via `ENV` in the Dockerfile.

`load: true` and `push: true` cannot be combined in one buildx call, so the
workflow builds into the local daemon first and pushes in a separate step. The
image has to be in the local daemon anyway for `docker create` / `docker export`.

GHCR rejects uppercase repository names, but `github.repository` keeps the
original casing. GitHub expressions have no `toLower()`, so the workflow
normalises it with bash parameter expansion: `${GITHUB_REPOSITORY,,}`.

`create_pizzasim_env.ps1` deliberately carries no `#Requires` statement.
`[scriptblock]::Create()` rejects those, and the install one-liner depends on it.
The version check lives in the script body instead.
