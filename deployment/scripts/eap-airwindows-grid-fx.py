#!/usr/bin/env python3
"""Manage the EAP Airwindows LV2 grid FX insert chain."""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import signal
import shutil
import socket
import subprocess
import time
from pathlib import Path
from contextlib import contextmanager
import fcntl


FX_NAMES = [
    "TapeDelay2", "PitchDelay", "Doublelay", "SampleDelay", "Melt", "ADT", "StarChild2", "TakeCare",
    "RingModulator", "Dubly3", "GalacticVibe", "Pafnuty2", "PitchNasty", "GuitarConditioner", "GlitchShifter", "Gringer",
    "Nikola", "HipCrush", "DeRez3", "Pockey2", "CrunchyGrooveWear", "BitGlitter", "TapeBias", "Vibrato",
    "Deckwrecka", "DeNoise", "Texturize", "VoiceOfTheStarship", "ElectroHat", "Silhouette",
]
MAX_ACTIVE = 3
STATE_DIR = Path(os.environ.get("EAP_AIRWINDOWS_STATE_DIR", "/home/we/.local/share/eap-airwindows"))
STATE_PATH = STATE_DIR / "grid-fx.json"
LOG_DIR = STATE_DIR / "logs"
LOCK_PATH = STATE_DIR / "grid-fx.lock"
RT_PRIO = int(os.environ.get("EAP_AIRWINDOWS_RT_PRIO", "55"))
HOST_PORT = int(os.environ.get("EAP_AIRWINDOWS_HOST_PORT", "57930"))
HOST_LOG = LOG_DIR / "eap-airwindows-host.log"


def run(args: list[str], check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


@contextmanager
def locked_state():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with LOCK_PATH.open("w") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file, fcntl.LOCK_UN)


def jalv_command(client: str) -> list[str]:
    base = ["jalv", "-i", "-n", client]
    if RT_PRIO > 0 and shutil.which("chrt") is not None:
        return ["chrt", "-f", str(RT_PRIO)] + base
    return base


def host_command() -> list[str]:
    return ["/usr/local/bin/eap-airwindows-host", str(HOST_PORT)]


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def send_host(message: str) -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.sendto(message.encode("utf-8"), ("127.0.0.1", HOST_PORT))
        return True
    except OSError:
        return False


def host_pids() -> list[int]:
    result = run(["ps", "-eo", "pid=,comm=,args="])
    if result.returncode != 0:
        return []
    pids: list[int] = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue
        comm = parts[1]
        args = parts[2] if len(parts) > 2 else ""
        argv0 = args.split(None, 1)[0] if args else ""
        if comm.startswith("eap-airwindows") or argv0 == "/usr/local/bin/eap-airwindows-host":
            pids.append(pid)
    return pids


def kill_hosts(except_pid: int = 0) -> None:
    pids = [pid for pid in host_pids() if pid != except_pid]
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for pid in pids:
        if pid_alive(pid):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def host_ports_ready() -> bool:
    result = run(["jack_lsp"])
    if result.returncode != 0:
        return False
    ports = set(result.stdout.splitlines())
    return {
        "eap-airwindows:in_l",
        "eap-airwindows:in_r",
        "eap-airwindows:out_l",
        "eap-airwindows:out_r",
    }.issubset(ports)


def connect_host_ports() -> None:
    pairs = [
        ("SuperCollider:out_3", "eap-airwindows:in_l"),
        ("SuperCollider:out_4", "eap-airwindows:in_r"),
        ("eap-airwindows:out_l", "SuperCollider:in_1"),
        ("eap-airwindows:out_r", "SuperCollider:in_2"),
    ]
    for src, dst in pairs:
        jack_connect(src, dst)


