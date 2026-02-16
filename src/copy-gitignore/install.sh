#!/usr/bin/env bash
set -euo pipefail

# Copy Global Gitignore
# This script creates a placeholder ~/.gitignore and configures git
# to use it as the global excludes file. The actual host file is copied
# into place by the postStartCommand defined in devcontainer-feature.json.

echo "Configuring global gitignore..."

setup_gitignore() {
    local user_home
    user_home="$(getent passwd vscode 2>/dev/null | cut -d: -f6 || echo "/home/vscode")"

    # Create placeholder so the container starts even if the host file is missing
    touch "${user_home}/.gitignore"

    # Configure git to use ~/.gitignore as the global excludes file.
    # Git expands the tilde, so this works regardless of the actual home path.
    git config -f "${user_home}/.gitconfig" core.excludesFile "~/.gitignore"

    # Fix ownership if the vscode user exists
    if id vscode &>/dev/null; then
        chown vscode:vscode "${user_home}/.gitignore" "${user_home}/.gitconfig"
    fi
}

setup_gitignore

echo "Global gitignore configured successfully."
