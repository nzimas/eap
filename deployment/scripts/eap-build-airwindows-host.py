#!/usr/bin/env python3
"""Build the persistent EAP Airwindows JACK host from official Airwindows sources."""

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
#define __audioeffect__ 1
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


HOST_PREFIX = r'''
#include "audioeffectx.h"
#include <jack/jack.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <random>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <vector>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

'''


HOST_BODY = r'''

struct Processor {
    virtual ~Processor() {}
    virtual void process(float* inL, float* inR, float* outL, float* outR, jack_nframes_t nframes) = 0;
};

template <typename T, int N>
struct AwProcessor : Processor {
    std::unique_ptr<T> fx;
    AwProcessor(double sampleRate, const std::vector<float>& params) : fx(new T(nullptr)) {
        fx->setSampleRate(sampleRate);
        for (int i = 0; i < N; ++i) {
            float value = i < (int)params.size() ? params[i] : 0.5f;
            fx->setParameter(i, std::max(0.0f, std::min(1.0f, value)));
        }
    }
    void process(float* inL, float* inR, float* outL, float* outR, jack_nframes_t nframes) override {
        float* inputs[2] = {inL, inR};
        float* outputs[2] = {outL, outR};
        fx->processReplacing(inputs, outputs, static_cast<VstInt32>(nframes));
    }
};

struct Chain {
    std::vector<std::unique_ptr<Processor>> processors;
};

static jack_client_t* g_client = nullptr;
static jack_port_t* g_in_l = nullptr;
static jack_port_t* g_in_r = nullptr;
static jack_port_t* g_out_l = nullptr;
static jack_port_t* g_out_r = nullptr;
static std::atomic<Chain*> g_chain{nullptr};
static std::vector<std::unique_ptr<Chain>> g_retired;
static std::mutex g_retired_mutex;
static std::atomic<bool> g_running{true};
static std::vector<float> g_a_l, g_a_r, g_b_l, g_b_r;
static double g_sample_rate = 48000.0;

static std::vector<float> random_params(int count, uint32_t seed) {
    std::mt19937 rng(seed);
    std::uniform_real_distribution<float> dist(0.20f, 0.85f);
    std::vector<float> params;
    params.reserve(count);
    for (int i = 0; i < count; ++i) {
        params.push_back((0.5f * 0.35f) + (dist(rng) * 0.65f));
    }
    return params;
}

static std::unique_ptr<Processor> make_processor(int index, uint32_t seed) {
    switch(index) {
'''


