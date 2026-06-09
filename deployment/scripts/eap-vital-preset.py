#!/usr/bin/env python3
"""Prepare modifier-aware control values for the realtime Vitalium LV2 engine."""

from __future__ import annotations

import argparse
import os
import random
import subprocess
from pathlib import Path


STATE_DIR = Path(os.environ.get("EAP_VITAL_STATE_DIR", "/home/we/.local/share/eap-vital"))
PRESET_ROOT = "file:///usr/local/lib/lv2/Vitalium-unfa.lv2"
PROFILE_PRESETS = {
    "percussive": ("Hardcore_Kick.ttl", "Kickbass.ttl", "Retro_Ambient_Pluck.ttl"),
    "drone": ("Dark_Ambient.ttl", "Sparkly_Dreamy_Pad.ttl", "Supersaw.ttl"),
    "harmonic": ("Analog_Brass.ttl", "Koto.ttl", "Pianium.ttl", "Trance_Pluck.ttl"),
    "chaos": ("Combat.ttl", "Nasty_Growl.ttl", "Sci_Fi_Computer.ttl", "Vitalium_Groove.ttl"),
    "default": ("Retro_Ambient_Pluck.ttl", "Sparkly_Dreamy_Pad.ttl", "Power_Lead.ttl"),
}


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def jitter(rng: random.Random, value: float, amount: float) -> float:
    return clamp(value + rng.uniform(-amount, amount), 0.0, 1.0)


def controls_for_profile(rng: random.Random, profile: str, mutate: float) -> dict[str, float]:
    amount = clamp(mutate, 0.0, 1.0)
    controls = {
        "oscillator_1_switch": 1.0,
        "oscillator_1_level": jitter(rng, 0.82, 0.10 * amount),
        "oscillator_1_wave_frame": jitter(rng, rng.choice([0.05, 0.18, 0.42, 0.66, 0.86]), 0.06 * amount),
        "oscillator_2_switch": rng.choice([0.0, 1.0]),
        "oscillator_2_level": jitter(rng, 0.32, 0.16 * amount),
        "oscillator_2_transpose": jitter(rng, rng.choice([0.25, 0.50, 0.75]), 0.03 * amount),
        "filter_1_switch": 1.0,
        "filter_1_cutoff": jitter(rng, 0.62, 0.14 * amount),
        "filter_1_resonance": jitter(rng, 0.22, 0.10 * amount),
        "chorus_switch": 0.0,
        "chorus_mix": 0.0,
        "delay_switch": 0.0,
        "delay_mix": 0.0,
        "reverb_switch": 0.0,
        "reverb_mix": 0.0,
        "distortion_switch": 0.0,
        "distortion_drive": 0.0,
        "envelope_1_attack": 0.02,
        "envelope_1_decay": 0.35,
        "envelope_1_sustain": 0.75,
        "envelope_1_release": 0.22,
    }

    if profile == "percussive":
        controls.update(
            {
                "oscillator_2_switch": 0.0,
                "filter_1_cutoff": jitter(rng, 0.70, 0.12 * amount),
                "filter_1_resonance": jitter(rng, 0.30, 0.10 * amount),
                "envelope_1_attack": 0.0,
                "envelope_1_decay": jitter(rng, 0.08, 0.04 * amount),
                "envelope_1_sustain": 0.0,
                "envelope_1_release": jitter(rng, 0.05, 0.03 * amount),
                "distortion_switch": 0.0,
                "distortion_drive": 0.0,
            }
        )
    elif profile == "drone":
        controls.update(
            {
                "oscillator_2_switch": 1.0,
                "oscillator_2_level": jitter(rng, 0.48, 0.12 * amount),
                "filter_1_cutoff": jitter(rng, 0.42, 0.16 * amount),
                "envelope_1_attack": jitter(rng, 0.34, 0.10 * amount),
                "envelope_1_decay": jitter(rng, 0.72, 0.10 * amount),
                "envelope_1_sustain": jitter(rng, 0.88, 0.06 * amount),
                "envelope_1_release": jitter(rng, 0.70, 0.12 * amount),
                "chorus_switch": 0.0,
                "chorus_mix": 0.0,
                "reverb_switch": 0.0,
                "reverb_mix": 0.0,
            }
        )
    elif profile == "harmonic":
        controls.update(
            {
                "filter_1_cutoff": jitter(rng, 0.56, 0.12 * amount),
                "envelope_1_attack": jitter(rng, 0.12, 0.08 * amount),
                "envelope_1_decay": jitter(rng, 0.55, 0.12 * amount),
                "envelope_1_sustain": jitter(rng, 0.78, 0.08 * amount),
                "envelope_1_release": jitter(rng, 0.46, 0.12 * amount),
                "chorus_switch": 0.0,
                "delay_switch": 0.0,
                "delay_mix": 0.0,
            }
        )
    elif profile == "chaos":
        controls.update(
            {
                "oscillator_2_switch": 1.0,
                "oscillator_2_level": jitter(rng, 0.62, 0.20 * amount),
                "filter_1_cutoff": jitter(rng, rng.choice([0.22, 0.48, 0.80]), 0.20 * amount),
                "filter_1_resonance": jitter(rng, 0.48, 0.22 * amount),
                "envelope_1_attack": jitter(rng, 0.02, 0.04 * amount),
                "envelope_1_decay": jitter(rng, 0.22, 0.18 * amount),
                "envelope_1_sustain": jitter(rng, 0.35, 0.30 * amount),
                "envelope_1_release": jitter(rng, 0.18, 0.18 * amount),
                "distortion_switch": 0.0,
                "distortion_drive": 0.0,
            }
        )

    return {key: clamp(value, 0.0, 1.0) for key, value in controls.items()}


def write_controls(slot: int, profile: str, rng: random.Random, mutate: float) -> Path:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    out = STATE_DIR / f"slot-{slot}.controls"
    controls = controls_for_profile(rng, profile, mutate)
    preset = rng.choice(PROFILE_PRESETS.get(profile, PROFILE_PRESETS["default"]))
    header = f"# preset_uri={PRESET_ROOT}/{preset}\n"
    out.write_text(
        header + "\n".join(f"{key}={value:.6f}" for key, value in sorted(controls.items())) + "\n",
        encoding="utf-8",
    )
    (STATE_DIR / "current.controls").write_text(out.read_text(encoding="utf-8"), encoding="utf-8")
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", default=None)
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--profile", default="default", choices=["chaos", "default", "drone", "harmonic", "percussive"])
    parser.add_argument("--mutate", type=float, default=0.18)
    parser.add_argument("--no-start", action="store_true", help="Only write the tweaked preset.")
    args = parser.parse_args()

    rng = random.Random(args.seed) if args.seed is not None else random.SystemRandom()
    out = write_controls(max(1, min(args.slot, 8)), args.profile, rng, args.mutate)

    if not args.no_start:
        subprocess.run(["/usr/local/bin/eap-start-vital", str(out)], check=True)

    print(f"vitalium controls output={out} profile={args.profile}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
