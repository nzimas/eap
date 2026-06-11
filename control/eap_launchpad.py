#!/usr/bin/env python3
"""Launchpad Mini Mk3 scene-slot controller for Electroacoustic Playground."""

from __future__ import annotations

import os
import json
import re
import select
import socket
import struct
import subprocess
import sys
import time
from dataclasses import dataclass


BOTTOM_ROW_NOTES = tuple(range(11, 19))
MATRIX_NOTES = tuple((row * 10) + col for row in range(1, 9) for col in range(1, 9))
REVERB_CC = 91
TUNING_CC = 92
SETTINGS_CC = 97
SESSION_CC = 98
MASTER_CC = 89
GRID_FX_CC = 93
PERCUSSIVE_CC = 19
DRONE_CC = 29
CHAOS_CC = 39
MODIFIER_CCS = (PERCUSSIVE_CC, DRONE_CC, CHAOS_CC)
RETIRED_MODIFIER_CCS = (49,)
LONG_PRESS_SECONDS = float(os.environ.get("EAP_LONG_PRESS_SECONDS", "0.65"))
MIDI_IN = os.environ.get("EAP_LAUNCHPAD_IN", "")
MIDI_OUT = os.environ.get("EAP_LAUNCHPAD_OUT", "")
OSC_HOST = os.environ.get("EAP_OSC_HOST", "127.0.0.1")
OSC_PORT = int(os.environ.get("EAP_OSC_PORT", "57120"))
OSC_REPLY_PORT = int(os.environ.get("EAP_OSC_REPLY_PORT", "57121"))
SLOTS_STATE_PATH = b"/eap/slots/state\x00"
SLOTS_STATE_TAGS = b",iiiiiiii\x00"
SLOTS_DENSITY_PATH = b"/eap/slots/density\x00"
SLOTS_DENSITY_TAGS = b",iiiiiiii\x00"
SESSION_INDEX_PATH = os.environ.get(
    "EAP_SESSION_INDEX",
    "/home/we/.local/share/eap-launchpad/sessions.json",
)
PROGRAMMER_MODE_SYSEX = "F0 00 20 29 02 0D 0E 01 F7"

RGB_BLANK = (12, 12, 12)
RGB_ACTIVE = (0, 72, 12)
RGB_MUTED = (38, 30, 0)
RGB_REVERB_DIM = (4, 10, 18)
RGB_REVERB_VALUE = (0, 50, 86)
RGB_REVERB_TOP = (0, 84, 102)
RGB_MASTER_DIM = (16, 6, 3)
RGB_MASTER_VALUE = (72, 22, 0)
RGB_MASTER_TOP = (104, 38, 0)
RGB_SESSION_SAVED = (54, 0, 80)
RGB_SESSION_SAVING = (112, 34, 126)
RGB_SESSION_ACTIVE = (126, 76, 126)
RGB_TUNING_DIM = (5, 8, 16)
RGB_TUNING_VALUE = (12, 42, 88)
RGB_TUNING_SELECTED = (28, 108, 126)
RGB_ENGINE_DIM = (10, 5, 14)
RGB_ENGINE_VALUE = (54, 18, 88)
RGB_ENGINE_SELECTED = (112, 44, 126)
RGB_MODIFIER_IDLE = (90, 28, 0)
RGB_MODIFIER_HELD = (220, 220, 200)
RGB_MODIFIER_REQUIRED = (126, 0, 0)
RGB_PERFORMANCE_SELECTED = (0, 96, 126)
RGB_PERFORMANCE_VALUE = (0, 52, 86)
RGB_PERFORMANCE_DIM = (2, 10, 16)
RGB_PAN_SELECTED = (96, 32, 126)
RGB_PAN_VALUE = (42, 12, 74)
RGB_PAN_CENTER = (24, 24, 32)
RGB_DENSITY_SELECTED = (96, 86, 0)
RGB_DENSITY_VALUE = (54, 42, 0)
RGB_TIMBRE_SELECTED = (0, 112, 54)
RGB_TIMBRE_VALUE = (0, 58, 28)
RGB_REVERB_SEND_SELECTED = (0, 68, 126)
RGB_REVERB_SEND_VALUE = (0, 28, 74)
RGB_TRANSPOSE_SELECTED = (126, 64, 0)
RGB_TRANSPOSE_VALUE = (74, 28, 0)
RGB_TRANSPOSE_CENTER = (32, 24, 18)
RGB_GRID_FX_IDLE = (16, 10, 4)
RGB_GRID_FX_PAGE = (126, 80, 0)
RGB_GRID_FX_DIM = (10, 6, 2)
RGB_GRID_FX_AVAILABLE = (58, 28, 0)
RGB_GRID_FX_ACTIVE = (126, 92, 12)
RGB_GRID_FX_SCENE_ACTIVE = (0, 62, 14)
RGB_GRID_FX_SCENE_SELECTED = (0, 126, 42)
RGB_GRID_FX_LOCKED = (24, 0, 0)
RGB_GRID_FX_LOCKED_ACTIVE = (126, 0, 0)
RGB_GRID_FX_LOCK_FLASH = (126, 0, 0)
RGB_GRAN_IDLE = (6, 4, 14)
RGB_GRAN_PAGE = (40, 28, 126)
RGB_GRAN_DIM = (6, 4, 14)
RGB_GRAN_SCENE_ACTIVE = (0, 62, 14)
RGB_GRAN_SCENE_SELECTED = (0, 126, 42)
# Granular params (cols 1-4) are bipolar and purple; the filter params
# (cols 5-6) are unipolar and amber; dry/wet (col 7) is unipolar and teal.
RGB_GRAN_SLIDER_BG = (8, 6, 18)         # granular trail
RGB_GRAN_SLIDER_LIT = (80, 60, 126)     # granular lit
RGB_GRAN_CENTER = (110, 96, 126)        # bipolar centre line marker
RGB_FILT_SLIDER_BG = (16, 8, 2)         # filter trail
RGB_FILT_SLIDER_LIT = (126, 78, 10)     # filter lit
RGB_MIX_SLIDER_BG = (2, 14, 12)         # dry/wet trail
RGB_MIX_SLIDER_LIT = (12, 120, 104)     # dry/wet lit
RGB_GRAN_ACTIVE_IDLE = (40, 66, 16)
RGB_GRAN_ACTIVE_ON = (40, 126, 18)
RGB_FREEZE_IDLE = (14, 50, 64)
RGB_FREEZE_ACTIVE = (40, 126, 126)
RGB_SETTINGS_DIM = (8, 8, 10)
RGB_SETTINGS_VALUE = (44, 44, 56)
RGB_SETTINGS_SELECTED = (126, 126, 104)
RGB_SETTINGS_PAGE = (96, 96, 72)

ROOT_NOTES = [0, 2, 4, 5, 7, 9, 11]
ENGINE_CODES = [1, 2, 3, 4, 5, 6]
ENGINE_PAD_POSITIONS = [(4, col) for col in range(1, 7)]
MUTE_MODE_PADS = {81: 0, 82: 1}
AIRWINDOWS_FX = [
    "TapeDelay2", "PitchDelay", "Doublelay", "SampleDelay", "Melt", "ADT", "StarChild2", "TakeCare",
    "RingModulator", "Dubly3", "GalacticVibe", "Pafnuty2", "PitchNasty", "GuitarConditioner", "GlitchShifter", "Gringer",
    "Nikola", "HipCrush", "DeRez3", "Pockey2", "CrunchyGrooveWear", "BitGlitter", "TapeBias", "Vibrato",
    "Deckwrecka", "DeNoise", "Texturize", "VoiceOfTheStarship", "ElectroHat", "Silhouette",
]
MAX_GRID_FX_ACTIVE = 3

