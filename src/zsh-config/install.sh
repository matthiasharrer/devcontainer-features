#!/usr/bin/env bash
set -euo pipefail

# Zsh Config — Oh My Zsh, zsh-autosuggestions, Spaceship prompt
# Designed for the "vscode" user that devcontainers create by default.

USERNAME="${USERNAME:-vscode}"
USER_HOME="$(getent passwd "${USERNAME}" 2>/dev/null | cut -d: -f6 || echo "/home/${USERNAME}")"

echo "Installing Oh My Zsh with zsh-autosuggestions and spaceship-prompt for ${USERNAME}..."

# Ensure zsh and git are available (common-utils usually provides them, but be safe)
if command -v apt-get &>/dev/null; then
    apt-get update -y
    apt-get install -y --no-install-recommends zsh git curl ca-certificates
    apt-get clean
    rm -rf /var/lib/apt/lists/*
elif command -v dnf &>/dev/null; then
    dnf install -y zsh git curl ca-certificates
    dnf clean all
elif command -v yum &>/dev/null; then
    yum install -y zsh git curl ca-certificates
    yum clean all
elif command -v apk &>/dev/null; then
    apk add --no-cache zsh git curl ca-certificates
fi

# Install Oh My Zsh (unattended, no shell change prompt)
if [ ! -d "${USER_HOME}/.oh-my-zsh" ]; then
    su - "${USERNAME}" -c \
        'export RUNZSH=no CHSH=no; curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash'
fi

OMZ_DIR="${USER_HOME}/.oh-my-zsh"
ZSH_CUSTOM="${OMZ_DIR}/custom"

# Install zsh-autosuggestions plugin
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
        "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi

# Install spaceship-prompt theme
if [ ! -d "${ZSH_CUSTOM}/themes/spaceship-prompt" ]; then
    git clone --depth 1 https://github.com/spaceship-prompt/spaceship-prompt \
        "${ZSH_CUSTOM}/themes/spaceship-prompt"
    ln -sf "${ZSH_CUSTOM}/themes/spaceship-prompt/spaceship.zsh-theme" \
        "${ZSH_CUSTOM}/themes/spaceship.zsh-theme"
fi

# Configure .zshrc — set theme and enable the plugin
ZSHRC="${USER_HOME}/.zshrc"
if [ -f "${ZSHRC}" ]; then
    # Set spaceship theme
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="spaceship"/' "${ZSHRC}"
    # Add zsh-autosuggestions to plugins list
    if ! grep -q 'zsh-autosuggestions' "${ZSHRC}"; then
        sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "${ZSHRC}"
    fi
fi

# Fix ownership
chown -R "${USERNAME}:${USERNAME}" "${OMZ_DIR}" "${ZSHRC}"

echo "Oh My Zsh with zsh-autosuggestions and spaceship-prompt installed successfully."
