# Electroacoustic Playground — User Guide

Electroacoustic Playground (EAP) is a performance instrument for Raspberry Pi / Fates built around **SuperCollider**, a **Launchpad Mini Mk3** control surface, and optional external engines (Dexed, Vitalium, VCV Rack). Up to **eight independent scene lanes** play at once, each with its own rhythm, timbre, effects, and optional sound engine.

This guide covers normal operation from the Launchpad, configuration pages, optional engines, sessions, and basic maintenance on the Pi.

---

## Table of contents

1. [Quick start](#quick-start)
2. [System overview](#system-overview)
3. [Launchpad layout conventions](#launchpad-layout-conventions)
4. [Scene page (default)](#scene-page-default)
5. [Performance page (per-scene mix)](#performance-page-per-scene-mix)
6. [Master reverb page](#master-reverb-page)
7. [Master dynamics page](#master-dynamics-page)
8. [Scales, root, and engine page](#scales-root-and-engine-page)
9. [Session page](#session-page)
10. [Airwindows grid FX page](#airwindows-grid-fx-page)
11. [Sound-type modifiers](#sound-type-modifiers)
12. [Scene generation behaviour](#scene-generation-behaviour)
13. [Optional external engines](#optional-external-engines)
14. [Command-line control (`eap`)](#command-line-control-eap)
15. [Pi operation and troubleshooting](#pi-operation-and-troubleshooting)

---

## Quick start

1. Power on the Pi. Systemd starts **JACK**, **SuperCollider**, and the **Launchpad daemon** automatically.
2. Connect a **Launchpad Mini Mk3** via USB. The console display (TTY1) should show `EAP - OK` and `LP - ONLINE`.
3. On the **Scene page**, hold a **sound-type modifier** and **long-press** (≈0.65 s) a bottom-row pad to **generate** a new scene in that slot.
4. **Tap** a non-blank bottom-row pad (no modifier) to **mute** or **unmute** the loaded scene.
5. **Long-press** a bottom-row pad **with a modifier held** to **regenerate** that slot with new material.

---

## System overview

| Component | Role |
|-----------|------|
| **JACK** (`eap-jack.service`) | Real-time audio server (48 kHz, 1024-frame buffers) |
| **SuperCollider** (`eap-supercollider.service`) | Scene engine, synthesis, master bus, shared reverb |
| **Launchpad** (`eap-launchpad.service`) | MIDI → OSC control, LED feedback |
| **SC connect** (`eap-sc-connect.service`) | Wires SuperCollider outputs to system playback |
| **Airwindows host** | On-demand insert FX when Grid FX page is used |
| **Dexed / Vital / VCV** | Optional external JACK/MIDI instruments (disabled by default on Pi) |

Audio path (simplified):

```
Scene lanes → lane FX (pedalboard or Clouds) → master bus
External engines (Dexed/Vital/VCV) → SC inputs 3/4 → master bus (pulsed on notes)
Grid FX (when active) → SC out 3/4 → Airwindows → SC in 1/2 → master
Master → JPverb reverb → dynamics / saturation → hardware out
```

---

## Launchpad layout conventions

### Pad grid coordinates

EAP numbers the **8×8 pad matrix** as **row 1–8** (bottom → top) and **column 1–8** (left → right).

```
        Col:  1   2   3   4   5   6   7   8
Row 8:  [ ·   ·   ·   ·   ·   ·   ·   · ]   ← top
Row 7:  [ ·   ·   ·   ·   ·   ·   ·   · ]
  ...
Row 2:  [ ·   ·   ·   ·   ·   ·   ·   · ]
Row 1:  [ ·   ·   ·   ·   ·   ·   ·   · ]   ← bottom (scene slots)
```

**Bottom row (row 1)** pads are **scene slots 1–8** (left = slot 1, right = slot 8).

### Side buttons (Launchpad Mini Mk3)

EAP uses **Up** side buttons as mode switches and modifiers. Hold to enter a page; release to return to the Scene page (except Grid FX, which toggles on/off).

| Control | MIDI CC | Physical (typical) | Action |
|---------|---------|-------------------|--------|
| Percussive modifier | **19** | Left Up, bottom | Hold while generating / regenerating |
| Drone modifier | **29** | Left Up, 2nd | Hold while generating / regenerating |
| Chaos modifier | **39** | Left Up, 3rd | Hold while generating / regenerating |
| Master dynamics | **89** | Left Up, top | Hold → Master page |
| Master reverb | **91** | Right Up, bottom | Hold → Reverb page |
| Scales / engine | **92** | Right Up, 2nd | Hold → Tuning page |
| Grid FX | **93** | Right Up, 3rd | **Tap** to enter/exit Grid FX page |
| Sessions | **98** | Right Up, top | Hold → Session page |

Modifier buttons glow **orange** when idle and **white** when held.

### Scene slot LED colours

| Colour | Meaning |
|--------|---------|
| Dark grey | **Blank** — no scene in this slot |
| Green | **Active** — scene playing |
| Amber / gold | **Muted** — scene loaded but silent |

If you try to **create** a scene without holding a modifier, the pad **flashes red** briefly.

---

## Scene page (default)

The Scene page is the home screen. The **bottom row** is the only interactive area (plus side buttons).

```
        Col:  1      2      3      4      5      6      7      8
Row 1:  Slot1  Slot2  Slot3  Slot4  Slot5  Slot6  Slot7  Slot8
        (scene control pads — see gestures below)
```

Upper rows are **off** on this page.

### Gestures (bottom row)

| Gesture | Modifier | Pad state | Result |
|---------|----------|-----------|--------|
| Short press | None | Blank | Flash red (modifier required to generate) |
| Long press (~0.65 s) | **Required** | Blank | **Generate** new scene |
| Short press | None | Active | **Mute** |
| Short press | None | Muted | **Unmute** (restores the same scene) |
| Long press (~0.65 s) | **Required** | Active or muted | **Regenerate** (replace scene) |
| Long press | None | Active or muted | Enter **Performance page** for that slot |

LED colours update from SuperCollider after each action (Launchpad syncs over OSC).

---

## Performance page (per-scene mix)

Enter by **long-pressing** a non-blank scene pad **without** a modifier. Adjust mix parameters on the grid; **release** the scene pad to return to the Scene page.

If you **only** long-pressed to enter Performance and **did not** touch the grid, a **short release** of the scene pad performs a normal **mute/unmute** toggle.

```
        Col:    1        2        3        4        5        6        7        8
Row 8:  (dim — unused)
Row 7:  Transpose faders (see below)
Row 6:  Per-scene reverb send (0 = left, 127 = right)
Row 5:  Timbre motion
Row 4:  Event density
Row 3:  Pan (centre = cols 4–5)
Row 2:  Volume
Row 1:  Scene slot mirrors (edited slot highlighted cyan)
```

### Row 7 — Transpose (octaves)

| Column | Semitone offset |
|--------|-----------------|
| 1 | −36 (−3 oct) |
| 2 | −24 (−2 oct) |
| 3 | −12 (−1 oct) |
| 4–5 | **0** (centre) |
| 6 | +12 (+1 oct) |
| 7 | +24 (+2 oct) |
| 8 | +36 (+3 oct) |

Tap a column to set transpose for the **selected** scene only.

### Row 6 — Reverb send

Horizontal fader: **column 1 = dry**, **column 8 = wet**. Bright pad = current value.

### Rows 2–5 — Volume, pan, density, timbre

Each row is a **horizontal fader** (same column = value mapping as reverb send). Pan row highlights columns **4–5** as centre.

Changes are sent immediately to SuperCollider for the selected slot.

---

## Master reverb page

**Hold CC 91** (right Up, bottom). Release to return to Scene page.

Eight **columns** = eight reverb parameters. **Row height** = value (row 1 = minimum, row 8 = maximum). The brightest pad in each column is the current setting.

```
        Col:   1       2       3       4       5       6       7       8
        Param: Wet    Room    Damp    Decay   Lo cut  Hi cut  Mod     Bright
Row 8:  [ max   max     max     max     max     max     max     max   ]
   ...
Row 1:  [ min   min     min     min     min     min     min     min   ]
```

| Col | Parameter | Effect |
|-----|-----------|--------|
| 1 | **Wet** | Global reverb mix level |
| 2 | **Room** | Room size |
| 3 | **Damp** | High-frequency damping |
| 4 | **Decay** | Reverb tail length |
| 5 | **Lo cut** | Low-frequency cutoff on reverb send |
| 6 | **Hi cut** | High-frequency cutoff on reverb send |
| 7 | **Mod depth** | Modulation inside the reverb |
| 8 | **Bright** | Reverb brightness |

Tap any pad in a column to set that parameter. All active scenes share this master reverb.

---

## Master dynamics page

**Hold CC 89** (left Up, top). Release to return to Scene page.

Five columns (columns **6–8** are unused / off):

```
        Col:   1          2           3            4            5 (CC 14)
        Param: Volume     Overdrive   Bit depth    Saturation   Compressor
Row 8:  [ max      max         max          max          profile 8 ]
   ...
Row 1:  [ min      min         min          min          bypass   ]
```

| Col | CC | Parameter | Effect |
|-----|----|-----------|--------|
| 1 | 10 | **Master volume** | Overall output level |
| 2 | 11 | **Overdrive** | Master drive amount |
| 3 | 12 | **Bit depth** | Lo-fi / bit reduction |
| 4 | 13 | **Saturation** | Soft saturation |
| 5 | **14** | **Compressor profile** | Row 1 = **bypass** (no compression); rows 2–8 = stepped dynamics (low → high) |

---

## Scales, root, and engine page

**Hold CC 92** (right Up, 2nd). Release to return to Scene page.

```
        Col:   1        2        3        4        5        6        7        8
Row 8:  Scale presets (tap column to select — see table below)
Row 7:  Root notes C  D   E   F   G   A   B   (col 8 unused)
Row 6:  (off)
Row 5:  [ VCV ]  (col 1 only — optional engine)
Row 4:  Engine preference row (see table below)
Row 1–3: (off)
```

### Row 8 — Scale (column = scale index 0–7)

| Col | Index | Scale (intervals from root) |
|-----|-------|----------------------------|
| 1 | 0 | Chromatic |
| 2 | 1 | Dorian (7-note) |
| 3 | 2 | Major / Ionian |
| 4 | 3 | Mixolydian |
| 5 | 4 | Lydian |
| 6 | 5 | Whole-tone / altered (7-note) |
| 7 | 6 | Minor pentatonic (+2) |
| 8 | 7 | Major pentatonic |

Changing scale or root **updates all active lanes** and plays a short preview.

### Row 7 — Root note

Columns **1–7** select root **C, D, E, F, G, A, B** (white-key roots only on the Launchpad).

### Row 4 — Source engine preference (future scenes)

Selecting an engine biases **new** scene generation toward that material. It does not replace running scenes.

| Col | Engine | Description |
|-----|--------|-------------|
| 1 | **Any** | No preference (default random mix) |
| 2 | **Plaits** | Mutable Plaits models |
| 3 | **Rings** | Resonator / modal material |
| 4 | **Passersby** | Wavetable / FM voices |
| 5 | **Molly** | Additional internal engine |
| 6 | **Fold** | Wavefolder-based material |
| 7 | **Dexed** | External FM (requires Dexed service) |
| 8 | **Vital** | External Vitalium (requires enable flag) |

### Row 5, column 1 — VCV Rack

Selects **VCV Rack** as the engine preference for future scenes. Requires `EAP_ENABLE_VCV=1` and a compatible cached patch on the Pi.

---

## Session page

**Hold CC 98** (right Up, top). Release to return to Scene page.

The full **8×8 grid** holds **64 session slots**. Slot number = `(row − 1) × 8 + column` (row 1 col 1 = slot 1, row 8 col 8 = slot 64).

```
        Col:  1    2    3    4    5    6    7    8
Row 8:  57   58   59   60   61   62   63   64
Row 7:  49   50   51   52   53   54   55   56
  ...
Row 1:  1    2    3    4    5    6    7    8
```

| LED | Meaning |
|-----|---------|
| Off | Empty slot |
| Purple | Saved session |
| Bright purple | Currently loaded session |

| Gesture | Action |
|---------|--------|
| **Short press** | **Load** session (SuperCollider lane archive + Launchpad mix/tuning snapshot) |
| **Long press** | **Save** current state to slot (purple blink while saving) |

Sessions store: scene slot states, per-scene performance parameters (volume, pan, density, timbre, reverb send, transpose), master reverb, master dynamics, tuning/engine selection, and the full SuperCollider lane definitions for recall.

---

## Airwindows grid FX page

**Tap CC 93** (right Up, 3rd) to **enter**; tap again to **exit** to Scene page.

Global **insert effects** on the scene mix (up to **three** active at once). Activating a fourth **drops the oldest**.

```
        Col:  1    2    3    4    5    6    7    8
Row 1:  Scene targeting mirrors (same as bottom row — see below)
Row 2:  FX 1–8
Row 3:  FX 9–16
Row 4:  FX 17–24
Row 5:  FX 25–30  (cols 7–8 unused)
Row 6:  (unused — no effects mapped)
Row 7:  (unused)
Row 8:  (off)
```

### Row 1 — Scene targeting

Mirrors bottom-row scene slots. Tap an **active** (green) scene to include/exclude it from the Grid FX bus.

| LED | Meaning |
|-----|---------|
| Dim | Inactive / blank / muted scene |
| Green | Active scene, **included** in FX |
| Bright green | Active scene, **selected** for FX |
| Amber | Muted scene |

At least one active scene must be selected when enabling an effect.

### Rows 2–5 — Effects (30 total, compacted left → right)

| Index | Plugin | Index | Plugin |
|-------|--------|-------|--------|
| 1 | TapeDelay2 | 16 | Gringer |
| 2 | PitchDelay | 17 | Nikola |
| 3 | Doublelay | 18 | HipCrush |
| 4 | SampleDelay | 19 | DeRez3 |
| 5 | Melt | 20 | Pockey2 |
| 6 | ADT | 21 | CrunchyGrooveWear |
| 7 | StarChild2 | 22 | BitGlitter |
| 8 | TakeCare | 23 | TapeBias |
| 9 | RingModulator | 24 | Vibrato |
| 10 | Dubly3 | 25 | Deckwrecka |
| 11 | GalacticVibe | 26 | DeNoise |
| 12 | Pafnuty2 | 27 | Texturize |
| 13 | PitchNasty | 28 | VoiceOfTheStarship |
| 14 | GuitarConditioner | 29 | ElectroHat |
| 15 | GlitchShifter | 30 | Silhouette |

| Gesture | Action |
|---------|--------|
| **Short press** on FX pad | Toggle effect on/off (randomises parameters when enabled) |
| **Long press** on FX pad | **Lock** / unlock parameter seed (locked = red; locked+active = bright red) |

Grid FX CC button glows **orange** while the page is open.

---

## Sound-type modifiers

Hold **one** modifier while generating or regenerating to shape the scene character:

| CC | Name | Character |
|----|------|-----------|
| 19 | **Percussive** | Short envelopes, dense rhythms, punchy materials |
| 29 | **Drone** | Low register, sparse events, sustain and Clouds-friendly textures |
| 39 | **Chaos** | Noisy FM, volatile timing, aggressive FX |

Without a modifier, generation uses the **default** random profile (still valid for mute/unmute on existing scenes).

---

## Scene generation behaviour

Each scene lane is an **independent** sequencer with:

- One or more **material sources** (Plaits, Rings, Passersby, Molly, fold, or optional externals)
- A **lane FX path**: pedalboard chain **or** Clouds-style granular (Clouds auto-muted if too many heavy lanes are active)
- **Adaptive** relationships between sibling lanes (register, density, rhythm)
- **Scale-aware** pitch selection using the global scale/root

CPU safeguards (automatic):

- Trigger **budgets** per modifier tighten as more lanes go active
- **Clouds** lanes may be muted and downgraded to pedalboard when load is high
- External input (Dexed/Vital/VCV) is **opened only during notes**, not held open continuously

---

## Optional external engines

These are **off by default** on the Pi to keep JACK stable. Enable only when needed.

### Dexed

- Install/build via deployment scripts; start `eap-dexed.service` when required
- Audio: Dexed → SuperCollider inputs **3/4**
- After restart: `eap --dexed-rescan`
- Patch cache: `eap-build-dexed-cache`

### Vital / Vitalium

- Install: `eap-install-vitalium`
- Enable: `EAP_ENABLE_VITAL=1` (heavy on CPU — expect xruns with many lanes)

### VCV Rack

- Install: `eap-install-vcv-rack`, `eap-vcv-install-seeds`, `eap-vcv-sync-patches`
- Enable: set `EAP_ENABLE_VCV=1` in `/etc/default/eap-vcv`, then enable `eap-vcv.service`
- Select **VCV** on tuning page row 5 col 1 before generating scenes
- Rescan MIDI: `eap --vcv-rescan`

---

## Command-line control (`eap`)

Run on the Pi (or over SSH). Sends OSC to SuperCollider on port **57120**.

```sh
# Generate N random scenes (requires modifier via Launchpad for full behaviour;
# CLI seed does not send modifier — use Launchpad for modifier-specific seeds)
eap --seedscene --n 4

# Toggle slot 3
eap --slot 3

# Regenerate slot 5
eap --slot 5 --regenerate

# Master reverb column 4 (decay) to 90
eap --reverb-param 4 --value 90

# Master dynamics column 1 (volume) to 100
eap --master-param 1 --value 100

# Tuning: scale index 2, root C (0)
eap --scale 2 --root 0

# Sessions
eap --save-session 12
eap --session 12

# External engine MIDI rescans
eap --dexed-rescan
eap --vcv-rescan
```

Useful maintenance scripts (installed to `/usr/local/bin/`):

| Script | Purpose |
|--------|---------|
| `eap-audio-stack-restart` | Full ordered restart of JACK, SC, Launchpad |
| `eap-alsa-mixer` | Restore WM8731 mixer defaults |
| `eap-connect-sc-jack` | Fix SuperCollider ↔ playback wiring |

---

## Pi operation and troubleshooting

### Boot services

Core services (always enabled):

- `eap-jack.service`
- `eap-supercollider.service`
- `eap-sc-connect.service`
- `eap-launchpad.service`
- `eap-console-status.service`

### Console status (TTY1)

Three lines refresh every ~2 s:

```
EAP - OK          (or BOOT / FAIL)
CPU 42% + RAM 38%
LP - ONLINE       (or WAIT / MISSING)
```

### Deploy from development machine

```sh
EAP_PI_HOST=we@<pi-address> ./deployment/deploy-to-pi.sh
```

Set `EAP_RESTART=0` to sync files without restarting services.

### Common issues

| Symptom | Check |
|---------|--------|
| No Launchpad response | `systemctl status eap-launchpad`; USB cable; `LP - MISSING` on console |
| No audio | `systemctl status eap-jack eap-supercollider`; run `eap-audio-stack-restart` |
| Scene pads flash red | Hold a **modifier** before generating on a blank pad |
| Mute/unmute LED wrong | Wait briefly — LEDs sync from SC; power-cycle Launchpad service if stuck |
| Xruns / glitches | Reduce active lanes; disable VCV/Vital; avoid Grid FX with many scenes; run `eap-audio-stack-restart` |
| Dexed/VCV silent | Rescan MIDI; confirm JACK routes with `jack_lsp -c` |

### Audio buffer profile (reference)

Current stable Pi profile: JACK **1024 frames × 2 periods**, SuperCollider **1024-sample** blocks. SuperCollider JACK autoconnect must target `system:playback_1/2` only — never channel counts (miswired SC ports cause xruns).

---

## OSC reference (advanced)

Launchpad and `eap` talk to SuperCollider on **UDP 57120**. Slot state replies arrive on **57121**.

| Address | Arguments | Purpose |
|---------|-----------|---------|
| `/eap/slot` | slot, action, modifier? | action 0 = mute/unmute toggle; action 1 = generate/regenerate (modifier 1–3 required) |
| `/eap/slots/query` | — | Request all slot states |
| `/eap/slots/state` | 8× int | Reply: 0 blank, 1 active, 2 muted |
| `/eap/scenes` | count, modifier? | Seed multiple lanes |
| `/eap/reverb` | param 1–8, value 0–127 | Master reverb |
| `/eap/master` | param 1–5, value 0–127 | Master dynamics |
| `/eap/tuning` | scale 0–7, root 0–11 | Global tuning |
| `/eap/engine` | code 0–8 | Engine preference |
| `/eap/session` | slot 1–64, action | 0 = load, 1 = save |
| `/eap/slot/volume` … `/transpose` | slot, value | Per-scene performance params |
| `/eap/gridfx` | index, 0/1 | Toggle Airwindows insert |
| `/eap/gridfx/scene` | slot, 0/1 | Scene FX routing |
| `/eap/gridfx/lock` | index, 0/1 | Lock FX parameters |

---

*Document version matches the repository `main` branch. For developer-oriented architecture notes, see [README.md](../README.md).*
