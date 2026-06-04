#!/usr/bin/env python3
"""Choose, gently mutate, and start a headless VCV Rack patch for EAP."""

from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path
from typing import Any


STATE_DIR = Path(os.environ.get("EAP_VCV_STATE_DIR", "/home/we/.local/share/eap-vcv"))
CACHE_DIR = Path(os.environ.get("EAP_VCV_PATCH_CACHE", "/opt/electroacoustic-playground/vcv/patch-cache"))
MODULE_STATUS_PATH = CACHE_DIR / "modules.json"


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def load_json(path: Path, fallback: Any) -> Any:
    if not path.exists():
        return fallback
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return fallback


def installed_modules() -> set[str]:
    status = load_json(MODULE_STATUS_PATH, {"plugins": {}})
    plugins = status.get("plugins", {})
    installed = {"Core", "Fundamental", "VCV"}
    if isinstance(plugins, dict):
        installed.update(
            str(name)
            for name, info in plugins.items()
            if isinstance(info, dict) and info.get("status") == "installed"
        )
    return installed


def extract_patch_json(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if data.lstrip().startswith(b"{"):
        return json.loads(data.decode("utf-8"))
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            for name in archive.namelist():
                if name.endswith(".vcv") or name.endswith("patch.json") or name.endswith(".json"):
                    with archive.open(name) as handle:
                        nested = handle.read()
                    if nested.lstrip().startswith(b"{"):
                        return json.loads(nested.decode("utf-8"))
                    with tempfile.NamedTemporaryFile(suffix=".vcv") as tmp:
                        tmp.write(nested)
                        tmp.flush()
                        return extract_patch_json(Path(tmp.name))
        raise RuntimeError(f"zip archive has no VCV patch JSON: {path}")
    if shutil.which("zstd"):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["tar", "--zstd", "-xf", str(path), "-C", tmp], check=True)
            patch_json = next(Path(tmp).rglob("patch.json"), None)
            if patch_json is None:
                raise RuntimeError(f"patch archive has no patch.json: {path}")
            return json.loads(patch_json.read_text(encoding="utf-8"))
    if tarfile.is_tarfile(path):
        with tarfile.open(path) as archive:
            member = next((m for m in archive.getmembers() if m.name.endswith("patch.json")), None)
            if member is None:
                raise RuntimeError(f"patch archive has no patch.json: {path}")
            handle = archive.extractfile(member)
            if handle is None:
                raise RuntimeError(f"could not read patch.json: {path}")
            return json.loads(handle.read().decode("utf-8"))
    raise RuntimeError(f"unsupported VCV patch archive: {path}")


def dependencies_available(entry: dict[str, Any], installed: set[str]) -> bool:
    if not entry.get("has_io", False):
        return False
    for dep in entry.get("dependencies", []) or []:
        plugin = str(dep.get("plugin") or "")
        if plugin and plugin not in installed:
            return False
    return True


def profile_matches(entry: dict[str, Any], profile: str) -> bool:
    profiles = set(entry.get("profiles", []) or [])
    return profile in profiles or "default" in profiles or not profiles


def choose_patch(rng: random.Random, profile: str, manifest: dict[str, Any]) -> dict[str, Any]:
    installed = installed_modules()
    patches = [
        patch for patch in manifest.get("patches", []) or []
        if dependencies_available(patch, installed)
    ]
    preferred = [patch for patch in patches if profile_matches(patch, profile)]
    if preferred:
        return rng.choice(preferred)
    if patches:
        return rng.choice(patches)
    raise RuntimeError("no compatible VCV Rack patches in cache")


