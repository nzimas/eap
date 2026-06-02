# Electroacoustic Playground

Electroacoustic Playground is a bespoke Raspberry Pi/Fates instrument stack built around SuperCollider, a Launchpad Mini Mk3 control layer, Mutable Instruments-inspired engines, Passersby/Molly sound material, pedalboard effects, and a shared master reverb.

The current stack includes:

- SuperCollider scene-slot engine with up to eight Launchpad-addressable scene slots.
- Random scene generation from Plaits, Rings, Passersby, Molly, and fold-based material.
- Per-scene pedalboard or Clouds-style effects, bounded for CPU safety.
- Launchpad Mini Mk3 controller daemon with scene toggles, long-press regeneration, LED states, and a master reverb page.
- Systemd units and deployment helpers for the Fates/Pi environment.

Primary runtime files:

- `supercollider/Scene_RandomLanes.scd`
- `supercollider/boot.scd`
- `control/eap_launchpad.py`
- `bin/eap`
- `deployment/systemd/`
