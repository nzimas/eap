#!/bin/sh
set -eu

repo_url="${EAP_AIRWINDOWS_REPO:-https://github.com/airwindows/airwindows.git}"
src_dir="${EAP_AIRWINDOWS_SRC_DIR:-/opt/eap-src/airwindows}"
build_dir="$src_dir/build"
lv2_dir="${EAP_AIRWINDOWS_LV2_DIR:-/usr/local/lib/lv2}"

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates git build-essential pkg-config libjack-jackd2-dev lv2-dev lilv-utils jalv

mkdir -p "$(dirname "$src_dir")" "$lv2_dir" /usr/local/lib/eap

if [ ! -d "$src_dir/.git" ]; then
    rm -rf "$src_dir"
    git clone --depth 1 "$repo_url" "$src_dir"
else
    git -C "$src_dir" fetch --depth 1 origin
    git -C "$src_dir" reset --hard FETCH_HEAD
fi

rm -rf "$build_dir"
python3 /usr/local/bin/eap-build-airwindows-lv2 "$src_dir" "$build_dir" "$lv2_dir"
python3 /usr/local/bin/eap-build-airwindows-host "$src_dir" "$src_dir/host-build" /usr/local/bin/eap-airwindows-host
chmod 0755 /usr/local/bin/eap-airwindows-host

ldconfig

missing=""
for fx in \
    TapeDelay2 PitchDelay Doublelay SampleDelay Melt ADT StarChild2 TakeCare \
    RingModulator Dubly3 GalacticVibe Pafnuty2 PitchNasty GuitarConditioner GlitchShifter Gringer \
    Nikola HipCrush DeRez3 Pockey2 CrunchyGrooveWear BitGlitter TapeBias Vibrato \
    Deckwrecka DeNoise Texturize VoiceOfTheStarship ElectroHat Silhouette
do
    if ! lv2ls | grep -qx "https://electroacoustic.local/lv2/airwindows/$fx"; then
        missing="$missing $fx"
    fi
done

if [ -n "$missing" ]; then
    echo "Airwindows LV2 installed, but these requested FX were not visible to lv2ls:$missing" >&2
    exit 2
fi

echo "Airwindows LV2 installed and requested EAP grid FX are visible."