def fallback_patch(profile: str) -> dict[str, Any]:
    """Small Core/Fundamental patch used only until compatible cached patches exist."""
    # Module ids are fixed for readable, deterministic cable definitions.
    midi_id = 1
    vco_id = 2
    adsr_id = 3
    vca_id = 4
    audio_id = 5
    base_release = 0.18 if profile == "percussive" else 0.45
    sustain = 0.25 if profile == "percussive" else 0.65
    freq = -12.0 if profile == "drone" else 0.0
    return {
        "version": "2.6.6",
        "zoom": 1.0,
        "gridOffset": [0.0, 0.0],
        "modules": [
            {
                "id": midi_id,
                "plugin": "Core",
                "model": "MIDIToCVInterface",
                "version": "2.6.6",
                "params": [],
                "data": {"midi": {}},
                "pos": [0, 0],
            },
            {
                "id": vco_id,
                "plugin": "Fundamental",
                "model": "VCO",
                "version": "2.6.4",
                "params": [
                    {"id": 1, "value": 1.0},
                    {"id": 2, "value": freq},
                    {"id": 4, "value": 0.0},
                    {"id": 5, "value": 0.5},
                    {"id": 6, "value": 0.0},
                    {"id": 7, "value": 0.0},
                ],
                "pos": [15, 0],
            },
            {
                "id": adsr_id,
                "plugin": "Fundamental",
                "model": "ADSR",
                "version": "2.6.4",
                "params": [
                    {"id": 0, "value": 0.02},
                    {"id": 1, "value": 0.12},
                    {"id": 2, "value": sustain},
                    {"id": 3, "value": base_release},
                    {"id": 4, "value": 0.0},
                    {"id": 5, "value": 0.0},
                    {"id": 6, "value": 0.0},
                    {"id": 7, "value": 0.0},
                    {"id": 8, "value": 0.0},
                ],
                "pos": [30, 0],
            },
            {
                "id": vca_id,
                "plugin": "Fundamental",
                "model": "VCA-1",
                "version": "2.6.4",
                "params": [{"id": 0, "value": 0.8}],
                "pos": [45, 0],
            },
            {
                "id": audio_id,
                "plugin": "Core",
                "model": "AudioInterface2",
                "version": "2.6.6",
                "params": [{"id": 0, "value": 1.0}],
                "data": {
                    "audio": {
                        "driver": 4,
                        "deviceName": "system",
                        "sampleRate": 48000.0,
                        "blockSize": 256,
                        "inputOffset": 0,
                        "outputOffset": 0,
                    },
                    "dcFilter": True,
                },
                "pos": [60, 0],
            },
        ],
        "cables": [
            {"id": 1, "outputModuleId": midi_id, "outputId": 0, "inputModuleId": vco_id, "inputId": 0, "color": "#0986ad", "inputPlugOrder": 1, "outputPlugOrder": 2},
            {"id": 2, "outputModuleId": midi_id, "outputId": 1, "inputModuleId": adsr_id, "inputId": 4, "color": "#c9b70e", "inputPlugOrder": 3, "outputPlugOrder": 4},
            {"id": 3, "outputModuleId": vco_id, "outputId": 2, "inputModuleId": vca_id, "inputId": 1, "color": "#f3374b", "inputPlugOrder": 5, "outputPlugOrder": 6},
            {"id": 4, "outputModuleId": adsr_id, "outputId": 0, "inputModuleId": vca_id, "inputId": 0, "color": "#8b4ade", "inputPlugOrder": 7, "outputPlugOrder": 8},
            {"id": 5, "outputModuleId": vca_id, "outputId": 0, "inputModuleId": audio_id, "inputId": 0, "color": "#f3374b", "inputPlugOrder": 9, "outputPlugOrder": 10},
            {"id": 6, "outputModuleId": vca_id, "outputId": 0, "inputModuleId": audio_id, "inputId": 1, "color": "#f3374b", "inputPlugOrder": 11, "outputPlugOrder": 12},
        ],
        "masterModuleId": audio_id,
    }


def mutate_value(rng: random.Random, value: float, amount: float, profile: str) -> float:
    spread = {
        "percussive": 0.12,
        "drone": 0.08,
        "harmonic": 0.10,
        "chaos": 0.24,
        "default": 0.12,
    }.get(profile, 0.12)
    return clamp(value + rng.uniform(-spread, spread) * amount, 0.0, 1.0)


def mutate_patch(patch: dict[str, Any], rng: random.Random, profile: str, amount: float) -> int:
    changed = 0
    for module in patch.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        params = module.get("params")
        if not isinstance(params, list):
            continue
        for param in params:
            if not isinstance(param, dict) or "value" not in param:
                continue
            if rng.random() > (0.18 + amount * 0.22):
                continue
            try:
                current = float(param["value"])
            except (TypeError, ValueError):
                continue
            if 0.0 <= current <= 1.0:
                param["value"] = mutate_value(rng, current, amount, profile)
                changed += 1
    return changed


def write_runtime_patch(patch: dict[str, Any], slot: int) -> Path:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / f"slot-{slot}.vcv"
    # Rack patch files are plain JSON. The zstd tar format is used for .vcvplugin bundles.
    encoded = json.dumps(patch, separators=(",", ":"))
    path.write_text(encoded, encoding="utf-8")
    (STATE_DIR / "current.vcv").write_text(encoded, encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", default=None)
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--profile", default="default", choices=["chaos", "default", "drone", "harmonic", "percussive"])
    parser.add_argument("--mutate", type=float, default=0.16)
    parser.add_argument("--cache-dir", default=str(CACHE_DIR))
    parser.add_argument("--no-start", action="store_true")
    args = parser.parse_args()

    rng = random.Random(args.seed) if args.seed is not None else random.SystemRandom()
    manifest = load_json(Path(args.cache_dir) / "manifest.json", {"patches": []})
    try:
        entry = choose_patch(rng, args.profile, manifest)
        patch = extract_patch_json(Path(entry["file"]))
    except RuntimeError:
        entry = {"title": "EAP Fundamental fallback"}
        patch = fallback_patch(args.profile)
    changed = mutate_patch(patch, rng, args.profile, clamp(args.mutate, 0.0, 1.0))
    runtime = write_runtime_patch(patch, max(1, min(args.slot, 8)))

    if not args.no_start:
        subprocess.run(["/usr/local/bin/eap-start-vcv", str(runtime)], check=True)
    print(
        f"vcv patch file={runtime} title={entry.get('title')!r} "
        f"profile={args.profile} mutated_params={changed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
