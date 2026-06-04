#!/usr/bin/env python3
"""Resolve and build VCV Rack modules referenced by cached patches."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any


CACHE_DIR = Path(os.environ.get("EAP_VCV_PATCH_CACHE", "/opt/electroacoustic-playground/vcv/patch-cache"))
MODULE_SRC_DIR = Path(os.environ.get("EAP_VCV_MODULE_SRC", "/opt/vcv-rack-src/modules"))
RACK_DIR = Path(os.environ.get("EAP_RACK_SRC", "/opt/vcv-rack-src/Rack"))
RACK_USER_DIR = Path(os.environ.get("EAP_VCV_USER_DIR", "/home/we/.local/share/eap-vcv/Rack2"))
MANIFEST_PATH = CACHE_DIR / "modules.json"

DEFAULT_REGISTRY: dict[str, str] = {
    "Fundamental": "https://github.com/VCVRack/Fundamental.git",
    "VCV": "https://github.com/VCVRack/Fundamental.git",
}
BUILT_IN_PLUGINS = {"Core", "Fundamental", "VCV"}


def run(args: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=str(cwd) if cwd else None, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=check)


def load_json(path: Path, fallback: Any) -> Any:
    if not path.exists():
        return fallback
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return fallback


def load_registry(path: Path | None) -> dict[str, str]:
    registry = dict(DEFAULT_REGISTRY)
    if path and path.exists():
        extra = load_json(path, {})
        if isinstance(extra, dict):
            registry.update({str(key): str(value) for key, value in extra.items()})
    return registry


def needed_plugins(cache_dir: Path) -> set[str]:
    manifest = load_json(cache_dir / "manifest.json", {"patches": []})
    needed: set[str] = set()
    for patch in manifest.get("patches", []) or []:
        for dep in patch.get("dependencies", []) or []:
            plugin = str(dep.get("plugin") or "").strip()
            if plugin and plugin not in BUILT_IN_PLUGINS:
                needed.add(plugin)
    return needed


def build_plugin(plugin: str, repo: str, force: bool) -> dict[str, Any]:
    MODULE_SRC_DIR.mkdir(parents=True, exist_ok=True)
    RACK_USER_DIR.mkdir(parents=True, exist_ok=True)
    target = MODULE_SRC_DIR / plugin
    result: dict[str, Any] = {"plugin": plugin, "repo": repo, "status": "unknown"}
    try:
        if target.exists() and force:
            shutil.rmtree(target)
        if target.exists() and (target / ".git").exists():
            run(["git", "fetch", "--depth", "1", "origin"], cwd=target)
            run(["git", "checkout", "FETCH_HEAD"], cwd=target)
        elif not target.exists():
            run(["git", "clone", "--depth", "1", repo, str(target)])
        if (target / ".gitmodules").exists():
            run(["git", "submodule", "update", "--init", "--recursive", "--depth", "1"], cwd=target)
        if (target / "Makefile").exists():
            env = os.environ.copy()
            env.setdefault("RACK_DIR", str(RACK_DIR))
            subprocess.run(["make", "dep"], cwd=str(target), env=env, check=False)
            subprocess.run(["make"], cwd=str(target), env=env, check=True)
            subprocess.run(["make", "install"], cwd=str(target), env=env, check=True)
        result["status"] = "installed"
    except subprocess.CalledProcessError as exc:
        result["status"] = "failed"
        result["error"] = (exc.stdout or str(exc))[-4000:]
    except Exception as exc:
        result["status"] = "failed"
        result["error"] = str(exc)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache-dir", default=str(CACHE_DIR))
    parser.add_argument("--registry", type=Path, default=None, help="JSON map of Rack plugin slug/name to git repo.")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cache_dir = Path(args.cache_dir)
    registry = load_registry(args.registry)
    installed = load_json(MANIFEST_PATH, {"plugins": {}})
    plugins = installed.setdefault("plugins", {})
    needed = needed_plugins(cache_dir)
    for plugin in sorted(needed):
        if plugin in plugins and plugins[plugin].get("status") == "installed" and not args.force:
            continue
        repo = registry.get(plugin)
        if not repo:
            plugins[plugin] = {"plugin": plugin, "status": "unknown", "error": "no repository mapping"}
            print(f"vcv module unknown plugin={plugin}")
            continue
        if args.dry_run:
            plugins[plugin] = {"plugin": plugin, "repo": repo, "status": "pending"}
            print(f"vcv module pending plugin={plugin} repo={repo}")
            continue
        outcome = build_plugin(plugin, repo, args.force)
        plugins[plugin] = outcome
        print(f"vcv module {outcome['status']} plugin={plugin}")
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(installed, indent=2, sort_keys=True), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
