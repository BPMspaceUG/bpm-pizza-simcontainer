# bpm-pizza-simcontainer

Prebuilt WSL environment for the BPM Pizza Sim training.

One command on a Windows machine produces a ready Linux distro: both project
repos cloned, a working PyTorch environment for the exercises, both coding
agents wired to the LiteLLM gateway, and a passwordless user.

Nothing needs to be installed on the Windows side except WSL itself.

---

## Where the image lives

Two artifacts, both hosted by GitHub.

**The WSL rootfs** — this is what the installer downloads:

| | |
|---|---|
| Release page | <https://github.com/BPMspaceUG/bpm-pizza-simcontainer/releases/tag/rootfs-latest> |
| Direct link | <https://github.com/BPMspaceUG/bpm-pizza-simcontainer/releases/latest/download/pizza-sim-rootfs.tar.gz> |
| Filename | `pizza-sim-rootfs.tar.gz` |
| Size | roughly 900 MB compressed |

The release is a rolling one: every successful build replaces the asset under
the same tag `rootfs-latest`. Its description always names the commit it was
built from, which is how you tell whether the published image is current:

```
Prebuilt WSL rootfs, commit `abc1234`
```

Compare that against the latest commit on `main`. If they differ, either the
last build failed or a commit touched only files under `paths-ignore`.

**The Docker image** — an intermediate product, not needed for WSL. It is
published to `ghcr.io/bpmspaceug/bpm-pizza-simcontainer:latest` and listed
under the organisation's **Packages** tab. Note that the organisation policy
currently forbids public packages, so it cannot be pulled anonymously. To run
the image in Docker or Compose without that, build it from the released rootfs:

```bash
curl -L -o rootfs.tar.gz https://github.com/BPMspaceUG/bpm-pizza-simcontainer/releases/latest/download/pizza-sim-rootfs.tar.gz
docker import rootfs.tar.gz pizza-sim:latest
```

On the Windows side the downloaded tarball is cached in
`%TEMP%\pizza-sim-rootfs.tar.gz` and the imported distro lives in
`%LOCALAPPDATA%\WSL\<name>`.

---

## Contents of the image

| | |
|---|---|
| Base | Debian 13 (trixie) |
| User | `roberto` — no password, passwordless `sudo` |
| CLI tools | git, curl, wget, jq, xxd, zip, unzip, ripgrep, nano, less, bubblewrap, build-essential, openssh-client |
| Runtimes | Python 3 (system), Node.js 22 |
| Agents | `claude` (Claude Code), `codex` (Codex CLI) — both routed through the gateway |
| ML env | `~/projects/bpm-pizza-ml/.venv` with torch, torchvision, tqdm, Pillow (CPU wheels) |
| Projects | `~/projects/bpm-pizza-ml`, `~/projects/bpm-pizza-vibecoding` |
| Tests | `~/tests` |
| Login dir | `~/projects` |

### The three simbox commands

| Command | Purpose |
|---|---|
| `simbox-update` | The one command after a reset: `.env`, apt, agents, repos, then the tests |
| `simbox-configure` | Fetch the `.env` and rewrite both agent configs |
| `simbox-test` | Run the acceptance tests (same as `~/tests/run-all.sh`) |

---

## Install

Run this in **PowerShell on Windows** — not inside WSL. No prior download, no
`Set-ExecutionPolicy`, no admin rights:

```powershell
$s = "https://raw.githubusercontent.com/BPMspaceUG/bpm-pizza-simcontainer/main/scripts/create_pizzasim_env.ps1"
& ([scriptblock]::Create((irm $s))) -EnvUrl <full-url-to-the-env-file> -SetDefault -FreshDownload
```

Then, inside the distro:

```bash
simbox-update
```

`irm` pulls the script as text, `[scriptblock]::Create()` turns it into an
executable block, `&` runs it and passes the arguments through. Because the
script never touches disk as a file, the execution policy does not apply.
The plain `irm ... | iex` form cannot take parameters — hence the scriptblock.

Prerequisite on the target machine: WSL (`wsl --install`).

