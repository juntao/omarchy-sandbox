# Omarchy sandbox template

A Docker Sandboxes template that runs **Omarchy as an agent OS**: the same
CLI/TUI environment agents use on a real Omarchy box, without the Linux
desktop. The desktop stays for humans. This image is for agents and their
tools.

Herdr and Tmux both work here. A headless Herdr server starts with the
shell so agents can create sessions, panes, and other agent CLIs without
a compositor. Codex, Claude Code, OpenCode, Gemini, and Copilot are
already installed.

This is **not** official Omarchy, and it is **not** a full Omarchy install.
There is no Hyprland UI. See [Limitations](#limitations) before you use it.

The kit lives in this directory:

```text
omarchy-sandbox/
├── Dockerfile                     # fast build FROM a local devmarchy:4.5.0 image
├── omarchy-sandbox.dockerfile     # standalone rebuild from archlinux:base-devel
├── omarchy-sandbox.yaml           # v3 workload kit descriptor
├── context.md                     # agent instructions (written as AGENTS.md)
├── scripts/                       # Herdr install, repo setup, and auto-start
└── README.md
```

The image built here is `omarchy-sandbox:4.5.0` (linux/amd64). It was not
pushed to a registry.

## Limitations

- **CLI/TUI only.** Hyprland, a GPU, systemd, Limine, Btrfs, SDDM, and uwsm
  are not in this image. Many `omarchy-*` desktop and hardware commands will
  fail.
- **Docker's kernel, not Omarchy's.** Docker Sandboxes still boots Docker's
  microVM kernel. This template only changes the userland (packages, configs,
  and CLIs).
- **linux/amd64 and large.** The image is about **6.42 GB**. On Apple Silicon
  it will run under emulation, if it runs at all, and the desktop still will
  not be present.
- **Not tested with `sbx`.** This image was built and smoke-tested with
  `docker run` on a Linux box that does not have Docker Desktop or the `sbx`
  CLI. The commands below match Docker's docs, but you should confirm them
  on your machine.
- **Network allow-list (v3 kit only).** `omarchy-sandbox.yaml` allows a fixed
  set of hosts (OpenAI, GitHub, npm, PyPI, Arch/AUR mirrors). Other hosts are
  blocked when you launch the kit with `sbx run ./omarchy-sandbox`. The
  `--template` path with built-in agents (`sbx run codex` or `sbx run shell`)
  uses those agents' own network and credential policies instead of this
  kit's list.
- **LazyVim** was installed with a best-effort headless sync. It may need a
  first-run update inside the sandbox.
- **No Docker Engine inside the image.** There is no nested Docker daemon.
- The fast local build may contain an **empty leftover `/home/devmarchy`
  directory**. It is not the live home (the account is `agent` at
  `/home/agent`). A standalone rebuild does not have this leftover.

## What is in the image

Smoke-tested with `docker run --rm omarchy-sandbox:4.5.0 bash -lc '...'` and
`bash -c` / `bash -ic`:

| Item | Value |
| --- | --- |
| User | `agent`, UID/GID 1000, home `/home/agent` |
| Workdir | `/home/agent/workspace` |
| Omarchy | v4.5.0 (commit `ac2690c`); `omarchy-version` prints `dev (ac2690c)` |
| `omarchy` | on PATH for login, non-interactive, and interactive bash |
| Codex CLI | `codex-cli 0.169.0` (`/usr/sbin/codex`) |
| nvim | v0.12.6 (LazyVim) |
| tmux | 3.8, with Omarchy's `tmux.conf` (`Ctrl + Space` prefix) |
| herdr | 0.9.5, official Omarchy package; headless `herdr server` auto-starts |
| lazygit | 0.66.3 |
| starship | 1.27.0 |
| git | 2.56.1 |

Also installed: fastfetch, yay, `claude`, `opencode`, `gemini`, and `copilot`.

## Herdr and Tmux

This image is meant to run agents, not to impersonate the Omarchy desktop.
Super keybindings (`Super + Ctrl + Return`, and so on) are not available.
Use the CLIs:

```bash
# Herdr: a headless server is started from BASH_ENV on first shell
herdr status server
herdr session list
herdr agent list
herdr --skill          # agent skill file
herdr                  # attach to the persistent session (needs a TTY)

# Tmux, with Omarchy's config already in ~/.config/tmux
tmux new-session -s work
```

Set `OMARCHY_SANDBOX_SKIP_HERDR=1` if you do not want the server auto-started.
The official Herdr desktop app (`herdr-app`) and Hyprland theme-sync are not
installed; those belong on a human desktop.


## Build or load the image

### Option A — load a saved image on a machine with Docker

On the machine that already has the image:

```bash
docker image save omarchy-sandbox:4.5.0 -o omarchy-sandbox.tar
```

Copy the tarball to the machine with Docker Desktop, then:

```bash
docker image load -i omarchy-sandbox.tar
sbx template load omarchy-sandbox.tar
```

(`sbx template load` is the sandbox-template path; `docker image load` is
enough if you only need the image tag for `--template`.)

### Option B — rebuild from this kit (no pre-built image required)

```bash
docker build -f omarchy-sandbox.dockerfile \
  --build-arg OMARCHY_VERSION=v4.5.0 \
  -t omarchy-sandbox:4.5.0 .
```

This starts from `archlinux:base-devel` and takes a while (pacman, npm,
AUR/yay, LazyVim).

The `Dockerfile` in this directory is a faster adapter that starts
`FROM devmarchy:4.5.0`. Use it only when that image is already present.

## Run Codex in this sandbox (preferred)

Store OpenAI credentials **on the host**, never in the image.

```bash
# API key (prompted; not written into the image or this repo)
sbx secret set openai

# or ChatGPT login; the browser runs on the host
sbx secret set openai --oauth
```

Then, from a project directory:

```bash
sbx run codex --template omarchy-sandbox:4.5.0
```

If your `sbx` version requires a registry prefix, use
`docker.io/library/omarchy-sandbox:4.5.0` or the name `sbx template load`
printed.

The built-in `codex` agent keeps its own launch command and credential
proxy. This template only replaces the OS and tool image. Codex is already
installed in the image, which that path requires.

## Shell sandbox, then run `codex` yourself

```bash
sbx run shell --template omarchy-sandbox:4.5.0
# inside the sandbox:
codex
```

OAuth or browser login **inside** the sandbox usually fails. Proxy-managed
OpenAI credentials are set up automatically for `sbx run codex`. They may
**not** be injected in a plain shell sandbox unless you launch the v3 kit
(next section), which declares the `openai` credential. You will be asked
to approve the kit's use of the stored key.

## v3 kit path

From this directory (or after a `docker buildx` publish of the kit):

```bash
sbx secret set openai    # once, on the host
sbx run --name omarchy-sandbox ./omarchy-sandbox
```

The default launch is bash (`CMD ["/bin/bash"]`; there is no agent
`ENTRYPOINT`). Then run `codex` inside. Because the kit declares a
proxy-managed `openai` credential, approve the binding when prompted so
requests to `api.openai.com` (and the other listed OpenAI hosts) can have
`Authorization: Bearer …` injected on the host. The real key stays on the
host.

Hosts not in the kit's allow-list are blocked on this path. Add more hosts
to `omarchy-sandbox.yaml` if pacman, yay, or git need them.

## Plain Docker (not a sandbox)

```bash
docker run -it \
  -e OPENAI_API_KEY \
  -v "$PWD":/home/agent/workspace \
  -w /home/agent/workspace \
  omarchy-sandbox:4.5.0
# then:
codex
```

This puts the API key **inside the container**, unlike `sbx run codex`.
Prefer the sandbox commands above when you can.

## Persistent environment

Use `/etc/sandbox-persistent.sh` for exports that later Bash sessions need.
Login, interactive, and non-interactive shells source it through
`/etc/sandbox-env.sh` (`BASH_ENV` is set). That wrapper also starts the
Herdr server. Do not put shell completion in either file.
