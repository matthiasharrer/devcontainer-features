#!/usr/bin/env bash
set -euo pipefail

# Workspace Color — build-time installer
# Installs jq and places the runtime color script at
# /usr/local/bin/devcontainer-workspace-color.

SATURATION="${SATURATION:-65}"
LIGHTNESS="${LIGHTNESS:-30}"
TARGETS="${TARGETS:-titleBar}"
SEED="${SEED:-}"

echo "Installing devcontainer-workspace-color..."

# --- Install jq (multi-distro) ---
install_jq() {
    if command -v jq &>/dev/null; then
        echo "jq is already installed."
        return
    fi

    if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y --no-install-recommends jq
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    elif command -v dnf &>/dev/null; then
        dnf install -y jq
        dnf clean all
    elif command -v yum &>/dev/null; then
        yum install -y jq
        yum clean all
    elif command -v apk &>/dev/null; then
        apk add --no-cache jq
    else
        echo "ERROR: Unsupported package manager. Install jq manually."
        exit 1
    fi
}

install_jq

# --- Write build-time config ---
mkdir -p /usr/local/lib
cat > /usr/local/lib/devcontainer-workspace-color.conf << EOF
SATURATION=${SATURATION}
LIGHTNESS=${LIGHTNESS}
TARGETS=${TARGETS}
SEED=${SEED}
EOF

# --- Embed the runtime color script ---
cat > /usr/local/bin/devcontainer-workspace-color << 'RUNTIME_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# devcontainer-workspace-color — runtime script
# Runs via postStartCommand on every container start.
# Deterministically colors VS Code UI elements based on the host workspace path.

# ---- Load config (baked at build time) ----
CONF="/usr/local/lib/devcontainer-workspace-color.conf"
if [ -f "$CONF" ]; then
    . "$CONF"
fi
SATURATION="${SATURATION:-65}"
LIGHTNESS="${LIGHTNESS:-30}"
TARGETS="${TARGETS:-titleBar}"
SEED="${SEED:-}"

# Clamp lightness to max 45 for white-text readability
if [ "$LIGHTNESS" -gt 45 ] 2>/dev/null; then
    LIGHTNESS=45
fi

# ---- Determine workspace path ----
WORKSPACE_DIR="${PWD}"

# ---- Resolve host path from /proc/self/mountinfo ----
# Field 4 = root (host source path), Field 5 = mount point (container path)
HOST_PATH=""
if [ -r /proc/self/mountinfo ]; then
    HOST_PATH="$(awk -v target="$WORKSPACE_DIR" '$5 == target {print $4; exit}' /proc/self/mountinfo 2>/dev/null)" || true
fi
HOST_PATH="${HOST_PATH:-$WORKSPACE_DIR}"