def start_host_if_needed(state: dict) -> int:
    host_pid = int(state.get("host_pid", 0) or 0)
    if pid_alive(host_pid) and host_ports_ready():
        kill_hosts(except_pid=host_pid)
        connect_host_ports()
        return host_pid
    kill_hosts()
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log = HOST_LOG.open("ab")
    proc = subprocess.Popen(host_command(), stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    deadline = time.time() + 5.0
    while time.time() < deadline:
        if host_ports_ready():
            connect_host_ports()
            return proc.pid
        if proc.poll() is not None:
            break
        time.sleep(0.1)
    return proc.pid


def load_state() -> dict:
    if not STATE_PATH.exists():
        return {"active": [], "pids": []}
    try:
        data = json.loads(STATE_PATH.read_text())
    except Exception:
        return {"active": [], "pids": []}
    data["active"] = [int(i) for i in data.get("active", []) if 1 <= int(i) <= len(FX_NAMES)]
    data["pids"] = [int(pid) for pid in data.get("pids", []) if int(pid) > 0]
    data["host_pid"] = int(data.get("host_pid", 0) or 0)
    return data


def save_state(active: list[int], pids: list[int]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    previous = load_state()
    STATE_PATH.write_text(json.dumps({
        "active": active,
        "pids": pids,
        "host_pid": int(previous.get("host_pid", 0) or 0),
        "updated_at": time.time(),
    }, indent=2))


def save_host_state(active: list[int], host_pid: int) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps({
        "active": active,
        "pids": [],
        "host_pid": host_pid,
        "updated_at": time.time(),
    }, indent=2))


def kill_old(pids: list[int]) -> None:
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
    time.sleep(0.25)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass


def lv2_uris() -> list[str]:
    result = run(["lv2ls"])
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def uri_for_fx(name: str, uris: list[str]) -> str | None:
    lower = name.lower()
    exact = [uri for uri in uris if uri.rstrip("/#").split("/")[-1].split("#")[-1].lower() == lower]
    if exact:
        return exact[0]
    contains = [uri for uri in uris if lower in uri.lower() and "airwindows" in uri.lower()]
    return contains[0] if contains else None


def control_ports(uri: str) -> list[tuple[str, float, float, float]]:
    result = run(["lv2info", uri])
    if result.returncode != 0:
        return []
    ports: list[tuple[str, float, float, float]] = []
    current: dict[str, str] = {}
    for raw in result.stdout.splitlines() + ["Port 999:"]:
        line = raw.strip()
        if re.match(r"^(Control )?Port [0-9]+:", line):
            symbol = current.get("symbol")
            if symbol and current.get("type", "").lower().find("input") >= 0:
                try:
                    default = float(current.get("default", "0.5"))
                    minimum = float(current.get("minimum", "0.0"))
                    maximum = float(current.get("maximum", "1.0"))
                except ValueError:
                    current = {}
                    continue
                if maximum > minimum and all(map(lambda v: abs(v) < 1.0e9, (minimum, maximum, default))):
                    ports.append((symbol, minimum, maximum, default))
            current = {}
            continue
        if ":" in line:
            key, value = line.split(":", 1)
            current[key.strip().lower()] = value.strip()
    return ports


def randomized_controls(uri: str, rng: random.Random) -> list[str]:
    controls = []
    for symbol, minimum, maximum, default in control_ports(uri):
        name = symbol.lower()
        if "bypass" in name or "enabled" in name:
            value = minimum
        elif maximum <= 1.0 and minimum >= 0.0:
            spread = rng.uniform(0.20, 0.85)
            value = (default * 0.35) + (spread * 0.65)
        else:
            value = rng.uniform(minimum, maximum)
        value = max(minimum, min(maximum, value))
        controls.append(f"{symbol}={value:.6f}")
    return controls[:24]


def jack_ports(client: str, direction: str) -> list[str]:
    result = run(["jack_lsp"])
    if result.returncode != 0:
        return []
    candidates = []
    for line in result.stdout.splitlines():
        port = line.strip()
        lower = port.lower()
        if not lower.startswith(client.lower() + ":"):
            continue
        if any(word in lower for word in ("midi", "event", "control")):
            continue
        if direction == "in" and re.search(r"(in|input|lv2_audio_in)", lower):
            candidates.append(port)
        if direction == "out" and re.search(r"(out|output|lv2_audio_out)", lower):
            candidates.append(port)
    return candidates[:2]


def jack_connect(src: str, dst: str) -> None:
    run(["jack_disconnect", src, dst])
    run(["jack_connect", src, dst])


def disconnect_insert_ports() -> None:
    pairs = [
        ("SuperCollider:out_3", "system:playback_1"),
        ("SuperCollider:out_4", "system:playback_2"),
        ("SuperCollider:out_3", "SuperCollider:in_1"),
        ("SuperCollider:out_4", "SuperCollider:in_2"),
    ]
    for src, dst in pairs:
        run(["jack_disconnect", src, dst])


def wait_for_ports(client: str, timeout_s: float = 6.0) -> tuple[list[str], list[str]]:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        ins = jack_ports(client, "in")
        outs = jack_ports(client, "out")
        if len(ins) >= 2 and len(outs) >= 2:
            return ins, outs
        time.sleep(0.15)
    return jack_ports(client, "in"), jack_ports(client, "out")


def rebuild_chain(active: list[int]) -> tuple[list[int], list[str]]:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    uris = lv2_uris()
    pids: list[int] = []
    clients: list[tuple[str, list[str], list[str]]] = []
    messages: list[str] = []
    disconnect_insert_ports()
    for slot, index in enumerate(active, start=1):
        name = FX_NAMES[index - 1]
        uri = uri_for_fx(name, uris)
        if uri is None:
            messages.append(f"missing={name}")
            continue
        rng = random.Random((time.time_ns() & 0xFFFFFFFF) + index + slot)
        client = f"eap-aw-{slot}"
        args = jalv_command(client)
        for control in randomized_controls(uri, rng):
            args += ["-c", control]
        args.append(uri)
        log = (LOG_DIR / f"{client}.log").open("ab")
        proc = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        pids.append(proc.pid)
        ins, outs = wait_for_ports(client)
        if len(ins) < 2 or len(outs) < 2:
            messages.append(f"ports-missing={name}")
            continue
        clients.append((client, ins, outs))
        messages.append(f"fx{slot}={name}")
    if clients:
        src_l, src_r = "SuperCollider:out_3", "SuperCollider:out_4"
        for _client, ins, outs in clients:
            jack_connect(src_l, ins[0])
            jack_connect(src_r, ins[1])
            src_l, src_r = outs[0], outs[1]
        jack_connect(src_l, "SuperCollider:in_1")
        jack_connect(src_r, "SuperCollider:in_2")
    return pids, messages


def set_fx(index: int, enabled: bool) -> str:
    with locked_state():
        state = load_state()
        active = [i for i in state["active"] if i != index]
        if enabled:
            active.append(index)
        while len(active) > MAX_ACTIVE:
            active.pop(0)
        if not active:
            if state["pids"]:
                kill_old(state["pids"])
            host_pid = int(state.get("host_pid", 0) or 0)
            if pid_alive(host_pid):
                send_host("CLEAR")
                time.sleep(0.1)
            kill_hosts()
            disconnect_insert_ports()
            save_host_state([], 0)
            return "active=0 stopped"
        if state["pids"]:
            kill_old(state["pids"])
        host_pid = start_host_if_needed(state)
        seed = time.time_ns() & 0xFFFFFFFF
        send_host("SET " + " ".join(str(i) for i in active) + f" seed {seed}")
        save_host_state(active, host_pid)
        names = [FX_NAMES[i - 1] for i in active]
        return "active={} host={} {}".format(len(active), host_pid, " ".join(names)).strip()


def clear() -> str:
    with locked_state():
        state = load_state()
        if state["pids"]:
            kill_old(state["pids"])
        host_pid = int(state.get("host_pid", 0) or 0)
        if pid_alive(host_pid):
            send_host(f"CLEAR seed {time.time_ns() & 0xFFFFFFFF}")
            time.sleep(0.1)
        kill_hosts()
        disconnect_insert_ports()
        save_host_state([], 0)
        return "active=0 cleared"


def stop_host() -> str:
    with locked_state():
        state = load_state()
        if state["pids"]:
            kill_old(state["pids"])
        host_pid = int(state.get("host_pid", 0) or 0)
        if pid_alive(host_pid):
            send_host("QUIT")
            time.sleep(0.2)
            try:
                os.kill(host_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        kill_hosts()
        disconnect_insert_ports()
        save_host_state([], 0)
        return "active=0 stopped"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--set", nargs=2, metavar=("INDEX", "ENABLED"))
    parser.add_argument("--clear", action="store_true")
    parser.add_argument("--stop", action="store_true")
    parser.add_argument("--status", action="store_true")
    args = parser.parse_args()
    if args.clear:
        print(clear())
        return 0
    if args.stop:
        print(stop_host())
        return 0
    if args.status:
        state = load_state()
        print(f"active={len(state['active'])} indices={state['active']} host={state.get('host_pid', 0)}")
        return 0
    if args.set:
        index = max(1, min(int(args.set[0]), len(FX_NAMES)))
        enabled = int(args.set[1]) > 0
        print(set_fx(index, enabled))
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
