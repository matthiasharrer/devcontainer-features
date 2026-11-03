# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **DevContainer Features** repository. Every subdirectory of `src/` is one feature, published to GitHub Container Registry (GHCR) as `ghcr.io/matthiasharrer/devcontainer-features/<id>` via the `devcontainers/action@v1` GitHub Action.

### Features

| Feature | What it does | Host bind mounts (host → container) |
|---|---|---|
| `mine` | Wrapper feature without its own installation; bundles `global-gitignore`, `atuin` and `zsh-config` via `dependsOn`. | none of its own (the bundled features bring theirs) |
| `claude-code` | Installs the Claude Code CLI with sandbox dependencies (bubblewrap, socat, ripgrep) and voice-mode audio support (sox, PulseAudio); runs privileged. | `~/.claude` → `/home/vscode/.claude`, `~/.claude.json` → `/home/vscode/.claude.json`, `~/.config/claude-code` → `/home/vscode/.config/claude-code`, `${XDG_RUNTIME_DIR:-/run/user/1000}/pulse` → `/run/user/1000/pulse` |
| `devcontainer-workspace-color` | Colors VS Code's title bar (optionally status/activity bar) with a deterministic color derived from the host workspace path. | none |
| `global-gitignore` | Mounts the host's global gitignore and configures it as git's global excludes file. | `~/.gitignore` → `/home/vscode/.gitignore` |
| `atuin` | Installs Atuin shell history with bash/zsh integration (up-arrow disabled, sync disabled — the host syncs). Never runs its own daemon; uses the host daemon through a socket in the mounted data dir (see `src/atuin/README.md`). | `~/.config/atuin` → `/home/vscode/.config/atuin`, `~/.local/share/atuin` → `/home/vscode/.local/share/atuin` |
| `zsh-config` | Installs Oh My Zsh with the zsh-autosuggestions plugin and the Spaceship prompt theme. | none |

`claude-code` and `devcontainer-workspace-color` are not part of `mine`; they stay available as standalone features.

## Repository Structure

- `src/<id>/devcontainer-feature.json` — Feature manifest (metadata, version, options, mounts, container environment, `dependsOn`/`installsAfter`)
- `src/<id>/install.sh` — Installation script run during the container build
- `.github/workflows/release.yaml` — Publishes all features to GHCR on push to `main` or manual dispatch

## Development

There is no build step, test suite, or linter. The project consists of shell scripts and JSON configuration following the [Dev Container Feature specification](https://containers.dev/implementors/features/).

### Testing changes locally

Use the [Dev Container CLI](https://github.com/devcontainers/cli) to test a feature, passing its id via `--features <id>`, e.g.:

```bash
devcontainer features test --features atuin --base-image mcr.microsoft.com/devcontainers/base:ubuntu
```

### Publishing

The release workflow publishes features to GHCR on every push to `main`; it can also be triggered manually via `workflow_dispatch`. Only the `main` branch is eligible for publishing.

> **Important — version bumps:** Consumers reference features by a version tag (e.g. `:1`) and only pick up changes when a new version is published. For every functional change to a feature, bump the `version` in that feature's `devcontainer-feature.json`. If what `mine` bundles changes (features added to or removed from its `dependsOn`), bump the version of `mine` as well.

## Key Design Decisions

### `claude-code`

- **Privileged mode**: The container runs privileged (`"privileged": true`) because bubblewrap requires it for sandboxing.
- **Host credential mounts**: Bind mounts pass `~/.claude`, `~/.claude.json`, and `~/.config/claude-code` from the host into the container at `/home/vscode/`; the host PulseAudio socket is mounted for voice mode.
- **Install order**: The feature depends on the `node` feature and declares `installsAfter` on `common-utils` and `node`.
- **Multi-distro support**: `install.sh` detects apt-get, dnf, yum, or apk and installs packages accordingly.
- **Version option**: Accepts `"latest"`, `"stable"`, or a specific version number, passed through to the Claude Code installer script.
- **`CLAUDE_CODE_DISABLE_NONINTERACTIVE=1`**: Set as a container environment variable.
