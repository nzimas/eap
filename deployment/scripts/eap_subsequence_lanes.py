"""Generative lane patterns for EAP using Subsequence's PatternBuilder API."""

from __future__ import annotations

import logging
import random
from typing import Any, Callable, Dict, List, Optional, Tuple

import subsequence.constants
import subsequence.constants.durations as dur
import subsequence.sequence_utils as su

LOG = logging.getLogger(__name__)

Modifier = str
Profile = str
LaneCfg = Dict[str, Any]

SCALE_STEPS = {
    "percussive": [-2, -1, 0, 0, 0, 0, 1, 1, 2],
    "drone": [0, 0, 0, 0, 1, 1, 2, -1],
    "harmonic": [-2, -1, 0, 0, 0, 1, 1, 2, 3, 4],
    "chaos": [-4, -3, -2, -1, 0, 1, 2, 3, 4, 5],
}

MODIFIER_TIMING: Dict[str, Tuple[int, float]] = {
    "percussive": (16, dur.SIXTEENTH),
    "chaos": (16, dur.SIXTEENTH),
    "harmonic": (16, dur.EIGHTH),
    "drone": (8, dur.HALF),
}

MODIFIER_BARS = {
    "percussive": 1,
    "chaos": 1,
    "harmonic": 2,
    "drone": 4,
}


def default_lane_cfg(slot: int) -> LaneCfg:
    return {
        "slot": slot,
        "active": False,
        "modifier": "harmonic",
        "profile": "euclid",
        "pulse": 0.12,
        "density": 1.0,
        "materials": 1,
        "material": "rings",
        "rest_prob": 0.12,
        "swing": 0.0,
        "seed": slot * 9973,
        "scale_index": 1,
        "root_note": 0,
        "scale_size": 7,
        "scale_steps": [],
        "engine": "none",
    }


def init_lane_data(composition: Any) -> None:
    composition.data.setdefault("lanes", {})
    composition.data.setdefault("tuning", {"scale_index": 1, "root_note": 0, "scale_size": 7, "scale_steps": []})
    composition.data.setdefault("engine", "none")
    for slot in range(1, 9):
        composition.data["lanes"][str(slot)] = default_lane_cfg(slot)


def update_lane_config(composition: Any, slot: int, cfg: LaneCfg) -> None:
    merged = default_lane_cfg(slot)
    merged.update(cfg)
    merged["slot"] = slot
    composition.data["lanes"][str(slot)] = merged


def update_tuning(composition: Any, scale_index: int, root_note: int, scale_steps: List[int]) -> None:
    composition.data["tuning"] = {
        "scale_index": scale_index,
        "root_note": root_note,
        "scale_size": len(scale_steps),
        "scale_steps": list(scale_steps),
    }


def update_engine(composition: Any, engine: str) -> None:
    composition.data["engine"] = engine or "none"


def _effective_cfg(cfg: LaneCfg, composition: Any) -> LaneCfg:
    tuning = composition.data.get("tuning", {})
    merged = dict(cfg)
    merged["scale_index"] = cfg.get("scale_index", tuning.get("scale_index", 1))
    merged["root_note"] = cfg.get("root_note", tuning.get("root_note", 0))
    merged["scale_size"] = cfg.get("scale_size", tuning.get("scale_size", 7))
    merged["scale_steps"] = cfg.get("scale_steps") or tuning.get("scale_steps") or []
    merged["engine"] = cfg.get("engine") or composition.data.get("engine", "none")
    return merged


def _degree_pool(cfg: LaneCfg, composition: Any) -> List[int]:
    modifier = cfg.get("modifier", "harmonic")
    eff = _effective_cfg(cfg, composition)
    scale_size = max(3, int(eff.get("scale_size", 7)))
    base = SCALE_STEPS.get(modifier, SCALE_STEPS["harmonic"])
    if modifier == "drone":
        fifth = min(4, scale_size - 1)
        return [0, 0, 0, 0, 1, 1, fifth, -1, 0]
    if scale_size <= 5:
        return [step for step in base if abs(step) <= 2] or [0, 0, 1, -1]
    if scale_size >= 10:
        return base
    return [step for step in base if abs(step) <= 3] or base


def _drone_degree(composition: Any, slot: int, cfg: LaneCfg, rng: random.Random, drift: bool = True) -> int:
    key = f"lane{slot}_degree"
    pool = _degree_pool(cfg, composition)
    prev = composition.data.get(key, 0)
    if not drift or rng.random() < 0.35:
        degree = rng.choice(pool)
    else:
        degree = prev + rng.choice([-1, 0, 0, 1])
        if degree not in pool:
            degree = min(pool, key=lambda value: abs(value - degree))
    composition.data[key] = degree
    return degree


def _scale_step(
    cfg: LaneCfg,
    composition: Any,
    slot: int,
    rng: random.Random,
    *,
    walk: bool = False,
) -> int:
    override = cfg.get("_scale_override")
    if override is not None:
        return int(override)
    if walk:
        return _drone_degree(composition, slot, cfg, rng, drift=True)
    return rng.choice(_degree_pool(cfg, composition))


def _pulse_to_beats(pulse_sec: float, bpm: float) -> float:
    return max(0.03, pulse_sec * bpm / 60.0)


def _configure_pattern_for_modifier(p: Any, cfg: LaneCfg) -> int:
    modifier = cfg.get("modifier", "harmonic")
    steps, step_duration = MODIFIER_TIMING.get(modifier, MODIFIER_TIMING["harmonic"])
    p._default_grid = steps
    p._pattern.length = steps * step_duration
    return steps


def _drone_event_budget(cfg: LaneCfg) -> int:
    material = str(cfg.get("material", "rings"))
    if material in {"rings", "passersby", "molly", "fm7"}:
        return 2
    if material in {"vital", "vcv", "dexed"}:
        return 2
    return 2


def _select_drone_steps(values: List[float], grid: int, budget: int, rng: random.Random) -> List[int]:
    if grid <= 0:
        return [0]
    ranked = sorted(range(grid), key=lambda idx: values[idx], reverse=True)
    count = max(1, min(budget, grid))
    chosen = ranked[:count]
    if not chosen:
        chosen = [rng.randrange(grid)]
    return sorted(set(chosen))


def _chaos_scale_step(cfg: LaneCfg, composition: Any, slot: int, rng: random.Random) -> int:
    pool = _degree_pool(cfg, composition)
    key = f"lane{slot}_chaos_degree"
    prev = composition.data.get(key, rng.choice(pool))
    if rng.random() < 0.62:
        step = prev + rng.choice([-7, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 7])
    else:
        step = rng.choice(pool)
    if step not in pool:
        step = min(pool, key=lambda value: abs(value - step))
    composition.data[key] = step
    return step


