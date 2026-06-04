# Changelog

All notable changes to [Electroacoustic Playground](README.md) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project does not yet use strict semantic versioning tags. Entries follow git history on `main`.

## [Unreleased]

### Added

- VCV Rack as an optional realtime external engine (Launchpad engine row 5, SuperCollider `\vcv` material and note routing).
- Patchstorage cache tooling (`eap-vcv-sync-patches.py`) with per-patch metadata, profiles, and dependency lists.
- VCV patch mutation and runtime loader (`eap-vcv-patch.py`) with modifier-aware parameter tweaks and a Core/Fundamental fallback patch when no cached patch is compatible.
- VCV module resolver (`eap-vcv-modules.py`) to attempt builds of third-party Rack plugins referenced by cached patches.
- Pi installer and services: `eap-install-vcv-rack.sh`, `eap-start-vcv.sh`, `eap-connect-vcv-jack.sh`, `eap-vcv.service`, `eap-vcv-connect.service`.
- README section for VCV Rack installation, patch sync, and enablement via `EAP_ENABLE_VCV=1`.

### Changed

- SuperCollider scene engine: VCV availability, patch load/rescan, MIDI note sending, and adaptive lane metadata for VCV patches.
- Launchpad tuning page: engine selection extended for VCV; OSC `/eap/engine` and `/eap/vcv/rescan` bounds updated.
- Deploy and audio-stack restart scripts: install/stop VCV units; console status no longer hard-depends on optional engine services.
- `bin/eap`: helpers for VCV patch sync and module resolution on the Pi.

### Notes

- VCV remains **disabled by default** (`EAP_ENABLE_VCV=0` in `/etc/default/eap-vcv`) until Pi/JACK stability is confirmed under load.
- Verified on Pi: Rack 2.6.6 Linux ARMv7 builds and runs headless; JACK audio routes to `SuperCollider:in_3/4`. MIDI input wiring for stock `MIDIToCVInterface` still depends on selecting an existing JACK MIDI source.

## 2026-06-04

### Added

- Airwindows grid FX lock: long-press saves randomized plugin state; locked pads show red feedback ([`8b3c895`](https://github.com/nzimas/eap/commit/8b3c895)).
- Targeted Airwindows grid FX page (CC 93): compact 30-effect grid, up to three active inserts, scene toggles on row 1 ([`1aa50e1`](https://github.com/nzimas/eap/commit/1aa50e1)).

## 2026-06-03

### Added

- Gated realtime Vital/Vitalium engine via `jalv`, preset cache, JACK/MIDI routing to SC inputs 3/4 ([`a6ea14f`](https://github.com/nzimas/eap/commit/a6ea14f)).
- Future engine selector on the Launchpad tuning page (row 4: Any, Plaits, Rings, Passersby, Molly, Fold, Dexed, Vital) ([`b3db6d9`](https://github.com/nzimas/eap/commit/b3db6d9)).

### Changed

- Scene performance controls while holding a scene without a modifier: volume, pan, density, timbral movement, reverb send, transpose (rows 2–7) ([`ee8beb8`](https://github.com/nzimas/eap/commit/ee8beb8), [`86fbe21`](https://github.com/nzimas/eap/commit/86fbe21)).
- Modifier-driven scene generation rewritten for clearer percussive, drone, harmonic, and chaos profiles ([`66dd9c3`](https://github.com/nzimas/eap/commit/66dd9c3)).

## 2026-06-02

### Added

- Initial electroacoustic playground stack: SuperCollider lanes, Launchpad control, systemd deployment, master bus ([`11f1d37`](https://github.com/nzimas/eap/commit/11f1d37)).
- Launchpad master dynamics page (CC 89), later moved from earlier CC ([`df9e27c`](https://github.com/nzimas/eap/commit/df9e27c), [`77aa7ab`](https://github.com/nzimas/eap/commit/77aa7ab)).
- Eight Launchpad session slots with active-slot highlighting ([`8f08ccc`](https://github.com/nzimas/eap/commit/8f08ccc), [`880b4ec`](https://github.com/nzimas/eap/commit/880b4ec)).
- Pattern-based scene event scheduling ([`22b78e0`](https://github.com/nzimas/eap/commit/22b78e0)).
- Pitch constraints across engines ([`9a6e366`](https://github.com/nzimas/eap/commit/9a6e366)).
- Molly and Passersby palette refinements ([`221b995`](https://github.com/nzimas/eap/commit/221b995)).
- Launchpad tuning page (scales, root note, modifiers) ([`ac6643a`](https://github.com/nzimas/eap/commit/ac6643a)).
- Headless Dexed integration: Xvfb host, JACK wiring, DX7 patch cache, `\dexed` material ([`46f0fbd`](https://github.com/nzimas/eap/commit/46f0fbd), [`c82522d`](https://github.com/nzimas/eap/commit/c82522d)).
- Automatic EAP boot on stack start ([`add74d7`](https://github.com/nzimas/eap/commit/add74d7)).
- Fates K3 graceful shutdown handling ([`faf934e`](https://github.com/nzimas/eap/commit/faf934e)).

### Changed

- Master saturation made more aggressive ([`9e80ac6`](https://github.com/nzimas/eap/commit/9e80ac6)).
- Console status display simplified and flicker reduced; Launchpad status line restored ([`9f76f7c`](https://github.com/nzimas/eap/commit/9f76f7c), [`bf9c4a4`](https://github.com/nzimas/eap/commit/bf9c4a4), [`6bf0cc7`](https://github.com/nzimas/eap/commit/6bf0cc7)).
