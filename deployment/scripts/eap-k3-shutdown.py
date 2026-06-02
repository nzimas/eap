#!/usr/bin/env python3
"""Gracefully power off EAP when the Fates K3 gpio-key is pressed."""

from __future__ import annotations

import os
import select
import struct
import subprocess
import sys
import time
from pathlib import Path


DEFAULT_DEVICE = "/dev/input/by-path/platform-keys-event"
K3_CODE = int(os.environ.get("EAP_K3_KEY_CODE", "3"))
DEBOUNCE_SECONDS = float(os.environ.get("EAP_K3_DEBOUNCE_SECONDS", "0.35"))
DEVICE = os.environ.get("EAP_K3_INPUT", DEFAULT_DEVICE)
TTY = os.environ.get("EAP_STATUS_TTY", "/dev/tty1")

EVENT_FORMAT = "llHHI"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)
EV_KEY = 1
KEY_DOWN = 1


def log(message: str) -> None:
    print(f"eap-k3-shutdown: {message}", flush=True)


def wait_for_device(path: str) -> Path:
    target = Path(path)
    last_log_at = 0.0
    while not target.exists():
        now = time.monotonic()
        if now - last_log_at >= 30.0:
            log(f"waiting for {path}")
            last_log_at = now
        time.sleep(1.0)
    return target


def write_status() -> None:
    try:
        with open(TTY, "w", encoding="utf-8", errors="ignore") as handle:
            handle.write("\033[2J\033[H")
            handle.write("EAP - HALT\n")
            handle.write("CPU -- + RAM --\n")
            handle.write("LP - OFFLINE\n")
    except OSError as exc:
        log(f"could not write shutdown status to {TTY}: {exc}")


def request_shutdown() -> None:
    log("K3 pressed, requesting graceful poweroff")
    write_status()
    subprocess.run(["systemctl", "poweroff"], check=False)


def watch_device(path: Path) -> None:
    with path.open("rb", buffering=0) as handle:
        poller = select.poll()
        poller.register(handle, select.POLLIN | select.POLLERR | select.POLLHUP)
        log(f"watching {path} for key code {K3_CODE}")
        while True:
            events = poller.poll()
            for _, mask in events:
                if mask & (select.POLLERR | select.POLLHUP):
                    raise OSError(f"{path} disappeared")
                data = handle.read(EVENT_SIZE)
                if len(data) != EVENT_SIZE:
                    continue
                _, _, event_type, code, value = struct.unpack(EVENT_FORMAT, data)
                if event_type == EV_KEY and code == K3_CODE and value == KEY_DOWN:
                    request_shutdown()
                    return


def main() -> int:
    while True:
        path = wait_for_device(DEVICE)
        try:
            watch_device(path)
            return 0
        except OSError as exc:
            log(str(exc))
            time.sleep(1.0)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
