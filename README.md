# Electroacoustic Playground

Electroacoustic Playground is a bespoke Raspberry Pi/Fates instrument stack built around SuperCollider, a Launchpad Mini Mk3 control layer, Mutable Instruments-inspired engines, Passersby/Molly sound material, pedalboard effects, and a shared master reverb.

**User documentation:** [docs/USER_GUIDE.md](docs/USER_GUIDE.md) — Launchpad pages, parameter positions, gestures, sessions, and Pi operation.

The current stack includes:

- SuperCollider scene-slot engine with up to eight Launchpad-addressable scene slots.
- Random scene generation from the six in-engine SC voices: Plaits, Rings, Passersby, Molly, FM7, and Harmonium. The Dexed and Vital/Vitalium infrastructure remains in the stack but is not currently exposed on the engine selector.
- Per-scene pedalboard or Clouds-style effects, bounded for CPU safety.
- Launchpad Mini Mk3 controller daemon with scene toggles, long-press regeneration, sound-type modifiers (CC 19/29/39), LED states, and auxiliary pages for reverb, tuning, master dynamics, and sessions.
- Systemd units and deployment helpers for the Fates/Pi environment.

Primary runtime files:

- `supercollider/Scene_RandomLanes.scd`
- `supercollider/boot.scd`
- `control/eap_launchpad.py`
- `bin/eap`
- `deployment/systemd/`

## Dexed Integration

Note: Dexed is not currently exposed on the engine selector. The infrastructure below remains in place and can be re-enabled when needed.

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

Note: Vital/Vitalium is not currently exposed on the engine selector. The infrastructure below remains in place and can be re-enabled when needed.

Vital/Vitalium is treated as a realtime external JACK/MIDI instrument, not as an offline renderer. EAP hosts the installed Vitalium LV2 plugin with `jalv`, chooses an installed Vitalium preset, applies small modifier-specific control tweaks, routes JACK audio back into SuperCollider inputs 3/4, and sends live MIDI notes from the same Pattern sequencer that drives the internal engines.

Use `eap-install-vitalium` on the Pi to build and install Vitalium LV2 plus the `jalv` host and MIDI bridge dependencies.

On the Scales / Root Note page, engine row 4 maps left to right (pads 41–46) as: Plaits, Rings, Passersby, Molly, FM7, Harmonium. VCV Rack infrastructure remains in the stack, but VCV is not currently exposed as a selectable scene engine.

## VCV Rack Integration

VCV Rack is currently disabled as a selectable scene engine while its infrastructure remains in place. The retained stack can start Rack 2 in headless mode with a cached `.vcv` patch, lightly mutate compatible patch parameters, route Rack audio back into SuperCollider inputs 3/4, and send live MIDI notes from the same scale-aware sequencer used by the other engines when re-enabled.

Use `eap-install-vcv-rack` on the Pi to build Rack for ARM64, install Fundamental, and create `/usr/local/bin/eap-rack`. Use `eap-vcv-install-seeds` to install the bundled Core/Fundamental MIDI performance patch, `eap-vcv-sync-patches` to cache Patchstorage patches, and `eap-vcv-sync-patches --reindex` to refresh compatibility flags. Only patches with installed modules and audio/MIDI capability are used; EAP does not synthesize fallback patches when the cache has no compatible entry. Runtime launch is gated behind `EAP_ENABLE_VCV=1` (enabled by the installer default).

## Airwindows Grid FX

The CC 93 button toggles a global Airwindows grid FX page. Row 1 mirrors the scene slots: active scenes are lit and selected scenes glow brighter, allowing the Airwindows chain to target specific scenes. The usable effects are compacted left-to-right from row 2, currently covering 30 selected Airwindows effects; up to three can be active at once. Activating a fourth effect drops the oldest active effect, and each activation randomizes that plugin's parameters.

Long-pressing an Airwindows FX pad locks its current/randomized parameter state. Locked pads flicker red and remain red while locked; short presses still toggle the effect on and off, but re-enabling a locked effect recalls the saved parameter seed until the pad is long-pressed again.

Use `eap-install-airwindows` on the Pi to build the exact Airwindows wrappers and persistent JACK host. The grid FX run as an external insert only while active: SuperCollider sends the scene mix out on outputs 3/4, the active Airwindows chain returns on inputs 1/2, and the processed signal enters EAP immediately before the master reverb/dynamics stage.

## Sound-Type Modifiers

Hold one of the four Up buttons while toggling or long-pressing a bottom-row scene pad to bias generation and regeneration:

| CC | Character |
|----|-----------|
| 19 | Percussive — short envelopes, dense rhythms, punchy materials |
| 29 | Drone / texture — low register, sparse events, clouds and sustain |
| 39 | Chaos — noisy FM, volatile timing, aggressive FX |

Modifier buttons are lit orange; the held button highlights white. With no modifier held, scene generation uses the default random profile. OSC `/eap/slot` accepts an optional third integer argument (1–3) matching the table above.
