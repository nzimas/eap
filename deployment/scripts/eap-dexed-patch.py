#!/usr/bin/env python3
"""Pick, gently mutate, and send a cached DX7 bank/program to Dexed."""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import subprocess
import tempfile
from pathlib import Path


DEFAULT_CACHE_DIR = "/opt/electroacoustic-playground/dexed/patch-cache"
DX7_BANK_SIZE = 4104
VOICE_SIZE = 128
VOICE_DATA_START = 6
VOICE_NAME_OFFSET = 118
OPERATOR_SIZE = 17
OPERATOR_OUTPUT_LEVEL_OFFSET = 14


def midi_hex(*values: int) -> str:
    return " ".join(f"{value & 0xFF:02X}" for value in values)


def load_manifest(cache_dir: Path) -> list[dict]:
    manifest_path = cache_dir / "manifest.json"
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    banks = data.get("banks", [])
    if not banks:
        raise RuntimeError(f"empty Dexed patch cache: {manifest_path}")
    return banks


def find_dexed_port() -> str:
    output = subprocess.check_output(["aconnect", "-l"], text=True)
    client = None
    for line in output.splitlines():
        client_match = re.match(r"client\s+(\d+):\s+'([^']+)'", line)
        if client_match:
            client = client_match.group(1) if client_match.group(2).lower() == "dexed" else None
            continue
        if client is not None:
            port_match = re.match(r"\s+(\d+)\s+'([^']+)'", line)
            if port_match and "out0" in port_match.group(2).lower():
                return f"{client}:{port_match.group(1)}"
    raise RuntimeError("Dexed ALSA MIDI port not found")


def voice_name(bank: bytes, program: int) -> str:
    start = VOICE_DATA_START + (program * VOICE_SIZE) + VOICE_NAME_OFFSET
    return bank[start : start + 10].decode("ascii", errors="ignore").strip() or "UNKNOWN"


def refresh_bulk_checksum(bank: bytearray) -> None:
    bank[-2] = (-sum(bank[6:-2])) & 0x7F


def gentle_mutation(bank: bytearray, program: int, rng: random.Random, amount: int) -> int:
    if amount <= 0:
        return 0
    voice_start = VOICE_DATA_START + (program * VOICE_SIZE)
    changed = 0
    for operator in range(6):
        if rng.random() > 0.45:
            continue
        offset = voice_start + (operator * OPERATOR_SIZE) + OPERATOR_OUTPUT_LEVEL_OFFSET
        current = bank[offset]
        if current > 99:
            continue
        delta = rng.choice([-amount, -1, 1, amount])
        bank[offset] = max(0, min(99, current + delta))
        changed += 1
    if changed:
        refresh_bulk_checksum(bank)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache-dir", default=os.environ.get("EAP_DEXED_PATCH_CACHE", DEFAULT_CACHE_DIR))
    parser.add_argument("--seed", default=None)
    parser.add_argument("--program", type=int, default=None)
    parser.add_argument("--channel", type=int, default=0)
    parser.add_argument("--mutate", type=int, default=2)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    rng = random.Random(args.seed) if args.seed is not None else random.SystemRandom()
    cache_dir = Path(args.cache_dir)
    banks = load_manifest(cache_dir)
    entry = rng.choice(banks)
    program = args.program if args.program is not None else rng.randrange(32)
    program = max(0, min(31, program))
    channel = max(0, min(15, args.channel))
    bank_path = cache_dir / "banks" / entry["bank"]
    bank = bytearray(bank_path.read_bytes())
    if len(bank) != DX7_BANK_SIZE:
        raise RuntimeError(f"invalid DX7 bank size: {bank_path}")
    selected_voice = voice_name(bank, program)
    changed = gentle_mutation(bank, program, rng, max(0, min(4, args.mutate)))
    mod_wheel = rng.randrange(0, 13)

    if not args.dry_run:
        port = find_dexed_port()
        with tempfile.NamedTemporaryFile(suffix=".syx") as handle:
            handle.write(bank)
            handle.flush()
            subprocess.run(["aseqsend", "-p", port, "-i", "2", "-s", handle.name], check=True)
        subprocess.run(["aseqsend", "-p", port, midi_hex(0xC0 | channel, program)], check=True)
        subprocess.run(["aseqsend", "-p", port, midi_hex(0xB0 | channel, 1, mod_wheel)], check=True)

    print(
        f"dexed patch bank={entry['bank']} program={program + 1} "
        f"voice={selected_voice!r} mutated_ops={changed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
