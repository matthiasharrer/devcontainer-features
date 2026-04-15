#!/usr/bin/env bash
set -euo pipefail

# Claude Code with Sandbox Dependencies and Voice Mode Support
# This script installs Claude Code CLI, the system packages required
# for its sandbox feature (bubblewrap, socat, ripgrep), and audio
# packages for voice mode (sox, PulseAudio/ALSA).

VERSION="${VERSION:-latest}"

echo "Installing Claude Code (version: ${VERSION}) with sandbox and voice-mode dependencies..."

# Detect the package manager and install sandbox dependencies
install_sandbox_deps() {
    if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y --no-install-recommends \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates \
            sox \
            libsox-fmt-pulse \
            alsa-utils \
            libpulse0
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    elif command -v dnf &>/dev/null; then
        dnf install -y \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates \
            sox \
            alsa-utils \
            pulseaudio-libs
        dnf clean all
    elif command -v yum &>/dev/null; then
        yum install -y \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates \
            sox \
            alsa-utils \
            pulseaudio-libs
        yum clean all
    elif command -v apk &>/dev/null; then
        apk add --no-cache \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates \
            sox \
            alsa-utils \
            pulseaudio-libs
    else
        echo "ERROR: Unsupported package manager. Install bubblewrap, socat, and ripgrep manually."
        exit 1
    fi
}

# Install Claude Code via the native installer.
# Run inside a subshell with HOME pointing at the vscode user's home so the
# installer places the binary where the container user can find it.
install_claude_code() {
    local user_home
    user_home="$(getent passwd vscode 2>/dev/null | cut -d: -f6 || echo "/home/vscode")"

    (
        export HOME="${user_home}"
        if [ "${VERSION}" = "latest" ]; then
            curl -fsSL https://claude.ai/install.sh | bash -s latest
        elif [ "${VERSION}" = "stable" ]; then
            curl -fsSL https://claude.ai/install.sh | bash
        else
            curl -fsSL https://claude.ai/install.sh | bash -s "${VERSION}"
        fi
    )
}

# Ensure mounted config paths exist with correct ownership inside the container.
# The bind mounts in devcontainer-feature.json will overlay these, but we create
# them so that the container can start even if the host paths don't exist yet.
prepare_config_dirs() {
    local user_home
    user_home="$(getent passwd vscode 2>/dev/null | cut -d: -f6 || echo "/home/vscode")"

    mkdir -p "${user_home}/.claude"
    mkdir -p "${user_home}/.config/claude-code"
    mkdir -p "${user_home}/.local/bin"
    # Write a valid empty JSON object if the file doesn't exist yet.
    # Using `touch` would produce an empty file which Claude Code's JSON
    # parser rejects with "Unexpected EOF" during installation.
    if [ ! -f "${user_home}/.claude.json" ]; then
        echo '{}' > "${user_home}/.claude.json"
    fi

}

# Install the Claude Code sandbox runtime via npm.
# npm is guaranteed to be available via the hard dependsOn on the node feature.
install_sandbox_runtime() {
    npm install -g @anthropic-ai/sandbox-runtime
}

install_sandbox_deps
prepare_config_dirs
install_claude_code
install_sandbox_runtime

# Fix ownership of ~/.local and ~/.cache after all installers have run.
# install_claude_code and install_sandbox_runtime execute as root with HOME set
# to the vscode home, so they may create these directories (or subdirs) owned
# by root. ~/.claude, ~/.claude.json, and ~/.config/claude-code are intentionally
# excluded: they are bind-mounted from the host at runtime and would be overlaid
# anyway, so chowning them here is both pointless and potentially misleading.
fix_ownership() {
    if ! id vscode &>/dev/null; then
        return
    fi
    local user_home
    user_home="$(getent passwd vscode 2>/dev/null | cut -d: -f6 || echo "/home/vscode")"

    for dir in \
        "${user_home}/.local" \
        "${user_home}/.cache"; do
        if [ -e "${dir}" ]; then
            chown -R vscode:vscode "${dir}"
        fi
    done
}

fix_ownership

echo "Claude Code with sandbox and voice-mode dependencies installed successfully."
