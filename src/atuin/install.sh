#!/usr/bin/env bash
set -euo pipefail

# Atuin Shell History
# This script installs the Atuin binary and configures shell integration
# for bash and zsh with --disable-up-arrow. Sync is disabled via the
# ATUIN_AUTO_SYNC=false container environment variable set in the feature manifest.

# Blanket safety net: if anything below fails without hitting one of our own
# explicit error messages (e.g. an unexpected command failure), at least say
# where, instead of the build log going straight from "Installing Atuin..."
# to "failed to install!" with nothing in between.
trap 'echo "ERROR: install.sh failed at line ${LINENO} (exit code $?)." >&2' ERR

# Optional DEBUG feature option (-> $DEBUG) traces every command, useful when
# diagnosing a failure that isn't covered by one of the messages below.
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# $HOME is not guaranteed to be set when a devcontainer feature's install.sh
# runs (the devcontainer CLI execs the script directly, not via a login
# shell). Under `set -u` an unset $HOME would abort the script instantly,
# before any of our own messages get a chance to print. Guard it.
HOME="${HOME:-/root}"

VERSION="${VERSION:-latest}"
# Normalize an accidentally-doubled "v" prefix: a user-supplied "v1.18.0"
# combined with our own "v${VERSION}" below would otherwise request the
# nonexistent tag "vv1.18.0".
VERSION="${VERSION#v}"

# The devcontainer CLI exports _REMOTE_USER / _REMOTE_USER_HOME for feature
# install scripts. Prefer those over hardcoding "vscode" so the feature also
# works against images with a differently named remote user; fall back to
# "vscode" (this feature's supported default) when they're absent.
TARGET_USER="${_REMOTE_USER:-vscode}"
TARGET_USER_HOME="${_REMOTE_USER_HOME:-$(getent passwd "${TARGET_USER}" 2>/dev/null | cut -d: -f6 || echo "/home/${TARGET_USER}")}"

echo "Installing Atuin (version: ${VERSION}) for user ${TARGET_USER}..."

# Install atuin using the official installer and move the resulting binary
# to a system-wide location.
install_atuin() {
    # Run the installer with an isolated, throwaway $HOME and an explicit
    # install directory instead of assuming $HOME/.atuin/bin/atuin:
    #   - The installer is cargo-dist based and honors CARGO_DIST_FORCE_INSTALL_DIR,
    #     so we don't have to guess (or keep up with) its default install path.
    #   - Redirecting $HOME also means the installer's own shell-rc edits
    #     (it appends PATH/env sourcing to .bashrc/.profile/.zshrc of whatever
    #     $HOME it sees) land in a scratch directory instead of root's real
    #     dotfiles, so there's nothing to clean up afterwards and no dangling
    #     "source ~/.atuin/bin/env" reference once we delete the install dir.
    #     Our own configure_shell_init() below is the sole writer of shell
    #     integration into the real dotfiles.
    local install_tmp
    install_tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${install_tmp}'" RETURN

    local installer_script="${install_tmp}/atuin-installer.sh"
    local install_dir="${install_tmp}/bin"

    if [ "${VERSION}" = "latest" ]; then
        # Download to a file first, then execute it as a separate step.
        # Piping curl straight into `sh` (the previous approach) merges both
        # commands' exit codes into one opaque `pipefail` result and hides
        # curl's own errors. It also runs the untrusted script fully
        # interactively-probed: without --non-interactive, setup.atuin.sh
        # tries `exec 3</dev/tty` to detect a terminal, and under `sh` (dash,
        # the default /bin/sh on Debian-based images) a failed redirection on
        # a special builtin like `exec` is fatal to the whole script -- even
        # though it's inside an `if` guard -- when no tty is attached, which
        # is always the case during a container build. That is the actual
        # cause of the ~1.7s, no-error-message failure this feature has been
        # hitting: the installer aborts via dash's exec/tty behavior before
        # printing anything, and our own error branches never get a chance
        # to run because the pipeline already failed under `set -euo pipefail`.
        if ! curl --proto '=https' --tlsv1.2 -LsSf -o "${installer_script}" https://setup.atuin.sh; then
            echo "ERROR: Failed to download the Atuin installer from https://setup.atuin.sh" >&2
            exit 1
        fi
        if ! HOME="${install_tmp}" CARGO_DIST_FORCE_INSTALL_DIR="${install_dir}" \
            sh "${installer_script}" --non-interactive; then
            echo "ERROR: Atuin installer (setup.atuin.sh) exited with a non-zero status." >&2
            exit 1
        fi
    else
        if ! curl --proto '=https' --tlsv1.2 -LsSf -o "${installer_script}" \
            "https://github.com/atuinsh/atuin/releases/download/v${VERSION}/atuin-installer.sh"; then
            echo "ERROR: Failed to download the Atuin installer for version ${VERSION}" >&2
            exit 1
        fi
        if ! HOME="${install_tmp}" CARGO_DIST_FORCE_INSTALL_DIR="${install_dir}" \
            sh "${installer_script}"; then
            echo "ERROR: Atuin installer (atuin-installer.sh) exited with a non-zero status." >&2
            exit 1
        fi
    fi

    if [ ! -f "${install_dir}/atuin" ]; then
        echo "ERROR: Atuin binary not found after installation (expected at ${install_dir}/atuin)." >&2
        exit 1
    fi

    # Move binary to /usr/local/bin so it is on the default PATH for all users
    mv "${install_dir}/atuin" /usr/local/bin/atuin
    chmod 755 /usr/local/bin/atuin
}

