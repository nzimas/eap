#!/usr/bin/env python3
"""Build exact EAP Airwindows LV2 wrappers from the official Airwindows source."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path


FX_NAMES = [
    "TapeDelay2", "PitchDelay", "Doublelay", "SampleDelay", "Melt", "ADT", "StarChild2", "TakeCare",
    "RingModulator", "Dubly3", "GalacticVibe", "Pafnuty2", "PitchNasty", "GuitarConditioner", "GlitchShifter", "Gringer",
    "Nikola", "HipCrush", "DeRez3", "Pockey2", "CrunchyGrooveWear", "BitGlitter", "TapeBias", "Vibrato",
    "Deckwrecka", "DeNoise", "Texturize", "VoiceOfTheStarship", "ElectroHat", "Silhouette",
]


STUB_HEADER = r'''
#pragma once
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <cstdio>

typedef int32_t VstInt32;
typedef intptr_t VstIntPtr;
typedef float VstFloat32;
typedef double VstFloat64;
typedef VstIntPtr (*audioMasterCallback)(void*, VstInt32, VstInt32, VstIntPtr, void*, float);
typedef int VstPlugCategory;

static const int kVstMaxProgNameLen = 24;
static const int kVstMaxParamStrLen = 8;
static const int kVstMaxProductStrLen = 64;
static const int kVstMaxVendorStrLen = 64;
static const int kPlugCategEffect = 1;

static inline void vst_strncpy(char* dest, const char* src, int len) {
    if (len <= 0) return;
    strncpy(dest, src, (size_t)len);
    dest[len] = '\0';
}

static inline void float2string(float value, char* text, int len) {
    snprintf(text, (size_t)len, "%.3f", value);
}

static inline void int2string(int value, char* text, int len) {
    snprintf(text, (size_t)len, "%d", value);
}

static inline void dB2string(float value, char* text, int len) {
    snprintf(text, (size_t)len, "%.2f", value);
}

class AudioEffect {
public:
    virtual ~AudioEffect() {}
};

class AudioEffectX : public AudioEffect {
public:
    AudioEffectX(audioMasterCallback, VstInt32, VstInt32) {}
    virtual ~AudioEffectX() {}
    void setNumInputs(VstInt32) {}
    void setNumOutputs(VstInt32) {}
    void setUniqueID(unsigned long) {}
    void canProcessReplacing() {}
    void canDoubleReplacing() {}
    void programsAreChunks(bool) {}
    double getSampleRate() const { return sampleRate; }
    void setSampleRate(double rate) { sampleRate = rate; }
    virtual VstInt32 canDo(char*) { return 0; }
private:
    double sampleRate = 48000.0;
};
'''


WRAPPER_TEMPLATE = r'''
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <lv2/core/lv2.h>
#include "{name}.h"
#include "{name}.cpp"
#include "{name}Proc.cpp"

struct EapAwLv2 {{
    {name}* fx;
    const float* inL;
    const float* inR;
    float* outL;
    float* outR;
    const float* params[kNumParameters];
}};

static LV2_Handle instantiate_{name}(const LV2_Descriptor*, double rate, const char*, const LV2_Feature* const*) {{
    auto* self = new EapAwLv2();
    self->fx = new {name}(nullptr);
    self->fx->setSampleRate(rate);
    self->inL = self->inR = nullptr;
    self->outL = self->outR = nullptr;
    for (int i = 0; i < kNumParameters; ++i) self->params[i] = nullptr;
    return reinterpret_cast<LV2_Handle>(self);
}}

static void connect_port_{name}(LV2_Handle instance, uint32_t port, void* data) {{
    auto* self = reinterpret_cast<EapAwLv2*>(instance);
    if (port == 0) self->inL = static_cast<const float*>(data);
    else if (port == 1) self->inR = static_cast<const float*>(data);
    else if (port == 2) self->outL = static_cast<float*>(data);
    else if (port == 3) self->outR = static_cast<float*>(data);
    else if (port >= 4 && port < static_cast<uint32_t>(4 + kNumParameters)) self->params[port - 4] = static_cast<const float*>(data);
}}

static void activate_{name}(LV2_Handle) {{}}

static void run_{name}(LV2_Handle instance, uint32_t n_samples) {{
    auto* self = reinterpret_cast<EapAwLv2*>(instance);
    if (!self || !self->fx || !self->inL || !self->inR || !self->outL || !self->outR) return;
    for (int i = 0; i < kNumParameters; ++i) {{
        float value = self->params[i] ? *self->params[i] : self->fx->getParameter(i);
        self->fx->setParameter(i, std::max(0.0f, std::min(1.0f, value)));
    }}
    float* inputs[2] = {{ const_cast<float*>(self->inL), const_cast<float*>(self->inR) }};
    float* outputs[2] = {{ self->outL, self->outR }};
    self->fx->processReplacing(inputs, outputs, static_cast<VstInt32>(n_samples));
}}

static void deactivate_{name}(LV2_Handle) {{}}

static void cleanup_{name}(LV2_Handle instance) {{
    auto* self = reinterpret_cast<EapAwLv2*>(instance);
    if (self) {{
        delete self->fx;
        delete self;
    }}
}}

static const void* extension_data_{name}(const char*) {{ return nullptr; }}

static const LV2_Descriptor descriptor_{name} = {{
    "https://electroacoustic.local/lv2/airwindows/{name}",
    instantiate_{name},
    connect_port_{name},
    activate_{name},
    run_{name},
    deactivate_{name},
    cleanup_{name},
    extension_data_{name}
}};

extern "C" const LV2_Descriptor* lv2_descriptor(uint32_t index) {{
    return index == 0 ? &descriptor_{name} : nullptr;
}}
'''


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def param_count(header: str) -> int:
    match = re.search(r"kNumParameters\s*=\s*(\d+)", header)
    if match:
        return int(match.group(1))
    params = re.findall(r"kParam[A-Z]\s*=", header)
    return len(params)


def write_ttl(bundle: Path, name: str, count: int) -> None:
    uri = f"https://electroacoustic.local/lv2/airwindows/{name}"
    manifest = f"""@prefix lv2: <http://lv2plug.in/ns/lv2core#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