GRANULATOR_CC = 79
GRAN_ACTIVE_CC = 28    # on/off for granulator processing; only listens on the page
FREEZE_CC = 38         # write-head freeze; only listens on the page
# Seven vertical sliders, one per granulator parameter. Each lives in one
# column of the matrix; rows 2..8 form a 7-step bar with row 2 (top) = min and
# row 8 (bottom) = max (slider grows from the bottom up, per user preference).
GRAN_PARAM_NAMES = ["density", "jitter", "grain_size", "pitch", "cutoff", "resonance", "dry_wet"]
GRAN_SLIDER_COLS = (1, 2, 3, 4, 5, 6, 7)   # col 8 left blank
GRAN_SLIDER_ROWS = (2, 3, 4, 5, 6, 7, 8)
GRAN_SLIDER_STEPS = len(GRAN_SLIDER_ROWS)        # 7
GRAN_CENTER_ROW = 5                              # row 5 = bipolar centre (cc ~64)
GRAN_SCENE_ROW = 1                                # top row reserved for scene picks
# Columns 1-4 are the granular params and behave as bipolar (centre-detented)
# sliders; the centre is the neutral value (e.g. density centre = "no grains",
# pitch centre = unison). Columns 5-7 (cutoff, resonance, dry/wet) stay unipolar.
GRAN_BIPOLAR_COLS = (1, 2, 3, 4)
# Defaults: density just above centre so there are audible grains, jitter and
# size at centre, pitch at centre (unison); cutoff fairly open, low resonance,
# full wet.  cc 64 == bipolar centre.
# density, jitter, grain, pitch, cutoff, reso, dry/wet
GRAN_DEFAULTS_CC = [82, 64, 64, 64, 95, 13, 127]

STATE_BLANK = 0
STATE_ACTIVE = 1
STATE_MUTED = 2

NOTE_ON_RE = re.compile(r"Note on\s+\d+,\s+note\s+(\d+),\s+velocity\s+(\d+)")
NOTE_OFF_RE = re.compile(r"Note off\s+\d+,\s+note\s+(\d+)")
CONTROL_RE = re.compile(r"Control change\s+\d+,\s+controller\s+(\d+),\s+value\s+(\d+)")


@dataclass
class Pad:
    note: int
    state: int = STATE_BLANK
    pressed_at: float | None = None
    modifier_latch: int = 0
    generation_sent: bool = False
    volume: int = 100
    pan: int = 64
    density: int = 100
    timbre_motion: int = 0
    reverb_send: int = 64
    transpose: int = 0


@dataclass
class SessionPad:
    note: int
    pressed_at: float | None = None


def osc_string(value: str) -> bytes:
    data = value.encode("utf-8") + b"\0"
    return data + (b"\0" * ((4 - (len(data) % 4)) % 4))


def create_osc_socket() -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((OSC_HOST, OSC_REPLY_PORT))
    sock.setblocking(False)
    return sock


def send_osc_packet(sock: socket.socket, packet: bytes) -> None:
    sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_slot_osc(sock: socket.socket, slot: int, action: int, modifier: int = 0) -> None:
    packet = osc_string("/eap/slot") + osc_string(",iii")
    packet += struct.pack(">iii", int(slot), int(action), int(modifier))
    send_osc_packet(sock, packet)


def send_slots_query_osc(sock: socket.socket) -> None:
    send_osc_packet(sock, osc_string("/eap/slots/query") + osc_string(",") + b"\0\0\0")


