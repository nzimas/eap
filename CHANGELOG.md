# Changelog

All notable changes to [Electroacoustic Playground](README.md) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project does not yet use strict semantic versioning tags. Entries follow git history on `main`.

## [Unreleased]

## 2026-06-07

### Added

- Subsequence rhythm bridge (`eap-subsequence-bridge.py`, `eap_subsequence_lanes.py`, `eap-subsequence.service`) with algorithmic percussive and chaos profile builders (euclidean variants, CA, Lorenz, de Bruijn, reaction–diffusion, and related structures — no genre-named profiles).
- Launchpad slot-state OSC feedback (`/eap/slots/query`, `/eap/slots/state`) and startup wait until SuperCollider responds.
- User guide: [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md).
- VCV Rack optional engine: Patchstorage cache (`eap-vcv-sync-patches.py`), patch loader/mutation (`eap-vcv-patch.py`), module resolver (`eap-vcv-modules.py`), seed installer, bundled patch cache, Pi services (`eap-vcv.service`, `eap-vcv-connect.service`), and SuperCollider `\vcv` material/routing.

### Changed

- Launchpad scene generation: modifier latch, generate at long-press threshold while held, longer OSC reply wait; chaos modifier on CC 39 (CC 49 retired).
- SuperCollider scene engine: Subsequence lane sync, expanded chaos stochasticity (rhythm + timbre), master compression bypass on profile 0, drone lane sustain fixes, async Airwindows grid-FX clear on start/stop.
- JACK profile: period raised to 2048 frames; SuperCollider block size matched; `memoryLocking` enabled (`scsynth -L`); empty default inputs, explicit playback outputs, no SC self-routing.
- Load governor: Clouds FX disabled with 2+ active lanes, single pedal per lane under load, master reverb wet scaled down as lane count grows.
- VCV: compatibility reindexing, seed patch install, no synthetic fallback when cache has no compatible patch; deploy enables subsequence install/restart.
- README: link to user guide; updated modifier table and VCV workflow.

### Fixed

- Dead scene slot pads: removed `eap-airwindows-grid-fx.sh` infinite exec loop; install Python grid-FX helper; fixed `~triggerLane` variable ordering parse error.
- Launchpad generation ignored when modifier CC released before slot pad release.
- JACK xrun storms from SuperCollider input self-routing, page faults, and per-block overload under multiple active lanes.

### Notes

- VCV remains **disabled by default** on deploy (`EAP_ENABLE_VCV=0`) until Pi/JACK stability is confirmed under load.

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
