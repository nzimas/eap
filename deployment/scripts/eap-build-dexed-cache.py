#!/usr/bin/env python3
"""Build a fast Dexed DX7 bank cache from a patch zip."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path


DX7_BANK_SIZE = 4104
DX7_BANK_HEADER = bytes([0xF0, 0x43, 0x00, 0x09, 0x20, 0x00])


def is_dx7_bank(data: bytes) -> bool:
    return (
        len(data) == DX7_BANK_SIZE
        and data.startswith(DX7_BANK_HEADER)
        and data[-1] == 0xF7
    )


def voice_name(bank: bytes, program: int) -> str:
    start = 6 + (program * 128) + 118
    raw = bank[start : start + 10]
    return raw.decode("ascii", errors="ignore").strip() or "UNKNOWN"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", help="DX7_AllTheWeb.zip or similar patch archive.")
    parser.add_argument("output_dir", help="Cache directory to create.")
    args = parser.parse_args()

    archive = Path(args.archive)
    output_dir = Path(args.output_dir)
    banks_dir = output_dir / "banks"
    if output_dir.exists():
        shutil.rmtree(output_dir)
    banks_dir.mkdir(parents=True)

    seen: dict[str, str] = {}
    manifest = []
    skipped = 0

    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if info.is_dir() or not info.filename.lower().endswith(".syx"):
                continue
            data = zf.read(info)
            if not is_dx7_bank(data):
                skipped += 1
                continue
            digest = hashlib.sha1(data).hexdigest()
            if digest in seen:
                continue
            bank_name = f"bank-{len(manifest):05d}.syx"
            (banks_dir / bank_name).write_bytes(data)
            seen[digest] = bank_name
            manifest.append(
                {
                    "bank": bank_name,
                    "source": info.filename,
                    "sha1": digest,
                    "voices": [voice_name(data, program) for program in range(32)],
                }
            )

    (output_dir / "manifest.json").write_text(
        json.dumps({"banks": manifest, "skipped": skipped}, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"cached {len(manifest)} unique DX7 banks, skipped {skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
