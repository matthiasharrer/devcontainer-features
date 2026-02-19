#!/usr/bin/env bash
set -euo pipefail

# Claude Code with Sandbox Dependencies
# This script installs Claude Code CLI and the system packages required
# for its sandbox feature (bubblewrap, socat, ripgrep).

VERSION="${VERSION:-latest}"

echo "Installing Claude Code (version: ${VERSION}) and sandbox dependencies..."

# Detect the package manager and install sandbox dependencies
install_sandbox_deps() {
    if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y --no-install-recommends \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    elif command -v dnf &>/dev/null; then
        dnf install -y \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates
        dnf clean all
    elif command -v yum &>/dev/null; then
        yum install -y \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates
        yum clean all
    elif command -v apk &>/dev/null; then
        apk add --no-cache \
            bubblewrap \
            socat \
            ripgrep \
            curl \
            ca-certificates
    else
        echo "ERROR: Unsupported package manager. Install bubblewrap, socat, and ripgrep manually."
        exit 1
    fi
}

# Install Claude Code via the native installer
install_claude_code() {
    if [ "${VERSION}" = "latest" ]; then
        curl -fsSL https://claude.ai/install.sh | bash -s latest
    elif [ "${VERSION}" = "stable" ]; then
        curl -fsSL https://claude.ai/install.sh | bash
    else
        curl -fsSL https://claude.ai/install.sh | bash -s "${VERSION}"
    fi
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
    touch "${user_home}/.claude.json"

    # Fix ownership if the vscode user exists.
    # Other features (e.g. atuin) may create ~/.local owned by root during the
    # build phase. Claude Code needs ~/.local/bin to be writable by the
    # container user, so we fix ownership here.
    if id vscode &>/dev/null; then
        chown -R vscode:vscode "${user_home}/.claude" "${user_home}/.claude.json" "${user_home}/.config/claude-code" "${user_home}/.local"
    fi
}

install_sandbox_deps
install_claude_code
prepare_config_dirs

echo "Claude Code and sandbox dependencies installed successfully."