HOST_SUFFIX = r'''
        default: return nullptr;
    }
}

struct FxSpec {
    int index;
    uint32_t seed;
};

static void install_chain(const std::vector<FxSpec>& specs) {
    std::unique_ptr<Chain> next(new Chain());
    for (size_t i = 0; i < specs.size() && i < 3; ++i) {
        auto proc = make_processor(specs[i].index, specs[i].seed);
        if (proc) next->processors.push_back(std::move(proc));
    }
    Chain* raw = next.release();
    Chain* old = g_chain.exchange(raw, std::memory_order_acq_rel);
    if (old) {
        std::lock_guard<std::mutex> lock(g_retired_mutex);
        g_retired.emplace_back(old);
        if (g_retired.size() > 64) {
            g_retired.erase(g_retired.begin(), g_retired.begin() + 16);
        }
    }
}

static int process_cb(jack_nframes_t nframes, void*) {
    auto* in_l = static_cast<float*>(jack_port_get_buffer(g_in_l, nframes));
    auto* in_r = static_cast<float*>(jack_port_get_buffer(g_in_r, nframes));
    auto* out_l = static_cast<float*>(jack_port_get_buffer(g_out_l, nframes));
    auto* out_r = static_cast<float*>(jack_port_get_buffer(g_out_r, nframes));
    Chain* chain = g_chain.load(std::memory_order_acquire);
    if (!chain || chain->processors.empty() || nframes > g_a_l.size()) {
        std::copy(in_l, in_l + nframes, out_l);
        std::copy(in_r, in_r + nframes, out_r);
        return 0;
    }
    std::copy(in_l, in_l + nframes, g_a_l.data());
    std::copy(in_r, in_r + nframes, g_a_r.data());
    float* cur_l = g_a_l.data();
    float* cur_r = g_a_r.data();
    float* next_l = g_b_l.data();
    float* next_r = g_b_r.data();
    for (auto& proc : chain->processors) {
        proc->process(cur_l, cur_r, next_l, next_r, nframes);
        std::swap(cur_l, next_l);
        std::swap(cur_r, next_r);
    }
    std::copy(cur_l, cur_l + nframes, out_l);
    std::copy(cur_r, cur_r + nframes, out_r);
    return 0;
}

static uint32_t parse_seed(const std::string& text) {
    auto pos = text.find("seed ");
    if (pos == std::string::npos) return static_cast<uint32_t>(std::chrono::high_resolution_clock::now().time_since_epoch().count());
    return static_cast<uint32_t>(std::strtoul(text.c_str() + pos + 5, nullptr, 10));
}

static std::vector<FxSpec> parse_specs(const std::string& text) {
    std::vector<FxSpec> specs;
    std::istringstream stream(text);
    std::string token;
    stream >> token;
    uint32_t chain_seed = parse_seed(text);
    size_t slot = 0;
    while (stream >> token) {
        if (token == "seed") break;
        auto sep = token.find(':');
        int index = std::atoi(token.c_str());
        uint32_t seed = sep == std::string::npos
            ? chain_seed + static_cast<uint32_t>((slot + 1) * 9973)
            : static_cast<uint32_t>(std::strtoul(token.c_str() + sep + 1, nullptr, 10));
        if (index >= 1 && index <= 30) {
            specs.push_back(FxSpec{index, seed});
            ++slot;
        }
    }
    return specs;
}

static void control_loop(uint16_t port) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return;
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    if (bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        close(fd);
        return;
    }
    while (g_running.load()) {
        char buffer[512] = {0};
        sockaddr_in from{};
        socklen_t from_len = sizeof(from);
        ssize_t n = recvfrom(fd, buffer, sizeof(buffer) - 1, 0, reinterpret_cast<sockaddr*>(&from), &from_len);
        if (n <= 0) continue;
        std::string msg(buffer, static_cast<size_t>(n));
        if (msg.find("QUIT") == 0) {
            g_running.store(false);
            break;
        }
        if (msg.find("SET") == 0) {
            install_chain(parse_specs(msg));
        }
        if (msg.find("CLEAR") == 0) {
            install_chain({});
        }
    }
    close(fd);
}

static void handle_signal(int) {
    g_running.store(false);
}

int main(int argc, char** argv) {
    uint16_t port = 57930;
    if (argc > 1) port = static_cast<uint16_t>(std::atoi(argv[1]));
    std::signal(SIGTERM, handle_signal);
    std::signal(SIGINT, handle_signal);
    jack_status_t status{};
    g_client = jack_client_open("eap-airwindows", JackNoStartServer, &status);
    if (!g_client) {
        std::fprintf(stderr, "failed to open JACK client\n");
        return 2;
    }
    g_sample_rate = static_cast<double>(jack_get_sample_rate(g_client));
    jack_nframes_t max_frames = jack_get_buffer_size(g_client) * 4;
    g_a_l.assign(max_frames, 0.0f);
    g_a_r.assign(max_frames, 0.0f);
    g_b_l.assign(max_frames, 0.0f);
    g_b_r.assign(max_frames, 0.0f);
    g_in_l = jack_port_register(g_client, "in_l", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    g_in_r = jack_port_register(g_client, "in_r", JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput, 0);
    g_out_l = jack_port_register(g_client, "out_l", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    g_out_r = jack_port_register(g_client, "out_r", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    jack_set_process_callback(g_client, process_cb, nullptr);
    if (jack_activate(g_client) != 0) {
        std::fprintf(stderr, "failed to activate JACK client\n");
        return 3;
    }
    std::thread controls(control_loop, port);
    std::fprintf(stdout, "eap-airwindows-host ready port=%u sampleRate=%.0f\n", port, g_sample_rate);
    std::fflush(stdout);
    while (g_running.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    if (controls.joinable()) controls.join();
    jack_deactivate(g_client);
    jack_client_close(g_client);
    return 0;
}
'''


def param_count(header: str) -> int:
    match = re.search(r"kNumParameters\s*=\s*(\d+)", header)
    if match:
        return int(match.group(1))
    return len(re.findall(r"kParam[A-Z]\s*=", header))


def header_guard(header: str) -> str | None:
    match = re.search(r"#ifndef\s+([A-Za-z0-9_]+)", header)
    return match.group(1) if match else None


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: eap-build-airwindows-host.py SRC_ROOT BUILD_ROOT OUTPUT_BINARY", file=sys.stderr)
        return 2
    src_root = Path(sys.argv[1])
    build_root = Path(sys.argv[2])
    output = Path(sys.argv[3])
    shutil.rmtree(build_root, ignore_errors=True)
    build_root.mkdir(parents=True)
    (build_root / "audioeffectx.h").write_text(STUB_HEADER)
    includes = []
    cases = []
    for index, name in enumerate(FX_NAMES, start=1):
        src_dir = src_root / "plugins" / "LinuxVST" / "src" / name
        if not src_dir.exists():
            raise FileNotFoundError(src_dir)
        work = build_root / name
        work.mkdir()
        for suffix in (".h", ".cpp", "Proc.cpp"):
            source = src_dir / f"{name}{suffix}"
            shutil.copy(source, work / source.name)
        header = (work / f"{name}.h").read_text(errors="replace")
        count = param_count(header)
        guard = header_guard(header)
        undef = f"#undef {guard}\n" if guard else ""
        ns = f"AW_{name}"
        includes.append(f'namespace {ns} {{\n{undef}#include "{name}/{name}.h"\n#include "{name}/{name}.cpp"\n#include "{name}/{name}Proc.cpp"\n}}\n')
        cases.append(f'        case {index}: return std::unique_ptr<Processor>(new AwProcessor<{ns}::{name}, {count}>(g_sample_rate, random_params({count}, seed)));\n')
    source = HOST_PREFIX + "\n".join(includes) + HOST_BODY + "".join(cases) + HOST_SUFFIX
    cpp = build_root / "eap-airwindows-host.cpp"
    cpp.write_text(source)
    subprocess.run([
        "g++", "-std=c++14", "-O3", "-fPIC", "-I", str(build_root),
        "-Wno-multichar", "-D__cdecl=", str(cpp), "-o", str(output),
        "-ljack", "-lpthread",
    ], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
