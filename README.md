# Bird Listener

24/7 bird detection using BirdNET-Go with push notifications via ntfy. Runs on a Raspberry Pi 3.

## How it works

```
USB microphone
        │
        ▼
  BirdNET-Go v0.6.4 (realtime mode)
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
- Downloads BirdNET-Go v0.6.4 binary (arm64)
- Installs the bundled TensorFlow Lite library
- Copies config to `~/.config/birdnet-go/config.yaml`
- Installs and enables both systemd services

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

## Configuration

### `config/birdnet-config.yaml`

Key settings:

| Setting | Value | Notes |
|---------|-------|-------|
| `birdnet.latitude` | `36.1183` | Tulsa, OK |
| `birdnet.longitude` | `-95.9765` | Tulsa, OK |
| `birdnet.threshold` | `0.75` | Min confidence to record (0.1–1.0) |
| `birdnet.threads` | `2` | CPU threads (Pi 3 has 4 cores) |
| `realtime.audio.source` | `USB Audio` | Matched by device name substring |

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

Run `arecord -l` to list devices. BirdNET-Go v0.6.4 matches `realtime.audio.source` by substring of the device name. Run `arecord -L` to see full ALSA names.

## Known issues

**Thumbnail errors in web UI** — BirdNET-Go v0.6.4 fetches bird images from Wikipedia, which has blocked its requests. This causes `Error getting thumbnail info` log spam but does not affect detection or notifications. Fixed in nightly builds, but nightly builds have an unrelated audio bug (broadcast callback not registered) that prevents audio capture entirely. Revisit upgrading when a new stable release is available.
