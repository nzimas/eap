# Electroacoustic Playground

Electroacoustic Playground is a bespoke Raspberry Pi/Fates instrument stack built around SuperCollider, a Launchpad Mini Mk3 control layer, Mutable Instruments-inspired engines, Passersby/Molly sound material, pedalboard effects, and a shared master reverb.

The current stack includes:

- SuperCollider scene-slot engine with up to eight Launchpad-addressable scene slots.
- Random scene generation from Plaits, Rings, Passersby, Molly, fold-based material, optional external Dexed, and optional realtime Vital/Vitalium.
- Per-scene pedalboard or Clouds-style effects, bounded for CPU safety.
- Launchpad Mini Mk3 controller daemon with scene toggles, long-press regeneration, sound-type modifiers (CC 19/29/39/49), LED states, and auxiliary pages for reverb, tuning, master dynamics, and sessions.
- Systemd units and deployment helpers for the Fates/Pi environment.

Primary runtime files:

- `supercollider/Scene_RandomLanes.scd`
- `supercollider/boot.scd`
- `control/eap_launchpad.py`
- `bin/eap`
- `deployment/systemd/`

## Dexed Integration

Dexed is treated as a real external JACK instrument rather than a SuperCollider recreation. The headless service starts the upstream standalone build under Xvfb with JACK/ALSA enabled, then the wiring service routes Dexed audio back into SuperCollider.

Dexed audio is connected to SuperCollider inputs 3/4. The SC server exposes four input channels, and an always-on external input bridge feeds channels 3/4 into the EAP master bus so Dexed receives the shared master reverb, dynamics, saturation, and volume controls.

MIDI is sent from SuperCollider to Dexed through the ALSA `out0` subscription created by Dexed's seeded settings. When the route is present, random scene generation can choose `\dexed` as a material source and sends notes to it from the same scale-aware sequencer used by the SC engines.

After starting or restarting a headless Dexed host, run:

```sh
eap --dexed-rescan
```

Dexed patch selection uses a runtime cache built from DX7 `.syx` banks. To rebuild it from a local archive:

```sh
eap-build-dexed-cache /path/to/DX7_AllTheWeb.zip /opt/electroacoustic-playground/dexed/patch-cache
```

At scene creation, EAP chooses a cached bank/program and applies only tiny operator-output-level changes before sending the patch to Dexed.

## Vital/Vitalium Integration

Vital/Vitalium is treated as a realtime external JACK/MIDI instrument, not as an offline renderer. EAP hosts the installed Vitalium LV2 plugin with `jalv`, chooses an installed Vitalium preset, applies small modifier-specific control tweaks, routes JACK audio back into SuperCollider inputs 3/4, and sends live MIDI notes from the same Pattern sequencer that drives the internal engines.

Use `eap-install-vitalium` on the Pi to build and install Vitalium LV2 plus the `jalv` host and MIDI bridge dependencies. Vital remains visible on the engine selector, but runtime launch is gated behind `EAP_ENABLE_VITAL=1` because the current Pi/JACK profile xruns with live Vitalium enabled.

On the Scales / Root Note page, engine row 4 now maps left to right as: Any, Plaits, Rings, Passersby, Molly, Fold, Dexed, Vital/Vitalium.

## Sound-Type Modifiers

Hold one of the four Up buttons while toggling or long-pressing a bottom-row scene pad to bias generation and regeneration:

| CC | Character |
|----|-----------|
| 19 | Percussive — short envelopes, dense rhythms, punchy materials |
| 29 | Drone / texture — low register, sparse events, clouds and sustain |
| 39 | Harmonic pads — evolving chords, mid register, lush modulation |
| 49 | Chaos — noisy FM, volatile timing, aggressive FX |

Modifier buttons are lit orange; the held button highlights white. With no modifier held, scene generation uses the default random profile. OSC `/eap/slot` accepts an optional third integer argument (1–4) matching the table above.
