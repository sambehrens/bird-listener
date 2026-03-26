#!/usr/bin/env bash
# install.sh — Set up bird-listener on a Raspberry Pi
# Run from the cloned repo directory: bash install.sh
set -euo pipefail

INSTALL_DIR="$HOME/bird-listener"
BIN_DIR="$INSTALL_DIR/bin"
BIRDNET_REPO="tphakala/birdnet-go"
BIRDNET_VERSION="v0.6.4"   # Pinned stable release

# BirdNET-Go v0.6.x reads config from this fixed location (no --config flag)
BIRDNET_CONFIG_DIR="$HOME/.config/birdnet-go"

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
        sox \
        alsa-utils \
        python3 \
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

    info "Downloading BirdNET-Go ${BIRDNET_VERSION}..."
    local archive="birdnet-go-linux-${BIRDNET_ARCH}-${BIRDNET_VERSION}.tar.gz"
    local url="https://github.com/${BIRDNET_REPO}/releases/download/${BIRDNET_VERSION}/${archive}"

    curl -L --progress-bar -o "/tmp/$archive" "$url" \
        || error "Download failed. Check that $url exists."

    info "Extracting..."
    tar -xzf "/tmp/$archive" -C "$BIN_DIR"
    chmod +x "$BIN_DIR/birdnet-go"
    rm "/tmp/$archive"

    # Install bundled TensorFlow Lite library system-wide
    if [[ -f "$BIN_DIR/libtensorflowlite_c.so" ]]; then
        info "Installing TensorFlow Lite library..."
        sudo cp "$BIN_DIR/libtensorflowlite_c.so" /usr/local/lib/
        sudo ldconfig
    fi

    info "BirdNET-Go installed at $BIN_DIR/birdnet-go"
}

# ── Config & directories ──────────────────────────────────────────────────────
setup_dirs() {
    mkdir -p "$INSTALL_DIR"/{logs,data,clips,scripts}
    mkdir -p "$BIRDNET_CONFIG_DIR"

    local repo_dir
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Copy birdnet config to the location BirdNET-Go expects
    if [[ ! -f "$BIRDNET_CONFIG_DIR/config.yaml" ]]; then
        cp "$repo_dir/config/birdnet-config.yaml" "$BIRDNET_CONFIG_DIR/config.yaml"
        info "Installed BirdNET-Go config to $BIRDNET_CONFIG_DIR/config.yaml"
    else
        info "Skipping BirdNET-Go config (already exists at $BIRDNET_CONFIG_DIR/config.yaml)"
    fi

    # Copy notify script and config
    if [[ "$repo_dir" != "$INSTALL_DIR" ]]; then
        cp "$repo_dir/config/blocklist.txt" "$INSTALL_DIR/config/blocklist.txt"
        cp "$repo_dir/scripts/notify.py"    "$INSTALL_DIR/scripts/notify.py"
    fi
    chmod +x "$INSTALL_DIR/scripts/notify.py"
}

# ── Systemd services ──────────────────────────────────────────────────────────
install_services() {
    info "Installing systemd services..."
    sudo cp systemd/birdnet-go.service  /etc/systemd/system/
    sudo cp systemd/bird-notify.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable birdnet-go bird-notify
    info "Services enabled."
}

# ── Config validation ─────────────────────────────────────────────────────────
check_config() {
    if grep -q "sam_b_bird_alerts" /etc/systemd/system/bird-notify.service 2>/dev/null; then
        info "ntfy topic: sam_b_bird_alerts — subscribe to this in the ntfy app on your phone."
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
    install_services
    check_config

    echo
    info "=== Installation complete ==="
    echo
    echo "Next steps:"
    echo "  1. Install the ntfy app on your phone and subscribe to: sam_b_bird_alerts"
    echo "  2. Start the services:"
    echo "       sudo systemctl start birdnet-go bird-notify"
    echo "  3. Check logs:"
    echo "       journalctl -u birdnet-go -f"
    echo "       journalctl -u bird-notify -f"
    echo "  4. Web UI: http://$(hostname -I | awk '{print $1}'):8080"
}

main "$@"
