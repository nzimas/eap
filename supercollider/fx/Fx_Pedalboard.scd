// Electroacoustic Playground standalone pedalboard.
// Adapted from 21echoes/pedalboard by 21echoes contributors.
// Original project: https://github.com/21echoes/pedalboard
// License: GPL-3.0. This file is an adaptation for a non-Norns SuperCollider stack.

~eap = ~eap ? IdentityDictionary.new;
~eapFx = ~eapFx ? IdentityDictionary.new;

~eapFx[\pedalboard] = Environment.make({
    ~name = \pedalboard;
    ~maxPedalsPerScene = 3;
    ~inputBus = nil;
    ~group = nil;
    ~chain = List.new;
    ~busChain = List.new;
    ~outputBus = 0;
    ~sceneName = \clear;

    ~pedalIds = [
        \equalizer, \compressor, \sustain, \overdrive, \distortion,
        \bitcrusher, \lofi, \wavefolder, \chorus, \flanger, \phaser,
        \vibrato, \tremolo, \ringmod, \pitchshifter, \subboost,
        \delay, \reverb, \ampsimulator, \autowah
    ];

    ~heavyPedals = [\delay, \reverb, \lofi, \pitchshifter, \subboost, \ampsimulator];
    ~unavailablePedals = [\clouds, \rings];

    ~scenes = IdentityDictionary[
        \mineral -> (
            count: [0, 2],
            candidates: [\equalizer, \compressor, \chorus, \phaser, \delay, \reverb],
            weightHeavy: 0.20
        ),
        \reed -> (
            count: [1, 3],
            candidates: [\compressor, \sustain, \autowah, \chorus, \vibrato, \delay, \reverb],
            weightHeavy: 0.25
        ),
        \ember -> (
            count: [1, 3],
            candidates: [\overdrive, \distortion, \bitcrusher, \wavefolder, \ringmod, \flanger, \delay],
            weightHeavy: 0.18
        ),
        \tide -> (
            count: [1, 3],
            candidates: [\equalizer, \lofi, \pitchshifter, \tremolo, \phaser, \delay, \reverb],
            weightHeavy: 0.30
        )
    ];

    ~auditionChains = IdentityDictionary[
        \mineral -> [\chorus, \delay],
        \reed -> [\autowah, \vibrato, \chorus],
        \ember -> [\wavefolder, \delay, \bitcrusher],
        \tide -> [\lofi, \tremolo, \reverb]
    ];

    ~rand = { |self, lo = 0.0, hi = 1.0| rrand(lo.asFloat, hi.asFloat) };
    ~exprand = { |self, lo = 0.001, hi = 1.0| exprand(lo.asFloat, hi.asFloat) };

    ~makeSynthDefs = { |self|
        SynthDef(\eapPedalPassThru, { |in = 0, out = 0, amp = 1|
            Out.ar(out, In.ar(in, 2) * amp);
        }).add;

        SynthDef(\eapPedalOutput, { |in = 0, out = 0, amp = 0.9|
            var sig = LeakDC.ar(In.ar(in, 2));
            sig = Limiter.ar(sig * amp, 0.92, 0.01);
            Out.ar(out, sig);
        }).add;

        SynthDef(\eapPedal_equalizer, { |in = 0, out = 0, mix = 1, bypass = 0, in_gain = 1, out_gain = 1,
            ls_freq = 70, ls_amp = 1, mid_freq = 1000, mid_q = 1, mid_amp = 1, hs_freq = 5000, hs_amp = 1|
            var dry = In.ar(in, 2), wet;
            wet = dry * in_gain;
            wet = BLowShelf.ar(wet, ls_freq, 1, ls_amp.ampdb);
            wet = BPeakEQ.ar(wet, mid_freq, mid_q.reciprocal, mid_amp.ampdb);
            wet = BHiShelf.ar(wet, hs_freq, 1, hs_amp.ampdb);
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_compressor, { |in = 0, out = 0, mix = 0.7, bypass = 0, in_gain = 1, out_gain = 1,
            drive = 0.5, tone = 0.5|
            var dry = In.ar(in, 2), wet, ratio, threshold, gain, freq, filterType;
            wet = HPF.ar(dry * in_gain, 25);
            ratio = LinExp.kr(drive, 0, 1, 0.25, 0.05);
            threshold = LinLin.kr(drive, 0, 1, 0.9, 0.5);
            gain = 1 / (((1 - threshold) * ratio) + threshold);
            wet = Compander.ar(wet, wet, threshold, 1, ratio, 0.005, 0.1, gain);
            freq = Select.kr(tone > 0.75, [
                Select.kr(tone > 0.2, [LinExp.kr(tone, 0, 0.2, 10, 400), LinExp.kr(tone, 0.2, 0.75, 400, 20000)]),
                LinExp.kr(tone, 0.75, 1, 20, 21000)
            ]);
            filterType = Select.kr(tone > 0.75, [0, 1]);
            wet = DFM1.ar(wet, freq, 0.1, 1, filterType, 0.0003);
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_sustain, { |in = 0, out = 0, mix = 0.7, bypass = 0, in_gain = 1, out_gain = 1,
            drive = 0.5, gate = 0.35, tone = 0.5|
            var dry = In.ar(in, 2), wet, g, ratio, threshold, freq, filterType;
            wet = HPF.ar(dry * in_gain, 25);
            g = Select.kr(gate > 0.5, [LinExp.kr(gate, 0, 0.5, 0.0001, 0.00075), LinExp.kr(gate, 0.5, 1, 0.00075, 0.05)]);
            wet = Compander.ar(wet, wet, g, 6, 1, 0.1, 0.01);
            ratio = LinExp.kr(drive, 0, 1, 0.8, 0.1);
            threshold = LinLin.kr(drive, 0, 1, 0, 1);
            wet = CompanderD.ar(wet, threshold, ratio, 1, 0.01, 0.01).softclip;
            freq = Select.kr(tone > 0.75, [
                Select.kr(tone > 0.2, [LinExp.kr(tone, 0, 0.2, 10, 400), LinExp.kr(tone, 0.2, 0.75, 400, 20000)]),
                LinExp.kr(tone, 0.75, 1, 20, 21000)
            ]);
            filterType = Select.kr(tone > 0.75, [0, 1]);
            wet = DFM1.ar(wet, freq, 0.1, 1, filterType, 0.0003);
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_overdrive, { |in = 0, out = 0, mix = 0.45, bypass = 0, in_gain = 1, out_gain = 0.8,
            drive = 0.35, tone = 0.55|
            var dry = In.ar(in, 2), wet, freq, filterType;
            wet = HPF.ar(dry * in_gain, 25);
            wet = (wet * LinLin.kr(drive, 0, 1, 1, 3)).softclip;
            freq = Select.kr(tone > 0.75, [
                Select.kr(tone > 0.2, [LinExp.kr(tone, 0, 0.2, 10, 400), LinExp.kr(tone, 0.2, 0.75, 400, 20000)]),
                LinExp.kr(tone, 0.75, 1, 20, 21000)
            ]);
            filterType = Select.kr(tone > 0.75, [0, 1]);
            wet = DFM1.ar(wet, freq, 0.1, 1, filterType, 0.0003).softclip;
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_distortion, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.65,
            drive = 0.35, tone = 0.6|
            var dry = In.ar(in, 2), wet, freq, filterType;
            wet = HPF.ar(dry * in_gain, 25);
            wet = (wet * LinExp.kr(drive, 0, 1, 1, 5)).distort;
            freq = Select.kr(tone > 0.75, [
                Select.kr(tone > 0.2, [LinExp.kr(tone, 0, 0.2, 10, 400), LinExp.kr(tone, 0.2, 0.75, 400, 20000)]),
                LinExp.kr(tone, 0.75, 1, 20, 21000)
            ]);
            filterType = Select.kr(tone > 0.75, [0, 1]);
            wet = DFM1.ar(wet, freq, 0.1, 1, filterType, 0.0003).softclip;
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_bitcrusher, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.75,
            bitrate = 12, samplerate = 16000, tone = 0.55, gate = 0.2|
            var dry = In.ar(in, 2), wet, g, freq, filterType;
            wet = HPF.ar(dry * in_gain, 25);
            g = Select.kr(gate > 0.5, [LinExp.kr(gate, 0, 0.5, 0.001, 0.015), LinExp.kr(gate, 0.5, 1, 0.015, 0.05)]);
            wet = Compander.ar(wet, wet, g, 6, 1, 0.1, 0.01);
            wet = LPF.ar(wet, 5.66.reciprocal * samplerate);
            wet = Decimator.ar(wet, samplerate, bitrate);
            freq = Select.kr(tone > 0.75, [
                Select.kr(tone > 0.2, [LinExp.kr(tone, 0, 0.2, 10, 400), LinExp.kr(tone, 0.2, 0.75, 400, 20000)]),
                LinExp.kr(tone, 0.75, 1, 20, 21000)
            ]);
            filterType = Select.kr(tone > 0.75, [0, 1]);
            wet = DFM1.ar(wet, freq, 0.1, 1, filterType, 0.0003).softclip;
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_lofi, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.75,
            drive = 0.35, tone = 0.45, wow = 0.25, noise = 0.2|
            var dry = In.ar(in, 2), wet, ratio, threshold, gain, wowRate, depth, maxDelay, noiseSignal, bitRate;
            wet = HPF.ar(dry * in_gain, 25);
            ratio = LinExp.kr(drive, 0, 1, 0.15, 0.01);
            threshold = LinLin.kr(drive, 0, 1, 0.8, 0.33);
            gain = 1 / (((1 - threshold) * ratio) + threshold);
            wet = Limiter.ar(Compander.ar(wet, wet, threshold, 1, ratio, 0.1, 1, gain), dur: 0.0008);
            wowRate = LinExp.kr(wow, 0, 1, 0.5, 4);
            depth = LinExp.kr(wow, 0, 1, 1, 30);
            maxDelay = 0.025;
            wet = DelayC.ar(wet, maxDelay, SinOsc.ar(wowRate, 2, depth * 0.000015, 0.002));
            noiseSignal = (Dust2.ar(LinLin.kr(noise, 0, 1, 1, 5)) + Crackle.ar(1.95, 0.1)) * LinExp.kr(noise, 0, 1, 0.002, 0.08);
            wet = ((wet * LinExp.kr(drive, 0, 1, 1, 2.5)) + noiseSignal).tanh;
            wet = LPF.ar(wet, LinExp.kr(tone, 0, 1, 2500, 10000));
            bitRate = 48000 * LinLin.kr(noise, 0, 1, 1, 3).ceil.reciprocal;
            wet = (Decimator.ar(wet, bitRate, LinExp.kr(noise, 0, 1, 24, 6)) * 0.3) + (wet * 0.7);
            wet = HPF.ar(wet, LinExp.kr(tone, 0, 1, 40, 1690));
            wet = MoogFF.ar(wet, LinExp.kr(tone, 0, 1, 1000, 10000), 0) * LinLin.kr(drive, 0, 1, 1, 0.66);
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_wavefolder, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.7,
            amount = 0.35, symmetry = 0.65, smoothing = 0.5, expression = 0.45|
            var dry = In.ar(in, 2), wet, gain, comp, env, amp, sym;
            wet = dry * in_gain;
            gain = LinLin.kr(amount, 0, 1, 1, 16);
            comp = max(gain * 0.75, 1).reciprocal;
            env = EnvFollow.ar((wet * 2).softclip, 0.9999);
            amp = (comp * (1 - expression)) + (env * expression);
            sym = LinLin.kr(symmetry, 0, 1, 1, 0);
            wet = Fold.ar((wet + sym) * gain, -1, 1).softclip * amp;
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_chorus, { |in = 0, out = 0, mix = 0.45, bypass = 0, in_gain = 1, out_gain = 1,
            rate = 0.3, depth = 0.5|
            var dry = In.ar(in, 2), wet, r, maxDelayTime, minDelayTime, lfos;
            wet = dry * in_gain;
            r = Select.kr(rate > 0.5, [LinExp.kr(rate, 0, 0.5, 0.025, 0.125), LinExp.kr(rate, 0.5, 1, 0.125, 2)]);
            maxDelayTime = LinLin.kr(depth, 0, 1, 0.016, 0.052);
            minDelayTime = LinLin.kr(depth, 0, 1, 0.012, 0.022);
            lfos = [0, 1, 2, 3].collect({ |i| LFPar.kr(r * (1 + (i * 0.017)), 0.9 * i, (maxDelayTime - minDelayTime) * 0.5, (maxDelayTime + minDelayTime) * 0.5) });
            wet = DelayC.ar(wet * 0.25, maxDelayTime * 2, lfos).sum;
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_flanger, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.9,
            rate = 0.4, depth = 0.45, feedback = 0.35, predelay = 0.5|
            var dry = In.ar(in, 2), wet, maxDelay = 0.0105, r, d, pre, fb, fbSig, lfo, delayed;
            wet = dry * in_gain;
            r = LinExp.kr(rate, 0, 1, 0.1, 8);
            d = LinExp.kr(depth, 0, 1, 0.00025, maxDelay * 0.45);
            pre = LinLin.kr(predelay, 0, 1, d, maxDelay - d);
            fb = LinLin.kr(feedback, 0, 1, 0, 0.85);
            fbSig = LocalIn.ar(2) * fb;
            lfo = LFPar.kr(r, 0, d, pre);
            delayed = DelayC.ar(wet + fbSig, maxDelay, lfo);
            LocalOut.ar(delayed + wet);
            wet = LeakDC.ar((wet + delayed) * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_phaser, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.9,
            rate = 0.35, depth = 0.45|
            var dry = In.ar(in, 2), wet, delayed, r, d, maxDelay = 0.01;
            wet = dry * in_gain;
            r = LinExp.kr(rate, 0, 1, 0.275, 16);
            d = LinExp.kr(depth, 0, 1, 0.0005, maxDelay * 0.5) * 0.25;
            delayed = wet;
            4.do({ |i| delayed = AllpassL.ar(delayed, maxDelay * 0.25, LFPar.kr(r, i + 0.13, d, d), 0) });
            wet = LeakDC.ar((wet + delayed) * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_vibrato, { |in = 0, out = 0, mix = 0.5, bypass = 0, in_gain = 1, out_gain = 1,
            rate = 0.4, depth = 0.35, expression = 0.45|
            var dry = In.ar(in, 2), wet, env, envMul, r, d, mul, maxDelay;
            wet = dry * in_gain;
            env = Lag.ar(EnvFollow.ar((wet * 6).clip(-1, 1), 0.999), 0.14);
            envMul = (1 - expression) + (env * expression);
            envMul = DelayN.ar(envMul, 0.1, 0.07);
            r = LinExp.ar(rate * envMul, 0, 1, 0.75, 40);
            d = LinExp.ar(depth * envMul, 0, 1, 3.3, 24);
            mul = ((2 ** (d * 1200.reciprocal)) - 1) / (4 * r);
            maxDelay = 0.025;
            wet = DelayC.ar(wet, maxDelay, SinOsc.ar(r, 2, mul, mul + ControlRate.ir.reciprocal));
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_tremolo, { |in = 0, out = 0, mix = 0.7, bypass = 0, in_gain = 1, out_gain = 1,
            time = 0.5, depth = 0.5, shape = 0.33|
            var dry = In.ar(in, 2), wet, rate, dep, ampMod;
            wet = dry * in_gain;
            rate = max(time - ControlRate.ir.reciprocal, 0.05).reciprocal;
            dep = LinLin.kr(depth, 0, 1, 0, 0.5);
            ampMod = Select.kr((shape * 3).clip(0, 2), [
                SinOsc.kr(rate, 0, dep, 1 - dep),
                LFTri.kr(rate, 0, dep, 1 - dep),
                LFPulse.kr(rate, 0, 0.5, dep * 2, 1 - (dep * 2))
            ]);
            wet = wet * ampMod;
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_ringmod, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.75,
            freq = 220, follow = 0, freq_mul = 1, shape = 0.33, tone = 0.5|
            var dry = In.ar(in, 2), wet, followFreq, clar, modFreq, mod, filterFreq;
            wet = dry * in_gain;
            # followFreq, clar = Pitch.kr(wet[0], initFreq: 220, minFreq: 30, maxFreq: 4200, execFreq: 120, ampThreshold: 0.02, median: 1, clar: 1);
            modFreq = Select.kr(follow, [freq, followFreq.max(30) * freq_mul.max(0.1)]);
            mod = Select.ar((shape * 4).clip(0, 3), [SinOsc.ar(modFreq), LFTri.ar(modFreq), LFSaw.ar(modFreq), LFPulse.ar(modFreq, width: 0.5, mul: 2, add: -1)]);
            wet = wet * mod;
            filterFreq = Select.kr(tone > 0.75, [
                Select.kr(tone > 0.2, [LinExp.kr(tone, 0, 0.2, 10, 400), LinExp.kr(tone, 0.2, 0.75, 400, 20000)]),
                LinExp.kr(tone, 0.75, 1, 20, 21000)
            ]);
            wet = Select.ar(tone > 0.75, [MoogFF.ar(wet, filterFreq, 0.1), HPF.ar(wet, filterFreq)]).softclip;
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_pitchshifter, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.85,
            freq_mul = 1, drift = 0.2|
            var dry = In.ar(in, 2), wet, disp, windowSize = 0.25;
            wet = dry * in_gain;
            disp = LinExp.kr(drift, 0, 1, 0.0001, 0.08);
            wet = PitchShift.ar(wet, windowSize, freq_mul, disp, disp);
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_subboost, { |in = 0, out = 0, mix = 0.3, bypass = 0, in_gain = 1, out_gain = 0.65,
            shape = 0.2, num_octaves_down = 2, amp = 0.35, sensitivity = 0.5|
            var dry = In.ar(in, 2), wet, freq, clar, threshold, env, sub, modShape;
            wet = dry * in_gain;
            # freq, clar = Pitch.kr(wet[0], initFreq: 110, minFreq: 30, maxFreq: 4200, ampThreshold: 0.02, median: 7, clar: 1);
            freq = (freq.max(30) * (0.5 ** num_octaves_down)).max(20);
            threshold = LinLin.kr(sensitivity, 0, 1, 0.05, 0.75);
            env = EnvFollow.ar((wet * 2).softclip, 0.9999);
            modShape = Select.ar((shape * 4).clip(0, 3), [SinOsc.ar(freq), LFTri.ar(freq), LFSaw.ar(freq), LFPulse.ar(freq, width: 0.5, mul: 2, add: -1)]);
            sub = MoogFF.ar(modShape, 300, 0, mul: 2.5 * amp * Select.kr(clar > threshold, [0, env]));
            wet = LeakDC.ar(sub.dup * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_delay, { |in = 0, out = 0, mix = 0.28, bypass = 0, in_gain = 1, out_gain = 0.9,
            time = 0.45, feedback = 0.35, quality = 1, mode = 0|
            var dry = In.ar(in, 2), wet, delayed, fb, t, local, feedIn;
            wet = dry * in_gain;
            t = LinExp.kr(time, 0, 1, 0.04, 2.8);
            fb = LinLin.kr(feedback, 0, 1, 0, 0.86);
            local = LocalIn.ar(2);
            feedIn = wet + (local * fb);
            feedIn = Select.ar(quality.clip(0, 3), [
                feedIn,
                LPF.ar((HPF.ar(feedIn, 25) * 1.25).softclip, 4500) * 0.78,
                MoogFF.ar(((feedIn * 1.2) + PinkNoise.ar(0.003)).tanh, 5000, 0) * 0.8,
                HPF.ar(Decimator.ar(LPF.ar(((feedIn * 1.1) + PinkNoise.ar(0.002)).softclip, 3500), 16000, 12), 260)
            ]);
            delayed = Select.ar(mode.clip(0, 2), [
                DelayC.ar(feedIn, 3.0, t),
                DelayC.ar([feedIn[1], feedIn[0]], 3.0, t),
                DelayC.ar(feedIn, 0.18, LinExp.kr(time, 0, 1, 0.035, 0.16))
            ]);
            LocalOut.ar(delayed);
            wet = LeakDC.ar(delayed * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_reverb, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.85,
            size = 0.5, decay = 0.45, shimmer = 0.0, tone = 0.55|
            var dry = In.ar(in, 2), wet, freq, t60, damp, room, shifted;
            wet = dry * in_gain;
            freq = Select.kr(tone > 0.75, [
                Select.kr(tone > 0.2, [LinExp.kr(tone, 0, 0.2, 40, 400), LinExp.kr(tone, 0.2, 0.75, 400, 16000)]),
                LinExp.kr(tone, 0.75, 1, 40, 12000)
            ]);
            wet = Select.ar(tone > 0.75, [MoogFF.ar(wet, freq, 0.1), HPF.ar(wet, freq)]).softclip;
            t60 = LinExp.kr(decay, 0, 1, 0.4, 18);
            room = LinExp.kr(size, 0, 1, 0.2, 0.95);
            damp = LinLin.kr(tone, 0, 1, 0.85, 0.15);
            wet = JPverb.ar(wet, t60, damp, room, 0.7, 0.1, 2, 1, 1, 1, 500, 2000);
            shifted = PitchShift.ar(wet, 0.5, 2.0, 0.03, 0.1);
            wet = wet + (shifted * shimmer.clip(0, 0.35));
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_ampsimulator, { |in = 0, out = 0, mix = 0.35, bypass = 0, in_gain = 1, out_gain = 0.65,
            drive = 0.35, room = 0.25, bass = 0, mid = 0, treble = 0, presence = 0.5|
            var dry = In.ar(in, 2), wet;
            wet = dry * in_gain;
            wet = BLowShelf.ar(wet, 720, 1, -3.3);
            wet = BLowShelf.ar(wet, 320, 1, -5);
            wet = (wet * LinLin.kr(drive, 0, 1, 1.5, 4.0)).tanh;
            wet = BLowShelf.ar(wet, 720, 1, -6);
            wet = BLowShelf.ar(wet, 100, 1, bass);
            wet = BPeakEQ.ar(wet, 1700, 0.7071.reciprocal, mid);
            wet = BHiShelf.ar(wet, 6500, 1, treble);
            wet = BPeakEQ.ar(wet, 3900, 1, LinLin.kr(presence, 0, 1, -12, 12));
            wet = BPeakEQ.ar(wet, 10000, 1, -25);
            wet = BPeakEQ.ar(wet, 60, 1, -19);
            wet = FreeVerb.ar(wet, LinExp.kr(room, 0, 1, 0.1, 0.5), LinExp.kr(room, 0, 1, 0.2, 0.8), LinExp.kr(room, 0, 1, 0.9, 0.1));
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;

        SynthDef(\eapPedal_autowah, { |in = 0, out = 0, mix = 0.45, bypass = 0, in_gain = 1, out_gain = 0.85,
            rate = 0.5, depth = 0.45, sensitivity = 0.5, mode = 0, res = 0.5|
            var dry = In.ar(in, 2), wet, env, min1, max1, min2, max2, cut1, cut2, rq, bpMul, formantRatio = 0.75;
            wet = dry * in_gain;
            env = Lag.ar(EnvFollow.ar((wet * LinLin.kr(sensitivity, 0, 1, 3, 9)).clip(-1, 1), 0.999), LinExp.kr(rate, 0, 1, 0.4, 0.0375));
            min1 = LinExp.kr(depth, 0, 1, 440, 85);
            max1 = LinExp.kr(depth, 0, 1, 1100, 1750);
            min2 = LinExp.kr(depth, 0, 1, 1450, 900);
            max2 = LinExp.kr(depth, 0, 1, 2175, 2750);
            cut1 = LinExp.ar(env, 0, 1, min1, max1);
            cut2 = LinExp.ar(env, 0, 1, min2, max2);
            rq = LinExp.kr(res, 0, 1, 0.325, 0.01925);
            bpMul = LinLin.kr(res, 0, 1, 2.5, 7.5);
            wet = Select.ar(mode.clip(0, 2), [
                (RLPF.ar(wet, cut1, rq, formantRatio) + RLPF.ar(wet, cut2, rq, 1 - formantRatio)) * 0.67,
                ((BPF.ar(wet, cut1, rq * 2, formantRatio) + BPF.ar(wet, cut2, rq * 2, 1 - formantRatio)) * bpMul).softclip,
                (RHPF.ar(wet, cut1, rq, formantRatio) + RHPF.ar(wet, cut2, rq, 1 - formantRatio)) * 0.75
            ]);
            wet = LeakDC.ar(wet * out_gain);
            Out.ar(out, XFade2.ar(dry, wet, (mix * (1 - bypass) * 2) - 1));
        }).add;
    };

    ~argsFor = { |self, pedalId, sceneName|
        var scene = sceneName ? self[\sceneName];
        var base = [\mix, self.rand(0.18, 0.55), \in_gain, self.rand(0.75, 1.15), \out_gain, self.rand(0.62, 0.98), \bypass, 0];
        var extra = switch(pedalId,
            \equalizer, { [\ls_freq, self.exprand(45, 180), \ls_amp, self.rand(0.75, 1.4), \mid_freq, self.exprand(350, 3400), \mid_q, self.rand(0.7, 2.2), \mid_amp, self.rand(0.75, 1.35), \hs_freq, self.exprand(2800, 9500), \hs_amp, self.rand(0.75, 1.25)] },
            \compressor, { [\drive, self.rand(0.2, 0.65), \tone, self.rand(0.32, 0.78)] },
            \sustain, { [\drive, self.rand(0.25, 0.7), \gate, self.rand(0.1, 0.45), \tone, self.rand(0.28, 0.75)] },
            \overdrive, { [\drive, self.rand(0.18, 0.62), \tone, self.rand(0.35, 0.8)] },
            \distortion, { [\drive, self.rand(0.08, 0.42), \tone, self.rand(0.45, 0.85), \mix, self.rand(0.12, 0.35)] },
            \bitcrusher, { [\bitrate, self.rand(6, 16), \samplerate, self.exprand(5000, 30000), \tone, self.rand(0.38, 0.82), \gate, self.rand(0.05, 0.35), \mix, self.rand(0.08, 0.28)] },
            \lofi, { [\drive, self.rand(0.15, 0.55), \tone, self.rand(0.2, 0.65), \wow, self.rand(0.08, 0.42), \noise, self.rand(0.03, 0.25), \mix, self.rand(0.12, 0.36)] },
            \wavefolder, { [\amount, self.rand(0.08, 0.48), \symmetry, self.rand(0.3, 0.85), \smoothing, self.rand(0.35, 0.85), \expression, self.rand(0.2, 0.65), \mix, self.rand(0.12, 0.35)] },
            \chorus, { [\rate, self.rand(0.08, 0.65), \depth, self.rand(0.22, 0.78)] },
            \flanger, { [\rate, self.rand(0.05, 0.55), \depth, self.rand(0.18, 0.62), \feedback, self.rand(0.05, 0.48), \predelay, self.rand(0.25, 0.75), \mix, self.rand(0.08, 0.32)] },
            \phaser, { [\rate, self.rand(0.08, 0.65), \depth, self.rand(0.18, 0.75), \mix, self.rand(0.10, 0.34)] },
            \vibrato, { [\rate, self.rand(0.08, 0.52), \depth, self.rand(0.08, 0.48), \expression, self.rand(0.15, 0.65), \mix, self.rand(0.08, 0.30)] },
            \tremolo, { [\time, self.exprand(0.18, 2.4), \depth, self.rand(0.15, 0.75), \shape, [0.15, 0.45, 0.85].choose] },
            \ringmod, { [\freq, self.exprand(35, 1200), \follow, [0, 0, 1].choose, \freq_mul, [0.5, 1, 1.5, 2].choose, \shape, self.rand(0.05, 0.9), \tone, self.rand(0.3, 0.85), \mix, self.rand(0.08, 0.30)] },
            \pitchshifter, { [\freq_mul, [0.5, 0.75, 1.25, 1.5, 2].choose, \drift, self.rand(0.02, 0.22), \mix, self.rand(0.06, 0.24)] },
            \subboost, { [\shape, self.rand(0.05, 0.75), \num_octaves_down, [1, 2, 3].choose, \amp, self.rand(0.12, 0.35), \sensitivity, self.rand(0.38, 0.72), \mix, self.rand(0.08, 0.24)] },
            \delay, { [\time, self.rand(0.18, 0.72), \feedback, self.rand(0.12, 0.55), \quality, [0, 1, 1, 2, 3].choose, \mode, [0, 0, 1, 2].choose, \mix, self.rand(0.12, 0.38)] },
            \reverb, { [\size, self.rand(0.25, 0.82), \decay, self.rand(0.18, 0.72), \shimmer, self.rand(0.0, 0.16), \tone, self.rand(0.28, 0.75), \mix, self.rand(0.16, 0.46)] },
            \ampsimulator, { [\drive, self.rand(0.12, 0.5), \room, self.rand(0.05, 0.35), \bass, self.rand(-3, 3), \mid, self.rand(-4, 3), \treble, self.rand(-3, 4), \presence, self.rand(0.2, 0.75), \mix, self.rand(0.10, 0.28)] },
            \autowah, { [\rate, self.rand(0.08, 0.7), \depth, self.rand(0.18, 0.75), \sensitivity, self.rand(0.25, 0.72), \mode, [0, 0, 1, 2].choose, \res, self.rand(0.18, 0.72), \mix, self.rand(0.10, 0.35)] },
            { [] }
        );
        base ++ extra;
    };

    ~auditionArgsFor = { |self, pedalId, sceneName|
        var args = self[\argsFor].value(self, pedalId, sceneName);
        var scene = sceneName ? self[\sceneName];
        var mixFloor = switch(scene,
            \mineral, { 0.68 },
            \reed, { 0.72 },
            \ember, { 0.74 },
            \tide, { 0.78 },
            { 0.70 }
        );
        (args.size - 1).do({ |index|
            if(args[index] == \mix) { args[index + 1] = min(0.94, max(args[index + 1], mixFloor)); };
            if(args[index] == \out_gain) { args[index + 1] = min(0.96, max(args[index + 1], 0.78)); };
        });
        args = switch(pedalId,
            \delay, { args ++ [\feedback, 0.68, \mix, 0.82] },
            \reverb, { args ++ [\size, 0.82, \decay, 0.78, \shimmer, 0.08, \mix, 0.84] },
            \lofi, { args ++ [\drive, 0.56, \wow, 0.52, \noise, 0.28, \mix, 0.80] },
            \tremolo, { args ++ [\depth, 0.86, \time, 0.72, \mix, 0.92] },
            \wavefolder, { args ++ [\amount, 0.72, \symmetry, 0.74, \expression, 0.62, \mix, 0.78] },
            \bitcrusher, { args ++ [\bitrate, 8, \samplerate, 9000, \gate, 0.12, \mix, 0.70] },
            \chorus, { args ++ [\rate, 0.34, \depth, 0.82, \mix, 0.78] },
            \vibrato, { args ++ [\rate, 0.30, \depth, 0.56, \expression, 0.72, \mix, 0.76] },
            \autowah, { args ++ [\depth, 0.84, \sensitivity, 0.78, \res, 0.68, \mix, 0.78] },
            { args }
        );
        args;
    };

    ~chooseChain = { |self, sceneName|
        var scene = self[\scenes][sceneName] ? self[\scenes][\mineral];
        var desired = rrand(scene[\count][0], scene[\count][1]).clip(0, self[\maxPedalsPerScene]);
        var pool = scene[\candidates].copy;
        var chosen = List.new;
        while({ chosen.size < desired and: { pool.notEmpty } }, {
            var candidate = pool.removeAt(pool.size.rand);
            if(self[\heavyPedals].includes(candidate).not or: { scene[\weightHeavy].coin }) {
                chosen.add(candidate);
            };
        });
        chosen.asArray.copyRange(0, self[\maxPedalsPerScene] - 1);
    };

    ~clear = { |self|
        self[\chain].do({ |entry| entry[\synth].free; });
        self[\chain].clear;
        self[\busChain].do({ |bus| bus.free; });
        self[\busChain].clear;
        if(self[\outputStage].notNil) { self[\outputStage].free; self[\outputStage] = nil; };
        if(self[\passThru].notNil) { self[\passThru].free; self[\passThru] = nil; };
    };

    ~rebuild = { |self, pedalIds, sceneName|
        var currentIn, currentOut, target, addAction;
        self[\clear].value(self);
        currentIn = self[\inputBus].index;
        target = self[\group];
        addAction = \addToTail;
        pedalIds = pedalIds.copyRange(0, self[\maxPedalsPerScene] - 1);
        pedalIds.do({ |pedalId, index|
            var bus = Bus.audio(s, 2);
            var synth;
            self[\busChain].add(bus);
            currentOut = bus.index;
            synth = Synth.new(("eapPedal_" ++ pedalId).asSymbol, [\in, currentIn, \out, currentOut] ++ self[\argsFor].value(self, pedalId, sceneName), target, addAction);
            self[\chain].add((id: pedalId, synth: synth, out: bus));
            currentIn = currentOut;
            target = synth;
            addAction = \addAfter;
        });
        if(self[\chain].isEmpty) {
            self[\passThru] = Synth.tail(self[\group], \eapPedalPassThru, [\in, currentIn, \out, self[\outputBus], \amp, 0.9]);
        } {
            self[\outputStage] = Synth.new(\eapPedalOutput, [\in, currentIn, \out, self[\outputBus], \amp, 0.9], target, \addAfter);
        };
        ("EAP Pedalboard scene " ++ sceneName ++ ": " ++ pedalIds.asString).postln;
    };

    ~rebuildAudition = { |self, pedalIds, sceneName|
        var currentIn, currentOut, target, addAction;
        self[\clear].value(self);
        currentIn = self[\inputBus].index;
        target = self[\group];
        addAction = \addToTail;
        pedalIds = pedalIds.copyRange(0, self[\maxPedalsPerScene] - 1);
        pedalIds.do({ |pedalId|
            var bus = Bus.audio(s, 2);
            var synth;
            self[\busChain].add(bus);
            currentOut = bus.index;
            synth = Synth.new(("eapPedal_" ++ pedalId).asSymbol, [\in, currentIn, \out, currentOut] ++ self[\auditionArgsFor].value(self, pedalId, sceneName), target, addAction);
            self[\chain].add((id: pedalId, synth: synth, out: bus));
            currentIn = currentOut;
            target = synth;
            addAction = \addAfter;
        });
        self[\outputStage] = Synth.new(\eapPedalOutput, [\in, currentIn, \out, self[\outputBus], \amp, 0.94], target, \addAfter);
        ("EAP Pedalboard active scene " ++ sceneName ++ ": " ++ pedalIds.asString).postln;
    };

    ~seedScene = { |self, sceneName = \mineral|
        var chain = self[\chooseChain].value(self, sceneName);
        self[\sceneName] = sceneName;
        self[\rebuild].value(self, chain, sceneName);
    };

    ~seedAuditionScene = { |self, sceneName = \mineral|
        var chain = self[\auditionChains][sceneName] ? self[\auditionChains][\ember];
        self[\sceneName] = sceneName;
        self[\rebuildAudition].value(self, chain, sceneName);
    };

    ~start = { |self|
        if(self[\group].notNil) { self[\stop].value(self); };
        self[\group] = Group.tail(s);
        self[\inputBus] = Bus.audio(s, 2);
        self[\makeSynthDefs].value(self);
        s.sync;
        self[\seedScene].value(self, \mineral);
        "EAP Pedalboard: started".postln;
    };

    ~stop = { |self|
        self[\clear].value(self);
        if(self[\inputBus].notNil) { self[\inputBus].free; self[\inputBus] = nil; };
        if(self[\group].notNil) { self[\group].free; self[\group] = nil; };
    };
}).know_(true);
