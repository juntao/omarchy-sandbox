# Omarchy as an Agent OS in Docker Sandboxes

[Omarchy Linux](https://omarchy.org/) is two things at once. For a person at a keyboard, it is a next-generation, opinionated Linux desktop: a complete Arch-based environment with a chosen set of tools, themes, and defaults. For an AI coding agent, the same project is an *agent OS* — a userland the agent can inspect and change through command-line tools and plain-text config, rather than through a mouse and a settings GUI.

Those two roles share a lot of machinery, but they do not have to share a display. The [omarchy-sandbox](https://github.com/juntao/omarchy-sandbox) image takes Omarchy's CLI and TUI stack, leaves the Hyprland desktop out, and runs that agent OS inside Docker or [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`). The result is a machine an agent can actually use — a shell, a multiplexer, browsers it can drive, and the coding agents themselves — without giving a non-deterministic program the keys to your laptop.

## An OS that agents can actually operate

A desktop is friendly to humans when its settings live in menus. An OS is friendly to agents when those same settings are commands and files. Omarchy leans that way. The `omarchy` wrapper and the `omarchy-*` commands on `PATH` are ordinary programs. An agent that can run a shell can list themes, switch fonts, query packages, or change defaults without opening a control panel.

In the published `juntaoyuan/omarchy-sandbox:4.5.0` image, these are real, working examples:

```bash
omarchy theme list              # Catppuccin, Nord, Tokyo Night, and others
omarchy theme dir "Tokyo Night" # path to that theme's text files
omarchy font list
omarchy font current            # DejaVu Sans Mono in this image
omarchy pkg present git tmux nvim
omarchy pkg missing firefox
omarchy default agent
omarchy default browser
omarchy default editor
omarchy default terminal
omarchy mise install
```

The matching configuration is plain text under the agent's home directory: `~/.config/omarchy/`, `~/.config/herdr/config.toml`, `~/.config/starship.toml`, and the usual git, tmux, and editor files. An agent can read them, patch them, and verify the result with another CLI call.

Not every Omarchy command belongs in a headless sandbox. The image still ships many `omarchy-hyprland-*` helpers and hardware tools (brightness, battery, and the like). Those targets need the desktop or the physical machine, and they fail here, as the image's limitations describe. The useful surface for agents is the CLI and TUI layer: packages, themes as text, fonts, mise, and the default-app helpers.

Browser use is part of that layer, not an add-on. The image includes Google Chrome (`google-chrome-stable`), Google's [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) with its `chrome-devtools` CLI, and Vercel's [agent-browser](https://github.com/vercel-labs/agent-browser), already pointed at that Chrome. Agents can open a page, take a snapshot, or drive DevTools without installing a second browser:

```bash
agent-browser open https://example.com
agent-browser snapshot -i

chrome-devtools new_page "https://example.com"
chrome-devtools take_screenshot 1 --filePath page.png
chrome-devtools stop
```

`chrome-devtools-mcp` is pre-registered for Claude Code, Codex, and Gemini, so those agents can use the same Chrome through MCP as well as from the shell.

The image also comes with the agents and coordination tools already installed: Claude Code, Codex, OpenCode, Gemini, and Copilot, plus Herdr, Tmux, Neovim (LazyVim), lazygit, and mise. Herdr is Omarchy's terminal workspace manager for coding agents — Claude in one pane, Codex in another, a browser CLI in a third, then detach and come back later. Tmux is there too, with the same Ctrl+Space prefix Omarchy uses on the desktop. The toolchain is the OS; an agent does not have to install it first.

## Agents need a sandbox, and the agent OS does too

Coding agents are not deterministic, and they are most useful when they have a real computer: a shell, a filesystem, a package manager, a browser, network access, and the ability to start other tools. That is a poor combination to drop unguarded onto a shared workstation. If the agent OS is going to look like a full machine, it should run in a sandbox that looks like a full machine from the inside and like a disposable, policy-bounded environment from the outside.

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) is built for that job. A sandbox is not just another container. Official documentation describes it as a [microVM](https://docs.docker.com/ai/sandboxes/architecture/): the agent gets its own kernel and its own virtual machine, rather than sharing the host kernel the way a process in a Linux container does. Docker's [security overview](https://docs.docker.com/ai/sandboxes/security/) compares this to ordinary containers and to Docker-in-Docker, and it is the main reason `sbx` is a better home for an agent OS than `docker run` alone. A container is still a useful way to try the image; it is not the same isolation model.

Several other properties follow from that design, and they matter for agents.

**It is just a Docker image.** You build or pull a normal image and use it as a sandbox template. The Omarchy agent OS is on Docker Hub as [`juntaoyuan/omarchy-sandbox`](https://hub.docker.com/r/juntaoyuan/omarchy-sandbox). `sbx create` and `sbx run` can take that tag directly. There is no separate appliance format to learn.

**Network and access control are explicit.** Sandboxes start from a [deny-by-default network policy](https://docs.docker.com/ai/sandboxes/security/). You choose a preset (`balanced`, `allow-all`, or `deny-all`) or write a tighter policy for what the sandbox may reach or mount. Organizations can go further with [governance policies](https://docs.docker.com/ai/sandboxes/security/governance/) that apply the same rules across a team. That is a better default for a non-deterministic agent than an open container on the host network.

**Credentials stay outside the VM.** This is one of the sharper differences from a container you start with `-e` or a mounted secrets file. Docker Sandboxes [injects credentials through a host-side proxy](https://docs.docker.com/ai/sandboxes/configuration/credentials/). The official architecture notes that a credential sentinel is rewritten on the host; the real secret is not placed in the virtual machine. You store keys once with `sbx secret set` (including OAuth flows that run on the host) and then start an agent. The Omarchy image itself does not bake credentials in, and it should not.

**The CLI is simple enough for a coordinator to drive.** `sbx login`, `sbx create`, `sbx run`, `sbx exec`, `sbx stop`, and `sbx rm` are ordinary commands. A planning agent on the host can start a sandbox, exec a task, and tear it down. You do not need a custom orchestrator to get a second Omarchy environment.

**The same CLI works locally and in the cloud.** [Local sandboxes](https://docs.docker.com/ai/sandboxes/get-started/) run on your machine (on Linux this needs KVM access, usually membership in the `kvm` group). [Cloud sandboxes](https://docs.docker.com/ai/sandboxes/cloud/) run on Docker's cloud after the same `sbx login`, with pay-as-you-go billing. That lets you keep a short-lived agent OS close to a laptop, or burst the same image into the cloud without rebuilding it.

The docs add more that is easy to miss if you only compare "VM versus container":

- [Workspace mounts and file sync.](https://docs.docker.com/ai/sandboxes/usage/) `sbx run` mounts the current directory into the sandbox (via virtiofs on the local path). `sbx create` can start a sandbox with or without a mount. Cloud sandboxes do not mount a host folder, so you clone work inside them.
- [Templates.](https://docs.docker.com/ai/sandboxes/usage/) Official agent templates exist for the built-in coding agents. You can also point `sbx` at your own image, which is how the Omarchy agent OS is used here.
- [TTL and size.](https://docs.docker.com/ai/sandboxes/cloud/) Cloud sandboxes accept `--ttl` (and a timeout action) and `--cpus` / `--memory`, so a coordinator can cap cost and lifetime. The default cloud TTL is one hour if you do not set one.
- [Docker-in-sandbox, with a caveat.](https://docs.docker.com/ai/sandboxes/architecture/) Official `sbx` agent templates include a private Docker engine inside the sandbox. The Omarchy image does not: it has no Docker Engine in the userland, which is called out in the project's limitations. Do not assume `docker` will work inside this particular template.

Plain `docker run` remains the quickest way to look around the image. Use `sbx` when you want the isolation, policy, and credential model that the agent OS is meant to live in.

## Quick start: Omarchy in a sandbox, then several agents in Herdr

The image is `juntaoyuan/omarchy-sandbox:4.5.0`. It has no desktop session; you get a shell as user `agent` in `/home/agent/workspace`.

Local Docker:

```bash
docker run -dit --name omarchy \
  -v "$PWD":/home/agent/workspace \
  juntaoyuan/omarchy-sandbox:4.5.0
```

Local Docker Sandboxes:

```bash
sbx login                     # once: sign in with your Docker account
sbx policy init balanced      # once: or allow-all / deny-all

cd ~/my-project
sbx create -t juntaoyuan/omarchy-sandbox:4.5.0 --name omarchy shell .
```

Cloud Docker Sandboxes, after the same `sbx login`:

```bash
sbx --cloud run --detach \
  --image-ref docker.io/juntaoyuan/omarchy-sandbox:4.5.0 \
  --cpus 2 --memory 4g --ttl 2h \
  --name omarchy
```

`--cpus 2 --memory 4g` is a small cloud size; `--ttl 2h` stops the sandbox after two hours. Nothing from the host is mounted, so clone repositories inside it. Cloud sandboxes are billed by size and time, so delete them when you are done (`sbx --cloud rm -f omarchy`, then `sbx --cloud ls`).

Log in:

```bash
docker exec -it omarchy bash -l          # Docker
sbx exec -it omarchy bash -l             # local sbx
sbx --cloud exec -it omarchy bash -l     # cloud sbx
```

Herdr's server is already running inside the environment. Start the TUI with `herdr`. On first launch, press Enter, then Esc, to dismiss the welcome screen.

From there the workflow is the one Omarchy uses on a desktop, minus the desktop. In the first pane, start Claude Code:

```bash
claude
```

Press **Ctrl+Space**, then **v**, to split a pane on the right (Ctrl+Space, then **h** splits below). In the new pane:

```bash
codex
```

Split once more and run a browser CLI, for example `agent-browser` or `chrome-devtools`. The prefix is Ctrl+Space throughout: **x** closes a pane, **z** zooms one, **c** opens a new tab, **d** detaches. Detaching leaves Herdr and every pane running. Run `herdr` again from a later shell to reattach to the same workspace.

The same layout can be driven from a script or a coordinator, without the TUI:

```bash
herdr pane list
herdr pane split w1:p1 --direction right
herdr pane run w1:p2 codex
```

The screenshots below were taken in this image, with Claude Code in the left pane, Codex in the upper right, and a Chrome-driven CLI in the lower right.

![Claude Code, Codex, and a Chrome browser CLI in three Herdr panes](images/herdr-multi-agent.png)

*Claude Code (Haiku) and Codex each wrote a short poem in their own Herdr pane, while the third pane used `agent-browser` and `chrome-devtools` to open example.com.*

![Herdr overview with workspaces and the agent sidebar](images/herdr-overview.png)

*Herdr's sidebar lists workspaces and the agents running in them. The same session can hold a "results" workspace and an "agents" workspace; Ctrl+Space, then d, detaches without stopping either.*

![Zoomed Herdr pane showing agent-browser and chrome-devtools](images/herdr-browser-pane.png)

*Zooming a pane (Ctrl+Space, then z) is useful when you want to read browser output in full. Here `agent-browser` has opened Example Domain, and `chrome-devtools` lists the pages in Chrome.*

When you are finished:

```bash
docker rm -f omarchy                # Docker
sbx stop omarchy; sbx rm omarchy    # local sbx
sbx --cloud rm -f omarchy           # cloud sbx
sbx --cloud ls
```

## Building the image

The image is a standalone build from `archlinux:base-devel`, not a fork of a desktop ISO. From a clone of [juntao/omarchy-sandbox](https://github.com/juntao/omarchy-sandbox):

```bash
docker build --build-arg OMARCHY_VERSION=v4.5.0 -t omarchy-sandbox:4.5.0 .
```

That Dockerfile is what turns Omarchy into a headless agent OS. It installs the Omarchy CLI and TUI configs (and records the tag and commit in `/etc/omarchy-sandbox-release`), then the agent and multiplexer stack, then Google Chrome, the `chrome-devtools` CLI, `chrome-devtools-mcp`, and `agent-browser`. Chrome and those CLIs are what make the image a complete agent computer, not only a shell with a text editor: an agent can install a package, edit a file, and also open a web page.

A short source-level cleanup policy keeps the layers small. Each `RUN` that downloads or builds something deletes its own caches — pacman, npm, yay and makepkg, nvim, `/tmp` — before the step ends, so those files never land in the committed layer. Desktop-only media (theme wallpapers, intro videos, preview images) and the Omarchy clone's `.git` directory are dropped for the same reason: a headless agent OS does not display them.

Publish a new build as a normal Docker Hub image:

```bash
docker tag omarchy-sandbox:4.5.0 juntaoyuan/omarchy-sandbox:4.5.0
docker tag omarchy-sandbox:4.5.0 juntaoyuan/omarchy-sandbox:latest
docker push juntaoyuan/omarchy-sandbox:4.5.0
docker push juntaoyuan/omarchy-sandbox:latest
```

Tags `4.5.0` and `latest` are linux/amd64. After a push, both `docker pull` and `sbx create -t juntaoyuan/omarchy-sandbox:4.5.0` pick up the new userland.

## Contribute

The project lives at [https://github.com/juntao/omarchy-sandbox](https://github.com/juntao/omarchy-sandbox). If you want a package, an agent, or a CLI in the sandbox, or you want a bug in the image or the docs fixed, change it there.

A typical contribution is a Dockerfile or script change, a rebuild, and a check that the new tool works in a plain container and, when you have KVM or cloud access, under `sbx`. Keep credentials out of the image and out of git. The repository README is the canonical quick start; this article follows the same commands.

Omarchy remains a desktop you can sit down at. The sandbox image is the same idea pointed at agents: an opinionated Linux userland, operable from a shell, isolated in a microVM, and easy to start, share, and throw away.
