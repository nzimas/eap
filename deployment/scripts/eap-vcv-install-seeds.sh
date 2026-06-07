#!/usr/bin/env bash
# Install bundled EAP VCV seed patches into the Pi patch cache.
set -euo pipefail

remote_root="${EAP_REMOTE_ROOT:-/opt/electroacoustic-playground}"
cache_dir="${EAP_VCV_PATCH_CACHE:-$remote_root/vcv/patch-cache}"
seed_dir="$remote_root/deployment/vcv/seed-patches"
files_dir="$cache_dir/files"
manifest="$cache_dir/manifest.json"

mkdir -p "$files_dir"
python3 - "$seed_dir" "$files_dir" "$manifest" <<'PY'
import json
import shutil
import sys
import time
from pathlib import Path

seed_dir = Path(sys.argv[1])
files_dir = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
manifest = {"patches": []}
if manifest_path.exists():
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        manifest = {"patches": []}
by_id = {str(item.get("id")): item for item in manifest.get("patches", []) if isinstance(item, dict)}
for seed in sorted(seed_dir.glob("*.vcv")):
    dest = files_dir / f"seed-{seed.stem}{seed.suffix}"
    shutil.copy2(seed, dest)
    entry = {
        "id": f"seed-{seed.stem}",
        "title": seed.stem.replace("-", " "),
        "slug": seed.stem,
        "file": str(dest),
        "profiles": ["default", "percussive", "harmonic", "drone"],
        "dependencies": [
            {"plugin": "Core", "model": "MIDIToCVInterface"},
            {"plugin": "Core", "model": "AudioInterface2"},
            {"plugin": "Fundamental", "model": "VCO"},
        ],
        "has_io": True,
        "compatible": True,
        "seed": True,
        "downloaded_at": time.time(),
    }
    by_id[entry["id"]] = entry
    print(f"vcv seed installed id={entry['id']} file={dest}")
manifest["patches"] = list(by_id.values())
manifest_path.parent.mkdir(parents=True, exist_ok=True)
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
print(f"vcv patch cache={manifest_path} total={len(manifest['patches'])}")
PY
