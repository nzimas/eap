#!/usr/bin/env bash
set -euo pipefail

DISK="${DISK:-/dev/disk5}"
IMAGE_URL="${IMAGE_URL:-https://ia903103.us.archive.org/0/items/fates-pi4b-20220328.img/fates-pi4b-20220401.img.zip}"
IMAGE_URL_FALLBACK="${IMAGE_URL_FALLBACK:-https://ia803103.us.archive.org/0/items/fates-pi4b-20220328.img/fates-pi4b-20220401.img.zip}"
IMAGE_ZIP="${IMAGE_ZIP:-/Volumes/DataBackup/Temp/fates-pi4b-20220401.img.zip}"
SSID="${SSID:-LMT-866D}"
WIFI_PASSWORD="${WIFI_PASSWORD:-}"
COUNTRY="${COUNTRY:-LV}"

if [[ -z "$WIFI_PASSWORD" ]]; then
  echo "Set WIFI_PASSWORD before running, for example:" >&2
  echo "  sudo WIFI_PASSWORD='...' $0" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo. This script overwrites $DISK." >&2
  exit 1
fi

echo "Official Fates Pi 4B image:"
echo "  $IMAGE_URL"
echo
echo "Target disk:"
diskutil list "$DISK"
echo
echo "This will erase $DISK completely."
read -r -p "Type FLASH-FATES to continue: " CONFIRM
if [[ "$CONFIRM" != "FLASH-FATES" ]]; then
  echo "Aborted."
  exit 1
fi

if [[ ! -f "$IMAGE_ZIP" ]]; then
  echo "Downloading Fates Pi 4B image to:"
  echo "  $IMAGE_ZIP"
  curl -L --fail --progress-bar "$IMAGE_URL" -o "$IMAGE_ZIP" || {
    echo "Primary download failed; trying fallback mirror:"
    echo "  $IMAGE_URL_FALLBACK"
    rm -f "$IMAGE_ZIP"
    curl -L --fail --progress-bar "$IMAGE_URL_FALLBACK" -o "$IMAGE_ZIP"
  }
fi

IMAGE_ENTRY="$(unzip -Z -1 "$IMAGE_ZIP" | grep -E '\.img$' | head -n 1)"
if [[ -z "$IMAGE_ENTRY" ]]; then
  echo "Could not find a .img file inside $IMAGE_ZIP" >&2
  unzip -Z -1 "$IMAGE_ZIP" >&2
  exit 1
fi

echo "Unmounting $DISK..."
diskutil unmountDisk "$DISK" >/dev/null || true

RAW_DISK="/dev/r$(basename "$DISK")"
echo "Writing image to $RAW_DISK..."
echo "  ZIP entry: $IMAGE_ENTRY"
unzip -p "$IMAGE_ZIP" "$IMAGE_ENTRY" | dd of="$RAW_DISK" bs=4m status=progress
sync

echo "Mounting boot partition..."
diskutil mountDisk "$DISK" >/dev/null || true
sleep 5

BOOT=""
for candidate in /Volumes/boot /Volumes/bootfs; do
  if [[ -d "$candidate" && -f "$candidate/config.txt" ]]; then
    BOOT="$candidate"
    break
  fi
done

if [[ -z "$BOOT" ]]; then
  echo "Could not find the mounted Fates boot partition." >&2
  diskutil list "$DISK"
  exit 1
fi

echo "Using boot partition: $BOOT"

echo "Enabling SSH and adding first-boot Wi-Fi config..."
touch "$BOOT/ssh"
cat > "$BOOT/wpa_supplicant.conf" <<WPA_EOF
country=$COUNTRY
update_config=1
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev

network={
  scan_ssid=1
  ssid="$SSID"
  psk="$WIFI_PASSWORD"
  key_mgmt=WPA-PSK
}
WPA_EOF

cat > "$BOOT/ELECTROACOUSTIC_PLAYGROUND_FATES_FLASH.txt" <<MARKER_EOF
Official Fates Pi 4B image flashed.

Image URL: $IMAGE_URL
ZIP entry: $IMAGE_ENTRY
Wi-Fi SSID: $SSID
Wi-Fi country: $COUNTRY
SSH: enabled
Default login expected: we / sleep

After first boot, try:
  ssh we@fates.local
or find the assigned IP in the router and use:
  ssh we@<ip-address>
MARKER_EOF

sync
echo "Ejecting $DISK..."
diskutil eject "$DISK" >/dev/null
echo "Done. Insert the SD card into the Fates/Raspberry Pi and power it on."
