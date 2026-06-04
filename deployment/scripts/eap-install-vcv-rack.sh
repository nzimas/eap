#!/usr/bin/env bash
# Build/install headless-capable VCV Rack for the EAP Pi stack.
set -euo pipefail

rack_src="${EAP_RACK_SRC:-/opt/vcv-rack-src/Rack}"
rpi_src="${EAP_VCV_RPI_SRC:-/opt/vcv-rack-src/VCVRack-rpi}"
rack_parent="$(dirname "$rack_src")"
rack_repo="${EAP_RACK_REPO:-https://github.com/VCVRack/Rack.git}"
rack_branch="${EAP_RACK_BRANCH:-v2}"
rpi_repo="${EAP_VCV_RPI_REPO:-https://github.com/DragonForgedTheArtist/VCVRack-rpi.git}"
fundamental_repo="${EAP_VCV_FUNDAMENTAL_REPO:-https://github.com/VCVRack/Fundamental.git}"
build_jobs="${EAP_RACK_BUILD_JOBS:-$(nproc)}"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root or via sudo." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    autoconf automake ca-certificates cmake curl g++ gcc git jq libasound2-dev \
    libglu1-mesa-dev libgtk-3-dev libjack-jackd2-dev libpulse-dev libx11-dev \
    libtool libtool-bin libxcursor-dev libxinerama-dev libxi-dev libxrandr-dev make markdown \
    pkg-config unzip zlib1g-dev zstd

mkdir -p "$rack_parent"
chown -R we:we "$rack_parent" 2>/dev/null || true
if [[ -d "$rpi_src/.git" ]]; then
    git -C "$rpi_src" fetch --depth 1 origin main
    git -C "$rpi_src" checkout FETCH_HEAD
else
    rm -rf "$rpi_src"
    git clone --depth 1 "$rpi_repo" "$rpi_src"
fi

if [[ -d "$rack_src/.git" ]]; then
    git -C "$rack_src" fetch --depth 1 origin "$rack_branch"
    git -C "$rack_src" checkout FETCH_HEAD
else
    rm -rf "$rack_src"
    git clone --depth 1 --branch "$rack_branch" "$rack_repo" "$rack_src"
fi

cd "$rack_src"
git submodule update --init --recursive --depth 1
if [[ -f "$rpi_src/patches/Rack-arm.patch" ]] && patch --dry-run -p1 < "$rpi_src/patches/Rack-arm.patch" >/dev/null 2>&1; then
    patch -p1 < "$rpi_src/patches/Rack-arm.patch"
fi
python3 - <<'PY'
import shutil
from pathlib import Path

arch = Path("arch.mk")
raw_lines = arch.read_text().splitlines()
lines = []
index = 0
while index < len(raw_lines):
    line = raw_lines[index]
    if line == "else ifneq (,$(findstring arm-linux-gnueabihf,$(MACHINE)))":
        index += 1
        while index < len(raw_lines) and not raw_lines[index].startswith("else") and not raw_lines[index].startswith("$(error"):
            index += 1
        continue
    if not line.startswith("OBJ_FORMAT :=") and not line.startswith("ARCH_FLAG :="):
        lines.append(line)
    index += 1
out = ["OBJ_FORMAT := elf64-x86-64", "ARCH_FLAG := i386:x86-64"]
inserted_armhf = False
for index, line in enumerate(lines):
    if (
        not inserted_armhf
        and line == "else"
        and index + 1 < len(lines)
        and "Could not determine CPU architecture" in lines[index + 1]
    ):
        out.append("else ifneq (,$(findstring arm-linux-gnueabihf,$(MACHINE)))")
        out.append("ARCH_ARM := 1")
        out.append("ARCH_CPU := armv7")
        out.append("OBJ_FORMAT := elf32-littlearm")
        out.append("ARCH_FLAG := arm")
        inserted_armhf = True
    out.append(line)
    if line == "ARCH_CPU := armv7":
        out.append("OBJ_FORMAT := elf32-littlearm")
        out.append("ARCH_FLAG := arm")
    if line == "ARCH_CPU := arm64":
        out.append("OBJ_FORMAT := elf64-littleaarch64")
        out.append("ARCH_FLAG := aarch64")
arch.write_text("\n".join(out) + "\n")

