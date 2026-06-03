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
SESSION_CC = 98
MASTER_CC = 89
PERCUSSIVE_CC = 19
DRONE_CC = 29
HARMONIC_CC = 39
CHAOS_CC = 49
MODIFIER_CCS = (PERCUSSIVE_CC, DRONE_CC, HARMONIC_CC, CHAOS_CC)
LONG_PRESS_SECONDS = float(os.environ.get("EAP_LONG_PRESS_SECONDS", "0.65"))
MIDI_IN = os.environ.get("EAP_LAUNCHPAD_IN", "")
MIDI_OUT = os.environ.get("EAP_LAUNCHPAD_OUT", "")
OSC_HOST = os.environ.get("EAP_OSC_HOST", "127.0.0.1")
OSC_PORT = int(os.environ.get("EAP_OSC_PORT", "57120"))
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

ROOT_NOTES = [0, 2, 4, 5, 7, 9, 11]

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
    volume: int = 100
    pan: int = 64
    density: int = 100
    timbre_motion: int = 0
    reverb_send: int = 64


@dataclass
class SessionPad:
    note: int
    pressed_at: float | None = None


def osc_string(value: str) -> bytes:
    data = value.encode("utf-8") + b"\0"
    return data + (b"\0" * ((4 - (len(data) % 4)) % 4))


def send_slot_osc(slot: int, action: int, modifier: int = 0) -> None:
    packet = osc_string("/eap/slot") + osc_string(",iii")
    packet += struct.pack(">iii", int(slot), int(action), int(modifier))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(packet, (OSC_HOST, OSC_PORT))


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


def handle_release(pad: Pad, held_modifier_cc: int | None) -> None:
    if pad.pressed_at is None:
        return

    held_for = time.monotonic() - pad.pressed_at
    pad.pressed_at = None
    modifier = active_modifier_index(held_modifier_cc)

    if held_for >= LONG_PRESS_SECONDS:
        if modifier == 0:
            flash_modifier_required(pad)
            return
        send_slot_osc(slot_for_note(pad.note), 1, modifier)
        pad.state = STATE_ACTIVE
    elif pad.state == STATE_BLANK:
        if modifier == 0:
            flash_modifier_required(pad)
            return
        send_slot_osc(slot_for_note(pad.note), 0, modifier)
        pad.state = STATE_ACTIVE
    elif pad.state == STATE_ACTIVE:
        send_slot_osc(slot_for_note(pad.note), 0, modifier)
        pad.state = STATE_MUTED
    else:
        send_slot_osc(slot_for_note(pad.note), 0, modifier)
        pad.state = STATE_ACTIVE

    paint(pad)


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


def paint_scene_page(pads: dict[int, Pad], held_modifier_cc: int | None = None) -> None:
    for note in MATRIX_NOTES:
        send_led(note, (0, 0, 0))
    for pad in pads.values():
        paint(pad)
    paint_modifier_leds(held_modifier_cc)


def col_for_value(value: int) -> int:
    return 1 + round((max(0, min(value, 127)) / 127) * 7)


def value_for_col(col: int) -> int:
    return round(((col - 1) / 7) * 127)


def paint_performance_page(pads: dict[int, Pad], selected_slot: int) -> None:
    selected_note = BOTTOM_ROW_NOTES[selected_slot - 1]
    pad = pads[selected_note]
    volume_col = col_for_value(pad.volume)
    pan_col = col_for_value(pad.pan)
    density_col = col_for_value(pad.density)
    timbre_col = col_for_value(pad.timbre_motion)
    reverb_send_col = col_for_value(pad.reverb_send)
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


def paint_tuning_page(scale_index: int, root_index: int) -> None:
    for note in MATRIX_NOTES:
        position = matrix_position(note)
        if position is None:
            continue
        row, col = position
        if row == 8:
            colour = RGB_TUNING_SELECTED if (col - 1) == scale_index else RGB_TUNING_VALUE
        elif row == 7 and col <= 7:
            colour = RGB_TUNING_SELECTED if (col - 1) == root_index else RGB_TUNING_DIM
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
    else:
        return
    send_tuning_osc(tuning_values[0], ROOT_NOTES[tuning_values[1]])
    paint_tuning_page(tuning_values[0], tuning_values[1])


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
) -> dict:
    return {
        "saved_at": time.time(),
        "pads": [pads[note].state for note in BOTTOM_ROW_NOTES],
        "scene_volume": [pads[note].volume for note in BOTTOM_ROW_NOTES],
        "scene_pan": [pads[note].pan for note in BOTTOM_ROW_NOTES],
        "scene_density": [pads[note].density for note in BOTTOM_ROW_NOTES],
        "scene_timbre_motion": [pads[note].timbre_motion for note in BOTTOM_ROW_NOTES],
        "scene_reverb_send": [pads[note].reverb_send for note in BOTTOM_ROW_NOTES],
        "reverb": list(reverb_values),
        "master": list(master_values),
        "tuning": list(tuning_values),
    }


def restore_session_snapshot(
    data: dict,
    pads: dict[int, Pad],
    reverb_values: list[int],
    master_values: list[int],
    tuning_values: list[int],
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
    for target, source in (
        (reverb_values, data.get("reverb", [])),
        (master_values, data.get("master", [])),
        (tuning_values, data.get("tuning", [])),
    ):
        for index, value in enumerate(source[: len(target)]):
            if isinstance(value, int):
                limit = 7 if target is tuning_values and index == 0 else 6 if target is tuning_values else 127
                target[index] = max(0, min(value, limit))


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
        slots[key] = session_snapshot(pads, reverb_values, master_values, tuning_values)
        session_index["active_slot"] = slot
        save_session_index(session_index)
        paint_session_page(session_index)
    elif key in slots:
        send_session_osc(slot, 0)
        restore_session_snapshot(slots[key], pads, reverb_values, master_values, tuning_values)
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
    tuning_values = [0, 0]
    mode = "scene"
    held_modifier_cc: int | None = None
    performance_slot: int | None = None
    performance_scene_note: int | None = None
    performance_interacted = False
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
        while proc.poll() is None:
            if mode == "scene" and active_modifier_index(held_modifier_cc) == 0:
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
                        paint_tuning_page(tuning_values[0], tuning_values[1])
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
                        pad.pressed_at = None
                        if not performance_interacted and held_for < LONG_PRESS_SECONDS:
                            send_slot_osc(slot_for_note(pad.note), 0, 0)
                            pad.state = STATE_MUTED if pad.state == STATE_ACTIVE else STATE_ACTIVE
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
                    )
                continue

            pad = pads.get(note)
            if pad is None:
                continue
            if kind == "on":
                pad.pressed_at = time.monotonic()
            else:
                handle_release(pad, held_modifier_cc)

        time.sleep(1.0)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as exc:
        print(f"eap-launchpad: {exc}", file=sys.stderr)
        raise