### Parameters of `create_pizzasim_env.ps1`

| Parameter | Effect |
|---|---|
| `-EnvUrl <url>` | Full URL of the `.env`, **including the filename**. Works with or without credentials. |
| `-EnvFile <path>` | Full path to a local `.env` on Windows, including the filename. No network request. |
| `user:password` | Optional basic-auth credentials for `-EnvUrl`. Not a source on its own — there is no default endpoint. |
| `-NoEnv` | Skip the `.env` entirely — the distro comes up with an empty one |
| `-Name <name>` | Distro name, default `pizza-sim`. Taken names get a numeric suffix. |
| `-SetDefault` | Make this the WSL default, so a bare `wsl` opens it |
| `-Force` | Replace an existing distro of the same name |
| `-FreshDownload` | Discard the cached rootfs in `%TEMP%` and download again |
| `-Rootfs <path>` | Import a locally built tarball instead of the release asset |

---

## The `.env` file

The `.env` is never baked into the image — it is fetched at import time, so the
same artifact works for every participant and contains no credentials.
It lands in `~/.env`, not in `~/projects`.

### Keys

| Key | Required | Meaning |
|---|---|---|
| `LITELLM_PIZZA_URL` | yes | Gateway base, e.g. `https://litellm.aipizzasim.com/v1` |
| `LITELLM_PIZZA_KEY` | yes | Participant-facing key. The real upstream key stays on the gateway. |
| `ENV_SELF_URL` | recommended | The URL this file is served from — see below |
| `CLAUDE_MODEL` | recommended | Model alias for Claude Code |
| `CODEX_MODEL` | recommended | Model alias for Codex CLI |
| `CODEX_WIRE_API` | no | `responses` (default) or `chat` |
| `CLAUDE_THEME` | no | `dark` (default), `light`, … |
| `PIZZASIM_URL` | exercises | Base URL of the simulation |
| `PIZZASIM_API_KEY` | exercises | API key for the simulation |
| `PIZZERIA_ID` | exercises | Which pizzeria the machine works on |

Values containing spaces must be quoted. Otherwise everything after the space
is silently dropped when the file is sourced, and the key arrives truncated.

### `ENV_SELF_URL` — the file names its own location

```
ENV_SELF_URL=https://ico-cdn.pages.dev/<token>/pizza.env
```

With this set, a machine remembers where its `.env` came from. Refreshing after
a change on the CDN then needs no arguments at all:

```bash
sudo simbox-configure
```

The value inside the file wins over the path remembered at install time
(`/etc/simbox/env-source`). That is the point: if the file ever moves to a
different URL, announce the new address once in the **old** file, and every
machine follows on its next update.

`ENV_FILE` is accepted as an alias, but `ENV_SELF_URL` is the better name —
`ENV_FILE` reads like a path rather than a URL.

### Other ways to supply it

```bash
sudo simbox-configure                                   # refresh from the remembered URL
sudo simbox-configure --url https://example.com/x.env   # from a different URL
sudo simbox-configure --file /mnt/c/sim/pizza.env       # from the Windows drive
cat pizza.env | sudo simbox-configure --stdin           # from stdin
```

`--file` takes any path inside the distro, so `/mnt/c/...` reaches the whole
Windows drive.

A missing or unreachable source is never fatal: an empty `.env` is written, the
distro stays usable, and the agents simply have no key yet. An existing `.env`
survives a failed refresh untouched.

---

## Model aliases

Both agents talk to the gateway, which forwards to OpenRouter. The aliases must
match what the gateway actually serves — **every alias there carries an
`openrouter/` prefix**. Bare names such as `kimi-k3` produce
`400 no healthy deployments for this model`.

List the real ones:

```bash
curl -s -H "Authorization: Bearer $LITELLM_PIZZA_KEY" $LITELLM_PIZZA_URL/models \
  | jq -r '.data[].id'
```

Current defaults, verified end to end:

```
CLAUDE_MODEL=openrouter/moonshotai/kimi-k2.5
CODEX_MODEL=openrouter/z-ai/glm-5.1
```