compile_mk = Path("compile.mk")
text = compile_mk.read_text()
text = text.replace(
    "$(OBJCOPY) -I binary -O elf64-x86-64 -B i386:x86-64",
    "$(OBJCOPY) -I binary -O $(OBJ_FORMAT) -B $(ARCH_FLAG)",
)
arm_flags = "ifdef ARCH_ARM\n\tFLAGS += -DARCH_ARM -DARCH_LIN -march=armv7-a -mfpu=neon -mfloat-abi=hard\nendif\n"
lines = text.splitlines()
cleaned = []
index = 0
while index < len(lines):
    if lines[index] == "ifdef ARCH_ARM":
        index += 1
        while index < len(lines) and lines[index] != "endif":
            index += 1
        index += 1
        continue
    cleaned.append(lines[index])
    index += 1
text = "\n".join(cleaned) + "\n"
text = text.replace(
    "ifdef ARCH_ARM64\n\tFLAGS += -march=armv8-a+fp+simd\nendif\n",
    "ifdef ARCH_ARM64\n\tFLAGS += -march=armv8-a+fp+simd\nendif\n" + arm_flags,
)
compile_mk.write_text(text)

makefile = Path("Makefile")
text = makefile.read_text()
if "ifdef ARCH_ARM\n\tLDFLAGS += -latomic" not in text:
    text = text.replace(
        "ifdef ARCH_LIN\n\tSED := sed -i\n\tTARGET := libRack.so",
        "ifdef ARCH_LIN\n\tSED := sed -i\n\tTARGET := libRack.so",
    )
    text = text.replace(
        "\tLDFLAGS += -lpthread -lGL -ldl -lX11 -lasound -ljack -lpulse -lpulse-simple\nendif",
        "\tLDFLAGS += -lpthread -lGL -ldl -lX11 -lasound -ljack -lpulse -lpulse-simple\nifdef ARCH_ARM\n\tLDFLAGS += -latomic\nendif\nendif",
    )
    text = text.replace(
        "\tSTANDALONE_LDFLAGS += -Wl,-rpath=.\nendif",
        "\tSTANDALONE_LDFLAGS += -Wl,-rpath=.\nifdef ARCH_ARM\n\tSTANDALONE_LDFLAGS += -latomic\nendif\nendif",
    )
makefile.write_text(text)

common_cpp = Path("src/common.cpp")
text = common_cpp.read_text()
if "defined ARCH_ARM\n\tconst std::string APP_CPU = \"armv7\";" not in text:
    text = text.replace(
        "#elif defined ARCH_ARM64\n\tconst std::string APP_CPU = \"arm64\";\n\tconst std::string APP_CPU_NAME = \"ARM64\";\n#endif",
        "#elif defined ARCH_ARM64\n\tconst std::string APP_CPU = \"arm64\";\n\tconst std::string APP_CPU_NAME = \"ARM64\";\n#elif defined ARCH_ARM\n\tconst std::string APP_CPU = \"armv7\";\n\tconst std::string APP_CPU_NAME = \"ARMv7\";\n#endif",
    )
common_cpp.write_text(text)

system_cpp = Path("src/system.cpp")
text = system_cpp.read_text()
if "#elif defined ARCH_ARM\n\treturn 0;" not in text:
    text = text.replace(
        "#elif defined ARCH_ARM64\n\tuint64_t fpcr;\n\t__asm__ volatile(\"mrs %0, fpcr\" : \"=r\" (fpcr));\n\treturn fpcr;\n#endif",
        "#elif defined ARCH_ARM64\n\tuint64_t fpcr;\n\t__asm__ volatile(\"mrs %0, fpcr\" : \"=r\" (fpcr));\n\treturn fpcr;\n#elif defined ARCH_ARM\n\treturn 0;\n#endif",
    )
system_cpp.write_text(text)

standalone_cpp = Path("adapters/standalone.cpp")
text = standalone_cpp.read_text()
if "#include <thread>" not in text:
    text = text.replace("#include <getopt.h>\n", "#include <getopt.h>\n#include <chrono>\n#include <thread>\n")
text = text.replace(
    '\tif (settings::headless) {\n\t\tprintf("Press enter to exit.\\n");\n\t\tgetchar();\n\t}',
    '\tif (settings::headless) {\n\t\tprintf("Headless Rack running. Send SIGTERM to exit.\\n");\n\t\twhile (true) {\n\t\t\tstd::this_thread::sleep_for(std::chrono::seconds(1));\n\t\t}\n\t}',
)
text = text.replace(
    "if (logger::wasTruncated() && osdialog_message(",
    "if (!settings::headless && logger::wasTruncated() && osdialog_message(",
)
standalone_cpp.write_text(text)

