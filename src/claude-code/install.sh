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

# Install seccomp filter binaries from the @anthropic-ai/sandbox-runtime npm
# package. This downloads only the tarball and extracts the pre-built vendor
# binaries, avoiding a full `npm install -g`. The files are placed at a path
# that Claude Code's sandbox-runtime probes automatically.
install_seccomp_filter() {
    local pkg="@anthropic-ai/sandbox-runtime"
    local dest="/usr/local/lib/node_modules/@anthropic-ai/sandbox-runtime"
    local tmpdir

    tmpdir="$(mktemp -d)"
    trap "rm -rf '${tmpdir}'" RETURN

    echo "Downloading ${pkg} tarball for seccomp binaries..."
    # npm pack writes a tarball without installing anything
    if ! npm pack "${pkg}" --pack-destination "${tmpdir}" >/dev/null 2>&1; then
        echo "WARNING: Failed to download ${pkg}. Seccomp filter will not be installed."
        return 0
    fi

    local tarball
    tarball="$(ls "${tmpdir}"/anthropic-ai-sandbox-runtime-*.tgz 2>/dev/null | head -1)"
    if [ -z "${tarball}" ]; then
        echo "WARNING: Tarball not found after npm pack. Seccomp filter will not be installed."
        return 0
    fi

    # Extract only the vendor/seccomp directory
    mkdir -p "${dest}/vendor/seccomp"
    tar xzf "${tarball}" -C "${dest}/vendor/seccomp" --strip-components=2 \
        "package/vendor/seccomp" 2>/dev/null || true

    # Ensure apply-seccomp binaries are executable
    chmod +x "${dest}/vendor/seccomp/x64/apply-seccomp" 2>/dev/null || true
    chmod +x "${dest}/vendor/seccomp/arm64/apply-seccomp" 2>/dev/null || true

    if [ -f "${dest}/vendor/seccomp/x64/apply-seccomp" ] || \
       [ -f "${dest}/vendor/seccomp/arm64/apply-seccomp" ]; then
        echo "Seccomp filter binaries installed to ${dest}/vendor/seccomp/"
    else
        echo "WARNING: Seccomp binaries were not found in the package."
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
    touch "${user_home}/.claude.json"

    # Fix ownership if the vscode user exists
    if id vscode &>/dev/null; then
        chown -R vscode:vscode "${user_home}/.claude" "${user_home}/.claude.json" "${user_home}/.config/claude-code"
    fi
}

install_sandbox_deps
install_claude_code
install_seccomp_filter
prepare_config_dirs

echo "Claude Code and sandbox dependencies installed successfully."
