# Bird Listener

24/7 bird detection using BirdNET-Go with push notifications via ntfy. Runs on a Raspberry Pi 3.

## How it works

```
Sennheiser Profile (USB mic, plughw:2,0)
        │
        ▼
  BirdNET-Go (realtime mode)
        │  built-in shoutrrr notification
        ▼
  ntfy.sh (sam_b_bird_alerts) → phone
```

BirdNET-Go handles everything: audio capture, bird identification, and push notifications. One service, no extra processes.

## Requirements

**Hardware:**
- Raspberry Pi 3 (or newer, 64-bit)
- USB microphone (Sennheiser Profile confirmed working on card 2)

**OS:** Raspberry Pi OS Lite **64-bit, Bookworm** (Debian 12+). Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) — enable SSH in the settings.

## Setup

### 1. Phone — subscribe to ntfy

1. Install the [ntfy app](https://ntfy.sh/) (iOS/Android, free)
2. Subscribe to topic: **`sam_b_bird_alerts`**

### 2. Flash the Pi

Use Raspberry Pi Imager to flash **Raspberry Pi OS Lite (64-bit)**. In the settings (⚙️):
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
- Installs ffmpeg, sox, alsa-utils
- Downloads the latest BirdNET-Go binary (arm64)
- Installs the bundled TensorFlow Lite library
- Installs and enables the systemd service

### 4. Start

```bash
sudo systemctl start birdnet-go
```

### 5. Verify

```bash
# Live logs
journalctl -u birdnet-go -f

# Web UI (detections, spectrogram, settings)
http://<pi-ip>:8080
```

## Configuration

**`config/birdnet-config.yaml`** — the only config file needed. Key settings:

| Setting | Value | Notes |
|---------|-------|-------|
| `birdnet.latitude` | `36.1183` | Tulsa, OK |
| `birdnet.longitude` | `-95.9765` | Tulsa, OK |
| `birdnet.threshold` | `0.75` | Min confidence to record (0.1–1.0) |
| `birdnet.threads` | `2` | CPU threads (Pi 3 has 4 cores) |
| `realtime.audio.source` | `USB Audio` | Sennheiser Profile (v0.6.4 matches by name) |
| `notification.push.providers[0].urls` | `ntfy://ntfy.sh/sam_b_bird_alerts` | ntfy topic |

### Changing the audio device

Run `arecord -l` to list devices. BirdNET-Go v0.6.4 matches the source by substring of the device name (e.g. `"USB Audio"` for Sennheiser Profile). Use `arecord -L` to see full ALSA names if needed.

### Adding more notification destinations

BirdNET-Go uses [shoutrrr](https://containrrr.dev/shoutrrr/services/overview/) for notifications. Add URLs to `notification.push.providers[0].urls`:
```yaml
urls:
  - ntfy://ntfy.sh/sam_b_bird_alerts
  - slack://token@channel
  - telegram://<bot-token>@telegram?chats=<chat-id>
```
