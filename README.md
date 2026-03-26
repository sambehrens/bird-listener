# Bird Listener

A bird detector using BirdNET-Go and Apprise to run bird detection 24/7 at my house. Runs on a Raspberry Pi 3.

## How it works

- **BirdNET-Go** continuously listens via a USB microphone and identifies bird species using a neural network
- **notify.py** tails the detection log and fires an **Apprise** notification for each new detection
- **ntfy** delivers push notifications to your phone (iOS/Android, free)
- Two **systemd services** keep both processes running and auto-restart them on failure

```
Sennheiser Profile (USB mic)
        │
        ▼
  BirdNET-Go (realtime mode)
        │  writes detections.log
        ▼
  notify.py (tails log)
        │  calls Apprise
        ▼
  ntfy.sh → phone notification
```

## Requirements

**Hardware:**
- Raspberry Pi 3 (or newer)
- USB microphone (Sennheiser Profile confirmed working)

**OS — IMPORTANT:**
This setup requires **Raspberry Pi OS Bookworm or Bullseye (64-bit recommended)**.
The Pi ships with a very old Raspbian Jessie image that is EOL and incompatible.
Flash a fresh OS before proceeding: https://www.raspberrypi.com/software/

## Setup

### 1. Phone notifications (do this first)

1. Install the [ntfy app](https://ntfy.sh/) on your phone (iOS/Android, free)
2. Choose a unique topic name — something like `yourname-birds-abc123`
3. Subscribe to it in the app

### 2. Flash the Pi

Flash a fresh **Raspberry Pi OS Lite (64-bit, Bookworm)** to the SD card using Raspberry Pi Imager.
Enable SSH in the imager settings and set your hostname/credentials.

### 3. Clone this repo onto the Pi

```bash
ssh pi@<pi-ip>
git clone <this-repo-url> /home/sam/bird-listener
cd /home/sam/bird-listener
```

### 4. Configure

**`config/birdnet-config.yaml`** — set your location:
```yaml
birdnet:
  latitude: 36.1183
  longitude: -95.9765
```

**`config/apprise.yaml`** — ntfy topic is already set to `sam_b_bird_alerts`. Subscribe to this in the ntfy app on your phone.

### 5. Run the installer

```bash
bash install.sh
```

The installer will:
- Install system dependencies (ffmpeg, alsa-utils, python3)
- Download the latest BirdNET-Go binary for your architecture
- Create a Python venv and install Apprise
- Install and enable both systemd services

### 6. Start

```bash
sudo systemctl start birdnet-go bird-notify
```

### 7. Verify

```bash
# Watch detections in real time
tail -f /home/sam/bird-listener/logs/detections.log

# Check service status
sudo systemctl status birdnet-go
sudo systemctl status bird-notify

# Web UI
http://<pi-ip>:8080
```

## Configuration reference

| File | Purpose |
|------|---------|
| `config/birdnet-config.yaml` | BirdNET-Go settings (audio source, location, thresholds) |
| `config/apprise.yaml` | Notification destinations (ntfy topic, can add more) |

### Tuning detection sensitivity

In `birdnet-config.yaml`:
- `birdnet.threshold` — minimum confidence to log a detection (default `0.75`)
- `birdnet.sensitivity` — model sensitivity, higher = more detections (default `1.0`)

In `bird-notify.service` / `notify.py`:
- `--min-confidence` — minimum confidence to send a notification (default `0.75`)

You can set the notification threshold higher than the log threshold to log everything
but only notify on high-confidence detections.

## Adding more notification destinations

Edit `config/apprise.yaml` and add entries. Apprise supports 80+ services:
```yaml
urls:
  - ntfy://ntfy.sh/YOUR_NTFY_TOPIC
  - discord://webhook_id/webhook_token
  - mailto://user:password@gmail.com
```

Full list: https://github.com/caronc/apprise/wiki
