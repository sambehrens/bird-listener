#!/usr/bin/env bash
# install.sh — Set up bird-listener on a Raspberry Pi
# Run from the cloned repo directory: bash install.sh
set -euo pipefail

INSTALL_DIR="$HOME/bird-listener"
BIN_DIR="$INSTALL_DIR/bin"
BIRDNET_REPO="tphakala/birdnet-go"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── OS check ──────────────────────────────────────────────────────────────────
check_os() {
    local version_id arch
    version_id=$(grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')
    arch=$(uname -m)

    if [[ "$version_id" -lt 11 ]] 2>/dev/null; then
        error "Raspbian/Raspberry Pi OS version $version_id is too old.\n" \
              "Please flash a fresh 64-bit Raspberry Pi OS (Bookworm/Bullseye) to your SD card.\n" \
              "Download: https://www.raspberrypi.com/software/"
    fi

    if [[ "$arch" == "aarch64" ]]; then
        BIRDNET_ARCH="arm64"
    elif [[ "$arch" == "armv7l" ]]; then
        BIRDNET_ARCH="armv7"
    else
        error "Unsupported architecture: $arch"
    fi

    info "OS OK — Debian $version_id, arch: $arch (BirdNET binary: $BIRDNET_ARCH)"
}

# ── Dependencies ──────────────────────────────────────────────────────────────
install_deps() {
    info "Updating package list..."
    sudo apt-get update -qq

    info "Installing system dependencies..."
    sudo apt-get install -y --no-install-recommends \
        ffmpeg \
        alsa-utils \
        python3 \
        python3-pip \
        python3-venv \
        curl \
        git

    info "Checking audio device..."
    if ! arecord -l 2>/dev/null | grep -q "Sennheiser"; then
        warn "Sennheiser Profile mic not detected. Check USB connection."
        warn "Run 'arecord -l' to list available devices."
    else
        info "Sennheiser Profile detected."
    fi
}

# ── BirdNET-Go binary ─────────────────────────────────────────────────────────
install_birdnet() {
    mkdir -p "$BIN_DIR"

    info "Fetching latest BirdNET-Go release..."
    local latest_tag
    latest_tag=$(curl -s "https://api.github.com/repos/${BIRDNET_REPO}/releases/latest" \
        | grep '"tag_name"' | head -1 | cut -d'"' -f4)

    if [[ -z "$latest_tag" ]]; then
        error "Could not fetch BirdNET-Go release info. Check internet connection."
    fi
    info "Latest release: $latest_tag"

    local archive="birdnet-go_Linux_${BIRDNET_ARCH}.tar.gz"
    local url="https://github.com/${BIRDNET_REPO}/releases/download/${latest_tag}/${archive}"

    info "Downloading $archive..."
    curl -L --progress-bar -o "/tmp/$archive" "$url" \
        || error "Download failed. Check that $url exists."

    info "Extracting..."
    tar -xzf "/tmp/$archive" -C "$BIN_DIR"
    chmod +x "$BIN_DIR/birdnet-go"
    rm "/tmp/$archive"

    info "BirdNET-Go installed at $BIN_DIR/birdnet-go"
}

# ── Python venv + Apprise ─────────────────────────────────────────────────────
install_apprise() {
    info "Creating Python virtual environment..."
    python3 -m venv "$INSTALL_DIR/.venv"
    "$INSTALL_DIR/.venv/bin/pip" install --quiet --upgrade pip
    "$INSTALL_DIR/.venv/bin/pip" install --quiet apprise
    info "Apprise installed."
}

# ── Config & directories ──────────────────────────────────────────────────────
setup_dirs() {
    mkdir -p "$INSTALL_DIR"/{logs,data,config}

    # Copy config files if they don't already exist (don't overwrite customised ones)
    for f in config/birdnet-config.yaml config/apprise.yaml; do
        if [[ ! -f "$INSTALL_DIR/$f" ]]; then
            cp "$f" "$INSTALL_DIR/$f"
            info "Copied $f"
        else
            info "Skipping $f (already exists)"
        fi
    done

    cp scripts/notify.py "$INSTALL_DIR/scripts/notify.py"
    chmod +x "$INSTALL_DIR/scripts/notify.py"
}

# ── Systemd services ──────────────────────────────────────────────────────────
install_services() {
    info "Installing systemd services..."
    sudo cp systemd/birdnet-go.service   /etc/systemd/system/
    sudo cp systemd/bird-notify.service  /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable birdnet-go bird-notify
    info "Services enabled (will start on next boot, or run 'sudo systemctl start birdnet-go bird-notify')"
}

# ── Config validation ─────────────────────────────────────────────────────────
check_config() {
    local cfg="$INSTALL_DIR/config/birdnet-config.yaml"
    local ntfy_cfg="$INSTALL_DIR/config/apprise.yaml"

    if grep -q "longitude: 0.0" "$cfg"; then
        warn "Latitude/longitude not set in birdnet-config.yaml."
        warn "BirdNET-Go uses location for species filtering — set these for better accuracy."
    fi

    if grep -q "YOUR_NTFY_TOPIC" "$ntfy_cfg"; then
        warn "ntfy topic not set in config/apprise.yaml."
        warn "Edit the file and replace YOUR_NTFY_TOPIC with your chosen topic name,"
        warn "then subscribe to it in the ntfy app on your phone."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    info "=== bird-listener installer ==="
    info "Install directory: $INSTALL_DIR"

    check_os
    install_deps
    setup_dirs
    install_birdnet
    install_apprise
    install_services
    check_config

    echo
    info "=== Installation complete ==="
    echo
    echo "Next steps:"
    echo "  1. Edit $INSTALL_DIR/config/birdnet-config.yaml"
    echo "     → Set latitude and longitude for your location"
    echo "  2. Edit $INSTALL_DIR/config/apprise.yaml"
    echo "     → Replace YOUR_NTFY_TOPIC with your chosen topic name"
    echo "     → Install the ntfy app and subscribe to that topic"
    echo "  3. Start the services:"
    echo "       sudo systemctl start birdnet-go bird-notify"
    echo "  4. Check logs:"
    echo "       journalctl -u birdnet-go -f"
    echo "       journalctl -u bird-notify -f"
    echo "  5. Web UI: http://$(hostname -I | awk '{print $1}'):8080"
}

main "$@"