<{uri}>
    a lv2:Plugin, lv2:DistortionPlugin ;
    lv2:binary <{name}.so> ;
    rdfs:seeAlso <{name}.ttl> .
"""
    ports = [
        """[
        a lv2:AudioPort, lv2:InputPort ;
        lv2:index 0 ;
        lv2:symbol "in_l" ;
        lv2:name "Input L"
    ]""",
        """[
        a lv2:AudioPort, lv2:InputPort ;
        lv2:index 1 ;
        lv2:symbol "in_r" ;
        lv2:name "Input R"
    ]""",
        """[
        a lv2:AudioPort, lv2:OutputPort ;
        lv2:index 2 ;
        lv2:symbol "out_l" ;
        lv2:name "Output L"
    ]""",
        """[
        a lv2:AudioPort, lv2:OutputPort ;
        lv2:index 3 ;
        lv2:symbol "out_r" ;
        lv2:name "Output R"
    ]""",
    ]
    for i in range(count):
        label = chr(ord("A") + i) if i < 26 else f"P{i + 1}"
        ports.append(f"""[
        a lv2:ControlPort, lv2:InputPort ;
        lv2:index {i + 4} ;
        lv2:symbol "p{i + 1}" ;
        lv2:name "{label}" ;
        lv2:minimum 0.0 ;
        lv2:maximum 1.0 ;
        lv2:default 0.5
    ]""")
    body = f"""@prefix lv2: <http://lv2plug.in/ns/lv2core#> .
@prefix doap: <http://usefulinc.com/ns/doap#> .

<{uri}>
    a lv2:Plugin, lv2:DistortionPlugin ;
    doap:name "Airwindows {name}" ;
    lv2:port {', '.join(ports)} .
"""
    (bundle / "manifest.ttl").write_text(manifest)
    (bundle / f"{name}.ttl").write_text(body)


def build_one(src_root: Path, build_root: Path, bundle_root: Path, name: str) -> None:
    src_dir = src_root / "plugins" / "LinuxVST" / "src" / name
    if not src_dir.exists():
        raise FileNotFoundError(src_dir)
    work = build_root / name
    bundle = bundle_root / f"EAP-Airwindows-{name}.lv2"
    shutil.rmtree(work, ignore_errors=True)
    shutil.rmtree(bundle, ignore_errors=True)
    work.mkdir(parents=True)
    bundle.mkdir(parents=True)
    (work / "audioeffectx.h").write_text(STUB_HEADER)
    for suffix in (".h", ".cpp", "Proc.cpp"):
        source = src_dir / f"{name}{suffix}"
        shutil.copy(source, work / source.name)
    header = (work / f"{name}.h").read_text(errors="replace")
    count = param_count(header)
    (work / f"{name}Lv2.cpp").write_text(WRAPPER_TEMPLATE.format(name=name))
    run([
        "g++", "-std=c++14", "-O3", "-fPIC", "-shared", "-I", str(work),
        "-Wno-multichar", "-D__cdecl=", str(work / f"{name}Lv2.cpp"), "-o", str(bundle / f"{name}.so")
    ])
    write_ttl(bundle, name, count)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: eap-build-airwindows-lv2.py SRC_ROOT BUILD_ROOT LV2_ROOT", file=sys.stderr)
        return 2
    src_root = Path(sys.argv[1])
    build_root = Path(sys.argv[2])
    bundle_root = Path(sys.argv[3])
    build_root.mkdir(parents=True, exist_ok=True)
    bundle_root.mkdir(parents=True, exist_ok=True)
    for name in FX_NAMES:
        print(f"building {name}")
        build_one(src_root, build_root, bundle_root, name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