# Create placeholder directories for bind mounts so the container starts
# even if the host paths don't exist yet.
#
# NOTE: ${TARGET_USER_HOME}/.config/atuin and .local/share/atuin are exactly
# the two paths bind-mounted from the host in devcontainer-feature.json's
# "mounts". At container start those mounts overlay whatever we create here
# entirely -- inode, permissions and ownership all come from the host source
# directory, not from this build step. So the mkdir/chown below only matters
# as a fallback for the image being run without those mounts attached (e.g.
# a standalone `docker run` or a test harness); it does nothing for actual
# ownership problems seen through the normal devcontainer mount at runtime.
# If the host directories are owned by something the target user can't
# write, that has to be fixed after the mount is live -- e.g. in
# postCreateCommand/postStartCommand -- not here at build time.
prepare_mount_dirs() {
    mkdir -p "${TARGET_USER_HOME}/.config/atuin"
    mkdir -p "${TARGET_USER_HOME}/.local/share/atuin"

    if id "${TARGET_USER}" &>/dev/null; then
        # Scoped to the atuin data dir only -- a recursive chown of the whole
        # .local would also re-own unrelated sibling directories (.local/bin,
        # other apps' .local/share/*) that other features may have already
        # populated.
        chown -R "${TARGET_USER}:${TARGET_USER}" \
            "${TARGET_USER_HOME}/.config/atuin" \
            "${TARGET_USER_HOME}/.local/share/atuin"
    fi
}

# Append atuin shell integration to bashrc and zshrc with up-arrow disabled.
configure_shell_init() {
    local bash_init='eval "$(atuin init bash --disable-up-arrow)"'
    local zsh_init='eval "$(atuin init zsh --disable-up-arrow)"'

    # Configure bash
    local bashrc="${TARGET_USER_HOME}/.bashrc"
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
    local zshrc="${TARGET_USER_HOME}/.zshrc"
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
    if id "${TARGET_USER}" &>/dev/null; then
        chown "${TARGET_USER}:${TARGET_USER}" "${bashrc}" "${zshrc}"
    fi
}

install_atuin
prepare_mount_dirs
configure_shell_init

echo "Atuin shell history installed and configured successfully."