def parse_slots_state_osc(data: bytes) -> list[int] | None:
    if SLOTS_STATE_PATH not in data:
        return None
    tag_index = data.find(SLOTS_STATE_TAGS)
    if tag_index < 0:
        return None
    offset = tag_index + len(SLOTS_STATE_TAGS)
    offset = ((offset + 3) // 4) * 4
    if len(data) < offset + 32:
        return None
    return list(struct.unpack(">8i", data[offset : offset + 32]))


def parse_slots_density_osc(data: bytes) -> list[int] | None:
    if SLOTS_DENSITY_PATH not in data:
        return None
    tag_index = data.find(SLOTS_DENSITY_TAGS)
    if tag_index < 0:
        return None
    offset = tag_index + len(SLOTS_DENSITY_TAGS)
    offset = ((offset + 3) // 4) * 4
    if len(data) < offset + 32:
        return None
    return list(struct.unpack(">8i", data[offset : offset + 32]))


def apply_slot_states(pads: dict[int, Pad], states: list[int]) -> None:
    for note, state in zip(BOTTOM_ROW_NOTES, states[: len(BOTTOM_ROW_NOTES)]):
        if state in (STATE_BLANK, STATE_ACTIVE, STATE_MUTED):
            pads[note].state = state


def apply_slot_densities(pads: dict[int, Pad], densities: list[int]) -> None:
    for note, density in zip(BOTTOM_ROW_NOTES, densities[: len(BOTTOM_ROW_NOTES)]):
        pads[note].density = max(0, min(int(density), 127))


def drain_slot_replies(osc_sock: socket.socket, pads: dict[int, Pad]) -> bool:
    updated = False
    while True:
        try:
            data, _ = osc_sock.recvfrom(4096)
        except BlockingIOError:
            break
        states = parse_slots_state_osc(data)
        densities = parse_slots_density_osc(data)
        if states is None and densities is None:
            continue
        if states is not None:
            apply_slot_states(pads, states)
        if densities is not None:
            apply_slot_densities(pads, densities)
        for pad in pads.values():
            paint(pad)
        updated = True
    return updated


def wait_slot_replies(osc_sock: socket.socket, pads: dict[int, Pad], timeout: float = 0.12) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        drain_slot_replies(osc_sock, pads)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        ready, _, _ = select.select([osc_sock], [], [], min(remaining, 0.05))
        if not ready:
            continue


def send_slot_volume_osc(slot: int, value: int) -> None:
    packet = osc_string("/eap/slot/volume") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), int(value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_slot_pan_osc(slot: int, value: int) -> None:
    packet = osc_string("/eap/slot/pan") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), int(value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_slot_density_osc(slot: int, value: int) -> None:
    packet = osc_string("/eap/slot/density") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), int(value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_slot_timbre_osc(slot: int, value: int) -> None:
    packet = osc_string("/eap/slot/timbre") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), int(value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_slot_reverb_send_osc(slot: int, value: int) -> None:
    packet = osc_string("/eap/slot/reverb") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), int(value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_slot_transpose_osc(slot: int, semitones: int) -> None:
    packet = osc_string("/eap/slot/transpose") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), int(semitones))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_mute_mode_osc(mode: int) -> None:
    packet = osc_string("/eap/settings/mute_mode") + osc_string(",i")
    packet += struct.pack(">i", int(mode))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_grid_fx_osc(index: int, enabled: bool) -> None:
    packet = osc_string("/eap/gridfx") + osc_string(",ii")
    packet += struct.pack(">ii", int(index), 1 if enabled else 0)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_grid_fx_scene_osc(slot: int, enabled: bool) -> None:
    packet = osc_string("/eap/gridfx/scene") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), 1 if enabled else 0)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_grid_fx_lock_osc(index: int, locked: bool) -> None:
    packet = osc_string("/eap/gridfx/lock") + osc_string(",ii")
    packet += struct.pack(">ii", int(index), 1 if locked else 0)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_granulator_active_osc(enabled: bool) -> None:
    packet = osc_string("/eap/granulator/active") + osc_string(",i")
    packet += struct.pack(">i", 1 if enabled else 0)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_granulator_scene_osc(slot: int, enabled: bool) -> None:
    packet = osc_string("/eap/granulator/scene") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), 1 if enabled else 0)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_granulator_param_osc(param: int, cc_value: int) -> None:
    packet = osc_string("/eap/granulator/param") + osc_string(",ii")
    packet += struct.pack(">ii", int(param), int(cc_value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_granulator_freeze_osc(enabled: bool) -> None:
    packet = osc_string("/eap/granulator/freeze") + osc_string(",i")
    packet += struct.pack(">i", 1 if enabled else 0)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def parse_status_indices(output: str, field: str) -> set[int]:
    match = re.search(rf"{field}=\[([^\]]*)\]", output)
    if match is None:
        return set()
    values: set[int] = set()
    for item in match.group(1).split(","):
        item = item.strip()
        if not item:
            continue
        try:
            values.add(int(item))
        except ValueError:
            pass
    return values


def sync_grid_fx_status(active_fx: list[int], locked_fx: set[int]) -> None:
    try:
        output = subprocess.check_output(["/usr/local/bin/eap-airwindows-grid-fx", "--status"], text=True)
    except (FileNotFoundError, subprocess.SubprocessError):
        return
    active_fx[:] = [index for index in sorted(parse_status_indices(output, "indices")) if 1 <= index <= len(AIRWINDOWS_FX)]
    locked_fx.clear()
    locked_fx.update(index for index in parse_status_indices(output, "locked") if 1 <= index <= len(AIRWINDOWS_FX))


def ensure_grid_fx_scene_selection(pads: dict[int, Pad], selected_scenes: set[int]) -> None:
    active_slots = {
        slot_for_note(note)
        for note, pad in pads.items()
        if pad.state == STATE_ACTIVE
    }
    selected_scenes.intersection_update(active_slots)
    if selected_scenes:
        return
    selected_scenes.update(active_slots)
    for slot in sorted(selected_scenes):
        send_grid_fx_scene_osc(slot, True)


def ensure_granulator_scene_selection(pads: dict[int, Pad], selected_scenes: set[int]) -> None:
    # Mirror of ensure_grid_fx_scene_selection: on page entry, drop selections
    # whose slot is no longer active, and if nothing is left, auto-route every
    # currently-active scene through the granulator so flipping CC 28 has
    # audible effect without a separate row-1 step.
    active_slots = {
        slot_for_note(note)
        for note, pad in pads.items()
        if pad.state == STATE_ACTIVE
    }
    selected_scenes.intersection_update(active_slots)
    if selected_scenes:
        return
    selected_scenes.update(active_slots)
    for slot in sorted(selected_scenes):
        send_granulator_scene_osc(slot, True)


def modifier_index_for_cc(cc: int) -> int:
    try:
        return MODIFIER_CCS.index(cc) + 1
    except ValueError:
        return 0


def active_modifier_index(held_cc: int | None) -> int:
    if held_cc is None:
        return 0
    return modifier_index_for_cc(held_cc)


def send_reverb_osc(param: int, value: int) -> None:
    packet = osc_string("/eap/reverb") + osc_string(",ii")
    packet += struct.pack(">ii", int(param), int(value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_master_osc(param: int, value: int) -> None:
    packet = osc_string("/eap/master") + osc_string(",ii")
    packet += struct.pack(">ii", int(param), int(value))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_session_osc(slot: int, action: int) -> None:
    packet = osc_string("/eap/session") + osc_string(",ii")
    packet += struct.pack(">ii", int(slot), int(action))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_tuning_osc(scale: int, root: int) -> None:
    packet = osc_string("/eap/tuning") + osc_string(",ii")
    packet += struct.pack(">ii", int(scale), int(root))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def send_engine_osc(engine_code: int) -> None:
    packet = osc_string("/eap/engine") + osc_string(",i")
    packet += struct.pack(">i", int(engine_code))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


def resolve_midi_in() -> str:
    if MIDI_IN:
        return MIDI_IN

    output = subprocess.check_output(["aconnect", "-l"], text=True)
    client = None
    for line in output.splitlines():
        client_match = re.match(r"client\s+(\d+):\s+'Launchpad Mini MK3'", line)
        if client_match:
            client = client_match.group(1)
            continue
        if client is not None:
            port_match = re.match(r"\s+(\d+)\s+'([^']+)'", line)
            if port_match and "MI" in port_match.group(2):
                return f"{client}:{port_match.group(1)}"

    raise RuntimeError("Launchpad Mini Mk3 MIDI input port not found")


def resolve_midi_out() -> str:
    if MIDI_OUT:
        return MIDI_OUT

    output = subprocess.check_output(["amidi", "-l"], text=True)
    fallback = None
    for line in output.splitlines():
        match = re.match(r"IO\s+(hw:\S+)\s+(.+)", line)
        if not match or "Launchpad Mini MK3" not in match.group(2):
            continue
        if "MI" in match.group(2):
            return match.group(1)
        if "DA" in match.group(2):
            fallback = match.group(1)

    if fallback is not None:
        return fallback

    raise RuntimeError("Launchpad Mini Mk3 MIDI output port not found")


def send_led(note: int, rgb: tuple[int, int, int]) -> None:
    red, green, blue = rgb
    sysex = f"F0 00 20 29 02 0D 03 03 {note:02X} {red:02X} {green:02X} {blue:02X} F7"
    subprocess.run(
        ["amidi", "-p", MIDI_OUT, "-S", sysex],
        check=False,
        stdout=sys.stderr,
        stderr=sys.stderr,
    )


def send_sysex(payload: str) -> None:
    subprocess.run(
        ["amidi", "-p", MIDI_OUT, "-S", payload],
        check=False,
        stdout=sys.stderr,
        stderr=sys.stderr,
    )


def enter_programmer_mode() -> None:
    send_sysex(PROGRAMMER_MODE_SYSEX)
    time.sleep(0.08)


def colour_for_state(state: int) -> tuple[int, int, int]:
    if state == STATE_ACTIVE:
        return RGB_ACTIVE
    if state == STATE_MUTED:
        return RGB_MUTED
    return RGB_BLANK


def paint(pad: Pad) -> None:
    send_led(pad.note, colour_for_state(pad.state))


def flash_modifier_required(pad: Pad) -> None:
    for colour in (RGB_MODIFIER_REQUIRED, (0, 0, 0), RGB_MODIFIER_REQUIRED):
        send_led(pad.note, colour)
        time.sleep(0.05)
    paint(pad)


def flash_engine_required(pad: Pad) -> None:
    for colour in (RGB_ENGINE_SELECTED, (0, 0, 0), RGB_ENGINE_SELECTED):
        send_led(pad.note, colour)
        time.sleep(0.05)
    paint(pad)


def parse_event(line: str) -> tuple[str, int] | None:
    match = NOTE_ON_RE.search(line)
    if match:
        note = int(match.group(1))
        velocity = int(match.group(2))
        return ("on" if velocity > 0 else "off", note)

    match = NOTE_OFF_RE.search(line)
    if match:
        return ("off", int(match.group(1)))

    match = CONTROL_RE.search(line)
    if match:
        return ("cc", (int(match.group(1)) << 8) | int(match.group(2)))

    return None


def wait_for_sc_ready(osc_sock: socket.socket, pads: dict[int, Pad], timeout: float = 45.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        send_slots_query_osc(osc_sock)
        wait_deadline = time.monotonic() + 0.75
        while time.monotonic() < wait_deadline:
            if drain_slot_replies(osc_sock, pads):
                print("eap-launchpad: SuperCollider ready", file=sys.stderr, flush=True)
                return True
            remaining = wait_deadline - time.monotonic()
            if remaining <= 0:
                break
            ready, _, _ = select.select([osc_sock], [], [], min(remaining, 0.05))
            if not ready:
                continue
        time.sleep(0.4)
    print("eap-launchpad: SuperCollider not ready for slot queries", file=sys.stderr, flush=True)
    return False


def modifier_for_pad(pad: Pad, held_modifier_cc: int | None) -> int:
    return pad.modifier_latch or active_modifier_index(held_modifier_cc)


def send_slot_generate(
    pad: Pad,
    held_modifier_cc: int | None,
    osc_sock: socket.socket,
    pads: dict[int, Pad],
    held_for: float,
    engine_index: int,
) -> bool:
    modifier = modifier_for_pad(pad, held_modifier_cc)
    if modifier == 0:
        return False
    if engine_index < 0:
        pad.generation_sent = True
        flash_engine_required(pad)
        return True
    slot = slot_for_note(pad.note)
    print(
        f"eap-launchpad: generate slot={slot} modifier={modifier} held={held_for:.2f}s",
        file=sys.stderr,
        flush=True,
    )
    send_slot_osc(osc_sock, slot, 1, modifier)
    pad.generation_sent = True
    pad.state = STATE_ACTIVE
    paint(pad)
    wait_slot_replies(osc_sock, pads, timeout=0.35)
    return True


def maybe_generate_on_hold(
    pads: dict[int, Pad],
    held_modifier_cc: int | None,
    osc_sock: socket.socket,
    engine_index: int,
) -> None:
    modifier = active_modifier_index(held_modifier_cc)
    if modifier == 0:
        return

    now = time.monotonic()
    for pad in pads.values():
        if pad.pressed_at is None or pad.generation_sent:
            continue
        held_for = now - pad.pressed_at
        if held_for < LONG_PRESS_SECONDS:
            continue
        send_slot_generate(pad, held_modifier_cc, osc_sock, pads, held_for, engine_index)


def latch_modifier_for_held_pads(pads: dict[int, Pad], held_modifier_cc: int | None) -> None:
    modifier = active_modifier_index(held_modifier_cc)
    if modifier == 0:
        return
    for pad in pads.values():
        if pad.pressed_at is not None:
            pad.modifier_latch = modifier


def handle_release(
    pad: Pad,
    held_modifier_cc: int | None,
    osc_sock: socket.socket,
    pads: dict[int, Pad],
    engine_index: int,
) -> None:
    if pad.pressed_at is None:
        return

    held_for = time.monotonic() - pad.pressed_at
    pad.pressed_at = None
    modifier = modifier_for_pad(pad, held_modifier_cc)
    pad.modifier_latch = 0
    slot = slot_for_note(pad.note)

    if pad.generation_sent:
        pad.generation_sent = False
        return

    if held_for >= LONG_PRESS_SECONDS:
        if not send_slot_generate(pad, held_modifier_cc, osc_sock, pads, held_for, engine_index):
            flash_modifier_required(pad)
    elif pad.state == STATE_BLANK:
        # Short taps never create scenes. SC may still unmute if local state is stale.
        send_slot_osc(osc_sock, slot, 0, 0)
        wait_slot_replies(osc_sock, pads)
    else:
        # Mute / unmute only — never pass modifier on toggle.
        send_slot_osc(osc_sock, slot, 0, 0)
        wait_slot_replies(osc_sock, pads)


def slot_for_note(note: int) -> int:
    return BOTTOM_ROW_NOTES.index(note) + 1


def session_slot_for_note(note: int) -> int:
    position = matrix_position(note)
    if position is None:
        return 0
    row, col = position
    return ((row - 1) * 8) + col


def matrix_position(note: int) -> tuple[int, int] | None:
    row, col = divmod(note, 10)
    if 1 <= row <= 8 and 1 <= col <= 8:
        return row, col
    return None


def paint_modifier_leds(held_cc: int | None) -> None:
    for cc in MODIFIER_CCS:
        colour = RGB_MODIFIER_HELD if cc == held_cc else RGB_MODIFIER_IDLE
        send_led(cc, colour)
    for cc in RETIRED_MODIFIER_CCS:
        send_led(cc, (0, 0, 0))


def paint_scene_page(pads: dict[int, Pad], held_modifier_cc: int | None = None) -> None:
    for note in MATRIX_NOTES:
        send_led(note, (0, 0, 0))
    for pad in pads.values():
        paint(pad)
    paint_modifier_leds(held_modifier_cc)
    send_led(SETTINGS_CC, RGB_SETTINGS_DIM)
    send_led(GRID_FX_CC, RGB_GRID_FX_IDLE)
    send_led(GRANULATOR_CC, RGB_GRAN_IDLE)
    # CC 28 (on/off) and CC 38 (freeze) only belong to the granulator page;
    # leave them dark when the user is on the main scenes view. The matrix
    # clear above already turned pads 28 and 38 off.


def col_for_value(value: int) -> int:
    return 1 + round((max(0, min(value, 127)) / 127) * 7)


def value_for_col(col: int) -> int:
    return round(((col - 1) / 7) * 127)


def transpose_for_col(col: int) -> int:
    if col <= 4:
        return (col - 4) * 12
    return (col - 5) * 12


def col_for_transpose(semitones: int) -> int:
    steps = max(-3, min(round(semitones / 12), 3))
    if steps < 0:
        return 4 + steps
    if steps > 0:
        return 5 + steps
    return 5


def paint_performance_page(pads: dict[int, Pad], selected_slot: int) -> None:
    selected_note = BOTTOM_ROW_NOTES[selected_slot - 1]
    pad = pads[selected_note]
    volume_col = col_for_value(pad.volume)
    pan_col = col_for_value(pad.pan)
    density_col = col_for_value(pad.density)
    timbre_col = col_for_value(pad.timbre_motion)
    reverb_send_col = col_for_value(pad.reverb_send)
    transpose_col = col_for_transpose(pad.transpose)
    for note in MATRIX_NOTES:
        position = matrix_position(note)
        if position is None:
            continue
        row, col = position
        if row == 1:
            if note == selected_note:
                send_led(note, RGB_PERFORMANCE_SELECTED)
            else:
                send_led(note, colour_for_state(pads[note].state) if note in pads else (0, 0, 0))
        elif row == 2:
            if col == volume_col:
                colour = RGB_PERFORMANCE_SELECTED
            elif col <= volume_col:
                colour = RGB_PERFORMANCE_VALUE
            else:
                colour = RGB_PERFORMANCE_DIM
            send_led(note, colour)
        elif row == 3:
            if col == pan_col:
                colour = RGB_PAN_SELECTED
            elif col in (4, 5):
                colour = RGB_PAN_CENTER
            elif (pan_col < 5 and pan_col <= col <= 4) or (pan_col > 4 and 5 <= col <= pan_col):
                colour = RGB_PAN_VALUE
            else:
                colour = RGB_PERFORMANCE_DIM
            send_led(note, colour)
        elif row == 4:
            if col == density_col:
                colour = RGB_DENSITY_SELECTED
            elif col <= density_col:
                colour = RGB_DENSITY_VALUE
            else:
                colour = RGB_PERFORMANCE_DIM
            send_led(note, colour)
        elif row == 5:
            if col == timbre_col:
                colour = RGB_TIMBRE_SELECTED
            elif col <= timbre_col:
                colour = RGB_TIMBRE_VALUE
            else:
                colour = RGB_PERFORMANCE_DIM
            send_led(note, colour)
        elif row == 6:
            if col == reverb_send_col:
                colour = RGB_REVERB_SEND_SELECTED
            elif col <= reverb_send_col:
                colour = RGB_REVERB_SEND_VALUE
            else:
                colour = RGB_PERFORMANCE_DIM
            send_led(note, colour)
        elif row == 7:
            if pad.transpose == 0 and col in (4, 5):
                colour = RGB_TRANSPOSE_SELECTED
            elif col == transpose_col:
                colour = RGB_TRANSPOSE_SELECTED
            elif col in (4, 5):
                colour = RGB_TRANSPOSE_CENTER
            elif (transpose_col < 5 and transpose_col <= col <= 4) or (transpose_col > 5 and 5 <= col <= transpose_col):
                colour = RGB_TRANSPOSE_VALUE
            else:
                colour = RGB_PERFORMANCE_DIM
            send_led(note, colour)
        else:
            send_led(note, RGB_PERFORMANCE_DIM)


def handle_performance_note(note: int, pads: dict[int, Pad], selected_slot: int) -> bool:
    position = matrix_position(note)
    if position is None:
        return False
    row, col = position
    selected_note = BOTTOM_ROW_NOTES[selected_slot - 1]
    pad = pads[selected_note]
    value = value_for_col(col)
    if row == 2:
        pad.volume = value
        send_slot_volume_osc(selected_slot, value)
        paint_performance_page(pads, selected_slot)
        return True
    if row == 3:
        pad.pan = value
        send_slot_pan_osc(selected_slot, value)
        paint_performance_page(pads, selected_slot)
        return True
    if row == 4:
        pad.density = value
        send_slot_density_osc(selected_slot, value)
        paint_performance_page(pads, selected_slot)
        return True
    if row == 5:
        pad.timbre_motion = value
        send_slot_timbre_osc(selected_slot, value)
        paint_performance_page(pads, selected_slot)
        return True
    if row == 6:
        pad.reverb_send = value
        send_slot_reverb_send_osc(selected_slot, value)
        paint_performance_page(pads, selected_slot)
        return True
    if row == 7:
        pad.transpose = transpose_for_col(col)
        send_slot_transpose_osc(selected_slot, pad.transpose)
        paint_performance_page(pads, selected_slot)
        return True
    return False


def grid_fx_index_for_note(note: int) -> int | None:
    position = matrix_position(note)
    if position is None:
        return None
    row, col = position
    if 2 <= row <= 7:
        index = ((row - 2) * 8) + col
        if 1 <= index <= len(AIRWINDOWS_FX):
            return index
    return None


def paint_grid_fx_page(
    active_fx: list[int],
    pads: dict[int, Pad],
    selected_scenes: set[int],
    locked_fx: set[int],
) -> None:
    active = set(active_fx)
    for note in MATRIX_NOTES:
        position = matrix_position(note)
        if position is None:
            continue
        row, col = position
        if row == 1:
            pad = pads.get(note)
            if pad is not None and pad.state == STATE_ACTIVE:
                slot = slot_for_note(note)
                colour = RGB_GRID_FX_SCENE_SELECTED if slot in selected_scenes else RGB_GRID_FX_SCENE_ACTIVE
            elif pad is not None and pad.state == STATE_MUTED:
                colour = RGB_MUTED
            else:
                colour = RGB_GRID_FX_DIM
            send_led(note, colour)
            continue
        index = grid_fx_index_for_note(note)
        if index is None:
            send_led(note, RGB_GRID_FX_DIM)
        elif index in locked_fx and index in active:
            send_led(note, RGB_GRID_FX_LOCKED_ACTIVE)
        elif index in locked_fx:
            send_led(note, RGB_GRID_FX_LOCKED)
        elif index in active:
            send_led(note, RGB_GRID_FX_ACTIVE)
        else:
            send_led(note, RGB_GRID_FX_AVAILABLE)
    send_led(GRID_FX_CC, RGB_GRID_FX_PAGE)


def flash_grid_fx_lock(note: int) -> None:
    for colour in (RGB_GRID_FX_LOCK_FLASH, (0, 0, 0), RGB_GRID_FX_LOCK_FLASH):
        send_led(note, colour)
        time.sleep(0.05)


def handle_grid_fx_note(
    note: int,
    active_fx: list[int],
    pads: dict[int, Pad],
    selected_scenes: set[int],
    locked_fx: set[int],
) -> bool:
    position = matrix_position(note)
    if position is not None and position[0] == 1:
        pad = pads.get(note)
        if pad is None or pad.state != STATE_ACTIVE:
            return False
        slot = slot_for_note(note)
        if slot in selected_scenes:
            selected_scenes.remove(slot)
            send_grid_fx_scene_osc(slot, False)
        else:
            selected_scenes.add(slot)
            send_grid_fx_scene_osc(slot, True)
        paint_grid_fx_page(active_fx, pads, selected_scenes, locked_fx)
        return True

    index = grid_fx_index_for_note(note)
    if index is None:
        return False
    if index in active_fx:
        active_fx.remove(index)
        send_grid_fx_osc(index, False)
    else:
        ensure_grid_fx_scene_selection(pads, selected_scenes)
        while len(active_fx) >= MAX_GRID_FX_ACTIVE:
            removed = active_fx.pop(0)
            send_grid_fx_osc(removed, False)
        active_fx.append(index)
        send_grid_fx_osc(index, True)
    paint_grid_fx_page(active_fx, pads, selected_scenes, locked_fx)
    return True


def handle_grid_fx_release(
    note: int,
    pressed_at: float | None,
    active_fx: list[int],
    pads: dict[int, Pad],
    selected_scenes: set[int],
    locked_fx: set[int],
) -> bool:
    if pressed_at is None:
        return False
    held_for = time.monotonic() - pressed_at
    index = grid_fx_index_for_note(note)
    if index is not None and held_for >= LONG_PRESS_SECONDS:
        if index in locked_fx:
            locked_fx.remove(index)
            send_grid_fx_lock_osc(index, False)
        else:
            locked_fx.add(index)
            send_grid_fx_lock_osc(index, True)
        flash_grid_fx_lock(note)
        paint_grid_fx_page(active_fx, pads, selected_scenes, locked_fx)
        return True
    return handle_grid_fx_note(note, active_fx, pads, selected_scenes, locked_fx)


def gran_slider_col_for_note(note: int) -> int | None:
    position = matrix_position(note)
    if position is None:
        return None
    row, col = position
    if row not in GRAN_SLIDER_ROWS:
        return None
    if col not in GRAN_SLIDER_COLS:
        return None
    return col


def gran_value_cc_for_row(row: int) -> int:
    # Row 2 (top) -> 0, row 8 (bottom) -> 127. The bar grows from the bottom
    # up as the value rises. Row 5 lands on ~cc 64, the bipolar centre.
    step = max(0, row - 2)
    return int(round((step / (GRAN_SLIDER_STEPS - 1)) * 127))


def gran_value_row_for_cc(cc_value: int) -> int:
    # Inverse of gran_value_cc_for_row: which row a cc value sits on (2..8).
    return int(round((cc_value / 127) * (GRAN_SLIDER_STEPS - 1))) + 2


def gran_lit_count_for_value(cc_value: int) -> int:
    # Unipolar fill: how many pads to light from the bottom up for a given cc.
    return int(round((cc_value / 127) * GRAN_SLIDER_STEPS))


def paint_granulator_page(
    granulator_params: list[int],
    pads: dict[int, Pad],
    granulator_scenes: set[int],
    granulator_freeze: bool,
    granulator_active: bool,
) -> None:
    for note in MATRIX_NOTES:
        position = matrix_position(note)
        if position is None:
            continue
        row, col = position
        if row == GRAN_SCENE_ROW:
            pad = pads.get(note)
            if pad is not None and pad.state == STATE_ACTIVE:
                slot = slot_for_note(note)
                colour = (
                    RGB_GRAN_SCENE_SELECTED
                    if slot in granulator_scenes
                    else RGB_GRAN_SCENE_ACTIVE
                )
            elif pad is not None and pad.state == STATE_MUTED:
                colour = RGB_MUTED
            else:
                colour = RGB_GRAN_DIM
            send_led(note, colour)
            continue
        if col in GRAN_SLIDER_COLS and row in GRAN_SLIDER_ROWS:
            param_idx = col - 1
            cc_value = granulator_params[param_idx]
            if col in GRAN_BIPOLAR_COLS:
                # Bipolar: lit band runs from the centre row to the value row,
                # with the centre always marked so the neutral point is findable.
                value_row = gran_value_row_for_cc(cc_value)
                lo, hi = sorted((GRAN_CENTER_ROW, value_row))
                if row == GRAN_CENTER_ROW:
                    send_led(note, RGB_GRAN_CENTER)
                elif lo <= row <= hi:
                    send_led(note, RGB_GRAN_SLIDER_LIT)
                else:
                    send_led(note, RGB_GRAN_SLIDER_BG)
            else:
                # Unipolar: fill from the bottom up. Filter cols amber, dry/wet teal.
                lit = gran_lit_count_for_value(cc_value)
                lit_colour = RGB_MIX_SLIDER_LIT if col == 7 else RGB_FILT_SLIDER_LIT
                bg_colour = RGB_MIX_SLIDER_BG if col == 7 else RGB_FILT_SLIDER_BG
                if row > (8 - lit):
                    send_led(note, lit_colour)
                else:
                    send_led(note, bg_colour)
            continue
        send_led(note, RGB_GRAN_DIM)
    send_led(GRANULATOR_CC, RGB_GRAN_PAGE)
    send_led(GRAN_ACTIVE_CC, RGB_GRAN_ACTIVE_ON if granulator_active else RGB_GRAN_ACTIVE_IDLE)
    send_led(FREEZE_CC, RGB_FREEZE_ACTIVE if granulator_freeze else RGB_FREEZE_IDLE)


def handle_granulator_note(
    note: int,
    granulator_params: list[int],
    pads: dict[int, Pad],
    granulator_scenes: set[int],
    granulator_freeze: bool,
    granulator_active: bool,
) -> bool:
    position = matrix_position(note)
    if position is None:
        return False
    row, col = position
    if row == GRAN_SCENE_ROW:
        pad = pads.get(note)
        if pad is None or pad.state != STATE_ACTIVE:
            return False
        slot = slot_for_note(note)
        # Toggle scene routing but leave the master active flag alone --
        # that one is now driven exclusively by CC 28.
        if slot in granulator_scenes:
            granulator_scenes.remove(slot)
            send_granulator_scene_osc(slot, False)
        else:
            granulator_scenes.add(slot)
            send_granulator_scene_osc(slot, True)
        paint_granulator_page(granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
        return True
    if col in GRAN_SLIDER_COLS and row in GRAN_SLIDER_ROWS:
        param_idx = col - 1
        cc_value = gran_value_cc_for_row(row)
        granulator_params[param_idx] = cc_value
        send_granulator_param_osc(param_idx + 1, cc_value)
        paint_granulator_page(granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
        return True
    return False


def paint_reverb_page(values: list[int]) -> None:
    for note in MATRIX_NOTES:
        position = matrix_position(note)
        if position is None:
            continue
        row, col = position
        current_row = 1 + round((values[col - 1] / 127) * 7)
        if row == current_row:
            colour = RGB_REVERB_TOP
        elif row < current_row:
            colour = RGB_REVERB_VALUE
        else:
            colour = RGB_REVERB_DIM
        send_led(note, colour)


def handle_reverb_note(note: int, values: list[int]) -> None:
    position = matrix_position(note)
    if position is None:
        return
    row, col = position
    value = round(((row - 1) / 7) * 127)
    values[col - 1] = value
    send_reverb_osc(col, value)
    paint_reverb_page(values)


def paint_master_page(values: list[int]) -> None:
    for note in MATRIX_NOTES:
        position = matrix_position(note)
        if position is None:
            continue
        row, col = position
        if col > 5:
            send_led(note, (0, 0, 0))
            continue
        current_row = 1 + round((values[col - 1] / 127) * 7)
        if row == current_row:
            colour = RGB_MASTER_TOP
        elif row < current_row:
            colour = RGB_MASTER_VALUE
        else:
            colour = RGB_MASTER_DIM
        send_led(note, colour)


def handle_master_note(note: int, values: list[int]) -> None:
    position = matrix_position(note)
    if position is None:
        return
    row, col = position
    if col > 5:
        return
    value = round(((row - 1) / 7) * 127)
    values[col - 1] = value
    send_master_osc(col, value)
    paint_master_page(values)


def paint_settings_page(mute_mode: int) -> None:
    for note in MATRIX_NOTES:
        if note in MUTE_MODE_PADS:
            colour = RGB_SETTINGS_SELECTED if MUTE_MODE_PADS[note] == mute_mode else RGB_SETTINGS_VALUE
        else:
            colour = RGB_SETTINGS_DIM
        send_led(note, colour)
    send_led(SETTINGS_CC, RGB_SETTINGS_PAGE)


def handle_settings_note(note: int, settings_values: list[int]) -> bool:
    if note not in MUTE_MODE_PADS:
        return False
    settings_values[0] = MUTE_MODE_PADS[note]
    send_mute_mode_osc(settings_values[0])
    paint_settings_page(settings_values[0])
    return True


def paint_tuning_page(scale_index: int, root_index: int, engine_index: int = -1) -> None:
    engine_positions = {position: index for index, position in enumerate(ENGINE_PAD_POSITIONS)}
    for note in MATRIX_NOTES:
        position = matrix_position(note)
        if position is None:
            continue
        row, col = position
        if row == 8:
            colour = RGB_TUNING_SELECTED if (col - 1) == scale_index else RGB_TUNING_VALUE
        elif row == 7 and col <= 7:
            colour = RGB_TUNING_SELECTED if (col - 1) == root_index else RGB_TUNING_DIM
        elif (row, col) in engine_positions:
            colour = RGB_ENGINE_SELECTED if engine_positions[(row, col)] == engine_index else RGB_ENGINE_VALUE
        else:
            colour = (0, 0, 0)
        send_led(note, colour)


def handle_tuning_note(note: int, tuning_values: list[int]) -> None:
    position = matrix_position(note)
    if position is None:
        return
    row, col = position
    if row == 8:
        tuning_values[0] = col - 1
    elif row == 7 and col <= 7:
        tuning_values[1] = col - 1
    elif (row, col) in ENGINE_PAD_POSITIONS:
        tuning_values[2] = ENGINE_PAD_POSITIONS.index((row, col))
        send_engine_osc(ENGINE_CODES[tuning_values[2]])
        paint_tuning_page(tuning_values[0], tuning_values[1], tuning_values[2])
        return
    else:
        return
    send_tuning_osc(tuning_values[0], ROOT_NOTES[tuning_values[1]])
    paint_tuning_page(tuning_values[0], tuning_values[1], tuning_values[2])


def load_session_index() -> dict:
    try:
        with open(SESSION_INDEX_PATH, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}
    slots = data.get("slots")
    if not isinstance(slots, dict):
        data["slots"] = {}
    active_slot = data.get("active_slot")
    if not isinstance(active_slot, int) or not 1 <= active_slot <= 64:
        data["active_slot"] = None
    return data


def save_session_index(index: dict) -> None:
    os.makedirs(os.path.dirname(SESSION_INDEX_PATH), exist_ok=True)
    with open(SESSION_INDEX_PATH, "w", encoding="utf-8") as handle:
        json.dump(index, handle, sort_keys=True)


def session_snapshot(
    pads: dict[int, Pad],
    reverb_values: list[int],
    master_values: list[int],
    tuning_values: list[int],
    settings_values: list[int],
) -> dict:
    return {
        "saved_at": time.time(),
        "pads": [pads[note].state for note in BOTTOM_ROW_NOTES],
        "scene_volume": [pads[note].volume for note in BOTTOM_ROW_NOTES],
        "scene_pan": [pads[note].pan for note in BOTTOM_ROW_NOTES],
        "scene_density": [pads[note].density for note in BOTTOM_ROW_NOTES],
        "scene_timbre_motion": [pads[note].timbre_motion for note in BOTTOM_ROW_NOTES],
        "scene_reverb_send": [pads[note].reverb_send for note in BOTTOM_ROW_NOTES],
        "scene_transpose": [pads[note].transpose for note in BOTTOM_ROW_NOTES],
        "reverb": list(reverb_values),
        "master": list(master_values),
        "tuning": list(tuning_values),
        "settings": list(settings_values),
    }


def restore_session_snapshot(
    data: dict,
    pads: dict[int, Pad],
    reverb_values: list[int],
    master_values: list[int],
    tuning_values: list[int],
    settings_values: list[int],
) -> None:
    for note, state in zip(BOTTOM_ROW_NOTES, data.get("pads", [])):
        if state in (STATE_BLANK, STATE_ACTIVE, STATE_MUTED):
            pads[note].state = state
    for note, value in zip(BOTTOM_ROW_NOTES, data.get("scene_volume", [])):
        if isinstance(value, int):
            pads[note].volume = max(0, min(value, 127))
            send_slot_volume_osc(slot_for_note(note), pads[note].volume)
    for note, value in zip(BOTTOM_ROW_NOTES, data.get("scene_pan", [])):
        if isinstance(value, int):
            pads[note].pan = max(0, min(value, 127))
            send_slot_pan_osc(slot_for_note(note), pads[note].pan)
    for note, value in zip(BOTTOM_ROW_NOTES, data.get("scene_density", [])):
        if isinstance(value, int):
            pads[note].density = max(0, min(value, 127))
            send_slot_density_osc(slot_for_note(note), pads[note].density)
    for note, value in zip(BOTTOM_ROW_NOTES, data.get("scene_timbre_motion", [])):
        if isinstance(value, int):
            pads[note].timbre_motion = max(0, min(value, 127))
            send_slot_timbre_osc(slot_for_note(note), pads[note].timbre_motion)
    for note, value in zip(BOTTOM_ROW_NOTES, data.get("scene_reverb_send", [])):
        if isinstance(value, int):
            pads[note].reverb_send = max(0, min(value, 127))
            send_slot_reverb_send_osc(slot_for_note(note), pads[note].reverb_send)
    for note, value in zip(BOTTOM_ROW_NOTES, data.get("scene_transpose", [])):
        if isinstance(value, int):
            pads[note].transpose = max(-36, min(value, 36))
            send_slot_transpose_osc(slot_for_note(note), pads[note].transpose)
    for target, source in (
        (reverb_values, data.get("reverb", [])),
        (master_values, data.get("master", [])),
        (tuning_values, data.get("tuning", [])),
        (settings_values, data.get("settings", [])),
    ):
        for index, value in enumerate(source[: len(target)]):
            if isinstance(value, int):
                limit = (
                    7
                    if target is tuning_values and index == 0
                    else 6
                    if target is tuning_values and index == 1
                    else len(ENGINE_CODES) - 1
                    if target is tuning_values and index == 2
                    else 1
                    if target is settings_values and index == 0
                    else 127
                )
                floor = -1 if target is tuning_values and index == 2 else 0
                target[index] = max(floor, min(value, limit))
    if len(tuning_values) > 2 and tuning_values[2] >= 0:
        send_engine_osc(ENGINE_CODES[tuning_values[2]])
    if settings_values:
        send_mute_mode_osc(settings_values[0])


def paint_session_page(index: dict) -> None:
    saved = index.get("slots", {})
    active_slot = index.get("active_slot")
    for note in MATRIX_NOTES:
        slot = session_slot_for_note(note)
        if slot == active_slot and str(slot) in saved:
            colour = RGB_SESSION_ACTIVE
        else:
            colour = RGB_SESSION_SAVED if str(slot) in saved else (0, 0, 0)
        send_led(note, colour)


def blink_session_save(note: int) -> None:
    for colour in (RGB_SESSION_SAVING, (0, 0, 0), RGB_SESSION_SAVING, RGB_SESSION_SAVED):
        send_led(note, colour)
        time.sleep(0.08)


def handle_session_release(
    session_pad: SessionPad,
    session_index: dict,
    pads: dict[int, Pad],
    reverb_values: list[int],
    master_values: list[int],
    tuning_values: list[int],
    settings_values: list[int],
) -> None:
    if session_pad.pressed_at is None:
        return

    held_for = time.monotonic() - session_pad.pressed_at
    session_pad.pressed_at = None
    slot = session_slot_for_note(session_pad.note)
    if slot <= 0:
        return

    slots = session_index.setdefault("slots", {})
    key = str(slot)
    if held_for >= LONG_PRESS_SECONDS:
        blink_session_save(session_pad.note)
        send_session_osc(slot, 1)
        slots[key] = session_snapshot(pads, reverb_values, master_values, tuning_values, settings_values)
        session_index["active_slot"] = slot
        save_session_index(session_index)
        paint_session_page(session_index)
    elif key in slots:
        send_session_osc(slot, 0)
        restore_session_snapshot(slots[key], pads, reverb_values, master_values, tuning_values, settings_values)
        session_index["active_slot"] = slot
        save_session_index(session_index)
        paint_session_page(session_index)


def main() -> int:
    global MIDI_IN, MIDI_OUT
    MIDI_IN = resolve_midi_in()
    MIDI_OUT = resolve_midi_out()
    enter_programmer_mode()

    pads = {note: Pad(note) for note in BOTTOM_ROW_NOTES}
    session_pads = {note: SessionPad(note) for note in MATRIX_NOTES}
    session_index = load_session_index()
    reverb_values = [31, 70, 57, 46, 32, 94, 31, 79]
    master_values = [104, 0, 127, 15, 0]
    tuning_values = [0, 0, -1]
    settings_values = [1]
    mode = "scene"
    held_modifier_cc: int | None = None
    performance_slot: int | None = None
    performance_scene_note: int | None = None
    performance_interacted = False
    grid_fx_active: list[int] = []
    grid_fx_scenes: set[int] = set()
    grid_fx_locked: set[int] = set()
    grid_fx_pressed: dict[int, float] = {}
    granulator_scenes: set[int] = set()
    granulator_params: list[int] = list(GRAN_DEFAULTS_CC)
    granulator_freeze: bool = False
    # Master engagement is now an explicit toggle (CC 28). Scene picks just
    # configure routing; nothing reaches the granulator until this flips on.
    granulator_active: bool = False
    paint_scene_page(pads, held_modifier_cc)
    osc_sock = create_osc_socket()
    wait_for_sc_ready(osc_sock, pads)
    send_mute_mode_osc(settings_values[0])
    send_slots_query_osc(osc_sock)
    wait_slot_replies(osc_sock, pads, timeout=1.0)
    paint_scene_page(pads, held_modifier_cc)

    while True:
        proc = subprocess.Popen(
            ["aseqdump", "-p", MIDI_IN],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
        )
        assert proc.stdout is not None
        send_slots_query_osc(osc_sock)
        wait_slot_replies(osc_sock, pads, timeout=0.5)
        while proc.poll() is None:
            if mode == "scene":
                if active_modifier_index(held_modifier_cc) == 0:
                    now = time.monotonic()
                    for held_pad in pads.values():
                        if (
                            held_pad.pressed_at is not None
                            and held_pad.state != STATE_BLANK
                            and now - held_pad.pressed_at >= LONG_PRESS_SECONDS
                        ):
                            performance_slot = slot_for_note(held_pad.note)
                            performance_scene_note = held_pad.note
                            performance_interacted = False
                            mode = "performance"
                            paint_performance_page(pads, performance_slot)
                            break
                else:
                    maybe_generate_on_hold(pads, held_modifier_cc, osc_sock, tuning_values[2])

            drain_slot_replies(osc_sock, pads)

            ready, _, _ = select.select([proc.stdout], [], [], 0.05)
            if not ready:
                continue

            line = proc.stdout.readline()
            if line == "":
                break
            event = parse_event(line)
            if event is None:
                continue
            kind, data = event
            if kind == "cc":
                controller = data >> 8
                value = data & 0xFF
                if controller in MODIFIER_CCS:
                    if value > 0:
                        held_modifier_cc = controller
                        latch_modifier_for_held_pads(pads, held_modifier_cc)
                    elif held_modifier_cc == controller:
                        held_modifier_cc = None
                    if mode == "scene":
                        paint_modifier_leds(held_modifier_cc)
                    continue
                if controller == REVERB_CC:
                    if value > 0 and mode != "reverb":
                        mode = "reverb"
                        performance_slot = None
                        performance_scene_note = None
                        paint_reverb_page(reverb_values)
                    elif value == 0 and mode != "scene":
                        mode = "scene"
                        paint_scene_page(pads, held_modifier_cc)
                elif controller == TUNING_CC:
                    if value > 0 and mode != "tuning":
                        mode = "tuning"
                        performance_slot = None
                        performance_scene_note = None
                        paint_tuning_page(tuning_values[0], tuning_values[1], tuning_values[2])
                    elif value == 0 and mode != "scene":
                        mode = "scene"
                        paint_scene_page(pads, held_modifier_cc)
                elif controller == SESSION_CC:
                    if value > 0 and mode != "session":
                        mode = "session"
                        performance_slot = None
                        performance_scene_note = None
                        paint_session_page(session_index)
                    elif value == 0 and mode != "scene":
                        mode = "scene"
                        paint_scene_page(pads, held_modifier_cc)
                elif controller == MASTER_CC:
                    if value > 0 and mode != "master":
                        mode = "master"
                        performance_slot = None
                        performance_scene_note = None
                        paint_master_page(master_values)
                    elif value == 0 and mode != "scene":
                        mode = "scene"
                        paint_scene_page(pads, held_modifier_cc)
                elif controller == SETTINGS_CC:
                    if value > 0 and mode != "settings":
                        mode = "settings"
                        performance_slot = None
                        performance_scene_note = None
                        paint_settings_page(settings_values[0])
                    elif value == 0 and mode != "scene":
                        mode = "scene"
                        paint_scene_page(pads, held_modifier_cc)
                elif controller == GRID_FX_CC:
                    if value > 0:
                        if mode == "gridfx":
                            mode = "scene"
                            paint_scene_page(pads, held_modifier_cc)
                        else:
                            mode = "gridfx"
                            performance_slot = None
                            performance_scene_note = None
                            grid_fx_pressed.clear()
                            sync_grid_fx_status(grid_fx_active, grid_fx_locked)
                            ensure_grid_fx_scene_selection(pads, grid_fx_scenes)
                            paint_grid_fx_page(grid_fx_active, pads, grid_fx_scenes, grid_fx_locked)
                elif controller == GRANULATOR_CC:
                    if value > 0:
                        if mode == "granulator":
                            mode = "scene"
                            paint_scene_page(pads, held_modifier_cc)
                        else:
                            mode = "granulator"
                            performance_slot = None
                            performance_scene_note = None
                            # Auto-route every currently-active scene through
                            # the granulator unless the user has already made a
                            # specific row-1 selection; CC 28 alone is then
                            # enough to make the effect audible.
                            ensure_granulator_scene_selection(pads, granulator_scenes)
                            paint_granulator_page(granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
                elif controller == GRAN_ACTIVE_CC:
                    # CC 28 is the master on/off, but it only reacts while the
                    # granulator page is open -- elsewhere it is ignored.
                    if value > 0 and mode == "granulator":
                        granulator_active = not granulator_active
                        send_granulator_active_osc(granulator_active)
                        paint_granulator_page(granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
                elif controller == FREEZE_CC:
                    # CC 38 is the real freeze. Page-scoped, same as CC 28.
                    if value > 0 and mode == "granulator":
                        granulator_freeze = not granulator_freeze
                        send_granulator_freeze_osc(granulator_freeze)
                        paint_granulator_page(granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
                continue

            note = data
            if mode == "performance":
                if kind == "on" and performance_slot is not None:
                    if handle_performance_note(note, pads, performance_slot):
                        performance_interacted = True
                    continue
                if kind == "off" and performance_scene_note == note:
                    pad = pads.get(note)
                    if pad is not None and pad.pressed_at is not None:
                        held_for = time.monotonic() - pad.pressed_at
                        if not performance_interacted and held_for < LONG_PRESS_SECONDS:
                            handle_release(pad, held_modifier_cc, osc_sock, pads, tuning_values[2])
                        else:
                            pad.pressed_at = None
                    mode = "scene"
                    performance_slot = None
                    performance_scene_note = None
                    performance_interacted = False
                    paint_scene_page(pads, held_modifier_cc)
                continue

            if mode == "reverb":
                if kind == "on":
                    handle_reverb_note(note, reverb_values)
                continue
            if mode == "master":
                if kind == "on":
                    handle_master_note(note, master_values)
                continue
            if mode == "tuning":
                if kind == "on":
                    handle_tuning_note(note, tuning_values)
                continue
            if mode == "session":
                session_pad = session_pads.get(note)
                if session_pad is None:
                    continue
                if kind == "on":
                    session_pad.pressed_at = time.monotonic()
                else:
                    handle_session_release(
                        session_pad,
                        session_index,
                        pads,
                        reverb_values,
                        master_values,
                        tuning_values,
                        settings_values,
                    )
                continue

            if mode == "gridfx":
                if kind == "on":
                    grid_fx_pressed[note] = time.monotonic()
                else:
                    pressed_at = grid_fx_pressed.pop(note, None)
                    handle_grid_fx_release(note, pressed_at, grid_fx_active, pads, grid_fx_scenes, grid_fx_locked)
                continue
            if mode == "granulator":
                if kind == "on":
                    # CC 28 (active) and CC 38 (freeze) are matrix pads on the
                    # Launchpad Mini Mk3, so they arrive here as Note On rather
                    # than as MIDI CCs. Handle the toggles inline since we
                    # have direct access to the local bool state.
                    if note == GRAN_ACTIVE_CC:
                        granulator_active = not granulator_active
                        send_granulator_active_osc(granulator_active)
                        paint_granulator_page(granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
                    elif note == FREEZE_CC:
                        granulator_freeze = not granulator_freeze
                        send_granulator_freeze_osc(granulator_freeze)
                        paint_granulator_page(granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
                    else:
                        handle_granulator_note(note, granulator_params, pads, granulator_scenes, granulator_freeze, granulator_active)
                continue
            if mode == "settings":
                if kind == "on":
                    handle_settings_note(note, settings_values)
                continue

            pad = pads.get(note)
            if pad is None:
                continue
            if kind == "on":
                pad.pressed_at = time.monotonic()
                pad.generation_sent = False
                pad.modifier_latch = active_modifier_index(held_modifier_cc)
            else:
                handle_release(pad, held_modifier_cc, osc_sock, pads, tuning_values[2])

        time.sleep(1.0)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        print(f"eap-launchpad: {exc}", file=sys.stderr)
        raise
