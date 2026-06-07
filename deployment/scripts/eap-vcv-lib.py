#!/usr/bin/env python3
"""Shared VCV Rack patch analysis and EAP runtime preparation."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

# RtMidi::LINUX_ALSA — matches Rack's RtMidi driver id on Linux.
MIDI_ALSA_DRIVER = 2

BUILT_IN_PLUGINS = frozenset({"Core", "Fundamental", "VCV"})
AUDIO_MODELS = frozenset({"AudioInterface", "AudioInterface2"})
MIDI_MODELS = frozenset({"MIDIToCVInterface", "MIDIToCV", "CV-MIDI", "MidiCat", "MIDI-CV"})
PITCH_TARGET_MODELS = frozenset(
    {
        "VCO",
        "VCO-2",
        "VCO2",
        "Plaits",
        "MacroOscillator",
        "Quantizer",
        "Quantizer2",
        "Keyboard",
    }
)

JACK_AUDIO_DATA = {
    "audio": {
        "driver": 4,
        "deviceName": "system",
        "sampleRate": 48000.0,
        "blockSize": 256,
        "inputOffset": 0,
        "outputOffset": 0,
    },
    "dcFilter": False,
}


def patch_plugins(patch: dict[str, Any]) -> set[str]:
    plugins: set[str] = set()
    for module in patch.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        plugin = str(module.get("plugin") or "").strip()
        if plugin:
            plugins.add(plugin)
    return plugins


def missing_plugins(patch: dict[str, Any], installed: set[str]) -> set[str]:
    allowed = set(BUILT_IN_PLUGINS) | set(installed)
    return patch_plugins(patch) - allowed


def has_audio_output(patch: dict[str, Any]) -> bool:
    for module in patch.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        if str(module.get("model") or "") in AUDIO_MODELS:
            return True
    return False


def has_midi_source(patch: dict[str, Any]) -> bool:
    for module in patch.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        model = str(module.get("model") or "")
        if model in MIDI_MODELS or "midi" in model.lower():
            return True
    return False


def pitch_targets(patch: dict[str, Any]) -> list[dict[str, Any]]:
    targets: list[dict[str, Any]] = []
    for module in patch.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        model = str(module.get("model") or "")
        if model in PITCH_TARGET_MODELS or model.endswith("Quantizer"):
            targets.append(module)
    return targets


def analyze_patch(patch: dict[str, Any], installed: set[str]) -> dict[str, Any]:
    missing = sorted(missing_plugins(patch, installed))
    audio = has_audio_output(patch)
    midi = has_midi_source(patch)
    targets = pitch_targets(patch)
    can_prepare_midi = bool(targets)
    compatible = audio and not missing and (midi or can_prepare_midi)
    reason = "ok"
    if not audio:
        reason = "no_audio_output"
    elif missing:
        reason = f"missing_plugins:{','.join(missing)}"
    elif not midi and not can_prepare_midi:
        reason = "no_midi_or_pitch_target"
    return {
        "compatible": compatible,
        "reason": reason,
        "has_audio": audio,
        "has_midi": midi,
        "can_prepare_midi": can_prepare_midi,
        "missing_plugins": missing,
    }


def next_module_id(patch: dict[str, Any]) -> int:
    ids = [int(module.get("id", 0)) for module in patch.get("modules", []) or [] if isinstance(module, dict)]
    return (max(ids) if ids else 0) + 1


def next_cable_id(patch: dict[str, Any]) -> int:
    ids = [int(cable.get("id", 0)) for cable in patch.get("cables", []) or [] if isinstance(cable, dict)]
    return (max(ids) if ids else 0) + 1


def ensure_midi_input(patch: dict[str, Any]) -> int:
    device_name = os.environ.get("EAP_VCV_MIDI_DEVICE", "14:0").strip()
    changed = 0
    for module in patch.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        if str(module.get("model") or "") not in MIDI_MODELS:
            continue
        data = module.get("data")
        if not isinstance(data, dict):
            data = {}
            module["data"] = data
        midi = data.get("midi")
        if not isinstance(midi, dict):
            midi = {}
            data["midi"] = midi
        if midi.get("driver") != MIDI_ALSA_DRIVER:
            midi["driver"] = MIDI_ALSA_DRIVER
            changed += 1
        if midi.get("deviceName") != device_name:
            midi["deviceName"] = device_name
            changed += 1
    return changed


def ensure_jack_audio(patch: dict[str, Any]) -> int:
    changed = 0
    master_id = patch.get("masterModuleId")
    for module in patch.get("modules", []) or []:
        if not isinstance(module, dict):
            continue
        if str(module.get("model") or "") not in AUDIO_MODELS:
            continue
        data = module.get("data")
        if not isinstance(data, dict):
            data = {}
            module["data"] = data
        audio = data.get("audio")
        if not isinstance(audio, dict):
            audio = {}
            data["audio"] = audio
        for key, value in JACK_AUDIO_DATA["audio"].items():
            if audio.get(key) != value:
                audio[key] = value
                changed += 1
        if data.get("dcFilter") is not False:
            data["dcFilter"] = False
            changed += 1
        master_id = module.get("id", master_id)
    if master_id is not None and patch.get("masterModuleId") != master_id:
        patch["masterModuleId"] = master_id
        changed += 1
    return changed


def inject_midi_to_target(patch: dict[str, Any]) -> bool:
    if has_midi_source(patch):
        return False
    targets = pitch_targets(patch)
    if not targets:
        return False
    target = targets[0]
    midi_id = next_module_id(patch)
    cable_id = next_cable_id(patch)
    modules = patch.setdefault("modules", [])
    cables = patch.setdefault("cables", [])
    modules.append(
        {
            "id": midi_id,
            "plugin": "Core",
            "model": "MIDIToCVInterface",
            "version": str(patch.get("version") or "2.6.6"),
            "params": [],
            "data": {"midi": {"driver": MIDI_ALSA_DRIVER, "deviceName": os.environ.get("EAP_VCV_MIDI_DEVICE", "14:0").strip()}},
            "pos": [-12, 0],
        }
    )
    cables.append(
        {
            "id": cable_id,
            "outputModuleId": midi_id,
            "outputId": 0,
            "inputModuleId": target["id"],
            "inputId": 0,
            "color": "#0986ad",
            "inputPlugOrder": 1,
            "outputPlugOrder": 2,
        }
    )
    if str(target.get("model") or "") == "ADSR":
        cables.append(
            {
                "id": cable_id + 1,
                "outputModuleId": midi_id,
                "outputId": 1,
                "inputModuleId": target["id"],
                "inputId": 4,
                "color": "#c9b70e",
                "inputPlugOrder": 3,
                "outputPlugOrder": 4,
            }
        )
    return True


def prepare_patch(patch: dict[str, Any]) -> tuple[dict[str, Any], dict[str, int]]:
    stats = {"audio": 0, "midi": 0, "midi_device": 0}
    stats["audio"] = ensure_jack_audio(patch)
    if inject_midi_to_target(patch):
        stats["midi"] = 1
    stats["midi_device"] = ensure_midi_input(patch)
    return patch, stats


def compatible_entries(manifest: dict[str, Any], installed: set[str], extract) -> list[dict[str, Any]]:
    ready: list[dict[str, Any]] = []
    for entry in manifest.get("patches", []) or []:
        if not isinstance(entry, dict):
            continue
        if entry.get("compatible") is False:
            continue
        path = Path(str(entry.get("file") or ""))
        if not path.exists():
            continue
        try:
            patch = extract(path)
        except Exception:
            continue
        if not isinstance(patch, dict):
            continue
        info = analyze_patch(patch, installed)
        if info["compatible"]:
            ready.append(entry)
    return ready
