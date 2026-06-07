#!/usr/bin/env python3
"""Choose, prepare, mutate, and start a cached VCV Rack patch for EAP."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import random
import subprocess
import sys
from pathlib import Path
from typing import Any

def _lib_path() -> Path:
    candidates = [
        Path(__file__).with_name("eap-vcv-lib.py"),
        Path("/opt/electroacoustic-playground/deployment/scripts/eap-vcv-lib.py"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise RuntimeError("could not find eap-vcv-lib.py")


_LIB_PATH = _lib_path()
_spec = importlib.util.spec_from_file_location("eap_vcv_lib", _LIB_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"could not load {_LIB_PATH}")
_lib = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_lib)

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
    installed: set[str] = set()
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
        import zipfile

        with zipfile.ZipFile(path) as archive:
            for name in archive.namelist():
                if name.endswith(".vcv") or name.endswith("patch.json") or name.endswith(".json"):
                    with archive.open(name) as handle:
                        nested = handle.read()
                    if nested.lstrip().startswith(b"{"):
                        return json.loads(nested.decode("utf-8"))
        raise RuntimeError(f"zip archive has no VCV patch JSON: {path}")
    import shutil
    import tarfile
    import tempfile

    if shutil.which("zstd"):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["tar", "--zstd", "-xf", str(path), "-C", tmp], check=True)
            patch_json = next(Path(tmp).rglob("patch.json"), None)
            if patch_json is None:
                patch_json = next(Path(tmp).rglob("*.vcv"), None)
            if patch_json is None:
                raise RuntimeError(f"patch archive has no patch JSON: {path}")
            return extract_patch_json(patch_json)
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


def profile_matches(entry: dict[str, Any], profile: str) -> bool:
    profiles = set(entry.get("profiles", []) or [])
    return profile in profiles or "default" in profiles or not profiles


def choose_patch(rng: random.Random, profile: str, manifest: dict[str, Any], installed: set[str]) -> dict[str, Any]:
    patches = [
        patch
        for patch in manifest.get("patches", []) or []
        if isinstance(patch, dict) and patch.get("compatible") is not False
    ]
    verified: list[dict[str, Any]] = []
    for entry in patches:
        path = Path(str(entry.get("file") or ""))
        if not path.exists():
            continue
        try:
            patch = extract_patch_json(path)
        except Exception:
            continue
        info = _lib.analyze_patch(patch, installed)
        if info["compatible"]:
            verified.append(entry)
    preferred = [patch for patch in verified if profile_matches(patch, profile)]
    if preferred:
        return rng.choice(preferred)
    if verified:
        return rng.choice(verified)
    raise RuntimeError("no compatible VCV Rack patches in cache")


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
    encoded = json.dumps(patch, separators=(",", ":"))
    path.write_text(encoded, encoding="utf-8")
    (STATE_DIR / "current.vcv").write_text(encoded, encoding="utf-8")
    return path


def count_compatible(manifest: dict[str, Any], installed: set[str]) -> int:
    count = 0
    for entry in manifest.get("patches", []) or []:
        if not isinstance(entry, dict) or entry.get("compatible") is False:
            continue
        path = Path(str(entry.get("file") or ""))
        if not path.exists():
            continue
        try:
            patch = extract_patch_json(path)
        except Exception:
            continue
        if _lib.analyze_patch(patch, installed)["compatible"]:
            count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", default=None)
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--profile", default="default", choices=["chaos", "default", "drone", "harmonic", "percussive"])
    parser.add_argument("--mutate", type=float, default=0.16)
    parser.add_argument("--cache-dir", default=str(CACHE_DIR))
    parser.add_argument("--no-start", action="store_true")
    parser.add_argument("--check", action="store_true", help="Print compatible patch count and exit.")
    args = parser.parse_args()

    installed = installed_modules()
    manifest = load_json(Path(args.cache_dir) / "manifest.json", {"patches": []})
    if args.check:
        total = count_compatible(manifest, installed)
        print(f"vcv compatible_patches={total}")
        return 0 if total > 0 else 2

    rng = random.Random(args.seed) if args.seed is not None else random.SystemRandom()
    entry = choose_patch(rng, args.profile, manifest, installed)
    patch = extract_patch_json(Path(entry["file"]))
    info = _lib.analyze_patch(patch, installed)
    if not info["compatible"]:
        print(f"vcv error chosen patch is not compatible: {info['reason']}", file=sys.stderr)
        return 2
    patch, prep = _lib.prepare_patch(patch)
    changed = mutate_patch(patch, rng, args.profile, clamp(args.mutate, 0.0, 1.0))
    runtime = write_runtime_patch(patch, max(1, min(args.slot, 8)))

    if not args.no_start:
        subprocess.run(["/usr/local/bin/eap-start-vcv", str(runtime)], check=True)
    print(
        f"vcv patch file={runtime} title={entry.get('title')!r} "
        f"profile={args.profile} prepared={prep} mutated_params={changed}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
