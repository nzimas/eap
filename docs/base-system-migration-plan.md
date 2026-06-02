# Base System Migration Plan

Goal: replace the norns image on the Fates/Norns Shield Raspberry Pi 4B with a minimal Raspberry Pi OS system that boots directly into a native SuperCollider-based electroacoustic instrument.

This is not a norns fork. Norns software, services, workflows, UI, and script compatibility are intentionally out of scope.

## Target Behavior

- Headless operation.
- SSH administration.
- Wi-Fi works on first boot.
- No desktop environment.
- Native JACK/ALSA audio.
- Native SuperCollider runtime.
- No Docker on the Raspberry Pi.
- Screen shows normal boot sequence, then a final ready message.
- Launchpad Mini MK3 becomes the primary performance interface in later milestones.

## Recommended Flashing Strategy

Use a locally attached microSD card on the MacBook and write a fresh Raspberry Pi OS Lite image.

This is safer than attempting an in-place remote conversion because the currently running system lives on the card that would be overwritten. A remote reimage of the active root filesystem is possible only with extra boot/recovery machinery and is not worth the risk for this phase.

Recommended image:

- Raspberry Pi OS Lite, 32-bit or 64-bit.
- For maximum compatibility with the existing armv7/norns-era kernel modules, start with 32-bit unless a later requirement needs 64-bit.

Use Raspberry Pi Imager OS customisation:

- Hostname: `playground` or `fates-playground`.
- User: `we` or a new project-specific admin user.
- Enable SSH.
- Configure Wi-Fi SSID/password and wireless country before first boot.
- Set timezone and keyboard locale.

## Hardware Compatibility Requirements

Current working norns/Fates card uses:

```text
dtparam=i2c_arm=on
dtparam=spi=on
dtparam=i2s=on
dtoverlay=i2s-mmap
enable_uart=1
dtoverlay=rpi-proto
dtoverlay=fates-buttons-4encoders
dtoverlay=fates-ssd1322,rotate=180
dtparam=audio=off
```

Current audio hardware:

- ALSA card: `snd_rpi_proto`
- Codec: WM8731
- Playback/capture: stereo, 48 kHz capable
- Required modules observed:
  - `snd_soc_rpi_proto`
  - `snd_soc_wm8731`
  - `snd_soc_bcm2835_i2s`

Current display hardware:

- Framebuffer: `/dev/fb0`
- Driver/name: `fb_ssd1322`
- Overlay: `fates-ssd1322,rotate=180`

Before destroying the old card, preserve these overlay files if the fresh Raspberry Pi OS image does not include them:

```text
/boot/overlays/rpi-proto.dtbo
/boot/overlays/fates-ssd1322.dtbo
/boot/overlays/fates-buttons-4encoders.dtbo
/boot/overlays/fates-buttons-encoders.dtbo
```

Also preserve current kernel modules as reference material:

```text
snd-soc-rpi-proto.ko
snd-soc-wm8731.ko
```

The preferred path is to use packaged/in-tree drivers where available. Copying old kernel modules into a new kernel is not expected to work unless the kernel versions match.

## First-Boot Provisioning

After the fresh OS boots and SSH works:

1. Update package metadata.
2. Install audio and development tools.
3. Configure realtime audio privileges.
4. Configure JACK against `hw:sndrpiproto`.
5. Install SuperCollider.
6. Add a minimal systemd service that starts JACK.
7. Add a minimal systemd service that starts a SuperCollider smoke test.
8. Add a final boot-status service that writes `System ready` to `/dev/tty1` after audio services are active.

Initial packages are expected to include:

```text
supercollider
supercollider-server
jackd2
alsa-utils
aconnectgui optional, but not for production
git
build-essential
cmake
libasound2-dev
libjack-jackd2-dev
```

Package names may need adjustment based on the Raspberry Pi OS release.

## Boot Screen

Keep Linux console boot output visible.

Do not install a desktop or graphical splash layer for the first pass.

Create a oneshot systemd service ordered after the instrument services:

```text
After=network-online.target jack.service playground.service
```

The service should clear or append to tty1 and print:

```text
System ready
```

Later, this can become a small framebuffer status display, but the first version should stay simple.

## Validation Checklist

- Pi appears on Wi-Fi after first boot.
- SSH login works without local keyboard/display.
- `/boot/firmware/config.txt` or `/boot/config.txt` contains the required Fates overlays.
- `aplay -l` shows `snd_rpi_proto` / WM8731.
- `arecord -l` shows matching stereo capture.
- `jackd` starts at 48 kHz.
- `sclang` and `scsynth` run.
- A SuperCollider test tone reaches the physical output.
- Physical input can be captured or monitored.
- `/dev/fb0` exists and reports `fb_ssd1322`.
- Boot screen ends with `System ready`.

## Open Questions

- Whether the current Raspberry Pi OS Lite kernel includes `rpi-proto` and `fates-ssd1322` overlays.
- Whether to start with Raspberry Pi OS Lite 32-bit for driver continuity or 64-bit for future performance/headroom.
- Whether Launchpad support should be implemented directly in SuperCollider MIDI, via a small companion daemon, or as a separate controller layer process.