Claude Code talks to the gateway's Anthropic-compatible `/v1/messages`; the
trailing `/v1` of `LITELLM_PIZZA_URL` is stripped because Claude Code appends
the path itself. `ANTHROPIC_API_KEY` is deliberately set to an empty string —
a leftover value there overrides the auth token.

Codex uses `/v1/responses`. `wire_api = "chat"` is not an option: Codex refuses
to load a config containing it since the chat protocol was retired.

Note that `ANTHROPIC_MODEL=... claude` on the command line has **no effect** —
`~/.claude/settings.json` sets it in its `env` block, which wins over the shell.
Use `claude --model <alias>` for a one-off, or fix the `.env` and rerun
`simbox-configure`.

---

## `simbox-update`

The first command on a reset machine. In order:

0. refresh `~/.env` from the remembered URL
1. `apt update` + `upgrade` + `autoremove`
2. Claude Code to `@latest`
3. Codex CLI to `@latest`
4. `git pull --ff-only` in both project repos
5. the acceptance tests

It ends with `READY` or `NOT READY`, and its exit code follows the tests.

```bash
simbox-update             # everything
simbox-update --check     # report only, change nothing
simbox-update --no-test   # steps 0-4
simbox-update --env       # only the .env
simbox-update --system    # only apt
simbox-update --agents    # only claude + codex
simbox-update --repos     # only git pull
simbox-update --test      # only the tests
```

The PyTorch venv is deliberately not upgraded — the exercises and the recorded
videos are pinned to the version baked into the image.

`git pull` runs with `--ff-only`. If a participant committed locally, the pull
stops and says so instead of overwriting work.

---

## Acceptance tests

In `~/tests`, next to `~/projects`. Run them all with `simbox-test`, or one at
a time.

| Test | Proves |
|---|---|
| `00-preconditions` | gateway reachable, key accepted, `.env` complete |
| `01-claude` | Claude Code — `/v1/messages` and the model alias |
| `02-codex` | Codex — `/v1/responses` and the model alias |
| `03-agents-chained` | Claude's Bash tool and agent-to-agent invocation |
| `04-audio-roundtrip` | text-to-speech and speech-to-text in both directions |
| `05-exercise-env` | PyTorch, datasets and both repos in place |

```bash
simbox-test          # all
simbox-test 03       # only the chained agent test
~/tests/02-codex.sh  # directly
```

If `00-preconditions` fails the runner stops — nothing else can pass without
the gateway. Every failure names the likely cause and the next step.

The audio test generates its own mp3 through the gateway and transcribes it
back, so no audio fixture ships in the image. It checks file size and mp3 magic
bytes before transcribing, otherwise a JSON error page would pass as audio.

---

## Several instances side by side

Existing distros are never touched. Running the install command twice
auto-suffixes the name: `pizza-sim`, `pizza-sim-2`, …

```powershell
wsl --list --verbose        # what exists
wsl -d pizza-sim            # enter
wsl -d pizza-sim -u root    # enter as root
wsl --terminate pizza-sim   # stop
wsl --unregister pizza-sim  # delete, irreversible
```

`wsl -d <name>` is a Windows command — it does not exist inside the distro.

| | |
|---|---|
| Filesystem, packages, users, home | separate — each distro has its own `ext4.vhdx` |
| Kernel, RAM, the VM itself | shared — all distros run in one WSL2 VM |
| Network and `localhost` | shared — port 3000 in one blocks it in the others |
| `/mnt/c` | shared — same Windows drive |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `400 no healthy deployments for this model` | alias does not exist on the gateway | list the real aliases, correct the `.env`, `sudo simbox-configure` |
| `Missing environment variable: LITELLM_PIZZA_KEY` | `.env` empty or not fetched | `sudo simbox-configure`, then `exec bash -l` |
| `wire_api = "chat" is no longer supported` | image predates the fix | re-import with `-FreshDownload` |
| `ANTHROPIC_MODEL=` on the command line is ignored | `settings.json` overrides the shell | `claude --model <alias>` |
| `Truncated tar archive` during import | incomplete download | rerun with `-FreshDownload` |
| `download failed` | no release published yet, or build still running | check Actions, or build locally with `-Rootfs` |
| Codex: `Model metadata not found` | no metadata for gateway aliases | expected and harmless |
| Codex refuses to run outside a repo | it requires a git repository | `cd` into one, or pass `--skip-git-repo-check` |
| `.env` seems missing | it lives in `~/.env`, not `~/projects` | `cat ~/.env` |
| 404 on the GHCR package page | org policy forbids public packages | import the released rootfs instead, see above |