dep_make = Path("dep/Makefile")
text = dep_make.read_text()
text = text.replace(
    'cd openssl-3.3.2 && ./Configure --prefix="$(DEP_PATH)" --libdir=lib no-zlib no-capieng no-pinshared no-apps no-tests no-docs no-ui-console',
    'cd openssl-3.3.2 && ./Configure --prefix="$(DEP_PATH)" --libdir=lib no-asm no-zlib no-capieng no-pinshared no-apps no-tests no-docs no-ui-console',
)
text = text.replace(
    'cd openssl-3.3.2 && ./Configure --prefix="$(DEP_PATH)" --libdir=lib no-asm no-zlib no-capieng no-pinshared no-apps no-tests no-docs no-ui-console\n\t$(MAKE) -C openssl-3.3.2\n\t$(MAKE) -C openssl-3.3.2 install_sw',
    'cd openssl-3.3.2 && ./Configure --prefix="$(DEP_PATH)" --libdir=lib no-asm no-zlib no-capieng no-pinshared no-apps no-tests no-docs no-ui-console\n\t$(MAKE) -C openssl-3.3.2\n\t$(MAKE) -C openssl-3.3.2 install_sw\n\tgrep -q -- "-latomic" lib/pkgconfig/libcrypto.pc || sed -i \'/^Libs:/ s/$$/ -latomic/\' lib/pkgconfig/libcrypto.pc',
)
text = text.replace(
    'cd curl-8.10.0 && PKG_CONFIG_PATH= ./configure',
    'cd curl-8.10.0 && PKG_CONFIG_PATH= LIBS="-latomic" ./configure',
)
text = text.replace(
    'cd curl-8.10.0 && PKG_CONFIG_PATH= $(CONFIGURE) $(CURL_FLAGS)',
    'cd curl-8.10.0 && PKG_CONFIG_PATH= LIBS="-latomic" $(CONFIGURE) $(CURL_FLAGS)',
)
dep_make.write_text(text)

openssl_config = Path("dep/openssl-3.3.2/configdata.pm")
if openssl_config.exists() and "no-asm" not in openssl_config.read_text(errors="ignore"):
    shutil.rmtree("dep/openssl-3.3.2")
    for artifact in ("dep/lib/libcrypto.a", "dep/lib/libssl.a", "dep/lib/libcrypto.so", "dep/lib/libssl.so"):
        path = Path(artifact)
        if path.exists():
            path.unlink()
curl_config = Path("dep/curl-8.10.0/config.status")
if curl_config.exists():
    curl_config.unlink()
for artifact in ("dep/lib/libcrypto.so", "dep/lib/libssl.so"):
    path = Path(artifact)
    if path.exists():
        path.unlink()
PY
touch .eap-arm-patch-applied
chown -R we:we "$rack_parent" /opt/electroacoustic-playground/vcv 2>/dev/null || true
make dep -j"$build_jobs"
make -j"$build_jobs"

mkdir -p "$rack_src/plugins"
if [[ -d "$rack_src/plugins/Fundamental/.git" ]]; then
    git -C "$rack_src/plugins/Fundamental" fetch --depth 1 origin
    git -C "$rack_src/plugins/Fundamental" checkout FETCH_HEAD
else
    rm -rf "$rack_src/plugins/Fundamental"
    git clone --depth 1 "$fundamental_repo" "$rack_src/plugins/Fundamental"
fi
git -C "$rack_src/plugins/Fundamental" submodule update --init --recursive --depth 1
make -C "$rack_src/plugins/Fundamental" dep || true
make -C "$rack_src/plugins/Fundamental" -j"$build_jobs"
RACK_DIR="$rack_src" make -C "$rack_src/plugins/Fundamental" install
mkdir -p /home/we/.local/share/eap-vcv/Rack2/plugins-lin-armv7
cp "$rack_src"/plugins/Fundamental/dist/*.vcvplugin /home/we/.local/share/eap-vcv/Rack2/plugins-lin-armv7/
chown -R we:audio /home/we/.local/share/eap-vcv

cat >/usr/local/bin/eap-rack <<EOF
#!/usr/bin/env bash
cd "$rack_src"
exec "$rack_src/Rack" "\$@"
EOF
chmod 0755 /usr/local/bin/eap-rack

mkdir -p /opt/electroacoustic-playground/vcv/patch-cache
cat >/etc/default/eap-vcv <<'EOF'
# Set to 1 after the Pi can tolerate the extra VCV Rack CPU load.
EAP_ENABLE_VCV=0
EOF
echo "VCV Rack installed: /usr/local/bin/eap-rack"
