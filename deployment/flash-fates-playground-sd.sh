#!/usr/bin/env bash
set -euo pipefail

DISK="${DISK:-/dev/disk5}"
IMAGE="${IMAGE:-/Users/nzimas/development/electroacoustic/raspios_lite_armhf_latest.img}"
BACKUP_DIR="${BACKUP_DIR:-/Users/nzimas/development/electroacoustic/hardware/fates-overlays-backup}"
SSID="${SSID:-LMT-866D}"
WIFI_PASSWORD="${WIFI_PASSWORD:-}"
HOSTNAME="${HOSTNAME:-fates-playground}"
USERNAME="${USERNAME:-we}"
USER_PASSWORD="${USER_PASSWORD:-sleep}"
COUNTRY="${COUNTRY:-LV}"

if [[ -z "$WIFI_PASSWORD" ]]; then
  echo "Set WIFI_PASSWORD before running, for example:"
  echo "  sudo WIFI_PASSWORD='...' $0"
  exit 1
fi

if [[ ! -f "$IMAGE" ]]; then
  echo "Image not found: $IMAGE" >&2
  exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "Overlay backup directory not found: $BACKUP_DIR" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo. This script overwrites $DISK." >&2
  exit 1
fi

echo "About to overwrite $DISK with:"
echo "  $IMAGE"
echo
diskutil list "$DISK"
echo
read -r -p "Type FLASH to continue: " CONFIRM
if [[ "$CONFIRM" != "FLASH" ]]; then
  echo "Aborted."
  exit 1
fi

echo "Unmounting $DISK..."
diskutil unmountDisk "$DISK" >/dev/null

RAW_DISK="/dev/r$(basename "$DISK")"
echo "Writing image to $RAW_DISK..."
dd if="$IMAGE" of="$RAW_DISK" bs=4m conv=sync status=progress
sync

echo "Mounting new boot partition..."
diskutil mountDisk "$DISK" >/dev/null || true
sleep 3

BOOT="/Volumes/bootfs"
if [[ ! -d "$BOOT" ]]; then
  BOOT="/Volumes/boot"
fi
if [[ ! -d "$BOOT" ]]; then
  echo "Could not find mounted Raspberry Pi boot partition." >&2
  diskutil list "$DISK"
  exit 1
fi

echo "Using boot partition: $BOOT"

echo "Copying Fates overlays..."
mkdir -p "$BOOT/overlays"
cp "$BACKUP_DIR/rpi-proto.dtbo" "$BOOT/overlays/"
cp "$BACKUP_DIR/fates-ssd1322.dtbo" "$BOOT/overlays/"
cp "$BACKUP_DIR/fates-buttons-4encoders.dtbo" "$BOOT/overlays/"
cp "$BACKUP_DIR/fates-buttons-encoders.dtbo" "$BOOT/overlays/"

CONFIG="$BOOT/config.txt"
if [[ ! -f "$CONFIG" ]]; then
  CONFIG="$BOOT/firmware/config.txt"
fi
if [[ ! -f "$CONFIG" ]]; then
  echo "Could not find config.txt on boot partition." >&2
  exit 1
fi

echo "Appending Fates hardware config to $CONFIG..."
cat >> "$CONFIG" <<'CONFIG_EOF'

# Electroacoustic Playground / Fates hardware
dtparam=i2c_arm=on
dtparam=spi=on
dtparam=i2s=on
dtoverlay=i2s-mmap
enable_uart=1
dtoverlay=rpi-proto
dtoverlay=fates-buttons-4encoders
dtoverlay=fates-ssd1322,rotate=180
dtparam=audio=off
CONFIG_EOF

echo "Enabling SSH..."
touch "$BOOT/ssh"

echo "Creating first-boot customisation..."
HASH="$(openssl passwd -6 "$USER_PASSWORD")"
cat > "$BOOT/userconf.txt" <<USERCONF_EOF
$USERNAME:$HASH
USERCONF_EOF

cat > "$BOOT/wpa_supplicant.conf" <<WPA_EOF
country=$COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$SSID"
    psk="$WIFI_PASSWORD"
}
WPA_EOF

cat > "$BOOT/firstrun.sh" <<FIRST_EOF
#!/bin/bash
set -e

echo "$HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\\t$HOSTNAME/" /etc/hosts || true

systemctl enable ssh || true
systemctl start ssh || true

if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_wifi_country "$COUNTRY" || true
fi

if command -v nmcli >/dev/null 2>&1; then
  nmcli radio wifi on || true
  nmcli dev wifi connect "$SSID" password "$WIFI_PASSWORD" ifname wlan0 || true
fi

install -m 0755 -d /usr/local/sbin
cat > /usr/local/sbin/playground-ready <<'READY_EOF'
#!/bin/sh
printf "\\n\\nSystem ready\\n" > /dev/tty1
READY_EOF
chmod 0755 /usr/local/sbin/playground-ready

cat > /etc/systemd/system/playground-ready.service <<'SERVICE_EOF'
[Unit]
Description=Electroacoustic Playground boot ready message
After=multi-user.target network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/playground-ready

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl enable playground-ready.service || true

rm -f /boot/firstrun.sh
sed -i 's# systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target##' /boot/cmdline.txt || true
reboot
FIRST_EOF
chmod +x "$BOOT/firstrun.sh"

CMDLINE="$BOOT/cmdline.txt"
if [[ ! -f "$CMDLINE" ]]; then
  CMDLINE="$BOOT/firmware/cmdline.txt"
fi
if [[ ! -f "$CMDLINE" ]]; then
  echo "Could not find cmdline.txt on boot partition." >&2
  exit 1
fi

if ! grep -q 'systemd.run=/boot/firstrun.sh' "$CMDLINE"; then
  perl -0pi -e 's/\n?$/ systemd.run=\/boot\/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target\n/' "$CMDLINE"
fi

sync
echo "Done. Ejecting $DISK..."
diskutil eject "$DISK" >/dev/null
echo "SD card is ready for first boot."