---

## Building

CI in `.github/workflows/build.yml` builds the image, pushes it to GHCR,
converts it to a WSL rootfs and publishes it as the `rootfs-latest` release
described at the top of this file.

**One build at a time.** A `concurrency` group with `cancel-in-progress: true`
cancels the running build when a newer push arrives.

**Not every commit builds.** `paths-ignore` covers `**.md`, `scripts/**`,
`.github/**` and dotfiles — none of which change the rootfs. Use
**Actions → Build WSL rootfs → Run workflow** to rebuild anyway.

The build fails rather than publishing a broken image. It stops on a failed
clone, a missing checkout, a missing `simbox-*` command, a `check_environment.py`
that does not pass, or a rootfs above the 2 GB release asset limit.

The install one-liner reads the script from `raw.githubusercontent.com/.../main/`,
not from the release asset, so script changes are live immediately.

A weekly cron rebuild keeps apt packages, npm globals and the repo checkouts
current.

### Build locally

```powershell
git clone https://github.com/BPMspaceUG/bpm-pizza-simcontainer.git
cd bpm-pizza-simcontainer
docker build -t pizza-sim .
docker export (docker create pizza-sim) -o rootfs.tar
.\scripts\create_pizzasim_env.ps1 -Rootfs .\rootfs.tar -NoEnv
```

---

## Layout

```
Dockerfile                        image definition
wsl.conf                          default user + systemd, baked into the image
files/bootstrap.sh                -> /usr/local/bin/simbox-configure
files/update.sh                   -> /usr/local/bin/simbox-update
files/profile.d/simbox.sh         -> /etc/profile.d/simbox.sh
files/tests/                      -> ~/tests, run-all.sh linked as simbox-test
scripts/create_pizzasim_env.ps1   Windows-side installer
.github/workflows/build.yml       build, export, publish release asset
```

---

## Implementation notes

`docker export` flattens the image and discards all image metadata. `ENV`,
`CMD`, `ENTRYPOINT` and `WORKDIR` do not survive the conversion to a WSL rootfs.
That is why every environment variable is set in `/etc/profile.d/simbox.sh`
rather than via `ENV` in the Dockerfile.

`load: true` and `push: true` cannot be combined in one buildx call, so the
workflow builds into the local daemon first and pushes in a separate step.

GHCR rejects uppercase repository names, but `github.repository` keeps the
original casing and GitHub expressions have no `toLower()`. The workflow
normalises it with `${GITHUB_REPOSITORY,,}` — which is why the package path is
`ghcr.io/bpmspaceug/...` in lowercase.

`create_pizzasim_env.ps1` carries no `#Requires` statement on purpose:
`[scriptblock]::Create()` rejects those, and the install one-liner depends on
it. The version check lives in the script body instead.

Downloads use `curl.exe` rather than `Invoke-WebRequest`, which truncates files
of this size on Windows PowerShell 5.1. The result is verified against
`Content-Length` and discarded on mismatch, because a partial rootfs fails deep
inside `bsdtar` with a confusing error.

`simbox-configure` resolves the target account explicitly and never falls back
to root: `wsl -u root -e` leaves `SUDO_USER` unset and `USER` set to root, which
once sent the whole configuration to `/root` while reporting success.

`run-all.sh` resolves `$0` through `readlink -f`, because it is also reachable
as the `/usr/local/bin/simbox-test` symlink, where a plain `dirname` would point
at the wrong directory.
