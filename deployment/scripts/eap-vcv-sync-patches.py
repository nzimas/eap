#!/usr/bin/env python3
"""Download and index VCV Rack patches from Patchstorage for EAP."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

import importlib.util

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
API_BASE = os.environ.get("EAP_PATCHSTORAGE_API", "https://patchstorage.com/api/beta")
USER_AGENT = os.environ.get("EAP_PATCHSTORAGE_USER_AGENT", "ElectroacousticPlayground/0.1")
PLATFORM_SLUG = os.environ.get("EAP_PATCHSTORAGE_VCV_PLATFORM", "vcv-rack")
DEFAULT_SEARCH = os.environ.get("EAP_PATCHSTORAGE_VCV_SEARCH", "VCV Rack")


def load_json(path: Path, fallback: Any) -> Any:
    if not path.exists():
        return fallback
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return fallback


def request_json(url: str) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def download(url: str, dest: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("wb") as handle:
            shutil.copyfileobj(response, handle)


def list_items(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        for key in ("results", "patches", "data"):
            value = payload.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
    return []


def platform_slug(patch: dict[str, Any]) -> str:
    platform = patch.get("platform") or {}
    if isinstance(platform, dict):
        return str(platform.get("slug") or platform.get("name") or "").lower()
    return str(platform).lower()


def patch_id(patch: dict[str, Any]) -> str:
    return str(patch.get("id") or patch.get("slug") or re.sub(r"\W+", "-", str(patch.get("title", "patch")).lower()))


def safe_name(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    return value.strip("-") or "patch"


def file_download_url(patch: dict[str, Any], file_info: dict[str, Any]) -> str | None:
    raw = file_info.get("url") or file_info.get("download_url")
    if isinstance(raw, str) and raw.startswith("http"):
        return raw
    pid = patch.get("id")
    fid = file_info.get("id")
    if pid is None or fid is None:
        return None
    return f"{API_BASE.rstrip('/')}/patches/{pid}/files/{fid}/download"


def patch_detail(patch: dict[str, Any]) -> dict[str, Any]:
    pid = patch.get("id")
    if pid is None:
        return patch
    try:
        detail = request_json(f"{API_BASE.rstrip('/')}/patches/{pid}")
    except (urllib.error.URLError, json.JSONDecodeError):
        return patch
    if isinstance(detail, dict):
        merged = dict(patch)
        merged.update(detail)
        return merged
    return patch


def extract_patch_json(path: Path) -> dict[str, Any] | None:
    suffix = path.suffix.lower()
    try:
        if suffix == ".zip":
            with zipfile.ZipFile(path) as archive:
                for name in archive.namelist():
                    if name.endswith(".vcv") or name.endswith("patch.json") or name.endswith(".json"):
                        with archive.open(name) as handle:
                            return json.loads(handle.read().decode("utf-8"))
        if suffix in (".json", ".vcv"):
            data = path.read_bytes()
            stripped = data.lstrip()
            if stripped.startswith(b"{"):
                return json.loads(data.decode("utf-8"))
            if shutil.which("zstd") and tarfile.is_tarfile(path):
                with tarfile.open(path) as archive:
                    member = next((m for m in archive.getmembers() if m.name.endswith("patch.json")), None)
                    if member is not None:
                        handle = archive.extractfile(member)
                        if handle is not None:
                            return json.loads(handle.read().decode("utf-8"))
            if shutil.which("zstd"):
                with tempfile.TemporaryDirectory() as tmp:
                    subprocess.run(["tar", "--zstd", "-xf", str(path), "-C", tmp], check=True)
                    patch_json = next(Path(tmp).rglob("patch.json"), None)
                    if patch_json is not None:
                        return json.loads(patch_json.read_text(encoding="utf-8"))
    except Exception:
        return None
    return None


def module_dependencies(patch_json: dict[str, Any] | None) -> list[dict[str, str]]:
    if not isinstance(patch_json, dict):
        return []
    deps: dict[tuple[str, str], dict[str, str]] = {}
    for module in patch_json.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        plugin = str(module.get("plugin") or module.get("pluginSlug") or module.get("brand") or "")
        model = str(module.get("model") or module.get("module") or "")
        if plugin or model:
            deps[(plugin, model)] = {"plugin": plugin, "model": model}
    return sorted(deps.values(), key=lambda item: (item["plugin"], item["model"]))


def installed_plugins(cache_dir: Path) -> set[str]:
    status_path = cache_dir / "modules.json"
    installed = set(_lib.BUILT_IN_PLUGINS)
    if status_path.exists():
        try:
            payload = json.loads(status_path.read_text(encoding="utf-8"))
            plugins = payload.get("plugins", {})
            if isinstance(plugins, dict):
                installed.update(
                    str(name)
                    for name, info in plugins.items()
                    if isinstance(info, dict) and info.get("status") == "installed"
                )
        except json.JSONDecodeError:
            pass
    return installed


def profile_tags(patch: dict[str, Any], deps: list[dict[str, str]]) -> list[str]:
    text = " ".join(
        str(patch.get(key, ""))
        for key in ("title", "excerpt", "content", "slug")
    ).lower()
    text += " " + " ".join(dep["model"].lower() for dep in deps)
    tags = []
    if re.search(r"drone|ambient|texture|pad|slow", text):
        tags.append("drone")
    if re.search(r"melod|chord|pad|arp|sequence|harmony", text):
        tags.append("harmonic")
    if re.search(r"drum|perc|kick|snare|hat|pluck|trigger", text):
        tags.append("percussive")
    if re.search(r"noise|glitch|chaos|distort|random|fm", text):
        tags.append("chaos")
    return tags or ["default"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=24)
    parser.add_argument("--pages", type=int, default=2)
    parser.add_argument("--sleep", type=float, default=1.5)
    parser.add_argument("--platform", default=PLATFORM_SLUG)
    parser.add_argument("--search", default=DEFAULT_SEARCH)
    parser.add_argument("--cache-dir", default=str(CACHE_DIR))
    parser.add_argument("--reindex", action="store_true", help="Recompute compatibility flags for cached patches.")
    args = parser.parse_args()

    cache_dir = Path(args.cache_dir)
    if args.reindex:
        manifest_path = cache_dir / "manifest.json"
        manifest = load_json(manifest_path, {"patches": []})
        installed = installed_plugins(cache_dir)
        for entry in manifest.get("patches", []) or []:
            if not isinstance(entry, dict):
                continue
            path = Path(str(entry.get("file") or ""))
            if not path.exists():
                entry["compatible"] = False
                entry["compat_reason"] = "missing_file"
                continue
            patch_json = extract_patch_json(path)
            deps = module_dependencies(patch_json)
            entry["dependencies"] = deps
            info = _lib.analyze_patch(patch_json, installed) if isinstance(patch_json, dict) else {"compatible": False, "reason": "unreadable"}
            entry["has_io"] = bool(info.get("has_audio"))
            entry["compatible"] = bool(info.get("compatible"))
            entry["compat_reason"] = info.get("reason", "unreadable")
            print(
                f"reindex id={entry.get('id')} compatible={entry['compatible']} "
                f"reason={entry.get('compat_reason')} title={entry.get('title')!r}"
            )
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
        compatible = sum(1 for entry in manifest.get("patches", []) if entry.get("compatible"))
        print(f"vcv patch cache={cache_dir} compatible={compatible} total={len(manifest.get('patches', []))}")
        return 0

    files_dir = cache_dir / "files"
    installed = installed_plugins(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    manifest_path = cache_dir / "manifest.json"
    manifest = {"patches": []}
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            manifest = {"patches": []}
    seen = {str(item.get("id")) for item in manifest.get("patches", [])}

    added = 0
    for page in range(1, max(1, args.pages) + 1):
        if added >= args.limit:
            break
        query_args = {"page": page}
        if args.search:
            query_args["search"] = args.search
        query = urllib.parse.urlencode(query_args)
        url = f"{API_BASE.rstrip('/')}/patches?{query}"
        try:
            patches = list_items(request_json(url))
        except (urllib.error.URLError, json.JSONDecodeError) as exc:
            print(f"patchstorage error page={page}: {exc}", flush=True)
            break
        for patch in patches:
            if added >= args.limit:
                break
            if args.platform and platform_slug(patch) and args.platform not in platform_slug(patch):
                continue
            if not patch.get("files"):
                patch = patch_detail(patch)
            if args.platform and platform_slug(patch) and args.platform not in platform_slug(patch):
                continue
            pid = patch_id(patch)
            if pid in seen:
                continue
            files = patch.get("files") or []
            if not isinstance(files, list) or not files:
                continue
            for file_info in files:
                if not isinstance(file_info, dict):
                    continue
                source_url = file_download_url(patch, file_info)
                if source_url is None:
                    continue
                ext = Path(str(file_info.get("filename") or file_info.get("name") or "patch.vcv")).suffix or ".vcv"
                dest = files_dir / f"{safe_name(pid)}-{safe_name(str(file_info.get('id', 'file')))}{ext}"
                try:
                    download(source_url, dest)
                except urllib.error.URLError as exc:
                    print(f"download failed patch={pid}: {exc}", flush=True)
                    continue
                patch_json = extract_patch_json(dest)
                deps = module_dependencies(patch_json)
                info = (
                    _lib.analyze_patch(patch_json, installed)
                    if isinstance(patch_json, dict)
                    else {"compatible": False, "reason": "unreadable", "has_audio": False}
                )
                entry = {
                    "id": pid,
                    "title": patch.get("title") or patch.get("slug") or pid,
                    "slug": patch.get("slug"),
                    "link": patch.get("link"),
                    "license": patch.get("license"),
                    "file": str(dest),
                    "profiles": profile_tags(patch, deps),
                    "dependencies": deps,
                    "has_io": bool(info.get("has_audio")),
                    "compatible": bool(info.get("compatible")),
                    "compat_reason": info.get("reason", "unreadable"),
                    "downloaded_at": time.time(),
                }
                manifest.setdefault("patches", []).append(entry)
                seen.add(pid)
                added += 1
                print(
                    f"cached patch={pid} profiles={','.join(entry['profiles'])} "
                    f"deps={len(deps)} compatible={entry['compatible']} reason={entry['compat_reason']}"
                )
                break
            time.sleep(max(0.0, args.sleep))

    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    print(f"vcv patch cache={cache_dir} added={added} total={len(manifest.get('patches', []))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
