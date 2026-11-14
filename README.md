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

The image is published on Docker Hub as
[`juntaoyuan/omarchy-sandbox`](https://hub.docker.com/r/juntaoyuan/omarchy-sandbox)
(public, linux/amd64), tags `4.5.0` and `latest`, digest
`sha256:3d84bcdd0b48e5360a0b3d80e512207aa3ac56d38fab327ef8ccc274005c5bdd`
(about 3.5 GB compressed, 6.45 GB unpacked). Pull it rather than building
it or copying a tarball:

```bash
docker pull juntaoyuan/omarchy-sandbox:4.5.0
```

A local build from this kit is tagged `omarchy-sandbox:4.5.0`; use that
name in the commands below if you built it yourself.

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
- **Verified with plain Docker; `sbx` only partly verified.** The image
  (pulled from Docker Hub), Herdr, and Tmux were tested with `docker run` /
  `docker exec` (see
  [Get a shell](#get-a-shell-in-the-container-or-sandbox)). With `sbx`
  v0.53.0, `sbx login`, `sbx template load`, and `sbx create` worked, but the
  test machine (itself a VM) could not boot any sandbox microVM, not even
  the stock `shell` agent. So Herdr inside an `sbx` sandbox has not been
  tested yet. Confirm on a machine where `sbx run shell` works.
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

Smoke-tested with `docker run --rm juntaoyuan/omarchy-sandbox:4.5.0 bash -lc '...'` and
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
Use the CLIs.

**Herdr lives inside the container or sandbox, not on the host.** The server
listens on a Unix socket inside it, `/home/agent/.config/herdr/herdr.sock`.
Every `herdr` command (including the TUI) must run inside, so first get a
shell there (next section). A `herdr` binary on the host cannot see that
socket, and Herdr does not listen on the network.

The server is started by `/etc/sandbox-env.sh`, which bash reads through
`BASH_ENV` or the login and interactive startup files. So the first **bash**
process inside starts it. A command that is not run through bash, such as
`docker exec omarchy herdr status server`, does not start it and reports
`status: not running` until some bash has run.

```bash
# Herdr: a headless server is started from BASH_ENV on first shell
herdr status server
herdr session list
herdr agent list
herdr --skill          # agent skill file
herdr                  # attach to the persistent session (needs a TTY)
                       # detach again with Ctrl+Space, then d

# Tmux, with Omarchy's config already in ~/.config/tmux
tmux new-session -s work
```

Set `OMARCHY_SANDBOX_SKIP_HERDR=1` if you do not want the server auto-started.

Herdr and Omarchy's Tmux config both use `Ctrl + Space` as the prefix. Run
one or the other in a terminal, not Herdr inside Tmux (or the reverse),
unless you change one prefix.

## Get a shell in the container or sandbox

### Plain Docker (verified)

Start a long-running container, then open shells in it with `docker exec`.
Wrap the keep-alive command in `bash -c` so `BASH_ENV` starts the Herdr
server when the container starts:

```bash
docker run -d --name omarchy \
  -v "$PWD":/home/agent/workspace \
  juntaoyuan/omarchy-sandbox:4.5.0 \
  bash -c 'exec sleep infinity'

docker exec -it omarchy bash -l      # interactive shell as `agent`
```

Inside that shell:

```bash
herdr status server         # status: running, socket: /home/agent/.config/herdr/herdr.sock
herdr session list          # default  running  ...
herdr                       # full TUI; Ctrl+Space then d detaches, workspaces persist
tmux new-session -s work    # Omarchy tmux config
```

Or run one command without an interactive shell:

```bash
docker exec omarchy bash -c 'herdr status server --json'
```

The image's default user is already `agent`, so `-u agent` is optional.
Use `docker exec -it -u root omarchy bash` for root (or `sudo` as `agent`).
Remove the container when you are done:

```bash
docker rm -f omarchy
```

`docker run -it --rm juntaoyuan/omarchy-sandbox:4.5.0` also works for a throwaway
interactive shell; Herdr's server stops with the container.

Tested on Docker Engine (Linux, amd64), with the image pulled from Docker
Hub and with a local build: the server was running after
`docker run -d ... bash -c 'exec sleep infinity'`; `herdr status server
--json` returned `"running":true`, `"version":"0.9.5"`; `herdr session list`
showed `default running`; the `herdr` TUI rendered over `docker exec -it`,
new panes opened bash, and `Ctrl+Space d` detached with the workspace kept;
a detached Tmux session ran commands; `codex`, `claude`, `opencode`,
`gemini`, `copilot`, `nvim`, `lazygit`, and `omarchy` were all on PATH.

### Docker Sandboxes (`sbx`)

One-time host setup (both were done and worked with `sbx` v0.53.0):

```bash
sbx login                      # Docker account; device-code sign-in in the browser
sbx policy init balanced       # or allow-all / deny-all; required before the first sandbox
```

Create a shell sandbox from the Docker Hub image, then attach or exec into
it:

```bash
cd ~/my-project
sbx run -t juntaoyuan/omarchy-sandbox:4.5.0 --name omarchy shell .     # creates, starts, and opens a shell
```

Or create it first and open shells separately:

```bash
sbx create -t juntaoyuan/omarchy-sandbox:4.5.0 --name omarchy shell .
sbx exec -it omarchy bash -l                  # interactive shell
sbx exec omarchy bash -c 'herdr status server'
sbx run --name omarchy                        # re-attach to the agent session
sbx ls                                        # list sandboxes
sbx stop omarchy                              # stop; sbx rm omarchy to delete
```

Inside, use Herdr exactly as in the Docker section (`herdr status server`,
`herdr`, `Ctrl+Space d`). `sbx` pulls `--template` images from the registry
by default, so the Hub image needs no extra step.

**Offline: load a tarball instead of pulling.** `sbx` keeps its own image
store, separate from Docker's, so a `docker image load` is not visible to
it. Load the tarball into `sbx` and pass `--pull never`:

```bash
sbx template load omarchy-sandbox.tar     # took about 20 s for the 6 GB image
sbx template ls                           # docker.io/library/omarchy-sandbox  4.5.0
sbx create --pull never -t omarchy-sandbox:4.5.0 --name omarchy shell .
```

**What was verified.** `sbx login`, `sbx policy init`, `sbx template load`,
`sbx template ls`, `sbx create --pull never` (from the loaded tarball),
`sbx ls`, and `sbx rm` all worked. Creating straight from the Docker Hub
reference was not tried in `sbx`, though `docker pull` of it works. Starting
the sandbox (`sbx run` / `sbx exec`) did not: on the test machine, which is
itself a cloud VM, the microVM never booted, and a stock
`sbx run -d shell .` (no custom template) hung the same way. That is a host
limit, not this image, but it means Herdr inside `sbx` is still untested.
On Linux, the user running `sbx` needs read/write access to `/dev/kvm`
(usually membership in the `kvm` group, active in the shell that starts the
`sbx` daemon); otherwise the daemon logs `KVM error: Permission denied`.

## Build or load the image

### Option A — pull from Docker Hub (recommended)

```bash
docker pull juntaoyuan/omarchy-sandbox:4.5.0
```

`sbx run -t juntaoyuan/omarchy-sandbox:4.5.0 ...` pulls it on its own.

### Option B — move a saved image (tarball, offline)

On the machine that already has the image:

```bash
docker image save omarchy-sandbox:4.5.0 -o omarchy-sandbox.tar
```

Copy the tarball to the other machine, then load it where you need it:

```bash
docker image load -i omarchy-sandbox.tar     # plain Docker (docker run)
sbx template load omarchy-sandbox.tar        # Docker Sandboxes (sbx run -t)
```

The tarball is only for machines that cannot pull from Docker Hub. Plain
Docker never needs it when you can pull or build. `sbx` reads templates
from its own store, which is why the offline path is `sbx template load`
plus `--pull never`.

**Do not commit the tarball to git.** It is about 6 GB, GitHub rejects any
file over 100 MB, and `*.tar` is in `.gitignore`. Share new versions by
pushing to Docker Hub:

```bash
docker tag omarchy-sandbox:4.5.0 juntaoyuan/omarchy-sandbox:4.5.0
docker tag omarchy-sandbox:4.5.0 juntaoyuan/omarchy-sandbox:latest
docker push juntaoyuan/omarchy-sandbox:4.5.0
docker push juntaoyuan/omarchy-sandbox:latest
```

### Option C — rebuild from this kit (no pre-built image required)

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
sbx run codex --template juntaoyuan/omarchy-sandbox:4.5.0
```

For a tarball you loaded with `sbx template load`, use
`--pull never --template omarchy-sandbox:4.5.0` instead.

The built-in `codex` agent keeps its own launch command and credential
proxy. This template only replaces the OS and tool image. Codex is already
installed in the image, which that path requires.

## Shell sandbox, then run `codex` yourself

```bash
sbx run shell --template juntaoyuan/omarchy-sandbox:4.5.0
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

See [Get a shell](#get-a-shell-in-the-container-or-sandbox) for the
long-running container workflow. For a one-off Codex session:

```bash
docker run -it --rm \
  -e OPENAI_API_KEY \
  -v "$PWD":/home/agent/workspace \
  -w /home/agent/workspace \
  juntaoyuan/omarchy-sandbox:4.5.0
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
