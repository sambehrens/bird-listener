# Bird Listener

24/7 bird detection using BirdNET-Go with push notifications via ntfy. Runs on a Raspberry Pi 3.

## How it works

```
  USB microphone
        │
        ▼
  BirdNET-Go nightly-20260414 (realtime mode)
        │  writes detections to logs/detections.log
        ▼
  notify.py (watches log file)
        │  HTTP POST
        ▼
  ntfy.sh (sam_b_bird_alerts) → phone
```

Two systemd services run continuously: `birdnet-go` for audio capture and detection, `bird-notify` for watching the log and sending phone notifications.

Notifications include the confidence score (e.g. "Carolina Wren (93%)") and are throttled to once per bird per 5 minutes.

## Requirements

**Hardware:**
- Raspberry Pi 3 (or newer, 64-bit)
- USB microphone

**OS:** Raspberry Pi OS Lite **64-bit, Bookworm** (Debian 12+). Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — enable SSH in the settings.

## Setup

### 1. Phone — subscribe to ntfy

1. Install the [ntfy app](https://ntfy.sh/) (iOS/Android, free)
2. Subscribe to topic: **`sam_b_bird_alerts`**

### 2. Flash the Pi

Use Raspberry Pi Imager to flash **Raspberry Pi OS Lite (64-bit)**. In the settings:
- Set hostname, username, password
- **Enable SSH**

### 3. Copy repo and run installer

From your Mac:
```bash
scp -r /path/to/bird-listener sam@<pi-ip>:/home/sam/
ssh sam@<pi-ip>
cd bird-listener
bash install.sh
```

The installer:
- Installs ffmpeg, sox, alsa-utils, python3
- Downloads BirdNET-Go nightly-20260414 binary (arm64)
- Installs the bundled TensorFlow Lite library
- Copies config to `~/.config/birdnet-go/config.yaml`
- Installs and enables both systemd services

If you are upgrading an existing Pi from BirdNET-Go v0.6.x, the first nightly start will migrate `~/.config/birdnet-go/config.yaml` to the new multi-source audio format automatically.

### 5. Start

```bash
sudo systemctl start birdnet-go bird-notify
```

### 6. Verify

```bash
# Live detection log
journalctl -u birdnet-go -f

# Notification watcher log
journalctl -u bird-notify -f

# Web UI (detections, spectrogram, settings)
http://<pi-ip>:8080
```

## SSH access

The Pi's IP is `192.168.1.97` (hostname: `pi3`, user: `sam`).

```bash
ssh sam@192.168.1.97
```

### Setting up from scratch on the Pi

If you need to set up or re-install directly on the Pi without copying from your Mac:

```bash
ssh sam@192.168.1.97

# Clone the repo
git clone https://github.com/sambehrens/bird-listener.git /home/sam/bird-listener

# Run the installer
cd /home/sam/bird-listener
bash install.sh

# Start services
sudo systemctl start birdnet-go bird-notify
```

### Making changes via SSH

Edit files directly on the Pi, then commit and push back to the repo:

```bash
ssh sam@192.168.1.97
cd ~/bird-listener

# Edit a file, e.g. the blocklist
nano config/blocklist.txt

# Commit and push
git add config/blocklist.txt
git commit -m "Update blocklist"
git push
```

For config changes that require a restart:
```bash
# birdnet-go config
nano ~/.config/birdnet-go/config.yaml
sudo systemctl restart birdnet-go

# notification script
nano ~/bird-listener/scripts/notify.py
sudo systemctl restart bird-notify
```

## Configuration

### `config/birdnet-config.yaml`

Key settings:

| Setting | Value | Notes |
|---------|-------|-------|
| `birdnet.latitude` | `36.1183` | Tulsa, OK |
| `birdnet.longitude` | `-95.9765` | Tulsa, OK |
| `birdnet.threshold` | `0.75` | Min confidence to record (0.1–1.0) |
| `birdnet.threads` | `2` | CPU threads (Pi 3 has 4 cores) |
| `realtime.audio.sources[0].device` | `USB Audio` | ALSA capture device name for the USB microphone |

After editing, copy to the Pi and restart:
```bash
scp config/birdnet-config.yaml sam@<pi-ip>:~/.config/birdnet-go/config.yaml
ssh sam@<pi-ip> sudo systemctl restart birdnet-go
```

### `config/blocklist.txt`

Birds to suppress notifications for. One name per line, case-insensitive. Lines starting with `#` are comments.

```
House Sparrow
European Starling
```

Changes take effect immediately — no restart needed. Deploy with:
```bash
scp config/blocklist.txt sam@<pi-ip>:/home/sam/bird-listener/config/blocklist.txt
```

### Changing the audio device

Run `arecord -l` to list devices. Set `realtime.audio.sources[0].device` to the ALSA capture device name you want BirdNET-Go to open. Run `arecord -L` to see full ALSA names.

## Upgrade notes

**nightly-20260414** replaces the old single-source `realtime.audio.source` setting with `realtime.audio.sources[]`. The bundled config in this repo already uses the new layout, and existing v0.6.x configs are migrated automatically by BirdNET-Go on first nightly start.

**nightly-20260414** also expects a model label locale such as `en-us` or `en-uk` instead of the old generic `en`. The bundled config now uses `en-us`.
