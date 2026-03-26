#!/usr/bin/env python3
"""
Bird detection notification watcher.

Tails the BirdNET-Go detection log and sends an ntfy push notification
for each new detection. Run as a systemd service alongside birdnet-go.

Detection log format (v0.6.4 OBS chat log):
  08:23:45 Northern Cardinal
"""

import re
import sys
import time
import argparse
import sqlite3
import urllib.request
from pathlib import Path

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


def lookup_confidence(db_path: Path, common_name: str, detection_time: str) -> float | None:
    """Return confidence from the DB for this detection, or None if not found."""
    if not db_path.exists():
        return None
    try:
        with sqlite3.connect(db_path) as conn:
            row = conn.execute(
                "SELECT confidence FROM notes WHERE common_name = ? AND time = ? "
                "ORDER BY id DESC LIMIT 1",
                (common_name, detection_time),
            ).fetchone()
        return row[0] if row else None
    except sqlite3.Error:
        return None


def notify(ntfy_url: str, title: str, body: str) -> None:
    req = urllib.request.Request(
        ntfy_url,
        data=body.encode(),
        headers={"Title": title},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=10)


def main():
    parser = argparse.ArgumentParser(description="BirdNET-Go → ntfy notifier")
    parser.add_argument(
        "--log",
        default="/home/sam/bird-listener/logs/detections.log",
        help="Path to BirdNET-Go detections.log",
    )
    parser.add_argument(
        "--ntfy-url",
        default="https://ntfy.sh/sam_b_bird_alerts",
        help="ntfy topic URL",
    )
    parser.add_argument(
        "--blocklist",
        default="/home/sam/bird-listener/config/blocklist.txt",
        help="Path to blocklist file (one bird name per line)",
    )
    parser.add_argument(
        "--db",
        default="/home/sam/bird-listener/birdnet.db",
        help="Path to BirdNET-Go SQLite database",
    )
    args = parser.parse_args()

    log_path = Path(args.log)
    blocklist_path = Path(args.blocklist)
    db_path = Path(args.db)

    # Wait for the log file to appear (birdnet-go may not have started yet)
    print(f"Waiting for detection log: {log_path}")
    while not log_path.exists():
        time.sleep(5)

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

        confidence = lookup_confidence(db_path, detection["common"], detection["time"])
        confidence_str = f" ({int(confidence * 100)}%)" if confidence is not None else ""

        title = f"{detection['common']}{confidence_str}"
        body = detection["time"]

        print(f"Notifying: {title}")
        notify(args.ntfy_url, title, body)


if __name__ == "__main__":
    main()