def _emit_hit(
    p: Any,
    slot: int,
    pulse: int,
    cfg: LaneCfg,
    composition: Any,
    rng: random.Random,
    accent_scale: float = 1.0,
    *,
    decay_scale: Optional[float] = None,
    sustain: int = 0,
    skip_density: bool = False,
) -> None:
    modifier = cfg.get("modifier", "harmonic")
    density = float(cfg.get("density", 1.0))
    rest_prob = float(cfg.get("rest_prob", 0.12))

    if not skip_density and rng.random() > density:
        return
    if not skip_density and rng.random() < rest_prob:
        return

    accent = accent_scale * rng.uniform(0.72, 1.55)
    scale_step = _scale_step(cfg, composition, slot, rng, walk=(modifier == "drone"))
    pan_bias = rng.uniform(-0.45, 0.45)
    if decay_scale is None:
        decay_scale = {
            "percussive": rng.uniform(0.55, 1.45),
            "drone": rng.uniform(2.8, 7.5),
            "chaos": rng.uniform(0.015, 2.8),
        }.get(modifier, rng.uniform(0.7, 1.25))

    if modifier == "percussive":
        accent = max(0.45, min(1.85, accent))
        pan_bias *= 0.72

    beat = pulse / subsequence.constants.MIDI_QUARTER_NOTE
    if modifier == "chaos":
        scale_step = _chaos_scale_step(cfg, composition, slot, rng)
        pan_bias = rng.uniform(-0.95, 0.95)
        accent = accent_scale * rng.uniform(0.08, 3.0)
        if rng.random() < rest_prob * 1.35:
            return
        step_beats = p._pattern.length / max(1, p.grid)
        beat += rng.uniform(-0.52, 0.52) * step_beats
        beat = max(0.0, min(p._pattern.length - 0.001, beat))

    p.osc(
        "/eap/seq/event",
        slot,
        accent,
        scale_step,
        1,
        pan_bias,
        decay_scale,
        0,  # reserved (is_rest) — keep this slot so sustain stays at OSC index 8
        sustain,
        beat=beat,
    )


def _emit_drone_hit(
    p: Any,
    slot: int,
    pulse: int,
    cfg: LaneCfg,
    composition: Any,
    rng: random.Random,
    accent_scale: float = 1.0,
    *,
    decay_scale: Optional[float] = None,
) -> None:
    _emit_hit(
        p,
        slot,
        pulse,
        cfg,
        composition,
        rng,
        accent_scale,
        decay_scale=decay_scale or rng.uniform(3.0, 8.0),
        sustain=1,
        skip_density=True,
    )


def _step_pulse(p: Any, step_index: int) -> int:
    step_beats = p._pattern.length / max(1, p.grid)
    beat = step_index * step_beats
    return int(beat * subsequence.constants.MIDI_QUARTER_NOTE)


def _rotate(values: List[int], offset: int) -> List[int]:
    if not values:
        return values
    return su.roll(values, offset, len(values))


def _grid_hits(p: Any, cfg: LaneCfg, composition: Any, rng: random.Random, pulses: int) -> None:
    slot = int(cfg["slot"])
    steps = p.grid
    hits = max(2, min(steps - 1, pulses))
    grid = su.generate_euclidean_sequence(steps, hits)
    for step, hit in enumerate(grid):
        if hit:
            _emit_hit(p, slot, _step_pulse(p, step), cfg, composition, rng)


def _emit_at_step(
    p: Any,
    slot: int,
    cfg: LaneCfg,
    composition: Any,
    rng: random.Random,
    step: int,
    accent_scale: float = 1.0,
    **kwargs: Any,
) -> None:
    _emit_hit(p, slot, _step_pulse(p, step % max(1, p.grid)), cfg, composition, rng, accent_scale, **kwargs)


def _percussive_decay(rng: random.Random, family: str) -> float:
    return {
        "groove": lambda: rng.uniform(0.72, 1.55),
        "clave": lambda: rng.uniform(0.62, 1.20),
        "ghost": lambda: rng.uniform(0.45, 0.88),
        "metal": lambda: rng.uniform(0.85, 1.85),
        "wood": lambda: rng.uniform(0.55, 1.05),
        "fill": lambda: rng.uniform(0.40, 0.95),
        "space": lambda: rng.uniform(1.05, 2.10),
    }.get(family, lambda: rng.uniform(0.58, 1.35))()


def _emit_percussive_step(
    p: Any,
    slot: int,
    cfg: LaneCfg,
    composition: Any,
    rng: random.Random,
    step: int,
    accent_scale: float = 1.0,
    family: str = "groove",
) -> None:
    _emit_at_step(
        p,
        slot,
        cfg,
        composition,
        rng,
        step,
        accent_scale,
        decay_scale=_percussive_decay(rng, family),
    )


def _emit_binary_grid(
    p: Any,
    slot: int,
    cfg: LaneCfg,
    composition: Any,
    rng: random.Random,
    grid: List[int],
    accent_fn: Optional[Callable[[int], float]] = None,
) -> None:
    for step, hit in enumerate(grid[: p.grid]):
        if hit:
            accent = accent_fn(step) if accent_fn else 1.0
            _emit_at_step(p, slot, cfg, composition, rng, step, accent)


def _emit_float_threshold(
    p: Any,
    slot: int,
    cfg: LaneCfg,
    composition: Any,
    rng: random.Random,
    values: List[float],
    threshold: float,
    *,
    accent_from_value: bool = False,
) -> None:
    for idx, value in enumerate(values[: p.grid]):
        if value >= threshold:
            accent = (0.72 + float(value) * 0.75) if accent_from_value else 1.0
            _emit_at_step(p, slot, cfg, composition, rng, idx, accent)


def _euclid_hits(p: Any, rng: random.Random, low: float = 0.35, high: float = 0.82) -> int:
    return max(2, min(p.grid - 1, int(p.grid * rng.uniform(low, high))))


def _fibonacci_steps(p: Any, grid: int) -> List[int]:
    times = su.fibonacci_rhythm(grid, p._pattern.length)
    step_beats = p._pattern.length / max(1, grid)
    steps: List[int] = []
    seen = set()
    for beat_time in times:
        step = int(round(beat_time / max(step_beats, 1e-9))) % grid
        if step not in seen:
            seen.add(step)
            steps.append(step)
    return sorted(steps) or [0]


def _vdc_sparse_steps(values: List[float], grid: int, rng: random.Random) -> List[int]:
    count = max(3, min(grid - 1, int(grid * rng.uniform(0.28, 0.58))))
    ranked = sorted(range(min(grid, len(values))), key=lambda idx: values[idx])
    return sorted(ranked[:count])


