// Electroacoustic Playground adaptation of Mark Wheeler's Passersby engine.
// Original concept: west-coast mono synth with complex waveform generation, FM and a low-pass gate.
// This version is standalone SuperCollider, independent of Norns/Crone.

~eap = ~eap ? IdentityDictionary.new;
~eapEngines = ~eapEngines ? IdentityDictionary.new;

~eapEngines[\passersby] = Environment.make({
    ~name = \passersby;
    ~numLfoDests = 9;
    ~maxDecay = 8;
    ~outBus = 0;
    ~rootMidi = 48;
    ~scale = [0, 2, 3, 5, 7, 9, 10];
    ~sceneNames = [\mineral, \reed, \ember, \tide];
    ~currentScene = \mineral;
    ~activeScale = [0, 2, 3, 5, 7, 9, 10];
    ~paramValues = IdentityDictionary.new;
    ~noteId = 0;

    ~specs = IdentityDictionary[
        \waveShape -> [0.0, 1.0],
        \waveFolds -> [0.0, 3.0],
        \fm1Ratio -> [0.25, 2.5],
        \fm2Ratio -> [1.0, 8.0],
        \fm1Amount -> [0.0, 0.8],
        \fm2Amount -> [0.0, 0.8],
        \envType -> [0, 1],
        \attack -> [0.003, 4.0],
        \peak -> [200.0, 10000.0],
        \decay -> [0.05, 8.0],
        \amp -> [0.05, 0.7],
        \reverbMix -> [0.0, 0.85],
        \lfoShape -> [0, 3],
        \lfoFreq -> [0.02, 3.0],
        \lfoToFreqAmount -> [0.0, 0.4],
        \lfoToWaveShapeAmount -> [0.0, 0.9],
        \lfoToWaveFoldsAmount -> [0.0, 0.8],
        \lfoToFm1Amount -> [0.0, 0.7],
        \lfoToFm2Amount -> [0.0, 0.7],
        \lfoToAttackAmount -> [0.0, 0.6],
        \lfoToPeakAmount -> [0.0, 0.6],
        \lfoToDecayAmount -> [0.0, 0.6],
        \lfoToReverbMixAmount -> [0.0, 0.6],
        \drift -> [0.0, 0.35]
    ];

    ~scenes = IdentityDictionary[
        \mineral -> (
            register: [36, 55], density: [4.0, 11.0], noteDur: [0.08, 0.9], gap: [0.2, 3.5],
            amp: [0.07, 0.18], reverbMix: [0.25, 0.72], waveShape: [0.05, 0.55], waveFolds: [0.0, 1.7],
            fm1Amount: [0.0, 0.22], fm2Amount: [0.0, 0.18], attack: [0.003, 0.08], decay: [0.25, 2.7],
            peak: [450, 4500], lfoFreq: [0.03, 0.25], drift: [0.04, 0.20]
        ),
        \reed -> (
            register: [47, 67], density: [6.0, 16.0], noteDur: [0.8, 4.5], gap: [0.1, 1.2],
            amp: [0.05, 0.16], reverbMix: [0.12, 0.45], waveShape: [0.25, 0.85], waveFolds: [0.2, 1.2],
            fm1Amount: [0.04, 0.28], fm2Amount: [0.0, 0.20], attack: [0.2, 2.2], decay: [1.2, 5.5],
            peak: [700, 5200], lfoFreq: [0.04, 0.45], drift: [0.08, 0.32]
        ),
        \ember -> (
            register: [55, 81], density: [2.0, 8.0], noteDur: [0.03, 0.25], gap: [0.05, 0.7],
            amp: [0.04, 0.13], reverbMix: [0.35, 0.82], waveShape: [0.55, 1.0], waveFolds: [0.8, 2.8],
            fm1Amount: [0.08, 0.55], fm2Amount: [0.04, 0.45], attack: [0.003, 0.03], decay: [0.05, 0.8],
            peak: [1600, 9500], lfoFreq: [0.15, 1.7], drift: [0.02, 0.18]
        ),
        \tide -> (
            register: [31, 50], density: [10.0, 28.0], noteDur: [2.0, 9.0], gap: [0.4, 4.0],
            amp: [0.05, 0.15], reverbMix: [0.45, 0.85], waveShape: [0.0, 0.45], waveFolds: [0.0, 0.7],
            fm1Amount: [0.0, 0.14], fm2Amount: [0.0, 0.10], attack: [1.0, 4.0], decay: [3.0, 8.0],
            peak: [250, 2600], lfoFreq: [0.02, 0.16], drift: [0.12, 0.35]
        )
    ];

    ~sceneProfiles = IdentityDictionary[
        \mineral -> (
            scale: [0, 2, 3, 7, 9],
            waveShape: 0.30, waveFolds: 1.10, fm1Ratio: 0.5, fm2Ratio: 3,
            fm1Amount: 0.10, fm2Amount: 0.06, envType: 0, attack: 0.018,
            peak: 2600, decay: 1.35, amp: 0.18, reverbMix: 0.55,
            lfoShape: 0, lfoFreq: 0.08, lfoToFreqAmount: 0.05,
            lfoToWaveShapeAmount: 0.18, lfoToWaveFoldsAmount: 0.16,
            lfoToFm1Amount: 0.08, lfoToFm2Amount: 0.05,
            lfoToAttackAmount: 0.03, lfoToPeakAmount: 0.10,
            lfoToDecayAmount: 0.08, lfoToReverbMixAmount: 0.10, drift: 0.14
        ),
        \reed -> (
            scale: [0, 2, 5, 7, 10],
            waveShape: 0.68, waveFolds: 0.75, fm1Ratio: 1.5, fm2Ratio: 3.333,
            fm1Amount: 0.17, fm2Amount: 0.08, envType: 1, attack: 0.95,
            peak: 3300, decay: 3.5, amp: 0.16, reverbMix: 0.32,
            lfoShape: 0, lfoFreq: 0.18, lfoToFreqAmount: 0.04,
            lfoToWaveShapeAmount: 0.24, lfoToWaveFoldsAmount: 0.10,
            lfoToFm1Amount: 0.10, lfoToFm2Amount: 0.04,
            lfoToAttackAmount: 0.12, lfoToPeakAmount: 0.12,
            lfoToDecayAmount: 0.10, lfoToReverbMixAmount: 0.06, drift: 0.22
        ),
        \ember -> (
            scale: [0, 1, 3, 6, 7, 10],
            waveShape: 0.92, waveFolds: 2.55, fm1Ratio: 2, fm2Ratio: 7,
            fm1Amount: 0.48, fm2Amount: 0.34, envType: 0, attack: 0.006,
            peak: 8200, decay: 0.32, amp: 0.14, reverbMix: 0.58,
            lfoShape: 3, lfoFreq: 0.85, lfoToFreqAmount: 0.08,
            lfoToWaveShapeAmount: 0.35, lfoToWaveFoldsAmount: 0.38,
            lfoToFm1Amount: 0.22, lfoToFm2Amount: 0.20,
            lfoToAttackAmount: 0.02, lfoToPeakAmount: 0.22,
            lfoToDecayAmount: 0.08, lfoToReverbMixAmount: 0.18, drift: 0.08
        ),
        \tide -> (
            scale: [0, 2, 5, 7, 9],
            waveShape: 0.16, waveFolds: 0.28, fm1Ratio: 0.666, fm2Ratio: 1.5,
            fm1Amount: 0.05, fm2Amount: 0.03, envType: 1, attack: 2.7,
            peak: 1200, decay: 7.0, amp: 0.17, reverbMix: 0.78,
            lfoShape: 0, lfoFreq: 0.045, lfoToFreqAmount: 0.08,
            lfoToWaveShapeAmount: 0.14, lfoToWaveFoldsAmount: 0.06,
            lfoToFm1Amount: 0.03, lfoToFm2Amount: 0.02,
            lfoToAttackAmount: 0.18, lfoToPeakAmount: 0.16,
            lfoToDecayAmount: 0.18, lfoToReverbMixAmount: 0.20, drift: 0.30
        )
    ];

    ~rangeRand = { |self, range|
        rrand(range[0].asFloat, range[1].asFloat);
    };

    ~chooseNote = { |self, scene|
        var reg = scene[\register];
        var octave = rrand((reg[0] / 12).floor, (reg[1] / 12).floor);
        var degree = self.activeScale.choose;
        var midi = ((octave * 12) + degree).clip(reg[0], reg[1]);
        (midi + [0, 0, 0, 12, -12].choose).clip(reg[0], reg[1]).midicps;
    };

    ~setParam = { |self, key, value|
        self.paramValues[key] = value;
        if(self.voice.notNil and: { [\waveShape, \waveFolds, \fm1Ratio, \fm2Ratio, \fm1Amount, \fm2Amount, \envType, \attack, \peak, \decay, \amp].includes(key) }) {
            self.voice.set(key, value);
        };
        if(self.reverb.notNil and: { key == \reverbMix }) {
            self.reverb.set(\mix, value);
        };
        if(self.lfos.notNil and: { key.asString.beginsWith("lfo") or: { key == \drift } }) {
            self.lfos.set(key, value);
        };
    };

    ~morphParam = { |self, key, range, inertia = 0.72|
        var target = self.rangeRand(range);
        var current = self.paramValues[key] ? target;
        var next = (current * inertia) + (target * (1 - inertia));
        self.setParam(key, next);
        next;
    };

    ~applyScene = { |self, sceneName|
        var profile = self.sceneProfiles[sceneName];
        self.currentScene = sceneName;
        self.activeScale = profile[\scale];
        [\waveShape, \waveFolds, \fm1Ratio, \fm2Ratio, \fm1Amount, \fm2Amount,
            \envType, \attack, \peak, \decay, \amp, \reverbMix, \lfoShape,
            \lfoFreq, \lfoToFreqAmount, \lfoToWaveShapeAmount,
            \lfoToWaveFoldsAmount, \lfoToFm1Amount, \lfoToFm2Amount,
            \lfoToAttackAmount, \lfoToPeakAmount, \lfoToDecayAmount,
            \lfoToReverbMixAmount, \drift].do({ |key|
            self.setParam(key, profile[key]);
        });
    };

    ~createScene = { |self, sceneName|
        self.applyScene(sceneName);
    };

    ~auditionScene = { |self, sceneName|
        var scene, freq, dur;
        self.applyScene(sceneName);
        scene = self.scenes[self.currentScene];
        freq = self.chooseNote(scene);
        dur = self.rangeRand(scene[\noteDur]).max(1.2);
        if(self.voice.notNil) {
            self.voice.set(\freq, freq, \vel, 0.85, \pressure, 0.45, \timbre, 0.65, \t_gate, 1, \gate, 1, \killGate, 1);
            Routine({
                dur.wait;
                if(self.voice.notNil) { self.voice.set(\gate, 0); };
            }).play(SystemClock);
        };
        ("EAP Passersby active scene " ++ sceneName ++ " freq " ++ freq.round(0.01)).postln;
    };

    ~setOutBus = { |self, bus|
        self.outBus = bus;
        if(self.reverb.notNil) { self.reverb.set(\out, bus); };
    };

    ~makeSynthDefs = { |self|
        SynthDef(\eapPassersbyLfos, { |out = 0, lfoShape = 0, lfoFreq = 0.5,
            lfoToFreqAmount = 0, lfoToWaveShapeAmount = 0, lfoToWaveFoldsAmount = 0, lfoToFm1Amount = 0, lfoToFm2Amount = 0,
            lfoToAttackAmount = 0, lfoToPeakAmount = 0, lfoToDecayAmount = 0, lfoToReverbMixAmount = 0, drift = 0|
            var i_driftRate = 0.15, outArray, lfo;
            lfo = Select.kr(lfoShape.clip(0, 3), [LFTri.kr(lfoFreq), LFSaw.kr(lfoFreq), LFPulse.kr(lfoFreq), LFDNoise0.kr(lfoFreq * 2)]);
            outArray = Array.fill(self.numLfoDests, 0);
            outArray[0] = (lfo * lfoToFreqAmount * 18).midiratio;
            outArray[1] = (lfo * lfoToWaveShapeAmount) + LFNoise1.kr(i_driftRate, drift);
            outArray[2] = ((lfo * lfoToWaveFoldsAmount) + LFNoise1.kr(i_driftRate, drift)) * 2;
            outArray[3] = ((lfo * lfoToFm1Amount) + LFNoise1.kr(i_driftRate, drift)) * 0.5;
            outArray[4] = ((lfo * lfoToFm2Amount) + LFNoise1.kr(i_driftRate, drift)) * 0.5;
            outArray[5] = ((lfo * lfoToAttackAmount) + LFNoise1.kr(i_driftRate, drift)) * 2.2;
            outArray[6] = (((lfo * lfoToPeakAmount) + LFNoise1.kr(i_driftRate, drift)) * 24).midiratio;
            outArray[7] = ((lfo * lfoToDecayAmount) + LFNoise1.kr(i_driftRate, drift)) * 2.2;
            outArray[8] = (lfo * lfoToReverbMixAmount) + LFNoise1.kr(i_driftRate, drift);
            Out.kr(out, outArray);
        }).add;

        SynthDef(\eapPassersbyVoice, { |out = 0, lfosIn = 0, t_gate = 0, gate = 0, killGate = 1, freq = 220,
            pitchBendRatio = 1, glide = 0, fm1Ratio = 0.66, fm2Ratio = 3.3, fm1Amount = 0.0, fm2Amount = 0.0,
            vel = 0.7, pressure = 0, timbre = 0, waveShape = 0, waveFolds = 0, envType = 0, attack = 0.04,
            peak = 10000, decay = 1, amp = 1|
            var i_nyquist = SampleRate.ir * 0.5, signal, controlLag = 0.005, i_numHarmonics = 44;
            var modFreq, mod1, mod2, mod1Index, mod2Index, mod1Freq, mod2Freq, sinOsc, triOsc, additiveOsc, additivePhase;
            var filterEnvVel, filterEnvLow, lpgEnvelope, lpgSignal, asrEnvelope, asrFilterFreq, asrSignal, killEnvelope, lfoIn;
            lfoIn = In.kr(lfosIn, self.numLfoDests);
            freq = (freq * lfoIn[0]).clip(0, i_nyquist);
            waveShape = (waveShape + lfoIn[1]).clip(0, 1);
            waveFolds = (waveFolds + lfoIn[2]).clip(0, 3);
            fm1Amount = (fm1Amount + lfoIn[3]).clip(0, 1);
            fm2Amount = (fm2Amount + lfoIn[4]).clip(0, 1);
            attack = (attack + lfoIn[5]).clip(0.003, 8);
            peak = (peak * lfoIn[6]).clip(100, 10000);
            decay = (decay + lfoIn[7]).clip(0.01, self.maxDecay);
            freq = Lag.kr(freq * pitchBendRatio, 0.007 + glide);
            fm1Ratio = Lag.kr(fm1Ratio, controlLag);
            fm2Ratio = Lag.kr(fm2Ratio, controlLag);
            fm1Amount = Lag.kr(fm1Amount.squared, controlLag);
            fm2Amount = Lag.kr(fm2Amount.squared, controlLag);
            vel = Lag.kr(vel, controlLag);
            waveShape = Lag.kr(waveShape, controlLag);
            waveFolds = Lag.kr(waveFolds, controlLag);
            attack = Lag.kr(attack, controlLag);
            peak = Lag.kr(peak, controlLag);
            decay = Lag.kr(decay, controlLag);
            mod1Index = fm1Amount * 22;
            mod1Freq = freq * fm1Ratio * LFNoise2.kr(0.1, 0.001, 1);
            mod1 = SinOsc.ar(mod1Freq, 0, mod1Index * mod1Freq);
            mod2Index = fm2Amount * 12;
            mod2Freq = freq * fm2Ratio * LFNoise2.kr(0.1, 0.005, 1);
            mod2 = SinOsc.ar(mod2Freq, 0, mod2Index * mod2Freq);
            modFreq = freq + mod1 + mod2;
            sinOsc = SinOsc.ar(modFreq, 0, 0.5);
            triOsc = VarSaw.ar(modFreq, 0, 0.5, 0.5);
            additivePhase = LFSaw.ar(modFreq, 1, pi, pi);
            additiveOsc = Mix.fill(i_numHarmonics, { |index|
                var harmonic = index + 1;
                var harmonicFreq = freq * harmonic;
                var harmonicCutoff = i_nyquist - harmonicFreq;
                var attenuation = Select.kr(index, [1, (harmonicCutoff - (harmonicFreq * 0.25) - harmonicFreq).expexp(0.000001, harmonicFreq * 0.5, 0.000001, 1)]);
                (sin(additivePhase * harmonic % 2pi) / harmonic) * attenuation * (harmonic % 2 + waveShape.linlin(0.666666, 1, 0, 1)).min(1);
            });
            signal = LinSelectX.ar(waveShape * 3, [sinOsc, triOsc, additiveOsc]);
            signal = Fold.ar(signal * (1 + (timbre * 0.5) + (waveFolds * 2)), -0.5, 0.5);
            signal = LPF.ar(signal, 12000) + PinkNoise.ar(0.003);
            filterEnvVel = vel.linlin(0, 1, 0.5, 1);
            filterEnvLow = (peak * filterEnvVel).min(300);
            lpgEnvelope = EnvGen.ar(Env([0, 1, 0], [0.003, decay], [4, -20]), t_gate);
            lpgSignal = RLPF.ar(signal, lpgEnvelope.linlin(0, 1, filterEnvLow, peak * filterEnvVel), 0.9);
            lpgSignal = lpgSignal * EnvGen.ar(Env([0, 1, 0], [0.002, decay], [4, -10]), t_gate);
            asrEnvelope = EnvGen.ar(Env([0, 1, 0], [attack, decay], -4, releaseNode: 1), gate);
            asrFilterFreq = asrEnvelope.linlin(0, 1, filterEnvLow, peak * filterEnvVel);
            asrSignal = RLPF.ar(signal, asrFilterFreq, 0.95);
            asrSignal = RLPF.ar(asrSignal, asrFilterFreq, 0.95);
            asrSignal = asrSignal * EnvGen.ar(Env.asr(attack, 1, decay, -4), gate);
            signal = Select.ar(envType.clip(0, 1), [lpgSignal, asrSignal]);
            killEnvelope = EnvGen.kr(Env.asr(0, 1, 0.01), killGate);
            signal = tanh(signal * vel.linlin(0, 1, 0.2, 1) * killEnvelope * pressure.linlin(0, 1, 1.5, 3) * amp).softclip;
            Out.ar(out, signal);
        }).add;

        SynthDef(\eapPassersbyReverb, { |in = 0, out = 0, lfosIn = 0, mix = 0|
            var dry, preProcess, springReso, wet, predelay = 0.015, lfoIn;
            lfoIn = In.kr(lfosIn, self.numLfoDests);
            mix = Lag.kr((mix + lfoIn[8]).clip(0, 1), 0.01);
            dry = In.ar(in, 1);
            preProcess = tanh(BHiShelf.ar(dry, 1000, 1, -6, 1.5));
            preProcess = DelayN.ar(preProcess, predelay, predelay);
            springReso = Klank.ar(`[[508, 270, 1153], [0.15, 0.25, 0.1], [1, 1.2, 1.4]], preProcess);
            springReso = Limiter.ar(springReso).dup;
            preProcess = preProcess * 0.55;
            wet = tanh(FreeVerb2.ar(preProcess, preProcess, 1, 0.7, 0.35, 1.8));
            wet = (wet * 0.935) + (springReso * 0.065);
            Out.ar(out, (dry.dup * (1 - mix)) + (wet * mix));
        }).add;
    };

    ~start = { |self|
        self.stop;
        self.group = Group.tail(s);
        self.lfosBus = Bus.control(s, self.numLfoDests);
        self.fxBus = Bus.audio(s, 1);
        self.makeSynthDefs;
        s.sync;
        self.lfos = Synth(\eapPassersbyLfos, [\out, self.lfosBus], self.group);
        self.voice = Synth(\eapPassersbyVoice, [\out, self.fxBus, \lfosIn, self.lfosBus, \gate, 0, \killGate, 1], self.group, \addToTail);
        self.reverb = Synth(\eapPassersbyReverb, [\in, self.fxBus, \out, self.outBus, \lfosIn, self.lfosBus, \mix, 0.25], self.group, \addToTail);
        self.createScene(self.currentScene);
        self.routine = Routine({
            var scene, freq, dur, gap, vel;
            loop {
                scene = self.scenes[self.currentScene];
                freq = self.chooseNote(scene);
                dur = self.rangeRand(scene[\noteDur]);
                gap = self.rangeRand(scene[\gap]);
                vel = rrand(0.25, 0.9);
                self.noteId = self.noteId + 1;
                self.voice.set(\freq, freq, \vel, vel, \pressure, rrand(0.0, 0.55), \timbre, rrand(0.0, 0.8), \t_gate, 1, \gate, 1, \killGate, 1);
                dur.wait;
                self.voice.set(\gate, 0);
                gap.wait;
            }
        }).play(SystemClock);
        "EAP Passersby: started".postln;
    };

    ~stop = { |self|
        if(self.routine.notNil) { self.routine.stop; self.routine = nil; };
        if(self.group.notNil) { self.group.free; self.group = nil; };
        if(self.lfosBus.notNil) { self.lfosBus.free; self.lfosBus = nil; };
        if(self.fxBus.notNil) { self.fxBus.free; self.fxBus = nil; };
    };
}).know_(true);
