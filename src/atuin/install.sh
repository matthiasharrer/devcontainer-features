#!/usr/bin/env bash
set -euo pipefail

# Atuin Shell History
# This script installs the Atuin binary and configures shell integration
# for bash and zsh with --disable-up-arrow. Sync is disabled via the
# ATUIN_AUTO_SYNC=false container environment variable set in the feature manifest.

VERSION="${VERSION:-latest}"

echo "Installing Atuin (version: ${VERSION})..."

# Install atuin using the official installer, then move the binary to a
# system-wide location. The installer drops the binary into ~/.atuin/bin/
# which during build time is /root/.atuin/bin/.
install_atuin() {
    if [ "${VERSION}" = "latest" ]; then
        curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
    else
        curl --proto '=https' --tlsv1.2 -LsSf \
            "https://github.com/atuinsh/atuin/releases/download/v${VERSION}/atuin-installer.sh" | sh
    fi

    # Move binary to /usr/local/bin so it is on the default PATH for all users
    if [ -f "$HOME/.atuin/bin/atuin" ]; then
        mv "$HOME/.atuin/bin/atuin" /usr/local/bin/atuin
        chmod 755 /usr/local/bin/atuin
        rm -rf "$HOME/.atuin"
    else
        echo "ERROR: Atuin binary not found after installation."
        exit 1
    fi
}

# Create placeholder directories for bind mounts so the container starts
# even if the host paths don't exist yet.
prepare_mount_dirs() {
    local user_home
    user_home="$(getent passwd vscode 2>/dev/null | cut -d: -f6 || echo "/home/vscode")"

    mkdir -p "${user_home}/.config/atuin"
    mkdir -p "${user_home}/.local/share/atuin"

    # Fix ownership if the vscode user exists
    if id vscode &>/dev/null; then
        chown -R vscode:vscode "${user_home}/.config/atuin" "${user_home}/.local/share/atuin"
    fi
}

# Append atuin shell integration to bashrc and zshrc with up-arrow disabled.
configure_shell_init() {
    local user_home
    user_home="$(getent passwd vscode 2>/dev/null | cut -d: -f6 || echo "/home/vscode")"

    local bash_init='eval "$(atuin init bash --disable-up-arrow)"'
    local zsh_init='eval "$(atuin init zsh --disable-up-arrow)"'

    # Configure bash
    local bashrc="${user_home}/.bashrc"
    if [ -f "${bashrc}" ]; then
        if ! grep -qF "atuin init bash" "${bashrc}"; then
            echo "" >> "${bashrc}"
            echo "# Atuin shell history" >> "${bashrc}"
            echo "${bash_init}" >> "${bashrc}"
        fi
    else
        echo "# Atuin shell history" > "${bashrc}"
        echo "${bash_init}" >> "${bashrc}"
    fi

    # Configure zsh
    local zshrc="${user_home}/.zshrc"
    if [ -f "${zshrc}" ]; then
        if ! grep -qF "atuin init zsh" "${zshrc}"; then
            echo "" >> "${zshrc}"
            echo "# Atuin shell history" >> "${zshrc}"
            echo "${zsh_init}" >> "${zshrc}"
        fi
    else
        echo "# Atuin shell history" > "${zshrc}"
        echo "${zsh_init}" >> "${zshrc}"
    fi

    # Fix ownership of rc files
    if id vscode &>/dev/null; then
        chown vscode:vscode "${bashrc}" "${zshrc}"
    fi
}

install_atuin
prepare_mount_dirs
configure_shell_init

echo "Atuin shell history installed and configured successfully."