def _lsystem_hit_steps(expanded: str, grid: int) -> List[int]:
    hits: List[int] = []
    stride = max(1, len(expanded) // grid)
    for idx in range(grid):
        pos = min(len(expanded) - 1, idx * stride)
        if expanded[pos].upper() in {"F", "X", "1"}:
            hits.append(idx)
    return hits or [0]


def _prime_steps(up_to: int) -> List[int]:
    if up_to < 2:
        return [0]
    primes: List[int] = []
    for candidate in range(2, up_to + 1):
        if all(candidate % divisor for divisor in range(2, int(candidate**0.5) + 1)):
            primes.append(candidate)
    return primes or [2]


def _ratio_lattice_steps(grid: int, rng: random.Random) -> List[int]:
    ratio = rng.choice([(1 + 5**0.5) / 2, 3**0.5, 2**0.5, rng.uniform(1.4, 2.6)])
    position = rng.uniform(0.0, float(grid))
    steps: List[int] = []
    seen = set()
    for _ in range(grid * 2):
        position += ratio
        step = int(position) % grid
        if step not in seen:
            seen.add(step)
            steps.append(step)
        if len(steps) >= max(3, grid // 3):
            break
    return sorted(steps) or [0]


def _percussive_profile_builders() -> Dict[Profile, Callable[[Any, LaneCfg, random.Random, Any], None]]:
    def bresenham(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        hits = _euclid_hits(p, rng)
        grid = su.generate_bresenham_sequence(p.grid, hits)
        _emit_binary_grid(p, slot, cfg, composition, rng, grid)

    def bresenhamWeighted(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        weights = [rng.uniform(0.35, 2.4) for _ in range(p.grid)]
        pulses = su.generate_bresenham_sequence_weighted(p.grid, weights)
        for step in sorted({value % p.grid for value in pulses}):
            accent = 0.85 + weights[step] * 0.22
            _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "wood")

    def cellular1d(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        rule = rng.choice([30, 45, 90, 110, 150])
        generation = rng.randint(2, 7)
        seed = rng.randint(1, 255)
        grid = su.generate_cellular_automaton_1d(p.grid, rule=rule, generation=generation, seed=seed)
        _emit_binary_grid(
            p,
            slot,
            cfg,
            composition,
            rng,
            grid,
            accent_fn=lambda step: 0.9 + (step % 4) * 0.08,
        )

    def cellular2d(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        rows = max(4, p.grid // 2)
        cols = p.grid
        rule = rng.choice(["B36/S23", "B368/S245", "B4678/S35678"])
        generation = rng.randint(1, 6)
        matrix = su.generate_cellular_automaton_2d(rows, cols, rule=rule, generation=generation, seed=rng.randint(1, 999))
        row = matrix[generation % len(matrix)]
        _emit_binary_grid(p, slot, cfg, composition, rng, row)

    def deBruijn(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        order = rng.choice([3, 4, 5])
        grid = su.de_bruijn(2, order)
        if len(grid) < p.grid:
            grid = (grid * ((p.grid // len(grid)) + 1))[: p.grid]
        else:
            grid = grid[: p.grid]
        offset = rng.randint(0, max(0, len(grid) - 1))
        grid = _rotate(grid, offset)
        _emit_binary_grid(p, slot, cfg, composition, rng, grid)

    def fibonacci(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        for step in _fibonacci_steps(p, p.grid):
            accent = 1.05 if step % 2 == 0 else 0.92
            _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "clave")

    def vanDerCorput(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        base = rng.choice([2, 3, 5, 7])
        values = su.generate_van_der_corput_sequence(p.grid, base)
        for step in _vdc_sparse_steps(values, p.grid, rng):
            accent = 0.78 + values[step] * 0.55
            _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "space")

    def logistic(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        r_value = rng.uniform(3.55, 3.98)
        chaos = su.logistic_map(r=r_value, steps=p.grid)
        threshold = rng.uniform(0.46, 0.62)
        _emit_float_threshold(p, slot, cfg, composition, rng, chaos, threshold, accent_from_value=True)

    def lorenz(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        orbit = su.lorenz_attractor(
            p.grid,
            dt=rng.uniform(0.008, 0.02),
            rho=rng.uniform(24.0, 34.0),
            x0=rng.uniform(-0.4, 0.4),
        )
        xs = [point[0] for point in orbit]
        peak = max(abs(value) for value in xs) or 1.0
        norm = [abs(value) / peak for value in xs]
        threshold = rng.uniform(0.42, 0.68)
        _emit_float_threshold(p, slot, cfg, composition, rng, norm, threshold, accent_from_value=True)

    def lsystem(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        presets = [
            ("F", {"F": "F+F-F"}),
            ("F", {"F": "F-F+F+F"}),
            ("FX", {"F": "F+F", "X": "X-X"}),
        ]
        axiom, rules = rng.choice(presets)
        expanded = su.lsystem_expand(axiom, rules, rng.randint(2, 4), rng)
        for step in _lsystem_hit_steps(expanded, p.grid):
            _emit_percussive_step(p, slot, cfg, composition, rng, step, rng.uniform(0.82, 1.25), "wood")

    def perlinGate(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        noise = su.perlin_1d_sequence(0.0, 0.22, p.grid, seed=p.cycle * 11 + int(cfg["slot"]) * 17)
        threshold = rng.uniform(0.42, 0.68)
        _emit_float_threshold(p, slot, cfg, composition, rng, noise, threshold, accent_from_value=True)

    def perlin2d(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        grid = su.perlin_2d_grid(0.0, 0.0, 0.31, 0.27, p.grid, 3, seed=p.cycle + int(cfg["slot"]) * 43)
        row = grid[rng.randint(0, len(grid) - 1)]
        threshold = rng.uniform(0.35, 0.62)
        _emit_float_threshold(p, slot, cfg, composition, rng, row, threshold, accent_from_value=True)

    def pinkGate(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        noise = su.pink_noise(p.grid, seed=p.cycle * 19 + int(cfg["slot"]))
        threshold = rng.uniform(0.28, 0.52)
        _emit_float_threshold(p, slot, cfg, composition, rng, noise, threshold, accent_from_value=True)

    def probGate(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        base = su.generate_euclidean_sequence(p.grid, _euclid_hits(p, rng, 0.48, 0.88))
        gated = su.probability_gate(base, rng.uniform(0.45, 0.82), rng)
        for step, hit in enumerate(gated):
            if hit:
                accent = 1.25 if step > 0 and base[step] and not gated[step - 1] else 0.88
                _emit_at_step(p, slot, cfg, composition, rng, step, accent)

    def reactionDiff(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        field = su.reaction_diffusion_1d(
            p.grid,
            steps=rng.randint(350, 1200),
            feed_rate=rng.uniform(0.04, 0.07),
            kill_rate=rng.uniform(0.055, 0.065),
        )
        threshold = rng.uniform(0.38, 0.72)
        _emit_float_threshold(p, slot, cfg, composition, rng, field, threshold, accent_from_value=True)

    def thueMorse(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        pattern = su.thue_morse(p.grid)
        offset = rng.randint(0, max(0, p.grid - 1))
        pattern = _rotate(pattern, offset)
        _emit_binary_grid(
            p,
            slot,
            cfg,
            composition,
            rng,
            pattern,
            accent_fn=lambda step: 1.12 if step % 3 == 0 else 0.88,
        )

    def selfAvoid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        length = max(4, min(p.grid, rng.randint(5, p.grid)))
        walk = su.self_avoiding_walk(length, 0, p.grid - 1, rng)
        for step in sorted(set(walk)):
            _emit_at_step(p, slot, cfg, composition, rng, step, rng.uniform(0.9, 1.4))

    def walkHits(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        hits = _euclid_hits(p, rng, 0.4, 0.78)
        grid = su.generate_euclidean_sequence(p.grid, hits)
        indices = su.sequence_to_indices(grid)
        accents = su.random_walk(len(indices), -3, 4, 1, rng, start=0)
        for step, accent_delta in zip(indices, accents):
            accent = max(0.65, min(1.65, 1.0 + accent_delta * 0.12))
            _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "groove")

    def rotateEuclid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        hits = _euclid_hits(p, rng)
        grid = su.generate_euclidean_sequence(p.grid, hits)
        indices = su.sequence_to_indices(grid)
        rolled = su.roll(indices, rng.randint(0, max(0, p.grid - 1)), p.grid)
        for step in rolled:
            _emit_percussive_step(p, slot, cfg, composition, rng, step, 1.08 if step % 4 == 0 else 0.92, "groove")

    def layeredEuclid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        hits_a = max(2, int(p.grid * rng.uniform(0.28, 0.52)))
        hits_b = max(2, int(p.grid * rng.uniform(0.22, 0.46)))
        grid_a = su.generate_euclidean_sequence(p.grid, hits_a)
        grid_b = su.generate_euclidean_sequence(p.grid, hits_b)
        merged = [a or b for a, b in zip(grid_a, grid_b)]
        _emit_binary_grid(
            p,
            slot,
            cfg,
            composition,
            rng,
            merged,
            accent_fn=lambda step: 1.25 if grid_a[step] and grid_b[step] else 0.92,
        )

    def nestedEuclid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        half = max(2, p.grid // 2)
        inner_hits = max(2, int(half * rng.uniform(0.35, 0.72)))
        inner = su.generate_euclidean_sequence(half, inner_hits)
        for idx, hit in enumerate(inner):
            if not hit:
                continue
            primary = idx * 2
            _emit_percussive_step(p, slot, cfg, composition, rng, primary, 1.15, "wood")
            if rng.random() < 0.42:
                _emit_percussive_step(p, slot, cfg, composition, rng, primary + 1, 0.62, "ghost")

    def xorEuclid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        hits_a = _euclid_hits(p, rng, 0.32, 0.58)
        hits_b = _euclid_hits(p, rng, 0.28, 0.52)
        grid_a = su.generate_euclidean_sequence(p.grid, hits_a)
        grid_b = su.generate_euclidean_sequence(p.grid, hits_b)
        merged = [a ^ b for a, b in zip(grid_a, grid_b)]
        _emit_binary_grid(
            p,
            slot,
            cfg,
            composition,
            rng,
            merged,
            accent_fn=lambda step: 1.2 if grid_a[step] and grid_b[step] else 0.86,
        )

    def moduloLattice(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        modulus = rng.choice([5, 7, 9, 11, 13])
        stride = rng.choice([2, 3, 5, 7])
        offset = rng.randint(0, modulus - 1)
        grid = [1 if (step * stride + offset) % modulus == 0 else 0 for step in range(p.grid)]
        _emit_binary_grid(p, slot, cfg, composition, rng, grid)

    def primeLattice(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        invert = rng.random() < 0.35
        primes = set(_prime_steps(p.grid - 1))
        for step in range(p.grid):
            is_prime = step in primes
            if is_prime ^ invert:
                accent = 1.12 if is_prime else 0.84
                _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "metal" if is_prime else "ghost")

    def interference(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        cycle_a = rng.choice([3, 5, 7, 11])
        cycle_b = rng.choice([4, 6, 8, 9])
        seq_a = su.generate_euclidean_sequence(cycle_a, max(1, cycle_a // 2 + rng.randint(-1, 1)))
        seq_b = su.generate_euclidean_sequence(cycle_b, max(1, cycle_b // 2 + rng.randint(-1, 1)))
        for step in range(p.grid):
            hit_a = seq_a[step % cycle_a]
            hit_b = seq_b[step % cycle_b]
            if hit_a and hit_b:
                _emit_percussive_step(p, slot, cfg, composition, rng, step, 1.28, "metal")
            elif hit_a or hit_b:
                _emit_percussive_step(p, slot, cfg, composition, rng, step, 0.78 if rng.random() < 0.55 else 0.92, "ghost")

    def densityWave(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        base = su.generate_euclidean_sequence(p.grid, _euclid_hits(p, rng, 0.55, 0.9))
        envelope = su.perlin_1d_sequence(0.0, 0.26, p.grid, seed=p.cycle * 23 + int(cfg["slot"]) * 29)
        threshold = rng.uniform(0.34, 0.62)
        for step, hit in enumerate(base):
            if hit and envelope[step] >= threshold:
                accent = 0.72 + envelope[step] * 0.85
                _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "space")

    def fracture(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        hits = _euclid_hits(p, rng, 0.42, 0.78)
        euclid = su.generate_euclidean_sequence(p.grid, hits)
        morse = su.thue_morse(p.grid)
        merged = [a ^ b for a, b in zip(euclid, morse)]
        _emit_binary_grid(
            p,
            slot,
            cfg,
            composition,
            rng,
            merged,
            accent_fn=lambda step: 1.18 if euclid[step] and not morse[step] else 0.84,
        )

    def clusterCompress(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        anchor = max(2, int(p.grid * rng.uniform(0.45, 0.72)))
        grid = su.generate_euclidean_sequence(p.grid, max(2, int(p.grid * 0.35)))
        for step, hit in enumerate(grid):
            if hit and step < anchor:
                _emit_percussive_step(p, slot, cfg, composition, rng, step, 1.05, "groove")
        tail = _fibonacci_steps(p, max(4, p.grid - anchor))[-max(3, p.grid // 4) :]
        for offset, _step in enumerate(tail):
            mapped = min(p.grid - 1, anchor + offset)
            accent = 0.95 + offset * 0.08
            _emit_percussive_step(p, slot, cfg, composition, rng, mapped, accent, "fill")

    def caXorEuclid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        rule = rng.choice([30, 90, 110])
        ca = su.generate_cellular_automaton_1d(p.grid, rule=rule, generation=rng.randint(2, 6), seed=rng.randint(1, 255))
        hits = _euclid_hits(p, rng, 0.35, 0.65)
        euclid = su.generate_euclidean_sequence(p.grid, hits)
        merged = [a & b for a, b in zip(ca, euclid)]
        _emit_binary_grid(p, slot, cfg, composition, rng, merged)

    def phaseDrift(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        hits = _euclid_hits(p, rng)
        grid = su.generate_euclidean_sequence(p.grid, hits)
        shift = (p.cycle * rng.randint(1, 5) + int(cfg["slot"])) % max(1, p.grid)
        drifted = _rotate(grid, shift)
        _emit_binary_grid(p, slot, cfg, composition, rng, drifted)

    def ghostGrid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        dense = su.generate_euclidean_sequence(p.grid, _euclid_hits(p, rng, 0.62, 0.92))
        gated = su.probability_gate(dense, rng.uniform(0.35, 0.62), rng)
        for step, hit in enumerate(gated):
            if hit:
                accent = 0.62 if dense[step] and rng.random() < 0.45 else 1.15
                _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "ghost" if accent < 0.8 else "groove")

    def weightedHits(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        options = [(step, rng.uniform(0.2, 2.8)) for step in range(p.grid)]
        count = max(3, int(p.grid * rng.uniform(0.24, 0.52)))
        picks = [su.weighted_choice(options, rng) for _ in range(count)]
        weight_by_step = {step: weight for step, weight in options}
        for step in sorted(set(picks)):
            accent = 0.82 + weight_by_step[step] * 0.25
            _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, "wood")

    return {
        "bresenham": bresenham,
        "bresenhamWeighted": bresenhamWeighted,
        "cellular1d": cellular1d,
        "cellular2d": cellular2d,
        "deBruijn": deBruijn,
        "fibonacci": fibonacci,
        "vanDerCorput": vanDerCorput,
        "logistic": logistic,
        "lorenz": lorenz,
        "lsystem": lsystem,
        "perlinGate": perlinGate,
        "perlin2d": perlin2d,
        "pinkGate": pinkGate,
        "probGate": probGate,
        "reactionDiff": reactionDiff,
        "thueMorse": thueMorse,
        "selfAvoid": selfAvoid,
        "walkHits": walkHits,
        "rotateEuclid": rotateEuclid,
        "layeredEuclid": layeredEuclid,
        "nestedEuclid": nestedEuclid,
        "xorEuclid": xorEuclid,
        "moduloLattice": moduloLattice,
        "primeLattice": primeLattice,
        "interference": interference,
        "densityWave": densityWave,
        "fracture": fracture,
        "clusterCompress": clusterCompress,
        "caXorEuclid": caXorEuclid,
        "phaseDrift": phaseDrift,
        "ghostGrid": ghostGrid,
        "weightedHits": weightedHits,
    }


def _chaos_profile_builders() -> Dict[Profile, Callable[[Any, LaneCfg, random.Random, Any], None]]:
    def _chaos_pulse(p: Any, step: float, rng: random.Random) -> int:
        step_beats = p._pattern.length / max(1, p.grid)
        jitter = rng.uniform(-0.55, 0.55) * step_beats
        beat = step * step_beats + jitter
        beat = max(0.0, min(p._pattern.length - 0.001, beat))
        return int(beat * subsequence.constants.MIDI_QUARTER_NOTE)

    def stutter(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        r_value = rng.uniform(3.65, 3.99)
        chaos = su.logistic_map(r=r_value, steps=p.grid * 2)
        threshold = rng.uniform(0.38, 0.68)
        for idx, value in enumerate(chaos[: p.grid]):
            if value > threshold:
                pulse = _chaos_pulse(p, idx * rng.uniform(0.18, 0.72), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    rng.uniform(0.35, 2.4),
                    decay_scale=rng.uniform(0.012, 1.6),
                )

    def wander(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        pink = su.pink_noise(p.grid, seed=p.cycle * 17 + slot)
        drift = su.perlin_1d_sequence(0.0, 0.24, p.grid, seed=p.cycle * 29 + slot * 13)
        threshold = rng.uniform(0.22, 0.58)
        for idx in range(p.grid):
            field = (pink[idx] * 0.55) + (drift[idx] * 0.45)
            if field >= threshold:
                pulse = _chaos_pulse(p, idx * rng.uniform(0.35, 2.4), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    0.45 + field * 1.8,
                    decay_scale=rng.uniform(0.02, 2.2),
                )

    def flare(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        field = su.reaction_diffusion_1d(
            p.grid,
            steps=rng.randint(400, 1400),
            feed_rate=rng.uniform(0.035, 0.075),
            kill_rate=rng.uniform(0.052, 0.068),
        )
        threshold = rng.uniform(0.32, 0.78)
        for idx, value in enumerate(field):
            if value >= threshold:
                pulse = _chaos_pulse(p, idx + rng.uniform(-0.35, 0.35), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    0.5 + value * 2.2,
                    decay_scale=rng.uniform(0.015, 2.5),
                )

    def glitch(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        morse = su.thue_morse(p.grid)
        morse = _rotate(morse, rng.randint(0, max(0, p.grid - 1)))
        for idx, hit in enumerate(morse[: p.grid]):
            if hit and rng.random() < rng.uniform(0.42, 0.88):
                pulse = _chaos_pulse(p, idx * rng.choice([0.25, 0.5, 0.75, 1.0, 1.33, 1.66, 2.0]), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    rng.uniform(0.6, 2.8),
                    decay_scale=rng.uniform(0.01, 1.2),
                )

    def grainCloud(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        grains = rng.randint(3, max(4, p.grid))
        base = rng.choice([2, 3, 5, 7])
        times = su.generate_van_der_corput_sequence(grains, base)
        for value in times:
            pulse = _chaos_pulse(p, value * p.grid, rng)
            _emit_hit(
                p,
                slot,
                pulse,
                cfg,
                composition,
                rng,
                rng.uniform(0.15, 2.6),
                decay_scale=rng.uniform(0.008, 0.85),
            )

    def lorenzSpray(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        orbit = su.lorenz_attractor(
            p.grid * 2,
            dt=rng.uniform(0.006, 0.022),
            rho=rng.uniform(20.0, 38.0),
            x0=rng.uniform(-0.8, 0.8),
        )
        xs = [abs(point[0]) for point in orbit[: p.grid]]
        peak = max(xs) or 1.0
        norm = [value / peak for value in xs]
        threshold = rng.uniform(0.35, 0.72)
        for idx, value in enumerate(norm):
            if value >= threshold and rng.random() < 0.82:
                pulse = _chaos_pulse(p, idx + rng.uniform(-0.4, 0.4), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    0.4 + value * 2.0,
                    decay_scale=rng.uniform(0.02, 2.0),
                )

    def poissonField(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        density = rng.uniform(0.08, 0.42)
        for idx in range(p.grid):
            if rng.random() < density:
                pulse = _chaos_pulse(p, idx, rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    rng.uniform(0.2, 2.2),
                    decay_scale=rng.uniform(0.01, 1.8),
                )

    def vdcScatter(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        values = su.generate_van_der_corput_sequence(p.grid, rng.choice([2, 3, 5, 7, 11]))
        ranked = sorted(range(p.grid), key=lambda idx: values[idx])
        count = rng.randint(2, max(3, int(p.grid * rng.uniform(0.18, 0.55))))
        for idx in ranked[:count]:
            if rng.random() < rng.uniform(0.55, 0.95):
                pulse = _chaos_pulse(p, idx + values[idx] * 0.75, rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    0.35 + values[idx] * 1.8,
                    decay_scale=rng.uniform(0.015, 2.4),
                )

    def microCluster(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        clusters = rng.randint(1, max(2, p.grid // 5))
        for _ in range(clusters):
            center = rng.randrange(p.grid)
            width = rng.randint(2, max(3, p.grid // 3))
            for offset in range(width):
                if rng.random() < rng.uniform(0.45, 0.92):
                    step = (center + offset) % p.grid
                    pulse = _chaos_pulse(p, step, rng)
                    _emit_hit(
                        p,
                        slot,
                        pulse,
                        cfg,
                        composition,
                        rng,
                        rng.uniform(0.5, 2.5),
                        decay_scale=rng.uniform(0.008, 0.75),
                    )

    def caSnapshot(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        rule = rng.choice([30, 45, 90, 110, 150])
        grid = su.generate_cellular_automaton_1d(
            p.grid,
            rule=rule,
            generation=rng.randint(3, 9),
            seed=rng.randint(1, 255),
        )
        gated = su.probability_gate(grid, rng.uniform(0.35, 0.75), rng)
        for idx, hit in enumerate(gated):
            if hit:
                pulse = _chaos_pulse(p, idx + rng.uniform(-0.25, 0.25), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    rng.uniform(0.4, 2.2),
                    decay_scale=rng.uniform(0.012, 1.5),
                )

    def deBruijnGlitch(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        order = rng.choice([3, 4, 5])
        stream = su.de_bruijn(2, order)
        stream = (stream * ((p.grid // len(stream)) + 2))[: p.grid]
        stream = _rotate(stream, rng.randint(0, max(0, p.grid - 1)))
        for idx, hit in enumerate(stream):
            if hit and rng.random() < rng.uniform(0.38, 0.82):
                pulse = _chaos_pulse(p, idx * rng.uniform(0.4, 1.6), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    rng.uniform(0.55, 2.4),
                    decay_scale=rng.uniform(0.01, 1.1),
                )

    def logisticSwarm(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        layers = [
            su.logistic_map(r=rng.uniform(3.6, 3.98), steps=p.grid)
            for _ in range(rng.randint(2, 4))
        ]
        for idx in range(p.grid):
            strength = sum(1 for layer in layers if layer[idx] > rng.uniform(0.42, 0.66))
            if strength >= rng.randint(1, 2):
                pulse = _chaos_pulse(p, idx * rng.uniform(0.25, 1.2), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    0.35 + strength * 0.75,
                    decay_scale=rng.uniform(0.015, 1.8),
                )

    def spectralDrift(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        steps = max(3, int(p.grid * rng.uniform(0.25, 0.65)))
        walk = su.random_walk(steps, 0, p.grid - 1, rng.randint(1, 4), rng, start=rng.randrange(p.grid))
        for step in walk:
            pulse = _chaos_pulse(p, step, rng)
            _emit_hit(
                p,
                slot,
                pulse,
                cfg,
                composition,
                rng,
                rng.uniform(0.35, 2.6),
                decay_scale=rng.uniform(0.02, 2.2),
            )

    def sparseBolt(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        bolts = rng.randint(1, max(2, p.grid // 5))
        for _ in range(bolts):
            anchor = rng.randrange(p.grid)
            pulse = _chaos_pulse(p, anchor, rng)
            _emit_hit(
                p,
                slot,
                pulse,
                cfg,
                composition,
                rng,
                rng.uniform(1.2, 2.8),
                decay_scale=rng.uniform(0.08, 2.8),
            )
            if rng.random() < 0.55:
                for offset in range(rng.randint(1, 4)):
                    tail = _chaos_pulse(p, anchor + offset * rng.uniform(0.2, 0.6), rng)
                    _emit_hit(
                        p,
                        slot,
                        tail,
                        cfg,
                        composition,
                        rng,
                        rng.uniform(0.2, 1.2),
                        decay_scale=rng.uniform(0.01, 0.45),
                    )

    def noiseConvolve(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        pink = su.pink_noise(p.grid, seed=p.cycle * 31 + slot)
        drift = su.perlin_1d_sequence(0.0, 0.28, p.grid, seed=p.cycle * 37 + slot * 7)
        base = su.generate_euclidean_sequence(p.grid, max(2, int(p.grid * rng.uniform(0.35, 0.72))))
        for idx, hit in enumerate(base):
            if not hit:
                continue
            field = (pink[idx] * drift[idx]) ** 0.5
            if field >= rng.uniform(0.18, 0.52):
                pulse = _chaos_pulse(p, idx * rng.uniform(0.5, 1.8), rng)
                _emit_hit(
                    p,
                    slot,
                    pulse,
                    cfg,
                    composition,
                    rng,
                    0.4 + field * 2.0,
                    decay_scale=rng.uniform(0.015, 1.6),
                )

    return {
        "stutter": stutter,
        "wander": wander,
        "flare": flare,
        "glitch": glitch,
        "grainCloud": grainCloud,
        "lorenzSpray": lorenzSpray,
        "poissonField": poissonField,
        "vdcScatter": vdcScatter,
        "microCluster": microCluster,
        "caSnapshot": caSnapshot,
        "deBruijnGlitch": deBruijnGlitch,
        "logisticSwarm": logisticSwarm,
        "spectralDrift": spectralDrift,
        "sparseBolt": sparseBolt,
        "noiseConvolve": noiseConvolve,
    }


def _profile_builders() -> Dict[Profile, Callable[[Any, LaneCfg, random.Random, Any], None]]:
    def grid16(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        if cfg.get("modifier") == "percussive":
            slot = int(cfg["slot"])
            density = rng.choice([0.38, 0.50, 0.62, 0.75])
            grid = su.generate_euclidean_sequence(p.grid, max(3, int(p.grid * density)))
            downbeat = rng.choice([0, 4, 8, 12])
            grid[downbeat % p.grid] = 1
            for step, hit in enumerate(grid):
                if hit:
                    accent = 1.35 if step % 4 == 0 else rng.uniform(0.72, 1.12)
                    family = "groove" if step % 4 == 0 else "ghost"
                    _emit_percussive_step(p, slot, cfg, composition, rng, step, accent, family)
        else:
            _grid_hits(p, cfg, composition, rng, int(p.grid * 0.72))

    def euclid(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        if cfg.get("modifier") == "percussive":
            slot = int(cfg["slot"])
            hits = max(3, min(p.grid - 1, int(p.grid * rng.uniform(0.30, 0.64))))
            grid = su.generate_euclidean_sequence(p.grid, hits)
            grid = _rotate(grid, rng.randint(0, max(0, p.grid - 1)))
            for step, hit in enumerate(grid):
                if hit:
                    _emit_percussive_step(p, slot, cfg, composition, rng, step, 1.15 if step % 4 == 0 else 0.92, "wood")
        else:
            _grid_hits(p, cfg, composition, rng, int(p.grid * rng.uniform(0.42, 0.82)))

    def shuffle16(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        steps = p.grid
        hits = max(2, min(steps - 1, int(steps * 0.66)))
        grid = su.generate_euclidean_sequence(steps, hits)
        swing = float(cfg.get("swing", 0.0))
        for step, hit in enumerate(grid):
            if hit:
                pulse = _step_pulse(p, step)
                if swing > 0.02 and step % 2 == 1:
                    pulse = int(pulse * (1.0 + swing * 0.35))
                if cfg.get("modifier") == "percussive":
                    _emit_hit(
                        p,
                        slot,
                        pulse,
                        cfg,
                        composition,
                        rng,
                        1.22 if step % 4 == 0 else rng.uniform(0.70, 1.05),
                        decay_scale=_percussive_decay(rng, "groove" if step % 4 == 0 else "ghost"),
                    )
                else:
                    _emit_hit(p, slot, pulse, cfg, composition, rng)

    def polyphase(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        cycles = rng.sample([3, 5, 7, 11], k=rng.randint(2, 3))
        merged = [0] * p.grid
        layers: Dict[int, List[int]] = {}
        for cycle in cycles:
            pulses = max(1, cycle // 2 + rng.randint(-1, 1))
            layer = su.generate_euclidean_sequence(cycle, max(1, min(cycle - 1, pulses)))
            layers[cycle] = layer
            for step in range(p.grid):
                if layer[step % cycle]:
                    merged[step] = 1
        _emit_binary_grid(
            p,
            slot,
            cfg,
            composition,
            rng,
            merged,
            accent_fn=lambda step: 1.22 if sum(l[step % c] for c, l in layers.items()) > 1 else 0.9,
        )

    def pulseFold(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        period = rng.choice([5, 7, 9, 11])
        hits = max(2, period // 2 + rng.randint(-1, 1))
        folded = su.generate_euclidean_sequence(period, min(period - 1, hits))
        grid = [folded[step % period] for step in range(p.grid)]
        grid = _rotate(grid, rng.randint(0, max(0, p.grid - 1)))
        _emit_binary_grid(p, slot, cfg, composition, rng, grid)

    def ratioLattice(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        for step in _ratio_lattice_steps(p.grid, rng):
            _emit_at_step(p, slot, cfg, composition, rng, step, rng.uniform(0.82, 1.28))

    def burst(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        cluster = rng.randint(4, 8)
        step_beats = p._pattern.length / max(1, p.grid)
        start = rng.randint(0, max(0, p.grid - 5))
        spacing = rng.choice([0.50, 0.67, 1.0])
        for i in range(cluster):
            beat = ((start + (i * spacing)) * step_beats) % p._pattern.length
            _emit_hit(
                p,
                slot,
                int(beat * subsequence.constants.MIDI_QUARTER_NOTE),
                cfg,
                composition,
                rng,
                1.20 - min(0.55, i * 0.08),
                decay_scale=_percussive_decay(rng, "fill"),
            )

    def poly23(p: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        if cfg.get("modifier") == "percussive":
            slot = int(cfg["slot"])
            cycle_a = rng.choice([3, 5])
            cycle_b = rng.choice([4, 7])
            for step in range(p.grid):
                if step % cycle_a == 0 or (step + rng.randint(0, 2)) % cycle_b == 0:
                    _emit_percussive_step(p, slot, cfg, composition, rng, step, 1.18 if step % cycle_a == 0 else 0.82, "clave")
        else:
            _grid_hits(p, cfg, composition, rng, int(p.grid * 0.58))

    def pulse(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        budget = _drone_event_budget(cfg)
        hits = max(1, min(budget, 2))
        grid = su.generate_euclidean_sequence(pf.grid, hits)
        indices = su.sequence_to_indices(grid)
        roll = rng.randint(0, max(0, pf.grid - 1))
        indices = su.roll(indices, roll, pf.grid)
        for step in indices[:hits]:
            _emit_drone_hit(pf, slot, _step_pulse(pf, step), cfg, composition, rng, 0.82)

    def breath(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        budget = _drone_event_budget(cfg)
        noise = su.perlin_1d_sequence(0.0, 0.18, pf.grid, seed=pf.cycle + slot * 31)
        step_beats = pf._pattern.length / max(1, pf.grid)
        for idx in _select_drone_steps(noise, pf.grid, budget, rng):
            value = noise[idx]
            beat = idx * step_beats
            jitter = rng.uniform(-0.08, 0.08) * pf._pattern.length
            beat = max(0.0, min(pf._pattern.length - 0.01, beat + jitter))
            pulse = int(beat * subsequence.constants.MIDI_QUARTER_NOTE)
            _emit_drone_hit(
                pf,
                slot,
                pulse,
                cfg,
                composition,
                rng,
                accent_scale=0.78 + value * 0.35,
                decay_scale=3.5 + value * 4.0,
            )

    def swell(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        budget = _drone_event_budget(cfg)
        envelope = su.perlin_1d_sequence(0.0, 0.24, pf.grid, seed=pf.cycle * 13 + slot)
        step_beats = pf._pattern.length / max(1, pf.grid)
        for idx in _select_drone_steps(envelope, pf.grid, budget, rng):
            value = envelope[idx]
            beat = idx * step_beats
            _emit_drone_hit(
                pf,
                slot,
                int(beat * subsequence.constants.MIDI_QUARTER_NOTE),
                cfg,
                composition,
                rng,
                accent_scale=0.7 + value * 0.65,
                decay_scale=4.0 + value * 4.5,
            )

    def ritual(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        budget = max(1, min(_drone_event_budget(cfg) + 1, 3))
        hits = max(1, min(budget, pf.grid // 2))
        grid = su.generate_euclidean_sequence(pf.grid, hits)
        walk = su.random_walk(hits, -2, 4, 1, rng, start=_drone_degree(composition, slot, cfg, rng, drift=False))
        for step, degree in zip(su.sequence_to_indices(grid)[:hits], walk):
            local = dict(cfg)
            local["_scale_override"] = degree
            _emit_drone_hit(
                pf,
                slot,
                _step_pulse(pf, step),
                local,
                composition,
                rng,
                accent_scale=0.88,
                decay_scale=rng.uniform(3.8, 7.2),
            )

    def arp(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        step_beats = pf._pattern.length / max(1, pf.grid)
        direction = 1
        degree = 0
        for idx in range(pf.grid):
            if idx % 2 == 0:
                beat = idx * step_beats
                local = dict(cfg)
                local["_scale_override"] = degree
                _emit_hit(pf, slot, int(beat * subsequence.constants.MIDI_QUARTER_NOTE), local, composition, rng)
                degree += direction
                if abs(degree) > 3:
                    direction *= -1

    def motif(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        _grid_hits(pf, cfg, composition, rng, int(pf.grid * 0.55))

    def canon(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        _grid_hits(pf, cfg, composition, rng, int(pf.grid * 0.48))

    def hymn(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        slot = int(cfg["slot"])
        step_beats = pf._pattern.length / max(1, pf.grid)
        for idx in range(0, pf.grid, 2):
            beat = idx * step_beats
            _emit_hit(pf, slot, int(beat * subsequence.constants.MIDI_QUARTER_NOTE), cfg, composition, rng, 0.95)

    def pulse_harm(pf: Any, cfg: LaneCfg, rng: random.Random, composition: Any) -> None:
        _grid_hits(pf, cfg, composition, rng, int(pf.grid * 0.62))

    return {
        "grid16": grid16,
        "shuffle16": shuffle16,
        "euclid": euclid,
        "burst": burst,
        "poly23": poly23,
        "polyphase": polyphase,
        "pulseFold": pulseFold,
        "ratioLattice": ratioLattice,
        "pulse": pulse,
        "breath": breath,
        "swell": swell,
        "ritual": ritual,
        "arp": arp,
        "motif": motif,
        "canon": canon,
        "hymn": hymn,
        "pulseHarm": pulse_harm,
        **_chaos_profile_builders(),
        **_percussive_profile_builders(),
    }


PROFILE_BUILDERS = _profile_builders()


def _event_cap(cfg: LaneCfg, profile: str) -> Optional[int]:
    modifier = str(cfg.get("modifier", "harmonic"))
    material = str(cfg.get("material", ""))
    if modifier != "chaos":
        return None
    base = 12
    if material == "rings":
        base = 8
    elif material in {"plaits", "molly", "fm7"}:
        base = 10
    if profile in {"deBruijnGlitch", "grainCloud", "logisticSwarm", "microCluster"}:
        base = max(5, base - 2)
    return base


def _thin_events(events: List[Any], cap: int) -> List[Any]:
    if cap <= 0 or len(events) <= cap:
        return events
    if cap == 1:
        return [events[0]]
    span = (len(events) - 1) / (cap - 1)
    return [events[round(index * span)] for index in range(cap)]


def _event_floor(cfg: LaneCfg, profile: str) -> int:
    modifier = str(cfg.get("modifier", "harmonic"))
    density = max(0.05, min(float(cfg.get("density", 1.0)), 1.0))
    if modifier == "percussive":
        return max(5, min(12, round(4 + density * 8)))
    if modifier == "chaos":
        material = str(cfg.get("material", ""))
        upper = 7 if material == "rings" else 9
        if profile in {"sparseBolt", "spectralDrift"}:
            upper = max(5, upper - 1)
        return max(4, min(upper, round(3 + density * 6)))
    if modifier == "drone":
        return max(2, min(4, round(1 + density * 4)))
    return max(4, min(8, round(3 + density * 6)))


def _add_floor_hits(
    p: Any,
    cfg: LaneCfg,
    composition: Any,
    rng: random.Random,
    target: int,
) -> None:
    slot = int(cfg["slot"])
    modifier = str(cfg.get("modifier", "harmonic"))
    cap = max(target, 1)
    attempts = 0
    while len(p._pattern.osc_events) < target and attempts < cap * 3:
        step = round((attempts / max(1, cap)) * max(1, p.grid - 1))
        step = (step + rng.randint(0, max(0, p.grid // 4))) % max(1, p.grid)
        _emit_hit(
            p,
            slot,
            _step_pulse(p, step),
            cfg,
            composition,
            rng,
            accent_scale=0.7 if modifier == "drone" else 0.9,
            decay_scale={
                "percussive": rng.uniform(0.55, 1.05),
                "drone": rng.uniform(3.0, 6.5),
                "chaos": rng.uniform(0.12, 0.9),
            }.get(modifier, rng.uniform(0.75, 1.25)),
            sustain=1 if modifier == "drone" else 0,
            skip_density=True,
        )
        attempts += 1


def build_lane_pattern(p: Any, cfg: LaneCfg, composition: Any) -> None:
    """Populate one lane cycle using Subsequence and emit EAP OSC triggers."""
    slot = int(cfg["slot"])
    effective = _effective_cfg(cfg, composition)

    _configure_pattern_for_modifier(p, effective)
    p._pattern.steps = {}
    p._pattern.osc_events = []

    if not cfg.get("active"):
        return

    profile = str(cfg.get("profile", "euclid"))
    seed = int(cfg.get("seed", slot * 9973)) + p.cycle * 7919
    rng = random.Random(seed)

    builder = PROFILE_BUILDERS.get(profile, PROFILE_BUILDERS["euclid"])
    try:
        builder(p, effective, rng, composition)
    except Exception:
        LOG.exception("lane %s profile %s failed; falling back to euclid", slot, profile)
        PROFILE_BUILDERS["euclid"](p, effective, rng, composition)

    cap = _event_cap(effective, profile)
    if cap is not None and len(p._pattern.osc_events) > cap:
        LOG.warning(
            "lane %s profile %s emitted %s events; thinning to %s",
            slot,
            profile,
            len(p._pattern.osc_events),
            cap,
        )
        p._pattern.osc_events = _thin_events(p._pattern.osc_events, cap)

    floor = _event_floor(effective, profile)
    if cap is not None:
        floor = min(floor, cap)
    if len(p._pattern.osc_events) < floor:
        LOG.warning(
            "lane %s profile %s emitted %s events; filling to %s",
            slot,
            profile,
            len(p._pattern.osc_events),
            floor,
        )
        _add_floor_hits(p, effective, composition, rng, floor)

    if not p._pattern.osc_events:
        LOG.warning("lane %s profile %s produced no events; adding anchored hit", slot, profile)
        anchor_decay = {
            "percussive": 0.85,
            "drone": 5.5,
            "chaos": 0.55,
        }.get(str(effective.get("modifier", "harmonic")), 1.15)
        _emit_hit(
            p,
            slot,
            0,
            effective,
            composition,
            rng,
            accent_scale=1.0,
            decay_scale=anchor_decay,
            sustain=1 if effective.get("modifier") == "drone" else 0,
            skip_density=True,
        )

    composition.data[f"lane{slot}_cycle"] = p.cycle


def lane_pattern_length_beats(cfg: LaneCfg, bpm: float) -> float:
    modifier = cfg.get("modifier", "harmonic")
    steps, step_duration = MODIFIER_TIMING.get(modifier, MODIFIER_TIMING["harmonic"])
    return steps * step_duration


def lane_grid_steps(cfg: LaneCfg) -> int:
    modifier = cfg.get("modifier", "harmonic")
    steps, _ = MODIFIER_TIMING.get(modifier, MODIFIER_TIMING["harmonic"])
    return steps
