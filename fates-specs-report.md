# Fates Hardware and Audio Specs Report

Generated: 2026-06-01
Host: `fates`
Address inspected: `192.168.8.241`

## Platform

- Device model: Raspberry Pi 4 Model B Rev 1.5
- OS: Raspbian GNU/Linux 10 `buster`
- Kernel: Linux `5.10.103-v7l+` armv7l
- System image/banner: monome norns

## CPU

- Architecture: ARMv7 little-endian
- CPU: ARM Cortex-A72
- Cores: 4
- Threads per core: 1
- Frequency range: 600 MHz to 1.5 GHz
- Reported flags: VFP, NEON, VFPv3, VFPv4, LPAE, CRC32, hardware integer divide

## Memory

- RAM total: 1.8 GiB
- RAM used during inspection: 285 MiB
- RAM available during inspection: 1.4 GiB
- Swap total: 1.6 GiB
- Swap used during inspection: 0 B

## Audio Hardware

- ALSA card: `snd_rpi_proto`
- Codec/device: WM8731 HiFi `wm8731-hifi-0`
- Playback: stereo, card 0 device 0
- Capture: stereo, card 0 device 0
- USB audio devices: none detected
- PCI audio devices: none detected

## Active Audio Engine

JACK is started by the norns system service:

```text
/usr/bin/jackd -R -P 95 -d alsa -d hw:sndrpiproto -r 48000 -n 3 -p 128 -S -s
```

Derived settings:

- JACK backend: ALSA
- ALSA device: `hw:sndrpiproto`
- Sample rate: 48 kHz
- Period size: 128 frames
- Periods/buffer count: 3
- Buffer size: 384 frames
- Sample format observed at ALSA layer: `S16_LE`
- Channels: 2 input, 2 output
- Realtime priority: 95

The ALSA hardware params matched the JACK service configuration for both playback and capture:

```text
channels: 2
rate: 48000
period_size: 128
buffer_size: 384
```

## Running Norns Audio Services

- `norns-jack.service`: running `jackd`
- `norns-crone.service`: running `/home/we/norns/build/crone/crone`
- `norns-sclang.service`: running SuperCollider language and `scsynth`
- `norns-matron.service`: running matron through `ws-wrapper`
- `norns-maiden.service`: running maiden
- `norns-watcher.service`: running watcher

Observed audio-related processes:

- `jackd`
- `crone`
- `sclang`
- `scsynth -u 57110 -a 1024 -i 2 -o 2 -R 0 -C 1 -l 1`
- `matron`

## Audio Routing

The hardware side is a stereo WM8731 codec exposed as one ALSA card:

```text
system capture/playback <-> JACK <-> norns crone / softcut / SuperCollider
```

SuperCollider/norns boot code explicitly connects:

```text
crone:output_5 -> SuperCollider:in_1
crone:output_6 -> SuperCollider:in_2
SuperCollider:out_1 -> crone:input_5
SuperCollider:out_2 -> crone:input_6
```

This indicates the norns routing model:

- Physical stereo input enters JACK through the WM8731/snd_rpi_proto ALSA device.
- `crone` handles core audio routing/mixing, softcut, monitoring, tape/reverb/compressor paths, and communication with matron.
- SuperCollider is connected as a stereo engine path through crone ports 5/6.
- Final stereo output returns through JACK to the WM8731 hardware playback pair.

## Mixer State

- Master playback: 98%, +3.00 dB left/right
- Input mux: Line In
- Capture gain: 97%, +10.50 dB left/right
- Line capture switch: off at ALSA mixer level
- Mic capture switch: off
- ADC high-pass filter: on
- Output mixer HiFi: on
- Output mixer line bypass: off
- Output mixer mic sidetone: off

## Notes

- `pactl` produced no PulseAudio/PipeWire information; this host appears to use JACK directly rather than PulseAudio or PipeWire for the norns audio path.
- `jack_lsp` from the SSH login could not connect to the running JACK server, even though `norns-jack.service` and the `jackd` process are active. The report therefore uses the systemd service, process list, ALSA hardware params, and norns source-level connection calls as the basis for routing.
- `norns-jack.service` logs showed recent XRUN/process errors involving `crone`, `softcut`, and SuperCollider. That may be worth investigating if audio glitches are being heard.
