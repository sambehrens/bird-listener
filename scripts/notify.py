#!/usr/bin/env python3
"""
Bird detection notification watcher.

Tails the BirdNET-Go detection log and sends an Apprise notification
for each new detection. Run as a systemd service alongside birdnet-go.

Detection log format (v0.6.4 OBS chat log):
  08:23:45 Northern Cardinal
"""

import re
import sys
import time
import argparse
from pathlib import Path

import apprise

# Regex to parse a detection log line (v0.6.4 format: HH:MM:SS Common Name)
DETECTION_RE = re.compile(r"(?P<time>\d{2}:\d{2}:\d{2})\s+(?P<common>.+)")


def parse_detection(line: str) -> dict | None:
    m = DETECTION_RE.search(line)
    if not m:
        return None
    return {
        "time": m.group("time"),
        "common": m.group("common").strip(),
    }


def tail_file(path: Path):
    """Open and seek to end, then yield new lines as they arrive."""
    with open(path) as f:
        f.seek(0, 2)  # seek to end
        while True:
            line = f.readline()
            if line:
                yield line
            else:
                time.sleep(0.5)


def build_apprise(config_path: Path) -> apprise.Apprise:
    ac = apprise.AppriseConfig()
    ac.add(str(config_path))
    ap = apprise.Apprise()
    ap.add(ac)
    return ap


def main():
    parser = argparse.ArgumentParser(description="BirdNET-Go → Apprise notifier")
    parser.add_argument(
        "--log",
        default="/home/sam/bird-listener/logs/detections.log",
        help="Path to BirdNET-Go detections.log",
    )
    parser.add_argument(
        "--config",
        default="/home/sam/bird-listener/config/apprise.yaml",
        help="Path to Apprise config file",
    )
    parser.add_argument(
        "--blocklist",
        default="/home/sam/bird-listener/config/blocklist.txt",
        help="Path to blocklist file (one bird name per line)",
    )
    args = parser.parse_args()

    log_path = Path(args.log)
    config_path = Path(args.config)
    blocklist_path = Path(args.blocklist)

    if not config_path.exists():
        print(f"ERROR: Apprise config not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    # Wait for the log file to appear (birdnet-go may not have started yet)
    print(f"Waiting for detection log: {log_path}")
    while not log_path.exists():
        time.sleep(5)

    ap = build_apprise(config_path)
    print(f"Watching {log_path} for detections...")

    for line in tail_file(log_path):
        line = line.strip()
        if not line:
            continue

        detection = parse_detection(line)
        if not detection:
            continue

        # Reload blocklist on every detection so edits take effect immediately
        blocklist = set()
        if blocklist_path.exists():
            for entry in blocklist_path.read_text().splitlines():
                entry = entry.strip()
                if entry and not entry.startswith("#"):
                    blocklist.add(entry.lower())

        if detection["common"].lower() in blocklist:
            print(f"Blocked: {detection['common']}")
            continue

        title = f"Bird detected: {detection['common']}"
        body = detection["time"]

        print(f"Notifying: {title}")
        ap.notify(title=title, body=body, tag="bird")


if __name__ == "__main__":
    main()
