// Electroacoustic Playground random independent scene lanes.
// A manual seed creates N autonomous lanes, each with its own source materials, parameters, buses, and FX.

~eap = ~eap ? IdentityDictionary.new;

~eapScenes = Environment.make({
    ~maxScenes = 8;
    ~maxSourcesPerScene = 2;
    ~maxFxPerScene = 2;
    ~group = nil;
    ~masterBus = nil;
    ~masterSynth = nil;
    ~reverbValues = nil;
    ~masterValues = nil;
    ~sessionDir = "/home/we/.local/share/eap/sessions";
    ~lanes = List.new;
    ~slots = nil;
    ~cloudLaneIndex = nil;

    ~scales = [
        [0, 2, 3, 7, 9],
        [0, 2, 5, 7, 10],
        [0, 2, 5, 7, 9],
        [0, 3, 5, 7, 10],
        [0, 2, 4, 7, 9]
    ];

    ~plaitsModelPool = [0, 1, 3, 4, 5, 6, 11, 12];

    ~pedalCandidates = [
        \chorus, \phaser, \vibrato, \tremolo, \delay, \reverb,
        \lofi, \wavefolder, \bitcrusher, \ringmod, \autowah
    ];

    ~rand = { |self, lo = 0.0, hi = 1.0| rrand(lo.asFloat, hi.asFloat) };
    ~exprand = { |self, lo = 0.001, hi = 1.0| exprand(lo.asFloat, hi.asFloat) };

    ~choosePitch = { |self, lane|
        var reg = lane[\register];
        var octave = rrand((reg[0] / 12).floor, (reg[1] / 12).floor);
        var midi = (octave * 12) + lane[\scale].choose + [0, 0, 7, 12, -12].choose;
        midi.clip(reg[0], reg[1]);
    };

    ~activeCount = { |self|
        self[\slots].count({ |lane| lane.notNil and: { lane[\state] == \active } });
    };

    ~hasActiveCloud = { |self|
        self[\slots].any({ |lane| lane.notNil and: { (lane[\state] == \active) and: { lane[\fx] == \clouds } } });
    };

    ~makeSynthDefs = { |self|
        if(~eapFx.notNil and: { ~eapFx[\pedalboard].notNil }) {
            ~eapFx[\pedalboard][\makeSynthDefs].value(~eapFx[\pedalboard]);
        };

        SynthDef(\eapSceneMaster, { |in = 0, out = 0, amp = 0.86,
            wet = 0.24, room = 0.55, damp = 0.45, decay = 3.2,
            lowCut = 120, highCut = 9500, modDepth = 0.08, bright = 0.75,
            masterVol = 0.82, overdrive = 0.0, bitDepth = 1.0, saturation = 0.12,
            compProfile = 0|
            var dry, pre, verb, sig, driven, saturated, folded, grimy, sat, srFreq, levels, degraded;
            var profile, threshold, slopeAbove, clampTime, relaxTime, makeup;
            dry = LeakDC.ar(In.ar(in, 2));
            pre = HPF.ar(LPF.ar(dry, highCut.clip(1200, 18000)), lowCut.clip(20, 1200));
            verb = JPverb.ar(pre, decay.clip(0.7, 12), damp.clip(0.05, 0.95),
                room.clip(0.15, 1.2), 0.72, modDepth.clip(0.0, 0.6), 2.0,
                1, bright.clip(0.1, 1.2), 1, lowCut.clip(20, 1200), highCut.clip(1200, 18000));
            sig = XFade2.ar(dry, verb, (wet.clip(0, 0.9) * 2) - 1);
            driven = tanh(sig * overdrive.linexp(0, 1, 1.0, 7.0));
            sig = XFade2.ar(sig, driven, (overdrive.clip(0, 1) * 2) - 1);
            sat = saturation.clip(0, 1);
            saturated = sig + (sig.abs * sat.linlin(0, 1, 0.0, 0.36));
            saturated = tanh(saturated * sat.linexp(0, 1, 1.0, 13.0));
            folded = Fold.ar(saturated * sat.linlin(0, 1, 1.0, 4.2), -0.58, 0.58);
            srFreq = sat.linexp(0, 1, 48000, 2600);
            grimy = Latch.ar(folded, Impulse.ar(srFreq));
            grimy = HPF.ar(LPF.ar(grimy, sat.linexp(0, 1, 15000, 3800)), sat.linexp(0, 1, 18, 160));
            sig = XFade2.ar(sig, LeakDC.ar(grimy) * sat.linlin(0, 1, 1.0, 0.78), (sat * 2) - 1);
            levels = 2.pow(bitDepth.clip(0, 1).linlin(0, 1, 1, 24)).max(2);
            degraded = ((sig * 0.5 + 0.5) * levels).round / levels;
            degraded = (degraded - 0.5) * 2;
            sig = XFade2.ar(degraded, sig, (bitDepth.clip(0, 1) * 2) - 1);
            profile = compProfile.clip(0, 7);
            threshold = Select.kr(profile, [0.82, 0.72, 0.62, 0.52, 0.42, 0.34, 0.26, 0.20]);
            slopeAbove = Select.kr(profile, [0.82, 0.70, 0.58, 0.46, 0.34, 0.25, 0.17, 0.11]);
            clampTime = Select.kr(profile, [0.030, 0.024, 0.018, 0.014, 0.010, 0.007, 0.004, 0.002]);
            relaxTime = Select.kr(profile, [0.360, 0.300, 0.240, 0.190, 0.145, 0.105, 0.075, 0.050]);
            makeup = Select.kr(profile, [1.00, 1.06, 1.13, 1.22, 1.34, 1.50, 1.74, 2.05]);
            sig = Compander.ar(sig, sig, threshold, 1, slopeAbove, clampTime, relaxTime) * makeup;
            sig = Limiter.ar(sig * masterVol.clip(0, 1) * amp, 0.98, 0.01);
            Out.ar(out, sig);
        }).add;

        SynthDef(\eapLanePlaitsNote, { |out = 0, pitch = 60, engine = 0, harm = 0.4,
            timbre = 0.5, morph = 0.5, level = 0.8, decay = 0.8, colour = 0.5,
            amp = 0.1, pan = 0|
            var trig, sig, env;
            trig = Trig1.kr(1, 0.01);
            sig = MiPlaits.ar(pitch, engine, harm, timbre, morph, trig, level, 0, 0, 0, decay, colour);
            env = EnvGen.kr(Env.linen(0.002, decay.max(0.05) + 0.2, 0.25), doneAction: 2);
            sig = Balance2.ar(sig[0], sig[1], pan, amp) * env;
            Out.ar(out, LeakDC.ar(sig));
        }).add;

        SynthDef(\eapLaneRingsNote, { |out = 0, pitch = 60, struct = 0.4,
            bright = 0.5, damp = 0.7, pos = 0.4, model = 0, poly = 2,
            amp = 0.12, pan = 0|
            var trig, exciter, sig, env;
            trig = Trig1.kr(1, 0.01);
            exciter = PinkNoise.ar(0.03) * Decay2.kr(trig, 0.004, 0.09);
            sig = MiRings.ar(exciter, trig, pitch, struct, bright, damp, pos, model, poly, 1, 0);
            env = EnvGen.kr(Env.linen(0.002, 8.0, 1.2), doneAction: 2);
            sig = Balance2.ar(sig[0], sig[1], pan, amp) * env;
            Out.ar(out, LeakDC.ar(sig));
        }).add;

        SynthDef(\eapLaneFoldNote, { |out = 0, freq = 220, fold = 1.0, fm = 0.1,
            cutoff = 2200, decay = 1.0, amp = 0.1, pan = 0|
            var env, mod, sig;
            env = EnvGen.kr(Env.perc(0.004, decay, curve: -4), doneAction: 2);
            mod = SinOsc.ar(freq * [1.5, 2, 3].choose, 0, freq * fm);
            sig = VarSaw.ar(freq + mod, 0, 0.45) + SinOsc.ar(freq * 0.5, 0, 0.25);
            sig = Fold.ar(sig * (1 + (fold * 3)), -0.7, 0.7);
            sig = RLPF.ar(sig, cutoff.clip(120, 10000), 0.72);
            sig = Pan2.ar(sig * env * amp, pan);
            Out.ar(out, LeakDC.ar(sig));
        }).add;

        SynthDef(\eapLaneMollyNote, { |out = 0, freq = 220, oscWaveShape = 0,
            pwMod = 0.0, freqModLfo = 0.0, freqModEnv = 0.0, mainOscLevel = 1,
            subOscLevel = 0.35, subOscDetune = 0, noiseLevel = 0.02,
            hpFilterCutoff = 25, lpFilterCutoff = 2200, lpFilterResonance = 0.25,
            lpFilterModEnv = 0.3, lpFilterTracking = 0.5, lfoFreq = 0.4,
            lfoWaveShape = 0, envAttack = 0.01, envDecay = 0.6, envSustain = 0.45,
            envRelease = 0.8, ringModFreq = 90, ringModMix = 0, ampMod = 0,
            amp = 0.1, pan = 0|
            var i_cFreq = 48.midicps, lfo, env, filterEnv, freqModRatio;
            var mainDrift, subDrift, oscArray, sig, filterRatio, lpCut, ring;
            lfo = Select.kr(lfoWaveShape.clip(0, 4), [
                SinOsc.kr(lfoFreq), LFTri.kr(lfoFreq), LFSaw.kr(lfoFreq),
                LFPulse.kr(lfoFreq, 0, 0.5, 2, -1), LFNoise0.kr(lfoFreq)
            ]);
            env = EnvGen.kr(Env.linen(envAttack, envDecay + (envSustain * 2.0), envRelease), doneAction: 2);
            filterEnv = EnvGen.kr(Env.perc(envAttack, envDecay.max(0.05), curve: -4), gate: 1);
            freqModRatio = ((lfo * freqModLfo) + (filterEnv * freqModEnv)).clip(-0.35, 0.35).midiratio;
            freq = (freq * freqModRatio).clip(20, SampleRate.ir * 0.45);
            mainDrift = LFNoise2.kr(0.1, 0.001, 1);
            subDrift = LFNoise2.kr(0.1, 0.0008, 1);
            oscArray = [
                VarSaw.ar(freq * mainDrift),
                Saw.ar(freq * mainDrift),
                Pulse.ar(freq * mainDrift, 0.5 + ((pwMod + (lfo * pwMod)).clip(0, 1) * 0.49))
            ];
            sig = Select.ar(oscWaveShape.clip(0, 2), oscArray) * mainOscLevel;
            sig = SelectX.ar(subOscLevel.clip(0, 1) * 0.5, [
                sig,
                Pulse.ar(freq * 0.5 * subOscDetune.midiratio * subDrift, 0.5)
            ]);
            sig = SelectX.ar(noiseLevel.clip(0, 1) * 0.5, [sig, WhiteNoise.ar()]);
            sig = sig + PinkNoise.ar(0.004);
            filterRatio = Select.kr(freq < i_cFreq, [
                i_cFreq + ((freq - i_cFreq) * lpFilterTracking),
                i_cFreq - ((i_cFreq - freq) * lpFilterTracking)
            ]) / i_cFreq;
            sig = HPF.ar(sig, (hpFilterCutoff * filterRatio).clip(10, 16000));
            lpCut = (lpFilterCutoff * filterRatio * (1 + (filterEnv * lpFilterModEnv * 5))).clip(30, 18000);
            sig = RLPF.ar(sig, lpCut, lpFilterResonance.linexp(0, 1, 1, 0.055));
            ring = SinOsc.ar(ringModFreq);
            sig = SelectX.ar(ringModMix.clip(0, 1) * 0.5, [sig, sig * ring]);
            sig = sig * env * lfo.range(1 - ampMod.clip(0, 1), 1) * amp;
            sig = Pan2.ar(tanh(sig).softclip, pan);
            Out.ar(out, LeakDC.ar(sig));
        }).add;

        SynthDef(\eapLanePassersbyNote, { |out = 0, freq = 220, waveShape = 0.4,
            waveFolds = 1.0, fm1Ratio = 0.66, fm2Ratio = 3.3, fm1Amount = 0.12,
            fm2Amount = 0.08, attack = 0.02, peak = 3600, decay = 1.2,
            reverbMix = 0.35, foldMix = 0.5, body = 0.2, air = 0.01,
            filterRq = 0.7, toneTilt = 0.5, amp = 0.1, pan = 0|
            var nyquist = SampleRate.ir * 0.5, signal, folded, bodySig, airSig, mod1, mod2, modFreq;
            var sinOsc, triOsc, additiveOsc, additivePhase, filterEnvLow, env, rq;
            fm1Amount = fm1Amount.squared;
            fm2Amount = fm2Amount.squared;
            mod1 = SinOsc.ar(freq * fm1Ratio * LFNoise2.kr(0.1, 0.001, 1), 0, fm1Amount * 22 * freq);
            mod2 = SinOsc.ar(freq * fm2Ratio * LFNoise2.kr(0.1, 0.005, 1), 0, fm2Amount * 12 * freq);
            modFreq = (freq + mod1 + mod2).clip(20, nyquist);
            sinOsc = SinOsc.ar(modFreq, 0, 0.5);
            triOsc = VarSaw.ar(modFreq, 0, 0.5, 0.5);
            additivePhase = LFSaw.ar(modFreq, 1, pi, pi);
            additiveOsc = Mix.fill(12, { |index|
                var harmonic = index + 1;
                (sin(additivePhase * harmonic % 2pi) / harmonic)
                    * (harmonic % 2 + waveShape.linlin(0.666666, 1, 0, 1)).min(1);
            });
            signal = LinSelectX.ar(waveShape.clip(0, 1) * 3, [sinOsc, triOsc, additiveOsc]);
            folded = Fold.ar(signal * (1 + (waveFolds.clip(0, 3) * 2)), -0.5, 0.5);
            signal = XFade2.ar(signal, folded, (foldMix.clip(0, 1) * 2) - 1);
            bodySig = SinOsc.ar(freq * 0.5, 0, body.clip(0, 1) * 0.22);
            airSig = BPF.ar(PinkNoise.ar(air.clip(0, 0.08)), toneTilt.linexp(0, 1, 1800, 9500), 0.45);
            signal = LPF.ar(signal + bodySig + airSig, toneTilt.linexp(0, 1, 4500, 15000));
            filterEnvLow = peak.min(300);
            rq = filterRq.clip(0.18, 0.95);
            env = EnvGen.ar(Env([0, 1, 0], [attack.max(0.003), decay.max(0.03)], [4, -8]), doneAction: 2);
            signal = RLPF.ar(signal, env.linlin(0, 1, filterEnvLow, peak.clip(120, 10000)), rq) * env;
            signal = signal * (1 + (reverbMix.clip(0, 0.7) * 0.18));
            Out.ar(out, Pan2.ar(tanh(signal * amp * 2.1).softclip, pan));
        }).add;

        SynthDef(\eapLaneCloudsFx, { |in = 0, out = 0, pit = 0, pos = 0.5,
            size = 0.25, dens = 0.4, tex = 0.5, drywet = 0.55, in_gain = 1,
            spread = 0.5, rvb = 0.2, fb = 0.1, freeze = 0, mode = 0, lofi = 0,
            amp = 0.84, fadeTime = 0.05|
            var source, sig;
            source = LeakDC.ar(In.ar(in, 2));
            sig = MiClouds.ar(source, pit, pos, size, dens, tex, drywet, in_gain,
                spread, rvb, fb, freeze, mode, lofi, 0);
            Out.ar(out, Limiter.ar(LeakDC.ar(sig) * Lag.kr(amp, fadeTime), 0.9, 0.01));
        }).add;

        SynthDef(\eapLaneOut, { |in = 0, out = 0, amp = 0.78, fadeTime = 0.05|
            Out.ar(out, Limiter.ar(LeakDC.ar(In.ar(in, 2)) * Lag.kr(amp, fadeTime), 0.9, 0.01));
        }).add;
    };

    ~randomLane = { |self, index, total|
        var materialPool = [\plaits, \plaits, \rings, \fold, \molly, \molly, \passersby];
        var maxMaterials = self[\maxSourcesPerScene];
        var materialCount = if(total >= 7, { 1 }, { rrand(1, maxMaterials) });
        var fx = if(total >= 5, {
            if((index == self[\cloudLaneIndex]) and: { self[\hasActiveCloud].value(self).not }, { \clouds }, { \pedalboard });
        }, {
            [\pedalboard, \pedalboard, \clouds].choose;
        });
        var register = [[31, 52], [36, 62], [45, 72], [52, 84]].choose;
        var minGap = if(total >= 7, { 1.15 }, { if(total >= 5, { 0.65 }, { 0.18 }) });
        var maxDensity = if(total >= 7, { 1.0 }, { if(total >= 5, { 1.15 }, { 1.45 }) });
        var phase = if(total >= 5, { self[\rand].value(self, 0.0, total * 0.7) }, { self[\rand].value(self, 0.0, 0.8) });
        (
            index: index,
            slot: index,
            total: total,
            materials: Array.fill(materialCount, { materialPool.choose }),
            fx: fx,
            scale: self[\scales].choose,
            register: register,
            phase: phase,
            gap: self[\rand].value(self, minGap, 7.0),
            densitySkew: self[\rand].value(self, 0.72, maxDensity),
            restProb: self[\rand].value(self, 0.04, 0.38),
            volatility: self[\rand].value(self, 0.65, 1.6),
            amp: (0.20 / total.sqrt).clip(0.055, 0.18),
            plaitsModels: Array.fill(rrand(1, 3), { self[\plaitsModelPool].choose }),
            ringsModel: rrand(0, 3),
            molly: (
                oscWaveShape: rrand(0, 2),
                pwMod: self[\rand].value(self, 0.0, 0.28),
                freqModLfo: self[\exprand].value(self, 0.0001, 0.045),
                freqModEnv: self[\rand].value(self, -0.025, 0.055),
                mainOscLevel: self[\rand].value(self, 0.55, 1.0),
                subOscLevel: self[\rand].value(self, 0.0, 0.55),
                subOscDetune: [-0.10, -0.05, 0, 0, 0, 0.05, 0.10].choose,
                noiseLevel: self[\exprand].value(self, 0.001, 0.16),
                hpFilterCutoff: self[\exprand].value(self, 10, 700),
                lpFilterCutoff: self[\exprand].value(self, 280, 9000),
                lpFilterResonance: self[\rand].value(self, 0.08, 0.48),
                lpFilterModEnv: self[\rand].value(self, 0.0, 0.24),
                lpFilterTracking: self[\rand].value(self, 0.12, 0.58),
                lfoFreq: self[\exprand].value(self, 0.04, 1.8),
                lfoWaveShape: [0, 0, 1].choose,
                envAttack: self[\exprand].value(self, 0.003, 0.38),
                envDecay: self[\exprand].value(self, 0.08, 2.4),
                envSustain: self[\rand].value(self, 0.0, 0.85),
                envRelease: self[\exprand].value(self, 0.08, 4.5),
                ringModFreq: [0.5, 1, 1.5, 2].choose,
                ringModMix: [0, 0, 0, self[\rand].value(self, 0.02, 0.10)].choose,
                ampMod: self[\rand].value(self, 0.0, 0.24)
            ),
            passersby: (
                waveShape: self[\rand].value(self, 0.05, 0.98),
                waveFolds: self[\rand].value(self, 0.0, 2.8),
                fm1Ratio: [0.5, 0.75, 1, 1.5, 2].choose,
                fm2Ratio: [1.5, 2, 3, 4].choose,
                fm1Amount: self[\rand].value(self, 0.0, 0.28),
                fm2Amount: self[\rand].value(self, 0.0, 0.22),
                attack: self[\exprand].value(self, 0.004, 2.4),
                peak: self[\exprand].value(self, 450, 9000),
                decay: self[\exprand].value(self, 0.08, 6.5),
                reverbMix: self[\rand].value(self, 0.02, 0.70),
                foldMix: self[\rand].value(self, 0.0, 1.0),
                body: self[\rand].value(self, 0.0, 0.85),
                air: self[\exprand].value(self, 0.001, 0.055),
                filterRq: self[\rand].value(self, 0.24, 0.92),
                toneTilt: self[\rand].value(self, 0.0, 1.0)
            ),
            clouds: (
                pit: [-12, -7, -5, 0, 7, 12].choose,
                pos: self[\rand].value(self, 0.05, 0.92),
                size: self[\rand].value(self, 0.14, 0.92),
                dens: self[\rand].value(self, 0.20, 0.82),
                tex: self[\rand].value(self, 0.18, 0.88),
                drywet: self[\rand].value(self, 0.42, 0.78),
                spread: self[\rand].value(self, 0.35, 0.95),
                rvb: self[\rand].value(self, 0.08, 0.52),
                fb: self[\rand].value(self, 0.02, 0.32),
                mode: [0, 0, 1, 2].choose,
                lofi: [0, 0, 1].choose
            ),
            state: \blank
        )
    };

    ~pedalArgs = { |self, pedalId|
        var base = [\mix, self[\rand].value(self, 0.46, 0.86), \in_gain, self[\rand].value(self, 0.82, 1.12), \out_gain, self[\rand].value(self, 0.70, 0.94), \bypass, 0];
        var extra = switch(pedalId,
            \delay, { [\time, self[\rand].value(self, 0.18, 0.76), \feedback, self[\rand].value(self, 0.24, 0.70), \quality, [0, 1, 2, 3].choose, \mode, [0, 1, 2].choose] },
            \reverb, { [\size, self[\rand].value(self, 0.35, 0.92), \decay, self[\rand].value(self, 0.30, 0.82), \shimmer, self[\rand].value(self, 0.0, 0.18), \tone, self[\rand].value(self, 0.24, 0.78)] },
            \lofi, { [\drive, self[\rand].value(self, 0.20, 0.62), \tone, self[\rand].value(self, 0.2, 0.72), \wow, self[\rand].value(self, 0.10, 0.58), \noise, self[\rand].value(self, 0.04, 0.34)] },
            \wavefolder, { [\amount, self[\rand].value(self, 0.22, 0.82), \symmetry, self[\rand].value(self, 0.24, 0.86), \smoothing, self[\rand].value(self, 0.28, 0.82), \expression, self[\rand].value(self, 0.20, 0.72)] },
            \bitcrusher, { [\bitrate, self[\rand].value(self, 6, 14), \samplerate, self[\exprand].value(self, 4500, 22000), \tone, self[\rand].value(self, 0.25, 0.82), \gate, self[\rand].value(self, 0.04, 0.30)] },
            \chorus, { [\rate, self[\rand].value(self, 0.10, 0.70), \depth, self[\rand].value(self, 0.30, 0.88)] },
            \phaser, { [\rate, self[\rand].value(self, 0.08, 0.75), \depth, self[\rand].value(self, 0.22, 0.86)] },
            \vibrato, { [\rate, self[\rand].value(self, 0.10, 0.56), \depth, self[\rand].value(self, 0.10, 0.58), \expression, self[\rand].value(self, 0.20, 0.75)] },
            \tremolo, { [\time, self[\exprand].value(self, 0.18, 2.2), \depth, self[\rand].value(self, 0.30, 0.88), \shape, [0.15, 0.45, 0.85].choose] },
            \ringmod, { [\freq, self[\exprand].value(self, 32, 1100), \follow, [0, 0, 1].choose, \freq_mul, [0.5, 1, 1.5, 2].choose, \shape, self[\rand].value(self, 0.05, 0.9), \tone, self[\rand].value(self, 0.25, 0.85)] },
            \autowah, { [\rate, self[\rand].value(self, 0.08, 0.7), \depth, self[\rand].value(self, 0.28, 0.88), \sensitivity, self[\rand].value(self, 0.30, 0.82), \mode, [0, 1, 2].choose, \res, self[\rand].value(self, 0.18, 0.78)] },
            { [] }
        );
        base ++ extra;
    };

    ~buildFx = { |self, lane, sourceBus|
        var currentIn = sourceBus.index;
        var currentOut;
        var target = lane[\group];
        var addAction = \addToTail;
        if(lane[\fx] == \clouds) {
            var c = lane[\clouds];
            var synth = Synth.tail(lane[\group], \eapLaneCloudsFx, [
                \in, currentIn, \out, self[\masterBus].index,
                \pit, c[\pit], \pos, c[\pos], \size, c[\size], \dens, c[\dens],
                \tex, c[\tex], \drywet, c[\drywet], \spread, c[\spread],
                \rvb, c[\rvb], \fb, c[\fb], \mode, c[\mode], \lofi, c[\lofi]
            ]);
            lane[\outSynth] = synth;
            lane[\synths].add(synth);
        } {
            var maxPedals = self[\maxFxPerScene];
            var pedalCount = if(lane[\total] >= 7, { 1 }, { rrand(1, maxPedals) });
            var chain = Array.fill(pedalCount, { self[\pedalCandidates].choose });
            var outSynth;
            chain.do({ |pedalId|
                var bus = Bus.audio(s, 2);
                var synth;
                lane[\buses].add(bus);
                currentOut = bus.index;
                synth = Synth.new(("eapPedal_" ++ pedalId).asSymbol,
                    [\in, currentIn, \out, currentOut] ++ self[\pedalArgs].value(self, pedalId),
                    target, addAction);
                lane[\synths].add(synth);
                currentIn = currentOut;
                target = synth;
                addAction = \addAfter;
            });
            outSynth = Synth.new(\eapLaneOut, [\in, currentIn, \out, self[\masterBus].index], target, \addAfter);
            lane[\synths].add(outSynth);
            lane[\outSynth] = outSynth;
            lane[\pedals] = chain;
        };
    };

    ~lanePattern = { |self, lane|
        var gap = lane[\gap].max(0.12);
        var rest = lane[\restProb].clip(0.02, 0.55);
        var volatility = lane[\volatility].clip(0.5, 2.0);
        var phraseA = Pseq([0.25, 0.25, 0.5, 1.0] * gap, 1);
        var phraseB = Pseq([0.125, 0.375, 0.25, 0.75, 1.5] * gap / volatility, 1);
        var phraseC = Pshuf([0.18, 0.22, 0.33, 0.66, 1.25] * gap, 1);
        var phraseD = Pseq([0.5, 0.25, 0.25, 0.125, 0.125, 1.0] * gap / volatility, 1);
        Pbind(
            \delta, (Pxrand([phraseA, phraseB, phraseC, phraseD], inf) / Pwhite(0.85, lane[\densitySkew].max(0.9), inf)).clip(0.055, 8.0),
            \isRest, Pwrand([0, 1], [1 - rest, rest].normalizeSum, inf),
            \accent, Pexprand(0.42, 1.65 * volatility, inf),
            \transpose, Pwrand([0, 0, 0, 7, 12, -12, 5, -5], [0.35, 0.20, 0.12, 0.10, 0.08, 0.06, 0.05, 0.04].normalizeSum, inf),
            \sourceCount, Pwrand([1, lane[\materials].size], [0.68, 0.32].normalizeSum, inf),
            \panBias, Pwhite(-0.35, 0.35, inf),
            \decayScale, Pexprand(0.55, 1.85, inf)
        );
    };

    ~triggerLane = { |self, lane, event = nil|
        var ev = event ? ();
        var sourceCount = (ev[\sourceCount] ? lane[\materials].size).asInteger.clip(1, lane[\materials].size);
        var sources = lane[\materials].scramble.keep(sourceCount);
        var accent = (ev[\accent] ? 1).asFloat.clip(0.2, 2.0);
        var transpose = (ev[\transpose] ? 0).asFloat;
        var panBias = (ev[\panBias] ? 0).asFloat.clip(-0.5, 0.5);
        var decayScale = (ev[\decayScale] ? 1).asFloat.clip(0.35, 2.4);
        sources.do({ |source|
            var pitch = (self[\choosePitch].value(self, lane) + transpose).clip(lane[\register][0], lane[\register][1]);
            if(source == \plaits) {
                Synth.head(lane[\group], \eapLanePlaitsNote, [
                    \out, lane[\sourceBus].index,
                    \pitch, (pitch + [0, 0, 7, 12].choose).clip(lane[\register][0], lane[\register][1]),
                    \engine, lane[\plaitsModels].choose,
                    \harm, self[\rand].value(self, 0.05, 0.95), \timbre, self[\rand].value(self, 0.10, 0.98),
                    \morph, self[\rand].value(self, 0.08, 0.98), \decay, self[\exprand].value(self, 0.08, 5.8) * decayScale,
                    \colour, self[\rand].value(self, 0.15, 0.90), \amp, lane[\amp] * accent,
                    \pan, (self[\rand].value(self, -0.75, 0.75) + panBias).clip(-1, 1)
                ]);
            };
            if(source == \rings) {
                Synth.head(lane[\group], \eapLaneRingsNote, [
                    \out, lane[\sourceBus].index, \pitch, pitch,
                    \struct, self[\rand].value(self, 0.12, 0.88), \bright, self[\rand].value(self, 0.18, 0.95),
                    \damp, self[\rand].value(self, 0.25, 0.96), \pos, self[\rand].value(self, 0.10, 0.88),
                    \model, lane[\ringsModel], \poly, [1, 2, 4].choose,
                    \amp, lane[\amp] * accent * self[\rand].value(self, 0.70, 1.25),
                    \pan, (self[\rand].value(self, -0.65, 0.65) + panBias).clip(-1, 1)
                ]);
            };
            if(source == \fold) {
                Synth.head(lane[\group], \eapLaneFoldNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \fold, self[\rand].value(self, 0.25, 2.8), \fm, self[\rand].value(self, 0.02, 0.60),
                    \cutoff, self[\exprand].value(self, 450, 9000), \decay, self[\exprand].value(self, 0.10, 3.8) * decayScale,
                    \amp, lane[\amp] * accent * 0.75,
                    \pan, (self[\rand].value(self, -0.70, 0.70) + panBias).clip(-1, 1)
                ]);
            };
            if(source == \molly) {
                var m = lane[\molly];
                Synth.head(lane[\group], \eapLaneMollyNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \oscWaveShape, m[\oscWaveShape], \pwMod, m[\pwMod],
                    \freqModLfo, m[\freqModLfo], \freqModEnv, m[\freqModEnv],
                    \mainOscLevel, m[\mainOscLevel], \subOscLevel, m[\subOscLevel],
                    \subOscDetune, m[\subOscDetune], \noiseLevel, m[\noiseLevel],
                    \hpFilterCutoff, m[\hpFilterCutoff], \lpFilterCutoff, m[\lpFilterCutoff],
                    \lpFilterResonance, m[\lpFilterResonance], \lpFilterModEnv, m[\lpFilterModEnv],
                    \lpFilterTracking, m[\lpFilterTracking], \lfoFreq, m[\lfoFreq],
                    \lfoWaveShape, m[\lfoWaveShape], \envAttack, m[\envAttack],
                    \envDecay, m[\envDecay], \envSustain, m[\envSustain],
                    \envRelease, m[\envRelease], \ringModFreq, m[\ringModFreq],
                    \ringModMix, m[\ringModMix], \ampMod, m[\ampMod],
                    \amp, lane[\amp] * accent * 0.85,
                    \pan, (self[\rand].value(self, -0.70, 0.70) + panBias).clip(-1, 1)
                ]);
            };
            if(source == \passersby) {
                var p = lane[\passersby];
                Synth.head(lane[\group], \eapLanePassersbyNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \waveShape, p[\waveShape], \waveFolds, p[\waveFolds],
                    \fm1Ratio, p[\fm1Ratio], \fm2Ratio, p[\fm2Ratio],
                    \fm1Amount, p[\fm1Amount], \fm2Amount, p[\fm2Amount],
                    \attack, p[\attack], \peak, p[\peak], \decay, p[\decay] * decayScale,
                    \reverbMix, p[\reverbMix], \foldMix, p[\foldMix], \body, p[\body],
                    \air, p[\air], \filterRq, p[\filterRq], \toneTilt, p[\toneTilt],
                    \amp, lane[\amp] * accent * 0.85,
                    \pan, (self[\rand].value(self, -0.70, 0.70) + panBias).clip(-1, 1)
                ]);
            };
        });
    };

    ~startLane = { |self, lane|
        if(lane[\state] != \active) {
            lane[\group] = Group.head(self[\group]);
            lane[\sourceBus] = Bus.audio(s, 2);
            lane[\buses] = List.new;
            lane[\buses].add(lane[\sourceBus]);
            lane[\synths] = List.new;
            self[\buildFx].value(self, lane, lane[\sourceBus]);
            lane[\routine] = Routine({
                var stream = self[\lanePattern].value(self, lane).asStream;
                var event;
                lane[\phase].wait;
                loop {
                    event = stream.next(Event.new);
                    if(event.notNil and: { (event[\isRest] ? 0).asInteger == 0 }) {
                        self[\triggerLane].value(self, lane, event);
                    };
                    ((event[\delta] ? lane[\gap]).asFloat.max(0.055)).wait;
                };
            }).play(SystemClock);
            lane[\state] = \active;
        };
        lane;
    };

    ~stopLane = { |self, lane, nextState = \muted|
        if(lane.notNil) {
            var group = lane[\group];
            var buses = lane[\buses];
            var outSynth = lane[\outSynth];
            var fadeTime = if(nextState == \muted, { 2.8 }, { 1.2 });
            if(lane[\routine].notNil) { lane[\routine].stop; lane[\routine] = nil; };
            if(outSynth.notNil) { outSynth.set(\fadeTime, fadeTime, \amp, 0); };
            if(group.notNil) {
                Routine({
                    fadeTime.wait;
                    group.free;
                    if(buses.notNil) { buses.do({ |bus| bus.free; }); };
                }).play(SystemClock);
            } {
                if(buses.notNil) { buses.do({ |bus| bus.free; }); };
            };
            lane[\group] = nil;
            lane[\buses] = nil;
            lane[\sourceBus] = nil;
            lane[\synths] = nil;
            lane[\pedals] = nil;
            lane[\outSynth] = nil;
            lane[\state] = nextState;
        };
        lane;
    };

    ~syncLoad = { |self|
        var total = self[\activeCount].value(self).max(1);
        self[\slots].do({ |lane|
            if(lane.notNil) {
                lane[\total] = total;
                lane[\amp] = (0.20 / total.sqrt).clip(0.055, 0.18);
            };
        });
    };

    ~reverbArg = { |self, param, value|
        var v = value.asFloat.clip(0, 1);
        switch(param,
            1, { [\wet, v.linlin(0, 1, 0.0, 0.72)] },
            2, { [\room, v.linlin(0, 1, 0.18, 1.15)] },
            3, { [\damp, v.linlin(0, 1, 0.10, 0.92)] },
            4, { [\decay, v.linexp(0, 1, 0.8, 11.0)] },
            5, { [\lowCut, v.linexp(0, 1, 30, 900)] },
            6, { [\highCut, v.linexp(0, 1, 1800, 16000)] },
            7, { [\modDepth, v.linlin(0, 1, 0.0, 0.32)] },
            8, { [\bright, v.linlin(0, 1, 0.35, 1.10)] },
            { nil }
        );
    };

    ~setReverb = { |self, param, value|
        var index = param.asInteger.clip(1, 8);
        var v = value.asFloat.clip(0, 1);
        var controlArg = self[\reverbArg].value(self, index, v);
        self[\reverbValues][index - 1] = v;
        if(self[\masterSynth].notNil and: { controlArg.notNil }) {
            self[\masterSynth].set(controlArg[0], controlArg[1]);
        };
        ("EAP master reverb param " ++ index ++ " = " ++ v.round(0.001)).postln;
    };

    ~applyReverb = { |self|
        self[\reverbValues].do({ |value, index|
            self[\setReverb].value(self, index + 1, value);
        });
    };

    ~masterArg = { |self, param, value|
        var v = value.asFloat.clip(0, 1);
        switch(param,
            1, { [\masterVol, v.linlin(0, 1, 0.0, 1.0)] },
            2, { [\overdrive, v] },
            3, { [\bitDepth, v] },
            4, { [\saturation, v] },
            5, { [\compProfile, (v * 7).round(1).asInteger.clip(0, 7)] },
            { nil }
        );
    };

    ~setMaster = { |self, param, value|
        var index = param.asInteger.clip(1, 5);
        var v = value.asFloat.clip(0, 1);
        var controlArg = self[\masterArg].value(self, index, v);
        self[\masterValues][index - 1] = v;
        if(self[\masterSynth].notNil and: { controlArg.notNil }) {
            self[\masterSynth].set(controlArg[0], controlArg[1]);
        };
        ("EAP master dynamics param " ++ index ++ " = " ++ v.round(0.001)).postln;
    };

    ~applyMaster = { |self|
        self[\masterValues].do({ |value, index|
            self[\setMaster].value(self, index + 1, value);
        });
    };

    ~sessionPath = { |self, slot|
        self[\sessionDir] ++ "/session-" ++ slot.asInteger.clip(1, 64).asString ++ ".archive";
    };

    ~laneSnapshot = { |self, lane|
        if(lane.isNil, {
            nil;
        }, {
            (
                index: lane[\index], slot: lane[\slot], total: lane[\total],
                materials: lane[\materials].copy, fx: lane[\fx],
                scale: lane[\scale].copy, register: lane[\register].copy,
                phase: lane[\phase], gap: lane[\gap], densitySkew: lane[\densitySkew],
                restProb: lane[\restProb], volatility: lane[\volatility],
                amp: lane[\amp], plaitsModels: lane[\plaitsModels].copy,
                ringsModel: lane[\ringsModel],
                molly: lane[\molly].copy, passersby: lane[\passersby].copy,
                clouds: lane[\clouds].copy, state: lane[\state]
            );
        });
    };

    ~prepareLoadedLane = { |self, lane, index|
        var m = lane[\molly];
        var p = lane[\passersby];
        lane[\index] = index + 1;
        lane[\slot] = index + 1;
        lane[\group] = nil;
        lane[\sourceBus] = nil;
        lane[\buses] = nil;
        lane[\synths] = nil;
        lane[\pedals] = nil;
        lane[\outSynth] = nil;
        lane[\routine] = nil;
        lane[\restProb] = lane[\restProb] ? 0.18;
        lane[\volatility] = lane[\volatility] ? 1.0;
        lane[\plaitsModels] = (lane[\plaitsModels] ? [0]).collect({ |model|
            if(self[\plaitsModelPool].includes(model), { model }, { self[\plaitsModelPool].choose });
        });
        if(m.notNil) {
            m[\pwMod] = (m[\pwMod] ? 0).clip(0, 0.28);
            m[\freqModLfo] = (m[\freqModLfo] ? 0).clip(0, 0.045);
            m[\freqModEnv] = (m[\freqModEnv] ? 0).clip(-0.025, 0.055);
            m[\subOscLevel] = (m[\subOscLevel] ? 0).clip(0, 0.55);
            m[\subOscDetune] = if((m[\subOscDetune] ? 0).abs > 0.15, { 0 }, { m[\subOscDetune] ? 0 });
            m[\noiseLevel] = (m[\noiseLevel] ? 0).clip(0, 0.16);
            m[\lpFilterResonance] = (m[\lpFilterResonance] ? 0.25).clip(0.08, 0.48);
            m[\lpFilterModEnv] = (m[\lpFilterModEnv] ? 0).clip(0, 0.24);
            m[\lpFilterTracking] = (m[\lpFilterTracking] ? 0.35).clip(0.12, 0.58);
            m[\lfoFreq] = (m[\lfoFreq] ? 0.4).clip(0.04, 1.8);
            m[\lfoWaveShape] = if([0, 1].includes(m[\lfoWaveShape]), { m[\lfoWaveShape] }, { 0 });
            m[\envAttack] = (m[\envAttack] ? 0.01).clip(0.003, 0.38);
            m[\ringModFreq] = if((m[\ringModFreq] ? 0) > 20, { [0.5, 1, 1.5, 2].choose }, { m[\ringModFreq] ? 1 });
            m[\ringModMix] = (m[\ringModMix] ? 0).clip(0, 0.10);
            m[\ampMod] = (m[\ampMod] ? 0).clip(0, 0.24);
        };
        if(p.notNil) {
            p[\fm1Ratio] = if([0.5, 0.75, 1, 1.5, 2].includes(p[\fm1Ratio]), { p[\fm1Ratio] }, { 1 });
            p[\fm2Ratio] = if([1.5, 2, 3, 4].includes(p[\fm2Ratio]), { p[\fm2Ratio] }, { 2 });
            p[\fm1Amount] = (p[\fm1Amount] ? 0).clip(0, 0.28);
            p[\fm2Amount] = (p[\fm2Amount] ? 0).clip(0, 0.22);
            p[\reverbMix] = (p[\reverbMix] ? 0.25).clip(0.02, 0.70);
            p[\foldMix] = (p[\foldMix] ? 0.5).clip(0, 1);
            p[\body] = (p[\body] ? 0.2).clip(0, 0.85);
            p[\air] = (p[\air] ? 0.01).clip(0, 0.055);
            p[\filterRq] = (p[\filterRq] ? 0.7).clip(0.24, 0.92);
            p[\toneTilt] = (p[\toneTilt] ? 0.5).clip(0, 1);
        };
        lane;
    };

    ~sessionSnapshot = { |self|
        (
            reverbValues: self[\reverbValues].copy,
            masterValues: self[\masterValues].copy,
            slots: self[\slots].collect({ |lane| self[\laneSnapshot].value(self, lane); })
        );
    };

    ~saveSession = { |self, slot|
        var index = slot.asInteger.clip(1, 64);
        var path = self[\sessionPath].value(self, index);
        ("mkdir -p " ++ self[\sessionDir]).unixCmdGetStdOut;
        self[\sessionSnapshot].value(self).writeArchive(path);
        ("EAP session " ++ index ++ " saved").postln;
        1;
    };

    ~loadSession = { |self, slot|
        var index = slot.asInteger.clip(1, 64);
        var path = self[\sessionPath].value(self, index);
        var snapshot;
        if(File.exists(path).not, {
            ("EAP session " ++ index ++ " is blank").postln;
            0;
        }, {
            snapshot = Object.readArchive(path);
            self[\clear].value(self);
            self[\reverbValues] = snapshot[\reverbValues].copy;
            self[\masterValues] = snapshot[\masterValues].copy;
            self[\applyReverb].value(self);
            self[\applyMaster].value(self);
            snapshot[\slots].do({ |lane, laneIndex|
                if(lane.notNil) {
                    self[\prepareLoadedLane].value(self, lane, laneIndex);
                    self[\slots][laneIndex] = lane;
                    self[\lanes].add(lane);
                    if(lane[\state] == \active) {
                        lane[\state] = \muted;
                        self[\startLane].value(self, lane);
                    };
                };
            });
            self[\syncLoad].value(self);
            ("EAP session " ++ index ++ " loaded").postln;
            1;
        });
    };

    ~clear = { |self|
        self[\slots].do({ |lane| self[\stopLane].value(self, lane, \blank); });
        self[\lanes].clear;
        self[\slots] = Array.fill(self[\maxScenes], { nil });
        self[\cloudLaneIndex] = nil;
    };

    ~slotStatus = { |self, slot|
        var lane = self[\slots].wrapAt(slot - 1);
        if(lane.isNil, {
            0;
        }, {
            if(lane[\state] == \active, { 1 }, { 2 });
        });
    };

    ~generateSlot = { |self, slot, total = nil|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var activeTotal;
        var oldLane = self[\slots][index - 1];
        var lane;
        if(oldLane.notNil) {
            self[\stopLane].value(self, oldLane, \blank);
            self[\lanes].remove(oldLane);
        };
        activeTotal = total ? (self[\activeCount].value(self) + 1).clip(1, self[\maxScenes]);
        self[\cloudLaneIndex] = if(activeTotal >= 5 and: { self[\hasActiveCloud].value(self).not }, {
            [0, index].choose;
        }, {
            nil;
        });
        lane = self[\randomLane].value(self, index, activeTotal);
        self[\slots][index - 1] = lane;
        self[\startLane].value(self, lane);
        self[\lanes].add(lane);
        self[\syncLoad].value(self);
        ("EAP slot " ++ index ++ " generated materials=" ++ lane[\materials].asString ++
            " fx=" ++ lane[\fx] ++ " plaits=" ++ lane[\plaitsModels].asString).postln;
        1;
    };

    ~toggleSlot = { |self, slot|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        if(lane.isNil or: { lane[\state] == \blank }, {
            self[\generateSlot].value(self, index);
        }, {
            if(lane[\state] == \active, {
                self[\stopLane].value(self, lane, \muted);
                self[\syncLoad].value(self);
                ("EAP slot " ++ index ++ " muted").postln;
                2;
            }, {
                self[\startLane].value(self, lane);
                self[\syncLoad].value(self);
                ("EAP slot " ++ index ++ " active").postln;
                1;
            });
        });
    };

    ~seed = { |self, count = 1|
        var n = count.asInteger.clip(1, self[\maxScenes]);
        self[\clear].value(self);
        self[\cloudLaneIndex] = if(n >= 5, { [0, rrand(1, n)].choose }, { nil });
        n.do({ |index|
            var lane = self[\randomLane].value(self, index + 1, n);
            lane[\state] = \muted;
            self[\startLane].value(self, lane);
            self[\lanes].add(lane);
            self[\slots][index] = lane;
            ("EAP random lane " ++ (index + 1) ++ "/" ++ n ++
                " materials=" ++ lane[\materials].asString ++
                " fx=" ++ lane[\fx] ++
                " plaits=" ++ lane[\plaitsModels].asString).postln;
        });
        ("EAP random scene set active: " ++ n ++ " independent lanes").postln;
    };

    ~start = { |self|
        if(self[\group].notNil) { self[\stop].value(self); };
        self[\group] = Group.tail(s);
        self[\masterBus] = Bus.audio(s, 2);
        self[\makeSynthDefs].value(self);
        s.sync;
        self[\reverbValues] = [0.24, 0.55, 0.45, 0.36, 0.25, 0.74, 0.24, 0.62];
        self[\masterValues] = [0.82, 0.0, 1.0, 0.12, 0.0];
        self[\masterSynth] = Synth.tail(self[\group], \eapSceneMaster, [\in, self[\masterBus].index, \out, 0]);
        self[\applyReverb].value(self);
        self[\applyMaster].value(self);
        self[\slots] = Array.fill(self[\maxScenes], { nil });
        self[\lanes].clear;
        "EAP RandomScenes: started with blank slots".postln;
    };

    ~stop = { |self|
        self[\clear].value(self);
        if(self[\masterSynth].notNil) { self[\masterSynth].free; self[\masterSynth] = nil; };
        if(self[\masterBus].notNil) { self[\masterBus].free; self[\masterBus] = nil; };
        if(self[\group].notNil) { self[\group].free; self[\group] = nil; };
    };
}).know_(true);