# ---- Generate deterministic hue from hash ----
HASH_INPUT="${SEED}${HOST_PATH}"
HEX="$(printf '%s' "$HASH_INPUT" | sha256sum | cut -c1-4)"
HUE=$(( 16#$HEX % 360 ))

# ---- HSL to RGB (integer arithmetic, scale=1000) ----
hsl_to_hex() {
    local h="$1" s="$2" l="$3"
    local s1000=$(( s * 10 ))
    local l1000=$(( l * 10 ))

    # C = (1 - |2L - 1|) * S
    local abs_2l_1=$(( 2 * l1000 - 1000 ))
    if [ "$abs_2l_1" -lt 0 ]; then abs_2l_1=$(( -abs_2l_1 )); fi
    local c=$(( (1000 - abs_2l_1) * s1000 / 1000 ))

    # X = C * (1 - |H/60 mod 2 - 1|)
    local h_prime=$(( h * 1000 / 60 ))
    local h_mod2=$(( h_prime % 2000 ))
    local abs_h=$(( h_mod2 - 1000 ))
    if [ "$abs_h" -lt 0 ]; then abs_h=$(( -abs_h )); fi
    local x=$(( c * (1000 - abs_h) / 1000 ))

    # m = L - C/2
    local m=$(( l1000 - c / 2 ))

    local r1=0 g1=0 b1=0
    if [ "$h" -lt 60 ]; then     r1=$c; g1=$x; b1=0
    elif [ "$h" -lt 120 ]; then  r1=$x; g1=$c; b1=0
    elif [ "$h" -lt 180 ]; then  r1=0;  g1=$c; b1=$x
    elif [ "$h" -lt 240 ]; then  r1=0;  g1=$x; b1=$c
    elif [ "$h" -lt 300 ]; then  r1=$x; g1=0;  b1=$c
    else                         r1=$c; g1=0;  b1=$x
    fi

    local r=$(( (r1 + m) * 255 / 1000 ))
    local g=$(( (g1 + m) * 255 / 1000 ))
    local b=$(( (b1 + m) * 255 / 1000 ))

    # Clamp
    [ "$r" -lt 0 ] && r=0; [ "$r" -gt 255 ] && r=255
    [ "$g" -lt 0 ] && g=0; [ "$g" -gt 255 ] && g=255
    [ "$b" -lt 0 ] && b=0; [ "$b" -gt 255 ] && b=255

    printf '#%02x%02x%02x' "$r" "$g" "$b"
}

BG_COLOR="$(hsl_to_hex "$HUE" "$SATURATION" "$LIGHTNESS")"
INACTIVE_SAT=$(( SATURATION * 60 / 100 ))
INACTIVE_LIGHT=$(( LIGHTNESS * 80 / 100 ))
INACTIVE_BG="$(hsl_to_hex "$HUE" "$INACTIVE_SAT" "$INACTIVE_LIGHT")"

# ---- Build jq filter from targets ----
JQ_FILTER="."

IFS=',' read -ra TARGET_LIST <<< "$TARGETS"
for target in "${TARGET_LIST[@]}"; do
    target="$(echo "$target" | tr -d ' ')"
    case "$target" in
        titleBar)
            JQ_FILTER="$JQ_FILTER"'
                | .["workbench.colorCustomizations"]["titleBar.activeBackground"] = "'"$BG_COLOR"'"
                | .["workbench.colorCustomizations"]["titleBar.activeForeground"] = "#ffffff"
                | .["workbench.colorCustomizations"]["titleBar.inactiveBackground"] = "'"$INACTIVE_BG"'"
                | .["workbench.colorCustomizations"]["titleBar.inactiveForeground"] = "#cccccc"'
            ;;
        statusBar)
            JQ_FILTER="$JQ_FILTER"'
                | .["workbench.colorCustomizations"]["statusBar.background"] = "'"$BG_COLOR"'"
                | .["workbench.colorCustomizations"]["statusBar.foreground"] = "#ffffff"'
            ;;
        activityBar)
            JQ_FILTER="$JQ_FILTER"'
                | .["workbench.colorCustomizations"]["activityBar.background"] = "'"$BG_COLOR"'"
                | .["workbench.colorCustomizations"]["activityBar.foreground"] = "#ffffff"'
            ;;
        *)
            echo "devcontainer-workspace-color: unknown target '$target', skipping" >&2
            ;;
    esac
done

if [ "$JQ_FILTER" = "." ]; then
    echo "devcontainer-workspace-color: no valid targets, exiting"
    exit 0
fi

# ---- Merge into VS Code machine settings (container-local, not in workspace) ----
SETTINGS_DIR="${HOME}/.vscode-server/data/Machine"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"

# Skip if the first target's key is already set (respect user customization)
FIRST_TARGET="$(echo "${TARGET_LIST[0]}" | tr -d ' ')"
CHECK_KEY=""
case "$FIRST_TARGET" in
    titleBar)    CHECK_KEY="titleBar.activeBackground" ;;
    statusBar)   CHECK_KEY="statusBar.background" ;;
    activityBar) CHECK_KEY="activityBar.background" ;;
esac

if [ -n "$CHECK_KEY" ] && [ -f "$SETTINGS_FILE" ]; then
    EXISTING="$(jq -r ".[\"workbench.colorCustomizations\"][\"$CHECK_KEY\"] // empty" "$SETTINGS_FILE" 2>/dev/null)" || true
    if [ -n "$EXISTING" ]; then
        exit 0
    fi
fi

# Create directory and merge/create settings
mkdir -p "$SETTINGS_DIR"

if [ -f "$SETTINGS_FILE" ]; then
    TEMP="$(mktemp)"
    if jq "$JQ_FILTER" "$SETTINGS_FILE" > "$TEMP" 2>/dev/null; then
        mv "$TEMP" "$SETTINGS_FILE"
    else
        rm -f "$TEMP"
        echo "devcontainer-workspace-color: could not parse existing settings.json, skipping" >&2
        exit 0
    fi
else
    echo '{}' | jq "$JQ_FILTER" > "$SETTINGS_FILE"
fi

echo "devcontainer-workspace-color: applied $BG_COLOR to ${TARGETS} (from ${HOST_PATH})"
RUNTIME_SCRIPT

chmod 755 /usr/local/bin/devcontainer-workspace-color

echo "devcontainer-workspace-color installed successfully."
