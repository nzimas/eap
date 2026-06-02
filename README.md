# Electroacoustic Playground

Electroacoustic Playground is a bespoke Raspberry Pi/Fates instrument stack built around SuperCollider, a Launchpad Mini Mk3 control layer, Mutable Instruments-inspired engines, Passersby/Molly sound material, pedalboard effects, and a shared master reverb.

The current stack includes:

- SuperCollider scene-slot engine with up to eight Launchpad-addressable scene slots.
- Random scene generation from Plaits, Rings, Passersby, Molly, fold-based material, and optional external Dexed.
- Per-scene pedalboard or Clouds-style effects, bounded for CPU safety.
- Launchpad Mini Mk3 controller daemon with scene toggles, long-press regeneration, LED states, and a master reverb page.
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
