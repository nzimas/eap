#!/usr/bin/env python3
"""Run Subsequence as EAP's generative sequencer, driving SuperCollider via OSC."""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import subsequence
import subsequence.constants.durations as dur

from eap_subsequence_lanes import (
    build_lane_pattern,
    default_lane_cfg,
    init_lane_data,
    update_engine,
    update_lane_config,
    update_tuning,
)

LOG = logging.getLogger("eap.subsequence")

OSC_RECV = int(os.environ.get("EAP_SUBSEQUENCE_OSC_RECV", "57122"))
OSC_SEND = int(os.environ.get("EAP_SUBSEQUENCE_OSC_SEND", "57120"))
OSC_HOST = os.environ.get("EAP_SUBSEQUENCE_OSC_HOST", "127.0.0.1")
BPM = float(os.environ.get("EAP_SUBSEQUENCE_BPM", "90"))
MIDI_OUT = os.environ.get("EAP_SUBSEQUENCE_MIDI_OUTPUT", "")

ENGINE_CODES = {
    0: "any",
    1: "plaits",
    2: "rings",
    3: "passersby",
    4: "molly",
    5: "dexed",
    6: "vital",
}


def _register_lane_patterns(composition: subsequence.Composition) -> None:
    for slot in range(1, 9):

        def make_builder(lane_slot: int):
            def lane_pattern(p: subsequence.pattern_builder.PatternBuilder) -> None:
                cfg = composition.data.get("lanes", {}).get(str(lane_slot), default_lane_cfg(lane_slot))
                cfg = dict(cfg)
                cfg["slot"] = lane_slot
                build_lane_pattern(p, cfg, composition)

            lane_pattern.__name__ = f"lane_{lane_slot}"
            return lane_pattern

        builder = make_builder(slot)
        composition.pattern(
            channel=slot,
            steps=16,
            step_duration=dur.SIXTEENTH,
        )(builder)


def _refresh_lane_pattern(composition: subsequence.Composition, slot: int, active: bool) -> None:
    if not composition._running_patterns:
        return
    name = f"lane_{slot}"
    pattern = composition._running_patterns.get(name)
    if pattern is None:
        return
    if active:
        composition.unmute(name)
    else:
        composition.mute(name)
    if hasattr(pattern, "on_reschedule"):
        pattern.on_reschedule()


def _attach_virtual_midi(composition: subsequence.Composition) -> None:
    if composition._sequencer._output_devices.get() is not None:
        return
    try:
        import mido

        port = mido.open_output("EAP Subsequence", virtual=True)
        composition._sequencer._output_devices.add("EAP Subsequence", port)
        LOG.info("opened virtual MIDI sink: EAP Subsequence")
    except Exception as exc:
        LOG.warning("no MIDI output (OSC-only mode): %s", exc)


def _install_lane_osc_handler(composition: subsequence.Composition) -> None:
    def handle_lane(address: str, *args: object) -> None:
        if len(args) < 2:
            return
        slot = int(args[0])
        active = int(args[1]) == 1
        lanes = composition.data.setdefault("lanes", {})
        cfg = dict(lanes.get(str(slot), default_lane_cfg(slot)))
        cfg["active"] = active
        if active and len(args) >= 4:
            cfg["modifier"] = str(args[2])
            cfg["pulse"] = float(args[3])
            cfg["density"] = float(args[4]) if len(args) > 4 else 1.0
            cfg["profile"] = str(args[5]) if len(args) > 5 else "euclid"
            cfg["materials"] = int(args[6]) if len(args) > 6 else 1
            cfg["rest_prob"] = float(args[7]) if len(args) > 7 else 0.12
            cfg["swing"] = float(args[8]) if len(args) > 8 else 0.0
            cfg["seed"] = int(args[9]) if len(args) > 9 else slot * 9973
            if len(args) > 10:
                cfg["material"] = str(args[10])
            if len(args) > 13:
                cfg["scale_index"] = int(args[11])
                cfg["root_note"] = int(args[12])
                engine_code = int(args[13])
                cfg["engine"] = ENGINE_CODES.get(engine_code, "any")
            if len(args) > 14:
                scale_size = int(args[14])
                cfg["scale_size"] = scale_size
                cfg["scale_steps"] = [int(value) for value in args[15 : 15 + scale_size]]
        update_lane_config(composition, slot, cfg)
        _refresh_lane_pattern(composition, slot, active)
        LOG.info(
            "lane %s active=%s modifier=%s profile=%s material=%s engine=%s scale=%s",
            slot,
            active,
            cfg.get("modifier"),
            cfg.get("profile"),
            cfg.get("material"),
            cfg.get("engine"),
            cfg.get("scale_index"),
        )

    def handle_density(address: str, *args: object) -> None:
        if len(args) < 2:
            return
        slot = int(args[0])
        density = float(args[1])
        lanes = composition.data.setdefault("lanes", {})
        cfg = dict(lanes.get(str(slot), default_lane_cfg(slot)))
        cfg["density"] = density
        update_lane_config(composition, slot, cfg)
        if cfg.get("active"):
            _refresh_lane_pattern(composition, slot, True)

    def handle_tuning(address: str, *args: object) -> None:
        if len(args) < 3:
            return
        scale_index = int(args[0])
        root_note = int(args[1])
        scale_size = int(args[2]) if len(args) > 2 else 0
        scale_steps = [int(value) for value in args[3 : 3 + scale_size]]
        update_tuning(composition, scale_index, root_note, scale_steps)
        LOG.info("tuning scale=%s root=%s steps=%s", scale_index, root_note, scale_steps)

    def handle_engine(address: str, *args: object) -> None:
        if not args:
            return
        engine = ENGINE_CODES.get(int(args[0]), "any")
        update_engine(composition, engine)
        LOG.info("engine preference=%s", engine)

    composition.osc_map("/eap/seq/lane", handle_lane)
    composition.osc_map("/eap/seq/density", handle_density)
    composition.osc_map("/eap/seq/tuning", handle_tuning)
    composition.osc_map("/eap/seq/engine", handle_engine)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    output_device = MIDI_OUT or "EAP-Subsequence-Null"
    seed_raw = os.environ.get("EAP_SUBSEQUENCE_SEED", "")
    seed = int(seed_raw) if seed_raw else None

    composition = subsequence.Composition(bpm=BPM, output_device=output_device, seed=seed)
    init_lane_data(composition)
    _register_lane_patterns(composition)

    composition.osc(
        receive_port=OSC_RECV,
        send_port=OSC_SEND,
        send_host=OSC_HOST,
        receive_host="127.0.0.1",
    )
    _attach_virtual_midi(composition)
    _install_lane_osc_handler(composition)

    LOG.info(
        "EAP Subsequence bridge: bpm=%s recv=%s send=%s:%s",
        BPM,
        OSC_RECV,
        OSC_HOST,
        OSC_SEND,
    )
    composition.play()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
