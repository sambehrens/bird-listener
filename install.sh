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
        sox \
        alsa-utils \
        curl \
        git

    info "Checking audio device..."
    if ! arecord -l 2>/dev/null | grep -q "Sennheiser"; then
        warn "Sennheiser Profile mic not detected. Check USB connection."
        warn "Run 'arecord -l' to list available devices and update audio.source in birdnet-config.yaml."
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

    local archive="birdnet-go-linux-${BIRDNET_ARCH}.tar.gz"
    local url="https://github.com/${BIRDNET_REPO}/releases/download/${latest_tag}/${archive}"

    info "Downloading $archive..."
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
    mkdir -p "$INSTALL_DIR"/{logs,data,config,clips}

    local repo_dir
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Only copy config if source and destination differ (repo cloned elsewhere)
    if [[ "$repo_dir" != "$INSTALL_DIR" ]]; then
        if [[ ! -f "$INSTALL_DIR/config/birdnet-config.yaml" ]]; then
            cp "$repo_dir/config/birdnet-config.yaml" "$INSTALL_DIR/config/birdnet-config.yaml"
            info "Copied config/birdnet-config.yaml"
        else
            info "Skipping config/birdnet-config.yaml (already exists)"
        fi
    else
        info "Running in-place — skipping file copy"
    fi
}

# ── Systemd services ──────────────────────────────────────────────────────────
install_services() {
    info "Installing systemd service..."
    sudo cp systemd/birdnet-go.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable birdnet-go
    info "Service enabled (will start on next boot, or run 'sudo systemctl start birdnet-go')"
}

# ── Config validation ─────────────────────────────────────────────────────────
check_config() {
    local cfg="$INSTALL_DIR/config/birdnet-config.yaml"

    if grep -q "latitude: 0" "$cfg"; then
        warn "Latitude/longitude not set in birdnet-config.yaml."
        warn "BirdNET-Go uses location for species filtering — set these for better accuracy."
    fi

    if grep -q "sam_b_bird_alerts" "$cfg"; then
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
    echo "  2. Start the service:"
    echo "       sudo systemctl start birdnet-go"
    echo "  3. Check logs:"
    echo "       journalctl -u birdnet-go -f"
    echo "  4. Web UI: http://$(hostname -I | awk '{print $1}'):8080"
}

main "$@"
