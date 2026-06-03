#!/usr/bin/env bash
set -euo pipefail

src_dir="${EAP_VITALIUM_SRC:-/opt/vitalium-src/DISTRHO-Ports}"
repo="${EAP_VITALIUM_REPO:-https://github.com/DISTRHO/DISTRHO-Ports.git}"
branch="${EAP_VITALIUM_BRANCH:-master}"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root or via sudo." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    git meson ninja-build pkg-config qemu-user-static jalv lilv-utils a2jmidid \
    libasound2-dev libjack-jackd2-dev libfreetype-dev libfftw3-dev \
    libgl1-mesa-dev libgles2-mesa-dev libx11-dev libxext-dev \
    libxrender-dev libxcursor-dev

mkdir -p "$(dirname "$src_dir")"
if [[ -d "$src_dir/.git" ]]; then
    git -C "$src_dir" fetch --depth 1 origin "$branch"
    git -C "$src_dir" checkout FETCH_HEAD
else
    rm -rf "$src_dir"
    git clone --depth 1 --recurse-submodules --shallow-submodules --branch "$branch" "$repo" "$src_dir"
fi
git -C "$src_dir" submodule update --init --recursive --depth 1

cd "$src_dir"
rm -rf build-eap-vitalium
export LDFLAGS="${LDFLAGS:-} -latomic"
meson setup build-eap-vitalium \
    --buildtype release \
    -Dplugins=vitalium \
    -Dbuild-lv2=true \
    -Dbuild-vst2=false \
    -Dbuild-vst3=false \
    -Dbuild-juce60-only=true \
    -Dlinux-headless=true \
    -Dneon-optimizations=true
ninja -C build-eap-vitalium
ninja -C build-eap-vitalium install
ldconfig

if ! lv2ls | grep -i vital >/dev/null; then
    echo "Vitalium LV2 installed, but lv2ls cannot see it." >&2
    exit 2
fi

echo "Vitalium LV2 installed:"
lv2ls | grep -i vital
