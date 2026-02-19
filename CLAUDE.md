# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **DevContainer Features** repository that provides a single feature: `claude-code`. The feature installs Claude Code CLI and its sandbox dependencies (bubblewrap, socat, ripgrep) into development containers. It is published to GitHub Container Registry (GHCR) via the `devcontainers/action@v1` GitHub Action.

## Repository Structure

- `src/claude-code/devcontainer-feature.json` — Feature manifest defining metadata, options, mounts, and container environment
- `src/claude-code/install.sh` — Bash installation script that detects the package manager and installs dependencies
- `.github/workflows/release.yaml` — Publishes features to GHCR on GitHub Release or manual dispatch

## Development

There is no build step, test suite, or linter. The project consists of shell scripts and JSON configuration following the [Dev Container Feature specification](https://containers.dev/implementors/features/).

### Testing changes locally

Use the [Dev Container CLI](https://github.com/devcontainers/cli) to test the feature:

```bash
devcontainer features test --features claude-code --base-image mcr.microsoft.com/devcontainers/base:ubuntu
```

### Publishing

Features are published automatically when a GitHub Release is created. The workflow can also be triggered manually via `workflow_dispatch`. Only the `main` branch is eligible for publishing.

> **Important:** Consumers who reference the feature by a version tag (e.g. `:1`) will not pick up changes until the version in `src/claude-code/devcontainer-feature.json` is bumped and a new release is published. Always bump the version when making functional changes so that existing devcontainers can rebuild and get the update.

## Key Design Decisions

- **Privileged mode**: The container runs privileged (`"privileged": true`) because bubblewrap requires it for sandboxing.
- **Host credential mounts**: Three bind mounts pass `~/.claude`, `~/.claude.json`, and `~/.config/claude-code` from the host into the container at `/home/vscode/`.
- **Install order**: The feature declares `installsAfter` dependencies on `common-utils` and `node` features.
- **Multi-distro support**: `install.sh` detects apt-get, dnf, yum, or apk and installs packages accordingly.
- **Version option**: Accepts `"latest"`, `"stable"`, or a specific version number, passed through to the Claude Code installer script.
- **`CLAUDE_CODE_DISABLE_NONINTERACTIVE=1`**: Set as a container environment variable.
