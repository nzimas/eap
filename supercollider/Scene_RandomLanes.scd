// Electroacoustic Playground random independent scene lanes.
// A manual seed creates N autonomous lanes, each with its own source materials, parameters, buses, and FX.

~eap = ~eap ? IdentityDictionary.new;

~eapScenes = Environment.make({
    ~maxScenes = 8;
    ~maxSourcesPerScene = 1;
    ~maxFxPerScene = 2;
    ~group = nil;
    ~masterGroup = nil;
    ~masterBus = nil;
    ~gridFxBus = nil;
    ~reverbBus = nil;
    ~masterSynth = nil;
    ~gridFxSendSynth = nil;
    ~gridFxActive = false;
    ~gridFxScenes = nil;
    ~gridFxQueue = List.new;
    ~gridFxProcessing = false;
    ~externalInputSynth = nil;
    ~externalInputHoldUntil = 0;
    ~reverbValues = nil;
    ~masterValues = nil;
    ~dexedMidi = nil;
    ~dexedAvailable = false;
    ~vitalMidi = nil;
    ~vitalAvailable = false;
    ~vcvMidi = nil;
    ~vcvAvailable = false;
    ~scaleIndex = 0;
    ~rootNote = 0;
    ~muteMode = \refresh;
    ~sourceEnginePreference = nil;
    ~sessionDir = "/home/we/.local/share/eap/sessions";
    ~lanes = List.new;
    ~slots = nil;
    ~cloudLaneIndex = nil;
    ~adaptiveJournal = List.new;
    ~adaptiveSerial = 0;

    ~scales = [
        (0..11),
        [0, 2, 3, 5, 7, 8, 10],
        [0, 2, 4, 5, 7, 9, 11],
        [0, 2, 3, 5, 7, 9, 10],
        [0, 2, 4, 6, 7, 9, 11],
        [0, 1, 4, 6, 8, 10, 11],
        [0, 2, 3, 7, 8],
        [0, 3, 5, 7, 10]
    ];

    ~plaitsModelPool = [0, 1, 3, 4, 5, 6, 11, 12];
    ~plaitsPercussiveModels = [11, 11, 12, 12, 3, 3, 4, 5, 6, 1];

    ~pedalCandidates = [
        \chorus, \phaser, \vibrato, \tremolo, \delay, \reverb,
        \lofi, \wavefolder, \bitcrusher, \ringmod, \autowah
    ];

    ~soundModifierSymbols = [\percussive, \drone, \chaos];
    ~sourceEngineSymbols = [\plaits, \rings, \passersby, \molly, \fm7, \harmonium];

    ~modifierFromCode = { |self, code|
        var index = code.asInteger;
        if((index >= 1) and: { index <= 3 }, { self[\soundModifierSymbols][index - 1] }, { nil });
    };

    ~sourceEngineFromCode = { |self, code|
        var index = code.asInteger;
        if((index >= 1) and: { index <= self[\sourceEngineSymbols].size }, {
            self[\sourceEngineSymbols][index - 1];
        }, {
            nil;
        });
    };

    ~setSourceEnginePreference = { |self, code|
        var engine = self[\sourceEngineFromCode].value(self, code);
        self[\sourceEnginePreference] = engine;
        self[\syncSubsequenceEngine].value(self);
        ("EAP future source engine=" ++ (engine ? \none)).postln;
        engine;
    };

    ~sourceEngineCode = { |self|
        var pref = self[\sourceEnginePreference];
        var code = if(pref.isNil, { 0 }, { self[\sourceEngineSymbols].indexOf(pref) + 1 });
        if(code < 0, { 0 }, { code });
    };

    ~muteModeFromCode = { |self, code|
        if(code.asInteger == 0, { \output }, { \refresh });
    };

    ~muteModeCode = { |self|
        if(self[\muteMode] == \output, { 0 }, { 1 });
    };

    ~setMuteMode = { |self, code|
        self[\muteMode] = self[\muteModeFromCode].value(self, code);
        ("EAP mute mode=" ++ self[\muteMode]).postln;
        self[\muteMode];
    };

    ~syncSubsequenceTuning = { |self|
        var scale = self[\scales].wrapAt(self[\scaleIndex]);
        self[\getSubsequenceAddr].value(self).sendMsg('/eap/seq/tuning',
            self[\scaleIndex], self[\rootNote], scale.size, *scale);
        self[\slots].do({ |lane|
            if(lane.notNil and: { lane[\state] == \active }) {
                self[\syncSubsequenceLane].value(self, lane, true);
            };
        });
        self;
    };

    ~syncSubsequenceEngine = { |self|
        self[\getSubsequenceAddr].value(self).sendMsg('/eap/seq/engine', self[\sourceEngineCode].value(self));
        self[\slots].do({ |lane|
            if(lane.notNil and: { lane[\state] == \active }) {
                self[\syncSubsequenceLane].value(self, lane, true);
            };
        });
        self;
    };

    ~rand = { |self, lo = 0.0, hi = 1.0| rrand(lo.asFloat, hi.asFloat) };
    ~exprand = { |self, lo = 0.001, hi = 1.0| exprand(lo.asFloat, hi.asFloat) };

    ~countInto = { |self, counts, key, amount = 1|
        if(key.notNil, {
            counts[key] = (counts[key] ? 0) + amount;
        });
        counts;
    };

    ~keysWithCountAtLeast = { |self, counts, threshold = 1|
        var keys = List.new;
        counts.keysValuesDo({ |key, value|
            if(value >= threshold, { keys.add(key); });
        });
        keys.asArray;
    };

    ~registerBandFor = { |self, register|
        var center = ((register ? [36, 72])[0] + (register ? [36, 72])[1]) / 2;
        if(center < 48, { \low }, { if(center < 66, { \mid }, { \high }) });
    };

    ~leastUsedRegisterBand = { |self, counts|
        var low = counts[\low] ? 0;
        var mid = counts[\mid] ? 0;
        var high = counts[\high] ? 0;
        if(low <= mid and: { low <= high }, { \low }, {
            if(mid <= high, { \mid }, { \high });
        });
    };

    ~choosePitch = { |self, lane, stepOffset = 0|
        var reg = lane[\register];
        var scale = self[\scales].wrapAt(self[\scaleIndex]);
        var root = self[\rootNote].asInteger.clip(0, 11);
        var degreeIdx;
        var semitone;
        var center = (reg[0] + reg[1]) / 2;
        var octave = (center / 12).floor;
        var transpose = (lane[\transpose] ? 0).asInteger.clip(-36, 36);
        var midi;
        if(lane[\lastDegree].isNil, {
            degreeIdx = [0, 0, 0, 0, 2, 4].choose.clip(0, scale.size - 1);
        }, {
            degreeIdx = (lane[\lastDegree] + stepOffset).wrap(0, scale.size - 1);
        });
        lane[\lastDegree] = degreeIdx;
        semitone = scale[degreeIdx] ? 0;
        midi = (octave * 12) + root + semitone;
        while({ midi < reg[0] and: { octave < 10 } }, {
            octave = octave + 1;
            midi = (octave * 12) + root + semitone;
        });
        while({ midi > reg[1] and: { octave > 0 } }, {
            octave = octave - 1;
            midi = (octave * 12) + root + semitone;
        });
        (midi + transpose).clip(0, 127);
    };

    ~chooseChaosPitch = { |self, lane, stepOffset = 0|
        var reg = lane[\register];
        var scale = self[\scales].wrapAt(self[\scaleIndex]);
        var root = self[\rootNote].asInteger.clip(0, 11);
        var center = (reg[0] + reg[1]) / 2;
        var octave = (center / 12).floor;
        var transpose = (lane[\transpose] ? 0).asInteger.clip(-36, 36);
        var degreeIdx;
        var semitone;
        var midi;
        if(0.38.coin, {
            rrand(reg[0], reg[1]).round(1).clip(0, 127);
        }, {
            if(lane[\lastDegree].isNil, {
                degreeIdx = rrand(0, scale.size - 1).round(1).asInteger;
            }, {
                degreeIdx = (lane[\lastDegree] + stepOffset + [-7, -5, -4, -3, -2, 2, 3, 4, 5, 7].choose)
                    .wrap(0, scale.size - 1);
            });
            lane[\lastDegree] = degreeIdx;
            semitone = scale[degreeIdx] ? 0;
            midi = (octave * 12) + root + semitone;
            while({ midi < reg[0] and: { octave < 10 } }, {
                octave = octave + 1;
                midi = (octave * 12) + root + semitone;
            });
            while({ midi > reg[1] and: { octave > 0 } }, {
                octave = octave - 1;
                midi = (octave * 12) + root + semitone;
            });
            (midi + transpose).clip(0, 127);
        });
    };

    ~scaleStepsForLane = { |self, lane|
        switch(lane[\soundModifier],
            \percussive, { [-2, -1, 0, 0, 0, 0, 1, 1, 2, 3] },
            \drone, { [0, 0, 0, 1, 1, 2, 2, 4, -1] },
            \harmonic, { [-2, -1, 0, 0, 0, 1, 1, 2, 3, 4] },
            \chaos, { [-4, -3, -2, -1, 0, 1, 2, 3, 4, 5] },
            { [-2, -1, 0, 0, 0, 1, 2, 3, 4] }
        );
    };

    ~subsequenceHost = "127.0.0.1";
    ~subsequencePort = 57122;
    ~subsequenceNetAddr = nil;

    ~getSubsequenceAddr = { |self|
        var addr = self[\subsequenceNetAddr];
        if(addr.isNil, {
            addr = NetAddr(self[\subsequenceHost], self[\subsequencePort]);
            self[\subsequenceNetAddr] = addr;
        });
        addr;
    };

    ~seqDensityForLane = { |self, lane|
        ((lane[\density] ? 1.0) * (lane[\densitySkew] ? 1.0)).asFloat.clip(0.05, 1.0);
    };

    ~displayDensityForLane = { |self, lane|
        if(lane.isNil or: { lane[\state] == \blank }, {
            0;
        }, {
            ((lane[\density] ? 1.0).asFloat.clip(0.05, 1.0) * 127).round(1).asInteger;
        });
    };

    ~syncSubsequenceLane = { |self, lane, active = true|
        var slot, addr, seed, scale, material;
        if(lane.isNil) { ^self; };
        slot = (lane[\slot] ? lane[\index] ? 1).asInteger.clip(1, self[\maxScenes]);
        addr = self[\getSubsequenceAddr].value(self);
        if(active and: { lane[\state] == \active }) {
            seed = (lane[\slot] ? lane[\index] ? 1).hash.abs;
            scale = self[\scales].wrapAt(self[\scaleIndex]);
            material = (lane[\materials][0] ? \none).asString;
            addr.sendMsg('/eap/seq/lane', slot, 1,
                (lane[\soundModifier] ? \harmonic).asString,
                (lane[\pulse] ? 0.12).asFloat,
                self[\seqDensityForLane].value(self, lane),
                (lane[\rhythmProfile] ? \euclid).asString,
                lane[\materials].size.max(1),
                (lane[\restProb] ? 0.12).asFloat,
                (lane[\swing] ? 0.0).asFloat,
                seed,
                material,
                self[\scaleIndex],
                self[\rootNote],
                self[\sourceEngineCode].value(self),
                scale.size,
                *scale
            );
        } {
            addr.sendMsg('/eap/seq/lane', slot, 0);
        };
        self;
    };

    ~syncSubsequenceDensity = { |self, slot, density|
        var lane = self[\slots][slot.asInteger - 1];
        var effective = if(lane.notNil, {
            self[\seqDensityForLane].value(self, lane);
        }, {
            density.asFloat.clip(0.05, 1.0);
        });
        self[\getSubsequenceAddr].value(self).sendMsg('/eap/seq/density', slot, effective);
        self;
    };

    ~syncSubsequenceAllLanes = { |self, active = false|
        (1).to(self[\maxScenes]).do({ |slot|
            self[\getSubsequenceAddr].value(self).sendMsg('/eap/seq/lane', slot, if(active, { 1 }, { 0 }));
        });
        self;
    };

    ~onSubsequenceEvent = { |self, msg|
        var slot, lane, event, voices, isDrone, isPerc, isRest, sustainEvent;
        slot = (msg[1] ? 1).asInteger.clip(1, self[\maxScenes]);
        lane = self[\slots][slot - 1];
        if(lane.isNil or: { lane[\state] != \active }) { ^self; };
        isRest = (msg[7] ? 0).asInteger == 1;
        if(isRest) { ^self; };
        isDrone = lane[\soundModifier] == \drone;
        isPerc = lane[\soundModifier] == \percussive;
        sustainEvent = (msg[8] ? 0).asInteger == 1;
        event = (
            accent: (msg[2] ? 1.0).asFloat.clip(0.0, 2.2),
            scaleStep: (msg[3] ? 0).asInteger,
            sourceCount: (msg[4] ? 1).asInteger,
            panBias: (msg[5] ? 0.0).asFloat.clip(-0.55, 0.55),
            decayScale: if(isDrone,
                { (msg[6] ? 1.0).asFloat.clip(1.5, 8.0) },
                if(isPerc,
                    { (msg[6] ? 1.0).asFloat.clip(0.45, 2.4) },
                    { (msg[6] ? 1.0).asFloat.clip(0.25, 2.4) }
                )
            ),
            sustain: sustainEvent,
            isRest: 0,
            hits: 1
        );
        voices = 1;
        if(isDrone or: { sustainEvent }, {
            self[\triggerLane].value(self, lane, event);
        }, {
            if(self[\laneMayTrigger].value(self, lane, voices)) {
                self[\triggerLane].value(self, lane, event);
            };
        });
        self;
    };

    ~rhythmProfilesFor = { |modifier|
        switch(modifier,
            \percussive, { [
                \grid16, \grid16, \shuffle16, \euclid, \euclid, \rotateEuclid, \layeredEuclid,
                \nestedEuclid, \bresenham, \bresenhamWeighted, \moduloLattice, \primeLattice,
                \fibonacci, \vanDerCorput, \thueMorse, \pulseFold, \poly23, \polyphase,
                \ratioLattice, \interference, \densityWave, \ghostGrid, \weightedHits,
                \clusterCompress, \walkHits, \selfAvoid, \lsystem, \probGate
            ] },
            \drone, { [\pulse, \breath, \swell, \ritual] },
            \harmonic, { [\arp, \motif, \canon, \hymn, \pulseHarm] },
            \chaos, { [
                \stutter, \wander, \flare, \glitch, \grainCloud, \lorenzSpray, \poissonField,
                \vdcScatter, \microCluster, \caSnapshot, \deBruijnGlitch, \logisticSwarm,
                \spectralDrift, \sparseBolt, \noiseConvolve
            ] },
            { [\steady, \flow] }
        );
    };


    ~playTuningPreview = { |self|
        self[\slots].do({ |lane|
            if(lane.notNil and: { lane[\state] == \active }) {
                lane[\lastDegree] = nil;
                self[\triggerLane].value(self, lane, (
                    sourceCount: 1,
                    accent: 0.9,
                    scaleStep: 0,
                    panBias: 0,
                    decayScale: 0.7
                ));
            };
        });
    };

    ~laneConsumesLoad = { |lane|
        lane.notNil and: {
            (lane[\state] == \active) or: {
                (lane[\state] == \muted) and: { lane[\mutedMode] == \output }
            }
        };
    };

    ~activeCount = { |self|
        self[\slots].count({ |lane| self[\laneConsumesLoad].value(lane) });
    };

    ~loadFactor = { |self|
        (self[\activeCount].value(self) / self[\maxScenes].max(1)).clip(0.0, 1.0);
    };

    ~minDeltaForLane = { |self, lane|
        var load = self[\activeCount].value(self);
        var base = switch(lane[\soundModifier],
            \percussive, { 0.055 },
            \chaos, { 0.065 },
            \harmonic, { 0.08 },
            \drone, { 0.12 },
            { 0.09 }
        );
        (base + (load * 0.04)).max(0.05);
    };

    ~maxDeltaForLane = { |self, lane|
        switch(lane[\soundModifier],
            \percussive, { 0.42 },
            \chaos, { 0.72 },
            \harmonic, { 1.15 },
            \drone, { 2.75 },
            { 1.35 }
        );
    };

    ~tickIntervalForLane = { |self, lane|
        var load = self[\activeCount].value(self);
        var base = switch(lane[\soundModifier],
            \percussive, { 0.18 },
            \chaos, { 0.26 },
            \harmonic, { 0.46 },
            \drone, { 1.35 },
            { 0.58 }
        );
        (base + (load * 0.015)).clip(0.08, 1.8);
    };

    ~laneTriggerBudget = { |self, lane|
        var idx = (self[\activeCount].value(self) - 1).clip(0, 5);
        switch(lane[\soundModifier],
            \percussive, { [10, 7, 4, 3, 2, 1][idx] },
            \drone, { [4, 3, 2, 1, 1, 1][idx] },
            \harmonic, { [5, 4, 3, 2, 1, 1][idx] },
            \chaos, { [8, 6, 4, 3, 2, 1][idx] },
            { [5, 4, 3, 2, 1, 1][idx] }
        );
    };

    ~laneMayTrigger = { |self, lane, voiceCount = 1|
        var now = Main.elapsedTime;
        var times = lane[\triggerTimes] ? [];
        var budget = self[\laneTriggerBudget].value(self, lane);
        times = times.select({ |t| now - t < 1.0 });
        if(times.size + voiceCount > budget, {
            false;
        }, {
            lane[\triggerTimes] = times ++ Array.fill(voiceCount, { now });
            true;
        });
    };

    ~sustainLoadScale = { |self|
        var load = self[\activeCount].value(self);
        if(load >= 4, { 0.38 }, {
            if(load >= 3, { 0.52 }, {
                if(load >= 2, { 0.72 }, { 1.0 });
            });
        });
    };

    ~hasActiveCloud = { |self|
        self[\slots].any({ |lane| lane.notNil and: { (lane[\state] == \active) and: { lane[\fx] == \clouds } } });
    };

    ~makeSynthDefs = { |self|
        if(~eapFx.notNil and: { ~eapFx[\pedalboard].notNil }) {
            ~eapFx[\pedalboard][\makeSynthDefs].value(~eapFx[\pedalboard]);
        };

        SynthDef(\eapSceneMaster, { |in = 0, reverbIn = 0, out = 0, amp = 0.86,
            wet = 0.24, room = 0.55, damp = 0.45, decay = 3.2,
            lowCut = 120, highCut = 9500, modDepth = 0.08, bright = 0.75,
            masterVol = 0.82, overdrive = 0.0, bitDepth = 1.0, saturation = 0.12,
            compProfile = 0, gridActive = 0, gridInGain = 1|
            var dryInternal, dryExternal, dry, send, pre, verb, sig, driven, saturated, folded, grimy, sat, srFreq, levels, degraded;
            var profile, idx, threshold, slopeAbove, clampTime, relaxTime, makeup, compressed, bypass;
            dryInternal = LeakDC.ar(In.ar(in, 2));
            dryExternal = LeakDC.ar(SoundIn.ar([0, 1])) * gridInGain.clip(0, 2);
            dry = dryInternal + (dryExternal * Lag.kr(gridActive.clip(0, 1), 0.08));
            send = LeakDC.ar(In.ar(reverbIn, 2));
            pre = HPF.ar(LPF.ar(send, highCut.clip(1200, 18000)), lowCut.clip(20, 1200));
            verb = JPverb.ar(pre, decay.clip(0.7, 12), damp.clip(0.05, 0.95),
                room.clip(0.15, 1.2), 0.72, modDepth.clip(0.0, 0.6), 2.0,
                1, bright.clip(0.1, 1.2), 1, lowCut.clip(20, 1200), highCut.clip(1200, 18000));
            sig = dry + (verb * wet.clip(0, 0.9));
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
            profile = compProfile.clip(0, 8);
            bypass = (profile <= 0).clip(0, 1);
            idx = (profile - 1).clip(0, 7);
            threshold = Select.kr(idx, [0.82, 0.72, 0.62, 0.52, 0.42, 0.34, 0.26, 0.20]);
            slopeAbove = Select.kr(idx, [0.82, 0.70, 0.58, 0.46, 0.34, 0.25, 0.17, 0.11]);
            clampTime = Select.kr(idx, [0.030, 0.024, 0.018, 0.014, 0.010, 0.007, 0.004, 0.002]);
            relaxTime = Select.kr(idx, [0.360, 0.300, 0.240, 0.190, 0.145, 0.105, 0.075, 0.050]);
            makeup = Select.kr(idx, [1.00, 1.06, 1.13, 1.22, 1.34, 1.50, 1.74, 2.05]);
            compressed = Compander.ar(sig, sig, threshold, 1, slopeAbove, clampTime, relaxTime) * makeup;
            sig = (sig * bypass) + (compressed * (1 - bypass));
            sig = Limiter.ar(sig * masterVol.clip(0, 1) * amp, 0.98, 0.01);
            Out.ar(out, sig);
        }).add;

        SynthDef(\eapGridFxSend, { |in = 0, out = 2, amp = 0, fadeTime = 0.08|
            var sig = LeakDC.ar(In.ar(in, 2));
            Out.ar(out, Limiter.ar(sig * Lag.kr(amp, fadeTime).clip(0, 1), 0.95, 0.01));
        }).add;

        SynthDef(\eapExternalInput, { |out = 0, amp = 0.0, fadeTime = 0.08, inL = 2, inR = 3|
            var sig = SoundIn.ar([inL, inR]);
            sig = HPF.ar(LeakDC.ar(sig), 18);
            Out.ar(out, Limiter.ar(sig * Lag.kr(amp, fadeTime), 0.94, 0.01));
        }).add;

        SynthDef(\eapLaneExternalInput, { |out = 0, amp = 0.0, fadeTime = 0.035, inL = 2, inR = 3|
            var sig = SoundIn.ar([inL, inR]);
            sig = HPF.ar(LeakDC.ar(sig), 18);
            Out.ar(out, Limiter.ar(sig * Lag.kr(amp, fadeTime), 0.94, 0.01));
        }).add;

        SynthDef(\eapLanePlaitsNote, { |out = 0, pitch = 60, engine = 0, harm = 0.4,
            timbre = 0.5, morph = 0.5, level = 0.8, decay = 0.8, colour = 0.5,
            amp = 0.1, pan = 0, envTail = 0.25, modDepth = 0, modRate = 0.2, modShape = 0, modRand = 0|
            var trig, sig, env, lfo, drift, h, t, m, c;
            trig = Trig1.kr(1, 0.01);
            lfo = Select.kr(modShape.clip(0, 3), [
                SinOsc.kr(modRate), LFTri.kr(modRate), LFSaw.kr(modRate), LFNoise2.kr(modRate)
            ]);
            drift = LFNoise1.kr((modRate * 0.5).max(0.05));
            h = (harm + (lfo * modDepth * 0.24) + (drift * modRand * 0.18)).clip(0, 1);
            t = (timbre + (lfo * modDepth * 0.30) + (drift * modRand * 0.24)).clip(0, 1);
            m = (morph + (lfo * modDepth * 0.36) + (drift * modRand * 0.28)).clip(0, 1);
            c = (colour + (lfo * modDepth * 0.22) + (drift * modRand * 0.18)).clip(0, 1);
            sig = MiPlaits.ar(pitch, engine, h, t, m, trig, level, 0, 0, 0, decay, c);
            env = EnvGen.kr(Env.linen(0.002, decay.max(0.015), envTail.clip(0.01, 6.0)), doneAction: 2);
            sig = Balance2.ar(sig[0], sig[1], pan, amp) * env;
            Out.ar(out, LeakDC.ar(sig));
        }).add;

        SynthDef(\eapLaneRingsNote, { |out = 0, pitch = 60, struct = 0.4,
            bright = 0.5, damp = 0.7, pos = 0.4, model = 0, poly = 2,
            envDecay = 8.0, envRelease = 1.2, amp = 0.12, pan = 0,
            modDepth = 0, modRate = 0.2, modShape = 0, modRand = 0,
            strike = 1.0, exciterDecay = 0.09|
            var trig, exciter, sig, env, lfo, drift, st, br, da, po, burst;
            // Audio-rate single strike. With the engine's 4096-sample block, a kr
            // trigger/exciter cannot resolve a sub-100ms burst (control period ~85ms),
            // which left MiRings barely excited and effectively silent. Drive it at ar.
            trig = Impulse.ar(0);
            lfo = Select.kr(modShape.clip(0, 3), [
                SinOsc.kr(modRate), LFTri.kr(modRate), LFSaw.kr(modRate), LFNoise2.kr(modRate)
            ]);
            drift = LFNoise1.kr((modRate * 0.4).max(0.04));
            st = (struct + (lfo * modDepth * 0.24) + (drift * modRand * 0.18)).clip(0, 1);
            br = (bright + (lfo * modDepth * 0.28) + (drift * modRand * 0.22)).clip(0, 1);
            da = (damp + (lfo * modDepth * 0.20) + (drift * modRand * 0.18)).clip(0, 1);
            po = (pos + (lfo * modDepth * 0.30) + (drift * modRand * 0.22)).clip(0, 1);
            burst = Decay2.ar(trig, 0.0008, exciterDecay.clip(0.03, 0.18));
            exciter = HPF.ar((PinkNoise.ar(0.6) + WhiteNoise.ar(0.4)) * burst * strike.clip(0.6, 1.8), 90);
            sig = MiRings.ar(exciter, trig, pitch, st, br, da, po, model, poly, 1, 0);
            env = EnvGen.ar(Env.linen(0.002, envDecay.max(0.04), envRelease.max(0.02)), doneAction: 2);
            // MiRings returns [odd, even] outputs. In monophonic mode those are
            // complementary partials of the same struck resonator (both lit).
            // In polyphonic mode (poly>1) they are odd-numbered vs even-numbered
            // strings, and a single strike excites only one string -> only one
            // of the two outputs carries signal. Sum to mono, then Pan2 by the
            // lane pan so audio always lands in both channels regardless of poly.
            sig = HPF.ar(LeakDC.ar(sig.sum), 28);
            sig = Pan2.ar(sig, pan, amp * strike.linlin(0.6, 1.8, 0.9, 1.2)) * env;
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
            filterRq = 0.7, toneTilt = 0.5, amp = 0.1, pan = 0,
            modDepth = 0, modRate = 0.2, modShape = 0, modRand = 0|
            var nyquist = SampleRate.ir * 0.5, signal, folded, bodySig, airSig, mod1, mod2, modFreq;
            var sinOsc, triOsc, additiveOsc, additivePhase, filterEnvLow, env, rq, lfo, drift;
            var shape, folds, fm1, fm2, peakMod, tilt;
            lfo = Select.kr(modShape.clip(0, 3), [
                SinOsc.kr(modRate), LFTri.kr(modRate), LFSaw.kr(modRate), LFNoise2.kr(modRate)
            ]);
            drift = LFNoise1.kr((modRate * 0.55).max(0.05));
            shape = (waveShape + (lfo * modDepth * 0.28) + (drift * modRand * 0.20)).clip(0, 1);
            folds = (waveFolds + (lfo * modDepth * 1.1) + (drift * modRand * 0.8)).clip(0, 3);
            fm1 = (fm1Amount + (lfo.abs * modDepth * 0.18) + (drift.abs * modRand * 0.14)).clip(0, 1).squared;
            fm2 = (fm2Amount + (lfo.abs * modDepth * 0.14) + (drift.abs * modRand * 0.12)).clip(0, 1).squared;
            peakMod = (peak * (1 + (lfo * modDepth * 1.0) + (drift * modRand * 0.75))).clip(120, 12000);
            tilt = (toneTilt + (lfo * modDepth * 0.24) + (drift * modRand * 0.18)).clip(0, 1);
            mod1 = SinOsc.ar(freq * fm1Ratio * LFNoise2.kr(0.1, 0.001, 1), 0, fm1 * 22 * freq);
            mod2 = SinOsc.ar(freq * fm2Ratio * LFNoise2.kr(0.1, 0.005, 1), 0, fm2 * 12 * freq);
            modFreq = (freq + mod1 + mod2).clip(20, nyquist);
            sinOsc = SinOsc.ar(modFreq, 0, 0.5);
            triOsc = VarSaw.ar(modFreq, 0, 0.5, 0.5);
            additivePhase = LFSaw.ar(modFreq, 1, pi, pi);
            additiveOsc = Mix.fill(12, { |index|
                var harmonic = index + 1;
                (sin(additivePhase * harmonic % 2pi) / harmonic)
                    * (harmonic % 2 + shape.linlin(0.666666, 1, 0, 1)).min(1);
            });
            signal = LinSelectX.ar(shape * 3, [sinOsc, triOsc, additiveOsc]);
            folded = Fold.ar(signal * (1 + (folds * 2)), -0.5, 0.5);
            signal = XFade2.ar(signal, folded, (foldMix.clip(0, 1) * 2) - 1);
            bodySig = SinOsc.ar(freq * 0.5, 0, body.clip(0, 1) * 0.22);
            airSig = BPF.ar(PinkNoise.ar(air.clip(0, 0.08)), tilt.linexp(0, 1, 1800, 9500), 0.45);
            signal = LPF.ar(signal + bodySig + airSig, tilt.linexp(0, 1, 4500, 15000));
            filterEnvLow = peakMod.min(300);
            rq = filterRq.clip(0.18, 0.95);
            env = EnvGen.ar(Env([0, 1, 0], [attack.max(0.003), decay.max(0.03)], [4, -8]), doneAction: 2);
            signal = RLPF.ar(signal, env.linlin(0, 1, filterEnvLow, peakMod), rq) * env;
            signal = signal * (1 + (reverbMix.clip(0, 0.7) * 0.18));
            Out.ar(out, Pan2.ar(tanh(signal * amp * 2.1).softclip, pan));
        }).add;

        SynthDef(\eapLaneFM7Note, { |out = 0, freq = 220, algorithm = 0,
            ratio1 = 1, ratio2 = 2, ratio3 = 3, ratio4 = 1.5, ratio5 = 4, ratio6 = 0.5,
            opAmp1 = 1, opAmp2 = 0.45, opAmp3 = 0.28, opAmp4 = 0.20, opAmp5 = 0.16, opAmp6 = 0.10,
            carrier1 = 1, carrier2 = 0, carrier3 = 0, carrier4 = 0, carrier5 = 0, carrier6 = 0,
            index1 = 0.5, index2 = 0.25, index3 = 0.14, feedback = 0.0,
            attack = 0.01, decay = 0.8, sustain = 0.35, release = 0.6,
            brightness = 0.55, grit = 0.12, amp = 0.1, pan = 0,
            modDepth = 0, modRate = 0.2, modShape = 0, modRand = 0|
            var alg, lfo, drift, bright, fb, idx1, idx2, idx3, ratios, amps, ctrls, mods, sigs, carriers, sig, env;
            var e1, e2, e3, e4, e5, e6;
            alg = algorithm.clip(0, 7);
            lfo = Select.kr(modShape.clip(0, 3), [
                SinOsc.kr(modRate), LFTri.kr(modRate), LFSaw.kr(modRate), LFNoise2.kr(modRate)
            ]);
            drift = LFNoise1.kr((modRate * 0.47).max(0.04));
            bright = (brightness + (lfo * modDepth * 0.35) + (drift * modRand * 0.24)).clip(0, 1);
            idx1 = (index1 + (lfo.abs * modDepth * 1.2) + (drift.abs * modRand * 0.65)).clip(0, 9.5);
            idx2 = (index2 + (lfo.abs * modDepth * 0.9) + (drift.abs * modRand * 0.45)).clip(0, 7.5);
            idx3 = (index3 + (lfo.abs * modDepth * 0.7) + (drift.abs * modRand * 0.35)).clip(0, 6.0);
            fb = (feedback + (drift.abs * modRand * 0.35)).clip(0, 3.0);
            ratios = [ratio1, ratio2, ratio3, ratio4, ratio5, ratio6].collect({ |r| r.clip(0.125, 16) });
            amps = [opAmp1, opAmp2, opAmp3, opAmp4, opAmp5, opAmp6].collect({ |a| a.clip(0, 1.4) });
            e1 = EnvGen.kr(Env.adsr(attack.max(0.001), decay.max(0.02), sustain.clip(0, 1), release.max(0.02), curve: -4), doneAction: 0);
            e2 = EnvGen.kr(Env.adsr((attack * 0.65).max(0.001), (decay * 0.75).max(0.02), (sustain * 0.8).clip(0, 1), (release * 0.72).max(0.02), curve: -4), doneAction: 0);
            e3 = EnvGen.kr(Env.adsr((attack * 0.45).max(0.001), (decay * 0.55).max(0.02), (sustain * 0.55).clip(0, 1), (release * 0.55).max(0.02), curve: -4), doneAction: 0);
            e4 = EnvGen.kr(Env.adsr((attack * 0.35).max(0.001), (decay * 0.42).max(0.02), (sustain * 0.45).clip(0, 1), (release * 0.45).max(0.02), curve: -4), doneAction: 0);
            e5 = EnvGen.kr(Env.adsr((attack * 0.28).max(0.001), (decay * 0.32).max(0.02), (sustain * 0.35).clip(0, 1), (release * 0.38).max(0.02), curve: -4), doneAction: 0);
            e6 = EnvGen.kr(Env.adsr((attack * 0.22).max(0.001), (decay * 0.25).max(0.02), (sustain * 0.25).clip(0, 1), (release * 0.32).max(0.02), curve: -4), doneAction: 0);
            ctrls = [
                [Lag.kr(freq * ratios[0], 0.01), 0, amps[0] * e1],
                [Lag.kr(freq * ratios[1], 0.01), 0, amps[1] * e2],
                [Lag.kr(freq * ratios[2], 0.01), 0, amps[2] * e3],
                [Lag.kr(freq * ratios[3], 0.01), 0, amps[3] * e4],
                [Lag.kr(freq * ratios[4], 0.01), 0, amps[4] * e5],
                [Lag.kr(freq * ratios[5], 0.01), 0, amps[5] * e6]
            ];
            mods = [
                [Select.kr(alg, [fb, 0, 0, fb, 0, fb * 0.35, 0, fb * 0.6]), Select.kr(alg, [idx1, idx1, 0, 0, idx2, 0, idx1, idx1]), Select.kr(alg, [idx2, 0, idx1, idx2, 0, idx1, 0, 0]), Select.kr(alg, [0, 0, 0, idx3, 0, 0, idx2, 0]), 0, Select.kr(alg, [0, 0, 0, 0, idx3, 0, 0, idx2])],
                [0, Select.kr(alg, [0, fb, fb, 0, 0, 0, fb, 0]), Select.kr(alg, [0, idx2, idx1, 0, idx1, idx2, 0, idx3]), Select.kr(alg, [0, 0, idx2, 0, 0, 0, idx2, 0]), 0, 0],
                [0, 0, Select.kr(alg, [0, 0, fb, 0, fb, 0, 0, fb * 0.25]), Select.kr(alg, [0, idx2, 0, idx1, idx1, idx3, idx1, idx2]), Select.kr(alg, [0, 0, 0, idx2, 0, 0, 0, 0]), 0],
                [0, 0, 0, Select.kr(alg, [0, 0, 0, fb, 0, fb, 0, 0]), Select.kr(alg, [0, 0, 0, idx2, idx1, idx2, idx3, idx1]), Select.kr(alg, [0, 0, 0, 0, idx2, 0, 0, 0])],
                [0, 0, 0, 0, Select.kr(alg, [0, 0, 0, 0, fb, 0, fb * 0.5, 0]), Select.kr(alg, [0, 0, 0, 0, idx1, idx1, idx2, idx3])],
                [0, 0, 0, 0, 0, Select.kr(alg, [0, 0, 0, 0, 0, fb, 0, fb])]
            ];
            sigs = FM7.ar(ctrls, mods);
            carriers = [carrier1, carrier2, carrier3, carrier4, carrier5, carrier6];
            sig = Mix.fill(6, { |i| sigs[i] * carriers[i].clip(0, 1) });
            sig = HPF.ar(LeakDC.ar(sig), 22);
            sig = LPF.ar(sig, bright.linexp(0, 1, 1200, 18000));
            sig = XFade2.ar(sig, Fold.ar(sig * grit.linlin(0, 1, 1.0, 3.4), -0.7, 0.7), (grit.clip(0, 1) * 2) - 1);
            env = EnvGen.kr(Env.linen(0.001, (attack + decay).max(0.03), release.max(0.02)), doneAction: 2);
            Out.ar(out, Pan2.ar(Limiter.ar(tanh(sig * 1.8) * amp * env, 0.95), pan));
        }).add;

        // Harmonium (after Trevor Treglia's HARMONIUM): an additive resonant-bank
        // voice. A selectable source feeds a 10-partial BPF bank tuned to a
        // harmonic/Bark/Buchla formation, with per-partial pan swirl and amp
        // shimmer, optional ring/freq-shift modulation and sub octaves. A dry
        // floor of the enveloped source guarantees audibility regardless of bank
        // settings. One-shot and audio-rate throughout so it renders correctly at
        // the engine's 4096-sample block.
        SynthDef(\eapLaneHarmoniumNote, { |out = 0, freq = 220, amp = 0.12, pan = 0,
            envAttack = 0.01, envDecay = 2.0, envRelease = 1.2,
            source = 4, formation = 0, num = 10, rolloff = 1.0,
            rq = 0.02, bandRes = 0.3, timbre = 0.5, ouMode = 0, pulseWidth = 0.5,
            rmMix = 0.0, rmHz = 30, rmRatio = 1.0, rmTrack = 0,
            fmMix = 0.0, fmIndex = 0.0, fmRatio = 1.0, fmTrack = 1,
            subAmp = 0.0, subOct1 = 0, subOct2 = 0,
            swirlDepth = 0.4, swirlRate = 0.05, ampShimmer = 0.3, makeup = 14, wet = 0.6,
            modDepth = 0, modRate = 0.2, modShape = 0, modRand = 0|
            var maxP = 10, inds, nyq, fundEff, freqsOver, freqsUnder, useUnder, bankHarm;
            var barkArr, barkFreqs, buchArr, buchFreqs, freqs, numMask, valid, actMask;
            var ampWeights, ampWG, qmul, rqSafe, bandArea;
            var saw, pulse, sine, tri, white, pink, harmFreqs, keep, harmOsc, src, srcMono;
            var lfo, timbreCtl, darkSrc, brightSrc, procSrc;
            var rmFreq, ringOsc, ringSig, fmFreq, fmMod, fmCar;
            var env, bands, resGain, wetSig, ampLFO, ampMod, pos, lGains, rGains, wetL, wetR, swirl;
            var powerSum, compGain, sig, subSig, sigOut, drySig, dryLevel;
            inds = (1..maxP);
            nyq = SampleRate.ir * 0.5;
            fundEff = freq.max(0.01);
            freqsOver = fundEff * inds;
            freqsUnder = fundEff / inds;
            useUnder = (ouMode > 0.5);
            bankHarm = ((1 - useUnder) * freqsOver) + (useUnder * freqsUnder);
            barkArr = #[60,150,250,350,450,570,700,840,1000,1170];
            barkFreqs = barkArr;
            buchArr = #[88,125,190,285,430,650,1000,1500,2200,3300];
            buchFreqs = buchArr;
            freqs = Array.fill(maxP, { |i| Select.kr(formation.clip(0,2), [bankHarm[i], barkFreqs[i], buchFreqs[i]]) });
            numMask = (inds <= num);
            valid = (freqs >= 20) * (freqs <= (nyq * 0.9));
            actMask = numMask * valid;
            ampWeights = inds.asFloat.pow(rolloff.neg);
            ampWG = ampWeights;
            qmul = bandRes.clip(0,1).exprange(1, 12);
            rqSafe = (rq / qmul).max(0.0001);
            bandArea = rqSafe * qmul;
            lfo = Select.kr(modShape.clip(0,3), [SinOsc.kr(modRate), LFTri.kr(modRate), LFSaw.kr(modRate), LFNoise2.kr(modRate)]);
            saw   = VarSaw.ar(fundEff, 0, 0.5);
            pulse = Pulse.ar(fundEff, pulseWidth.clip(0.01,0.99));
            sine  = SinOsc.ar(fundEff);
            tri   = LFTri.ar(fundEff);
            pink  = PinkNoise.ar;
            white = WhiteNoise.ar;
            harmFreqs = fundEff * inds;
            keep = harmFreqs <= nyq;
            harmOsc = Mix.ar(SinOsc.ar(harmFreqs, 0, keep)) * (1.0 / maxP);
            // normalize source amplitudes so all selections sit near +/-0.45
            src = Select.ar(source.clip(0,6), [sine*0.5, tri*0.5, saw*0.45, pulse*0.4, harmOsc*3.5, pink*0.6, white*0.45]);
            src = LeakDC.ar(src);
            srcMono = src;
            timbreCtl = (timbre + (lfo * modDepth * 0.18)).clip(0,1);
            darkSrc = LPF.ar(srcMono, timbreCtl.exprange(800,4000));
            brightSrc = (HPF.ar(srcMono, timbreCtl.exprange(200,4000)) * timbreCtl.linlin(0,1,1,3)).tanh;
            procSrc = XFade2.ar(darkSrc, brightSrc, timbreCtl.linlin(0,1,-1,1));
            rmFreq = ((1 - rmTrack.clip(0,1)) * rmHz.clip(0.1,20000)) + (rmTrack.clip(0,1) * (fundEff * rmRatio).clip(0.1,20000));
            ringOsc = SinOsc.ar(rmFreq);
            ringSig = procSrc * ringOsc;
            procSrc = XFade2.ar(procSrc, ringSig, (rmMix.clip(0,1) * 2 - 1));
            fmFreq = ((1 - fmTrack.clip(0,1)) * 100) + (fmTrack.clip(0,1) * (fundEff * fmRatio).clip(0.1,20000));
            fmMod = SinOsc.ar(fmFreq);
            fmCar = FreqShift.ar(procSrc, fmMod * fmIndex.max(0) * fmFreq);
            procSrc = XFade2.ar(procSrc, fmCar, (fmMix.clip(0,1) * 2 - 1));
            env = EnvGen.ar(Env.linen(envAttack.max(0.001), envDecay.max(0.02), envRelease.max(0.02), curve: -3), doneAction: 2);
            resGain = bandRes.clip(0,1).exprange(1, 8);
            bands = BPF.ar(procSrc * env, freqs, rqSafe) * rqSafe * resGain * actMask * ampWG;
            // per-partial amp shimmer (one cheap control-rate LFO each)
            ampLFO = Array.fill(maxP, { |i| SinOsc.kr((0.05 + (0.06 * i)) * (1 + ampShimmer), Rand(0,2pi)).range(0,1) });
            ampMod = (1 - ampShimmer.clip(0,1)) + (ampShimmer.clip(0,1) * ampLFO);
            bands = bands * ampMod;
            // Cheap stereo: equal-power static spread via compile-time pan gains
            // (no per-partial Pan2 UGens) followed by one slow Rotate2 swirl. The
            // pan param biases the rotation so lane panning still applies.
            pos = Array.fill(maxP, { |i| ((i / (maxP - 1)) * 2 - 1) * 0.9 });
            lGains = pos.collect({ |p| ((1 - p) * 0.25 * pi).cos });
            rGains = pos.collect({ |p| ((1 - p) * 0.25 * pi).sin });
            wetL = (bands * lGains).sum;
            wetR = (bands * rGains).sum;
            swirl = (SinOsc.kr(swirlRate.max(0.0001)) * swirlDepth.clip(0,1) * 0.4) + (pan * 0.25);
            wetSig = Rotate2.ar(wetL, wetR, swirl);
            powerSum = (((ampWG * ampWG) * bandArea * actMask).sum) + 1e-9;
            compGain = powerSum.reciprocal.sqrt * makeup.max(0.1);
            // Dry enveloped source guarantees audibility; the resonant bank adds
            // the harmonium colour on top. Dry is never fully removed.
            drySig = Pan2.ar(procSrc * env, pan.clip(-1, 1));
            dryLevel = 1 - (wet.clip(0,1) * 0.7);
            sig = (drySig * dryLevel) + (wetSig * compGain * wet.clip(0,1));
            subSig = ((SinOsc.ar(fundEff * 0.5) * subOct1) + (SinOsc.ar(fundEff * 0.25) * subOct2)) * subAmp.clip(0,1);
            sig = sig + ((subSig * env) ! 2);
            sigOut = LeakDC.ar(sig) * amp;
            sigOut = Limiter.ar(sigOut, 0.95, 0.01);
            Out.ar(out, sigOut);
        }).add;

        SynthDef(\eapLaneCloudsFx, { |in = 0, out = 0, sendOut = 0, gridOut = 0,
            send = 0.5, gridSend = 0, dryAmp = 1, pit = 0, pos = 0.5,
            size = 0.25, dens = 0.4, tex = 0.5, drywet = 0.55, in_gain = 1,
            spread = 0.5, rvb = 0.2, fb = 0.1, freeze = 0, mode = 0, lofi = 0,
            amp = 0.84, pan = 0, fadeTime = 0.05|
            var source, sig;
            source = LeakDC.ar(In.ar(in, 2));
            sig = MiClouds.ar(source, pit, pos, size, dens, tex, drywet, in_gain,
                spread, rvb, fb, freeze, mode, lofi, 0);
            sig = Balance2.ar(sig[0], sig[1], Lag.kr(pan, fadeTime).clip(-1, 1), Lag.kr(amp, fadeTime));
            sig = Limiter.ar(LeakDC.ar(sig), 0.9, 0.01);
            Out.ar(out, sig * Lag.kr(dryAmp, fadeTime).clip(0, 1));
            Out.ar(gridOut, sig * Lag.kr(gridSend, fadeTime).clip(0, 1));
            Out.ar(sendOut, sig * Lag.kr(send, fadeTime).clip(0, 1));
        }).add;

        SynthDef(\eapLaneOut, { |in = 0, out = 0, sendOut = 0, gridOut = 0,
            amp = 0.78, pan = 0, send = 0.5, gridSend = 0, dryAmp = 1, fadeTime = 0.05|
            var sig = LeakDC.ar(In.ar(in, 2));
            sig = Balance2.ar(sig[0], sig[1], Lag.kr(pan, fadeTime).clip(-1, 1), Lag.kr(amp, fadeTime));
            sig = Limiter.ar(sig, 0.9, 0.01);
            Out.ar(out, sig * Lag.kr(dryAmp, fadeTime).clip(0, 1));
            Out.ar(gridOut, sig * Lag.kr(gridSend, fadeTime).clip(0, 1));
            Out.ar(sendOut, sig * Lag.kr(send, fadeTime).clip(0, 1));
        }).add;

        SynthDef(\eapTestTone, { |out = 0, freq = 440, dur = 1.2, amp = 0.45|
            var sig = SinOsc.ar(freq) * EnvGen.kr(Env.perc(0.01, dur, 1.0, curve: -4), doneAction: 2);
            Out.ar(out, Pan2.ar(LeakDC.ar(sig), 0, amp));
        }).add;
    };

    ~playTestTone = { |self, freq = 440, dur = 1.2|
        if(self[\masterBus].notNil, {
            Synth.tail(self[\masterGroup] ? self[\group], \eapTestTone, [
                \out, self[\masterBus].index, \freq, freq, \dur, dur, \amp, 0.45
            ]);
            ("EAP test tone -> master bus " ++ freq ++ " Hz").postln;
        }, {
            Synth.tail(s, \default, [\freq, freq, \amp, 0.35]);
            "EAP test tone -> direct out (no master bus)".postln;
        });
    };

    ~audioStatus = { |self|
        var lines = List.new;
        lines.add("synths=" ++ s.numSynths ++ " groups=" ++ s.numGroups);
        lines.add("masterBus=" ++ (self[\masterBus].index ? "nil")
            ++ " masterSynth=" ++ (self[\masterSynth].notNil));
        self[\slots].do({ |lane, i|
            if(lane.notNil, {
                lines.add("slot " ++ (i + 1) ++ " state=" ++ lane[\state]
                    ++ " modifier=" ++ (lane[\soundModifier] ? \none)
                    ++ " profile=" ++ (lane[\patternProfile] ? lane[\rhythmProfile] ? \unknown)
                    ++ " cpu=" ++ (lane[\cpuClass] ? \normal)
                    ++ " level=" ++ (lane[\level] ? 1.0).round(0.001)
                    ++ " pan=" ++ (lane[\pan] ? 0.0).round(0.001)
                    ++ " density=" ++ (lane[\density] ? 1.0).round(0.001)
                    ++ " timbreMotion=" ++ (lane[\timbreMotion] ? 0.0).round(0.001)
                    ++ " reverbSend=" ++ (lane[\reverbSend] ? 0.5).round(0.001)
                    ++ " transpose=" ++ (lane[\transpose] ? 0)
                    ++ " seq=" ++ (lane[\state] == \active and: { lane[\routine].notNil })
                    ++ " triggers=" ++ (lane[\triggerCount] ? 0)
                    ++ " adaptiveSiblings=" ++ ((lane[\adaptive] ? ())[\siblingCount] ? 0)
                    ++ " adaptiveRegister=" ++ ((lane[\adaptive] ? ())[\registerBand] ? \mid)
                    ++ " materials=" ++ lane[\materials].asString);
            });
        });
        lines.add("adaptiveJournal=" ++ self[\adaptiveJournal].size
            ++ " adaptiveSerial=" ++ (self[\adaptiveSerial] ? 0));
        lines.join("\n").postln;
        lines;
    };

    ~refreshDexed = { |self|
        var destination;
        var alsaState;
        if(MIDIClient.initialized.not, { MIDIClient.init; });
        destination = MIDIClient.destinations.detect({ |endpoint|
            var label = (endpoint.device.asString ++ " " ++ endpoint.name.asString).toLower;
            label.contains("dexed");
        });
        if(destination.notNil, {
            if(self[\dexedMidi].isNil, {
                self[\dexedMidi] = MIDIOut.newByName(destination.device, destination.name);
                ("EAP Dexed MIDI connected: " ++ destination.device ++ " / " ++ destination.name).postln;
            });
            self[\dexedAvailable] = true;
        }, {
            alsaState = "aconnect -l 2>/dev/null".unixCmdGetStdOut.toLower;
            if(alsaState.contains("dexed") and: { alsaState.contains("connected from") and: { alsaState.contains("supercollider") } }, {
                if(self[\dexedMidi].isNil, {
                    self[\dexedMidi] = MIDIOut(0);
                    "EAP Dexed MIDI using SuperCollider out0 subscription".postln;
                });
                self[\dexedAvailable] = true;
            }, {
                if(self[\dexedAvailable], { "EAP Dexed MIDI route disappeared".postln; });
                self[\dexedMidi] = nil;
                self[\dexedAvailable] = false;
            });
        });
        self[\dexedAvailable];
    };

    ~ensureDexed = { |self|
        var result = "sh -lc 'EAP_ENABLE_DEXED=1 /usr/local/bin/eap-ensure-dexed 25 0.25 2>&1'".unixCmdGetStdOut.stripWhiteSpace;
        if(result.notEmpty, { ("EAP " ++ result).postln; });
        self[\refreshDexed].value(self);
    };

    ~queueEnsureDexed = { |self|
        var now = Main.elapsedTime;
        if((now - (self[\lastDexedEnsureQueuedAt] ? -9999)) > 10.0, {
            self[\lastDexedEnsureQueuedAt] = now;
            "sh -lc 'EAP_ENABLE_DEXED=1 /usr/local/bin/eap-ensure-dexed 25 0.25 >/tmp/eap-dexed-ensure.log 2>&1'".unixCmd;
        });
        self;
    };

    ~sendDexedNote = { |self, channel = 0, note = 60, velocity = 80, duration = 0.6|
        var midi = self[\dexedMidi];
        if(midi.isNil, {
            self[\refreshDexed].value(self);
            midi = self[\dexedMidi];
            if(midi.isNil, { self[\queueEnsureDexed].value(self); });
        });
        if(midi.notNil, {
            var chan = channel.asInteger.clip(0, 15);
            var pitch = note.asInteger.clip(0, 127);
            var vel = velocity.asInteger.clip(1, 127);
            midi.noteOn(chan, pitch, vel);
            Routine({
                duration.asFloat.clip(0.04, 12.0).wait;
                midi.noteOff(chan, pitch, 0);
            }).play(SystemClock);
        });
    };

    ~loadDexedPatch = { |self, seed = 1, channel = 0, profile = nil|
        var cmd;
        var result;
        self[\ensureDexed].value(self);
        cmd = "sh -lc " ++ ("EAP_ENABLE_DEXED=1 /usr/local/bin/eap-dexed-patch --seed " ++ seed.asInteger.asString
            ++ " --channel " ++ channel.asInteger.clip(0, 15).asString
            ++ if(profile.notNil, { " --profile " ++ profile.asSymbol.asString }, { "" })).quote;
        result = cmd.unixCmdGetStdOut.stripWhiteSpace;
        if(result.notEmpty, { ("EAP " ++ result).postln; });
        self[\refreshDexed].value(self);
        result;
    };

    ~queueDexedPatch = { |self, seed = 1, channel = 0, profile = nil|
        var command = "EAP_ENABLE_DEXED=1 /usr/local/bin/eap-ensure-dexed 25 0.25 >/tmp/eap-dexed-ensure.log 2>&1; "
            ++ "EAP_ENABLE_DEXED=1 /usr/local/bin/eap-dexed-patch --seed " ++ seed.asInteger.asString
            ++ " --channel " ++ channel.asInteger.clip(0, 15).asString
            ++ (if(profile.notNil, { " --profile " ++ profile.asSymbol.asString }, { "" }))
            ++ " >/tmp/eap-dexed-patch-" ++ channel.asInteger.clip(0, 15).asString ++ ".log 2>&1";
        self[\lastDexedEnsureQueuedAt] = Main.elapsedTime;
        ("sh -lc " ++ command.quote).unixCmd;
        "queued seed=" ++ seed.asInteger.asString;
    };

    ~vitalRuntimeAvailable = { |self|
        "sh -lc 'command -v jalv >/dev/null 2>&1 && command -v eap-vital-preset >/dev/null 2>&1 && lv2ls 2>/dev/null | grep -qx \"urn:distrho:vitalium\" && echo yes'".unixCmdGetStdOut.contains("yes");
    };

    ~ensureVital = { |self|
        var result = "sh -lc 'EAP_ENABLE_VITAL=1 /usr/local/bin/eap-ensure-vital 18 0.25 2>&1'".unixCmdGetStdOut.stripWhiteSpace;
        if(result.notEmpty, { ("EAP " ++ result).postln; });
        self[\refreshVital].value(self);
    };

    ~queueEnsureVital = { |self|
        var now = Main.elapsedTime;
        if((now - (self[\lastVitalEnsureQueuedAt] ? -9999)) > 10.0, {
            self[\lastVitalEnsureQueuedAt] = now;
            "sh -lc 'EAP_ENABLE_VITAL=1 /usr/local/bin/eap-ensure-vital 18 0.25 >/tmp/eap-vital-ensure.log 2>&1'".unixCmd;
        });
        self;
    };

    ~refreshVital = { |self|
        var destination;
        var alsaState;
        if(MIDIClient.initialized.not, { MIDIClient.init; });
        destination = MIDIClient.destinations.detect({ |endpoint|
            var label = (endpoint.device.asString ++ " " ++ endpoint.name.asString).toLower;
            label.contains("vital");
        });
        if(destination.notNil, {
            if(self[\vitalMidi].isNil, {
                self[\vitalMidi] = MIDIOut.newByName(destination.device, destination.name);
                ("EAP Vital MIDI connected: " ++ destination.device ++ " / " ++ destination.name).postln;
            });
            self[\vitalAvailable] = true;
        }, {
            alsaState = "aconnect -l 2>/dev/null".unixCmdGetStdOut.toLower;
            if(alsaState.contains("vital"), {
                if(self[\vitalMidi].isNil, {
                    self[\vitalMidi] = MIDIOut(0);
                    "EAP Vital MIDI using SuperCollider out0 subscription".postln;
                });
                self[\vitalAvailable] = true;
            }, {
                var jackState = "jack_lsp -c 2>/dev/null".unixCmdGetStdOut.toLower;
                if(jackState.contains("eap-vital:lv2_events_in") and: { jackState.contains("supercollider") and: { jackState.contains("out0") } }, {
                    if(self[\vitalMidi].isNil, {
                        self[\vitalMidi] = MIDIOut(0);
                        "EAP Vital MIDI using bridged SuperCollider out0 -> JACK MIDI".postln;
                    });
                    self[\vitalAvailable] = true;
                }, {
                    if(self[\vitalAvailable], { "EAP Vital MIDI route disappeared".postln; });
                    self[\vitalMidi] = nil;
                    self[\vitalAvailable] = false;
                });
            });
        });
        self[\vitalAvailable];
    };

    ~loadVitalPatch = { |self, seed = 1, slot = 1, profile = nil|
        var cmd;
        var result;
        cmd = "sh -lc " ++ ("EAP_ENABLE_VITAL=1 /usr/local/bin/eap-vital-preset --seed " ++ seed.asInteger.asString
            ++ " --slot " ++ slot.asInteger.clip(1, self[\maxScenes]).asString
            ++ " --profile " ++ (profile ? \default).asSymbol.asString
            ++ " --no-start").quote;
        result = cmd.unixCmdGetStdOut.stripWhiteSpace;
        if(result.notEmpty, { ("EAP " ++ result).postln; });
        self[\ensureVital].value(self);
        "sleep 0.8".unixCmdGetStdOut;
        self[\refreshVital].value(self);
        result;
    };

    ~queueVitalPatch = { |self, seed = 1, slot = 1, profile = nil|
        var slotIndex = slot.asInteger.clip(1, self[\maxScenes]);
        var command = "EAP_ENABLE_VITAL=1 /usr/local/bin/eap-vital-preset --seed " ++ seed.asInteger.asString
            ++ " --slot " ++ slotIndex.asString
            ++ " --profile " ++ (profile ? \default).asSymbol.asString
            ++ " --no-start >/tmp/eap-vital-preset-" ++ slotIndex.asString ++ ".log 2>&1; "
            ++ "EAP_ENABLE_VITAL=1 /usr/local/bin/eap-ensure-vital 18 0.25 >/tmp/eap-vital-ensure.log 2>&1";
        self[\lastVitalEnsureQueuedAt] = Main.elapsedTime;
        ("sh -lc " ++ command.quote).unixCmd;
        "queued seed=" ++ seed.asInteger.asString;
    };

    ~sendVitalNote = { |self, note = 60, velocity = 80, duration = 0.6|
        var midi = self[\vitalMidi];
        if(midi.isNil, {
            self[\refreshVital].value(self);
            midi = self[\vitalMidi];
            if(midi.isNil, { self[\queueEnsureVital].value(self); });
        });
        if(midi.notNil, {
            var pitch = note.asInteger.clip(0, 127);
            var vel = velocity.asInteger.clip(1, 127);
            midi.noteOn(0, pitch, vel);
            Routine({
                duration.asFloat.clip(0.04, 12.0).wait;
                midi.noteOff(0, pitch, 0);
            }).play(SystemClock);
        });
    };

    ~vcvRuntimeAvailable = { |self|
        "sh -lc '[ \"${EAP_ENABLE_VCV:-0}\" = \"1\" ] && command -v eap-rack >/dev/null 2>&1 && command -v eap-vcv-patch >/dev/null 2>&1 && eap-vcv-patch --check >/dev/null 2>&1 && echo yes'".unixCmdGetStdOut.contains("yes");
    };

    ~laneUsesExternalInput = { |lane|
        var materials = lane[\materials] ? [];
        materials.includes(\dexed) or: { materials.includes(\vital) } or: { materials.includes(\vcv) };
    };

    ~muteExternalInput = { |self|
        if(self[\externalInputSynth].notNil, {
            self[\externalInputSynth].set(\amp, 0.0, \fadeTime, 0.12);
        });
    };

    ~externalInputChannelsFor = { |source|
        switch(source,
            \dexed, { [2, 3] },
            \vital, { [4, 5] },
            \vcv, { [6, 7] },
            { [2, 3] }
        );
    };

    ~ensureLaneExternalInput = { |self, lane, source|
        var key = source.asSymbol;
        var synths = lane[\externalInputSynths];
        var synth;
        var channels;
        if(synths.isNil, {
            synths = IdentityDictionary.new;
            lane[\externalInputSynths] = synths;
        });
        synth = synths[key];
        if(synth.isNil, {
            channels = self[\externalInputChannelsFor].value(key);
            synth = Synth.head(lane[\group], \eapLaneExternalInput, [
                \out, lane[\sourceBus].index,
                \inL, channels[0],
                \inR, channels[1],
                \amp, 0.0
            ]);
            synths[key] = synth;
            lane[\synths].add(synth);
            ("EAP lane " ++ (lane[\slot] ? lane[\index] ? "?") ++
                " external " ++ key ++ " routed through lane bus from SC inputs " ++
                (channels[0] + 1) ++ "/" ++ (channels[1] + 1)).postln;
        });
        synth;
    };

    ~pulseExternalInput = { |self, lane, source, duration = 0.5|
        var synth = self[\ensureLaneExternalInput].value(self, lane, source);
        if(synth.notNil, {
            var holdUntil = Main.elapsedTime + duration.asFloat.clip(0.04, 12.0) + 0.08;
            var holdKey = (source.asString ++ "ExternalInputHoldUntil").asSymbol;
            lane[holdKey] = (lane[holdKey] ? 0).max(holdUntil);
            synth.set(\amp, (lane[\amp] ? 0.18) * 1.12, \fadeTime, 0.02);
            Routine({
                duration.asFloat.clip(0.04, 12.0).wait;
                if(lane.notNil and: { Main.elapsedTime >= ((lane[holdKey] ? 0) - 0.001) }, {
                    synth.set(\amp, 0.0, \fadeTime, 0.12);
                });
            }).play(SystemClock);
        });
    };

    ~anyActiveVcvLane = { |self|
        self[\lanes].any({ |lane|
            lane.notNil and: { lane[\state] == \active } and: { (lane[\materials] ? []).includes(\vcv) };
        });
    };

    ~anyNeededExternalLane = { |self, source|
        self[\slots].any({ |lane|
            lane.notNil and: { lane[\state] == \active } and: { (lane[\materials] ? []).includes(source) };
        });
    };

    ~restoreExternalEngineForLane = { |self, lane|
        var materials = lane[\materials] ? [];
        if(materials.includes(\dexed), {
            var d = lane[\dexed] ? ();
            self[\queueDexedPatch].value(self, d[\patchSeed] ? 0, d[\channel] ? 0, d[\patchProfile]);
        });
        if(materials.includes(\vital), {
            var v = lane[\vital] ? ();
            self[\queueVitalPatch].value(self, v[\patchSeed] ? 0, lane[\slot] ? (lane[\index] ? 1), v[\patchProfile] ? \default);
        });
        self;
    };

    ~stopVitalEngine = { |self|
        "/usr/local/bin/eap-stop-vital >/tmp/eap-stop-vital.log 2>&1".unixCmd;
        "EAP vital stop queued".postln;
        self[\vitalMidi] = nil;
        self[\vitalAvailable] = false;
        self;
    };

    ~stopDexedEngine = { |self|
        "/usr/local/bin/eap-stop-dexed >/tmp/eap-stop-dexed.log 2>&1".unixCmd;
        "EAP dexed stop queued".postln;
        self[\dexedMidi] = nil;
        self[\dexedAvailable] = false;
        self;
    };

    ~stopVcvEngine = { |self|
        "sh -lc \"pkill -f '[R]ack .*-h ' 2>/dev/null; pkill -f '[e]ap-vcv-midi-bridge' 2>/dev/null\" >/tmp/eap-stop-vcv.log 2>&1".unixCmd;
        "EAP vcv stop queued".postln;
        self[\vcvMidi] = nil;
        self[\vcvAvailable] = false;
        self;
    };

    ~syncVcvEngine = { |self|
        var needsVcv = self[\anyActiveVcvLane].value(self);
        if(needsVcv.not and: { (self[\vcvAvailable] ? false) or: { self[\vcvMidi].notNil or: { self[\vcvWasNeeded] ? false } } }, {
            self[\stopVcvEngine].value(self);
        });
        self[\vcvWasNeeded] = needsVcv;
        self;
    };

    ~syncExternalEngines = { |self|
        var needsVital = self[\anyNeededExternalLane].value(self, \vital);
        var needsDexed = self[\anyNeededExternalLane].value(self, \dexed);
        if(needsVital.not and: { (self[\vitalAvailable] ? false) or: { self[\vitalMidi].notNil or: { self[\vitalWasNeeded] ? false } } }, {
            self[\stopVitalEngine].value(self);
        });
        if(needsDexed.not and: { (self[\dexedAvailable] ? false) or: { self[\dexedMidi].notNil or: { self[\dexedWasNeeded] ? false } } }, {
            self[\stopDexedEngine].value(self);
        });
        self[\vitalWasNeeded] = needsVital;
        self[\dexedWasNeeded] = needsDexed;
        self[\syncVcvEngine].value(self);
        self;
    };

    ~refreshVcv = { |self|
        if(MIDIClient.initialized.not, { MIDIClient.init; });
        if(self[\vcvMidi].isNil, {
            self[\vcvMidi] = MIDIOut(0);
            "EAP VCV MIDI using SuperCollider out0 -> a2jmidid".postln;
        });
        "/usr/local/bin/eap-vcv-midi-bridge 6 0.3".unixCmdGetStdOut;
        self[\vcvAvailable] = true;
        self[\vcvAvailable];
    };

    ~loadVcvPatch = { |self, seed = 1, slot = 1, profile = nil|
        var cmd = "/usr/local/bin/eap-vcv-patch --seed "
            ++ seed.asInteger.asString
            ++ " --slot " ++ slot.asInteger.clip(1, self[\maxScenes]).asString
            ++ " --profile " ++ (profile ? \default).asSymbol.asString;
        var wrapper = "sh -lc " ++ (cmd ++ " > /tmp/eap-vcv-patch.out 2>&1; echo $? > /tmp/eap-vcv-patch.st").quote;
        var result, status;
        wrapper.unixCmdGetStdOut;
        result = File.readAllString("/tmp/eap-vcv-patch.out").stripWhiteSpace;
        status = File.readAllString("/tmp/eap-vcv-patch.st").stripWhiteSpace.asInteger;
        if(status != 0, {
            "EAP VCV patch load failed; no fallback patch will be used".postln;
            if(result.notEmpty, { ("EAP " ++ result).postln; });
            self[\vcvMidi] = nil;
            self[\vcvAvailable] = false;
            ^"vcv patch load failed";
        });
        if(result.notEmpty, { ("EAP " ++ result).postln; });
        if("/usr/local/bin/eap-connect-vcv-jack 30 0.25".systemCmd != 0, {
            "EAP VCV JACK/MIDI wiring failed".postln;
            self[\vcvMidi] = nil;
            self[\vcvAvailable] = false;
            ^"vcv jack wiring failed";
        });
        self[\refreshVcv].value(self);
        result;
    };

    ~sendVcvNote = { |self, note = 60, velocity = 80, duration = 0.6|
        var midi = self[\vcvMidi];
        if(midi.isNil, { self[\refreshVcv].value(self); midi = self[\vcvMidi]; });
        if(midi.notNil, {
            var pitch = note.asInteger.clip(0, 127);
            var vel = velocity.asInteger.clip(1, 127);
            midi.noteOn(0, pitch, vel);
            Routine({
                duration.asFloat.clip(0.04, 12.0).wait;
                midi.noteOff(0, pitch, 0);
            }).play(SystemClock);
        });
    };

    ~chooseFxBackend = { |self, index, total, modifier|
        var allowClouds = total <= 2 and: { self[\hasActiveCloud].value(self).not };
        if(allowClouds.not, {
            \pedalboard;
        }, {
            switch(modifier,
                \percussive, { \pedalboard },
                \drone, { [\clouds, \pedalboard, \pedalboard].choose },
                \harmonic, { [\clouds, \pedalboard, \pedalboard, \pedalboard].choose },
                \chaos, { \pedalboard },
                { [\pedalboard, \pedalboard, \pedalboard, \clouds].choose }
            );
        });
    };

    ~choosePedalsForLane = { |self, lane|
        var modifier = lane[\soundModifier];
        var total = lane[\total] ? 1;
        var pedalCount = if(total >= 4, { 1 }, {
            if(total >= 2, { 1 }, { rrand(1, self[\maxFxPerScene]) });
        });
        var pool;
        var chain;
        pool = switch(modifier,
            \percussive, { [\tremolo, \tremolo, \autowah, \autowah, \phaser, \chorus, \delay, \wavefolder] },
            \drone, { [\reverb, \lofi, \chorus, \delay, \vibrato, \phaser] },
            \harmonic, { [\chorus, \vibrato, \reverb, \phaser, \delay, \tremolo] },
            \chaos, { [\ringmod, \wavefolder, \bitcrusher, \lofi, \autowah, \delay, \reverb] },
            { self[\pedalCandidates] }
        );
        chain = Array.fill(pedalCount, { pool.choose });
        if(modifier == \chaos and: { total < 2 } and: { chain.size < self[\maxFxPerScene] and: { 0.62.coin } }, {
            chain = chain ++ [pool.choose];
        });
        if(modifier == \chaos and: { total < 2 } and: { chain.size < self[\maxFxPerScene] and: { 0.28.coin } }, {
            chain = chain ++ [pool.choose];
        });
        chain;
    };

    ~adaptiveContextForSlot = { |self, slot, modifier = nil|
        var materialCounts = IdentityDictionary.new;
        var activeMaterialCounts = IdentityDictionary.new;
        var fxCounts = IdentityDictionary.new;
        var rhythmCounts = IdentityDictionary.new;
        var registerCounts = IdentityDictionary.new;
        var modifierCounts = IdentityDictionary.new;
        var engineCounts = IdentityDictionary.new;
        var siblings = List.new;
        var siblingCount;
        var pulseSum = 0.0;
        var pulseCount = 0;
        var gapSum = 0.0;
        var gapCount = 0;
        var slotIndex = slot.asInteger.clip(1, self[\maxScenes]) - 1;
        if(self[\slots].notNil, {
            self[\slots].do({ |lane, laneIndex|
                if(lane.notNil and: { laneIndex != slotIndex and: { lane[\state] != \blank } }) {
                    siblings.add(lane);
                    (lane[\materials] ? []).do({ |source|
                        self[\countInto].value(self, materialCounts, source, 2);
                        self[\countInto].value(self, activeMaterialCounts, source, 1);
                    });
                    self[\countInto].value(self, fxCounts, lane[\fx], 2);
                    self[\countInto].value(self, rhythmCounts, lane[\rhythmProfile], 2);
                    self[\countInto].value(self, registerCounts, self[\registerBandFor].value(self, lane[\register]), 1);
                    self[\countInto].value(self, modifierCounts, lane[\soundModifier], 1);
                    if(lane[\sourceEngine].notNil, {
                        self[\countInto].value(self, engineCounts, lane[\sourceEngine], 1);
                    });
                    if(lane[\pulse].notNil, {
                        pulseSum = pulseSum + lane[\pulse].asFloat;
                        pulseCount = pulseCount + 1;
                    });
                    if(lane[\gap].notNil, {
                        gapSum = gapSum + lane[\gap].asFloat;
                        gapCount = gapCount + 1;
                    });
                };
            });
        });
        self[\adaptiveJournal].do({ |entry|
            if(entry[\slot] != (slotIndex + 1), {
                (entry[\materials] ? []).do({ |source| self[\countInto].value(self, materialCounts, source, 1); });
                self[\countInto].value(self, fxCounts, entry[\fx], 1);
                self[\countInto].value(self, rhythmCounts, entry[\rhythmProfile], 1);
                self[\countInto].value(self, registerCounts, entry[\registerBand], 1);
                self[\countInto].value(self, modifierCounts, entry[\modifier], 1);
                self[\countInto].value(self, engineCounts, entry[\sourceEngine], 1);
                if(entry[\pulse].notNil, {
                    pulseSum = pulseSum + entry[\pulse].asFloat;
                    pulseCount = pulseCount + 1;
                });
                if(entry[\gap].notNil, {
                    gapSum = gapSum + entry[\gap].asFloat;
                    gapCount = gapCount + 1;
                });
            });
        });
        siblingCount = siblings.size;
        (
            siblingCount: siblingCount,
            avoidMaterials: self[\keysWithCountAtLeast].value(self, activeMaterialCounts, 1),
            overusedMaterials: self[\keysWithCountAtLeast].value(self, materialCounts, if(siblingCount >= 3, { 3 }, { 2 })),
            avoidFx: self[\keysWithCountAtLeast].value(self, fxCounts, if(siblingCount >= 3, { 3 }, { 2 })),
            avoidRhythms: self[\keysWithCountAtLeast].value(self, rhythmCounts, if(siblingCount >= 3, { 3 }, { 2 })),
            registerBand: self[\leastUsedRegisterBand].value(self, registerCounts),
            pulseAnchor: if(pulseCount > 0, { pulseSum / pulseCount }, { nil }),
            gapAnchor: if(gapCount > 0, { gapSum / gapCount }, { nil }),
            materialCounts: materialCounts,
            fxCounts: fxCounts,
            rhythmCounts: rhythmCounts,
            registerCounts: registerCounts,
            modifierCounts: modifierCounts,
            engineCounts: engineCounts
        );
    };

    ~applyAdaptiveBias = { |self, lane, adaptive|
        var band;
        if(lane.notNil and: { adaptive.notNil }) {
            band = adaptive[\registerBand] ? \mid;
            lane[\adaptive] = (
                siblingCount: adaptive[\siblingCount] ? 0,
                avoidMaterials: (adaptive[\avoidMaterials] ? []).copy,
                overusedMaterials: (adaptive[\overusedMaterials] ? []).copy,
                avoidRhythms: (adaptive[\avoidRhythms] ? []).copy,
                avoidFx: (adaptive[\avoidFx] ? []).copy,
                registerBand: band
            );
            lane[\register] = switch(band,
                \low, { [[24, 48], [28, 55], [31, 58]].choose },
                \mid, { [[36, 62], [40, 67], [45, 72]].choose },
                \high, { [[52, 84], [55, 88], [60, 91]].choose },
                { lane[\register] }
            );
            if(adaptive[\pulseAnchor].notNil, {
                lane[\pulse] = ((lane[\pulse] ? 0.12) * 0.65 + (adaptive[\pulseAnchor].asFloat * 0.35)).clip(0.045, 0.9);
            });
            if(adaptive[\gapAnchor].notNil, {
                lane[\gap] = ((lane[\gap] ? 0.2) * 0.78 + (adaptive[\gapAnchor].asFloat * 0.22)).clip(0.04, 8.0);
            });
            if((adaptive[\siblingCount] ? 0) > 0, {
                lane[\densitySkew] = ((lane[\densitySkew] ? 1.0) * [0.86, 0.94, 1.08, 1.16].choose).clip(0.35, 2.4);
                if(lane[\molly].notNil, {
                    lane[\molly][\lfoFreq] = ((lane[\molly][\lfoFreq] ? 0.1) * [0.65, 0.82, 1.28, 1.55].choose).clip(0.01, 3.5);
                    lane[\molly][\lpFilterCutoff] = ((lane[\molly][\lpFilterCutoff] ? 1200) * [0.72, 0.9, 1.15, 1.38].choose).clip(180, 12000);
                });
                if(lane[\passersby].notNil, {
                    lane[\passersby][\toneTilt] = ((lane[\passersby][\toneTilt] ? 0.5) + [-0.18, -0.09, 0.11, 0.20].choose).clip(0.0, 1.0);
                    lane[\passersby][\waveFolds] = ((lane[\passersby][\waveFolds] ? 0.6) * [0.72, 0.9, 1.18, 1.42].choose).clip(0.0, 3.4);
                });
                if(lane[\rings].notNil, {
                    lane[\rings][\bright] = ((lane[\rings][\bright] ? 0.5) + [-0.14, -0.06, 0.08, 0.16].choose).clip(0.05, 0.98);
                    lane[\rings][\pos] = ((lane[\rings][\pos] ? 0.5) + [-0.16, -0.08, 0.10, 0.18].choose).clip(0.02, 0.98);
                });
            });
        };
        lane;
    };

    ~adaptiveJournalEntryForLane = { |self, lane, action = \generate|
        (
            serial: self[\adaptiveSerial],
            action: action,
            slot: lane[\slot] ? lane[\index],
            modifier: lane[\soundModifier],
            sourceEngine: lane[\sourceEngine] ? (self[\sourceEnginePreference] ? \none),
            materials: (lane[\materials] ? []).copy,
            fx: lane[\fx],
            rhythmProfile: lane[\rhythmProfile],
            register: (lane[\register] ? [0, 0]).copy,
            registerBand: self[\registerBandFor].value(self, lane[\register]),
            plaitsModels: (lane[\plaitsModels] ? []).copy,
            ringsModel: lane[\ringsModel],
            pedalChain: (lane[\pedals] ? []).copy,
            gap: lane[\gap],
            pulse: lane[\pulse],
            swing: lane[\swing],
            transpose: lane[\transpose] ? 0,
            densitySkew: lane[\densitySkew],
            restProb: lane[\restProb],
            volatility: lane[\volatility],
            scaleIndex: self[\scaleIndex],
            rootNote: self[\rootNote],
            adaptive: lane[\adaptive]
        );
    };

    ~recordAdaptiveScene = { |self, lane, action = \generate|
        var entry;
        if(lane.notNil, {
            self[\adaptiveSerial] = (self[\adaptiveSerial] ? 0) + 1;
            entry = self[\adaptiveJournalEntryForLane].value(self, lane, action);
            self[\adaptiveJournal].add(entry);
            while({ self[\adaptiveJournal].size > 64 }, { self[\adaptiveJournal].removeAt(0); });
            ("EAP adaptive journal #" ++ entry[\serial]
                ++ " slot=" ++ entry[\slot]
                ++ " action=" ++ action
                ++ " materials=" ++ entry[\materials].asString
                ++ " rhythm=" ++ (entry[\rhythmProfile] ? \unknown)
                ++ " registerBand=" ++ (entry[\registerBand] ? \mid)
                ++ " siblings=" ++ ((entry[\adaptive] ? ())[\siblingCount] ? 0)).postln;
        });
        entry;
    };

    ~randomLane = { |self, index, total, modifier = nil, adaptive = nil|
        var enginePreference = self[\sourceEnginePreference];
        var materialPool = [\plaits, \plaits, \rings, \rings, \passersby, \passersby, \molly, \fm7, \fm7];
        var materials;
        var fx = self[\chooseFxBackend].value(self, index, total, modifier);
        var register = [[31, 52], [36, 62], [45, 72], [52, 84]].choose;
        var minGap = if(total >= 7, { 1.15 }, { if(total >= 5, { 0.65 }, { 0.18 }) });
        var maxDensity = if(total >= 7, { 1.0 }, { if(total >= 5, { 1.15 }, { 1.45 }) });
        var phase = if(total >= 5, { self[\rand].value(self, 0.0, total * 0.35) }, { self[\rand].value(self, 0.0, 0.25) });
        var restProb = self[\rand].value(self, 0.04, 0.38);
        var volatility = self[\rand].value(self, 0.65, 1.6);
        var densitySkew = self[\rand].value(self, 0.72, maxDensity);
        var density = self[\rand].value(self, 0.55, 0.88);
        var gap = self[\rand].value(self, minGap, 7.0);
        var rhythmProfile;
        var pulse = self[\rand].value(self, 0.1, 0.35);
        var swing = self[\rand].value(self, 0.0, 0.15);
        var timbreMotion = 0.0;
        var molly = (
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
        );
        var passersby = (
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
        );
        var fm7 = (
            algorithm: rrand(0, 7),
            ratios: [
                [1, 2, 3, 4, 5, 6],
                [1, 1.5, 2, 2.5, 3, 4],
                [0.5, 1, 2, 3, 4, 6],
                [1, 2, 2.01, 3, 4, 5],
                [1, 1.25, 1.5, 2, 3, 6],
                [0.5, 0.75, 1, 1.5, 2, 4]
            ].choose,
            opAmps: [1.0, self[\rand].value(self, 0.28, 0.72), self[\rand].value(self, 0.16, 0.58),
                self[\rand].value(self, 0.10, 0.42), self[\rand].value(self, 0.06, 0.34), self[\rand].value(self, 0.04, 0.26)],
            carriers: [[1, 0, 0, 0, 0, 0], [1, 1, 0, 0, 0, 0], [1, 0, 1, 0, 0, 0], [1, 0, 0, 1, 0, 0], [1, 1, 0, 1, 0, 0]].choose,
            index1: self[\rand].value(self, 0.35, 2.8),
            index2: self[\rand].value(self, 0.12, 1.7),
            index3: self[\rand].value(self, 0.04, 1.0),
            feedback: self[\rand].value(self, 0.0, 0.75),
            attack: self[\exprand].value(self, 0.004, 0.35),
            decay: self[\exprand].value(self, 0.12, 2.6),
            sustain: self[\rand].value(self, 0.08, 0.62),
            release: self[\exprand].value(self, 0.10, 3.2),
            brightness: self[\rand].value(self, 0.25, 0.92),
            grit: self[\rand].value(self, 0.0, 0.18)
        );
        var harmonium = (
            // Bias toward harmonic formation + broadband sources for reliable
            // audibility; bark/buchla and noise sources appear as occasional colour.
            source: [0, 1, 2, 2, 3, 4, 4, 5].choose,
            formation: [0, 0, 0, 0, 1, 2].choose,
            num: rrand(5, 10),
            rolloff: self[\rand].value(self, 0.5, 1.5),
            rq: self[\exprand].value(self, 0.01, 0.06),
            bandRes: self[\rand].value(self, 0.15, 0.6),
            timbre: self[\rand].value(self, 0.3, 0.72),
            ouMode: [0, 0, 0, 1].choose,
            pulseWidth: self[\rand].value(self, 0.2, 0.7),
            rmMix: [0, 0, 0, self[\rand].value(self, 0.1, 0.45)].choose,
            rmHz: self[\exprand].value(self, 8, 220),
            rmRatio: [0.5, 1, 1.5, 2, 3].choose,
            rmTrack: [0, 1].choose,
            fmMix: [0, 0, 0, self[\rand].value(self, 0.08, 0.4)].choose,
            fmIndex: self[\rand].value(self, 0.05, 0.5),
            fmRatio: [0.5, 1, 2, 3].choose,
            subAmp: [0, 0, self[\rand].value(self, 0.2, 0.6)].choose,
            subOct1: [0, 1].choose,
            subOct2: [0, 0, 1].choose,
            swirlDepth: self[\rand].value(self, 0.25, 0.7),
            swirlRate: self[\exprand].value(self, 0.02, 0.18),
            ampShimmer: self[\rand].value(self, 0.1, 0.5),
            wet: self[\rand].value(self, 0.45, 0.78),
            envDecay: self[\exprand].value(self, 1.5, 6.0),
            envRelease: self[\exprand].value(self, 0.6, 2.5)
        );
        var clouds = (
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
        );
        var plaitsModels = [ self[\plaitsModelPool].choose ];
        var rings = (
            model: rrand(0, 3),
            poly: [1, 2, 4].choose,
            struct: self[\rand].value(self, 0.12, 0.88),
            bright: self[\rand].value(self, 0.18, 0.95),
            damp: self[\rand].value(self, 0.25, 0.96),
            pos: self[\rand].value(self, 0.10, 0.88),
            envDecay: self[\rand].value(self, 2.0, 10.0),
            envRelease: self[\rand].value(self, 0.6, 2.5)
        );
        var dexed = (
            channel: (index - 1).clip(0, 15),
            velocity: self[\rand].value(self, 54, 104).round(1),
            durScale: self[\exprand].value(self, 0.35, 2.8),
            octaveBias: [-12, 0, 0, 0, 12].choose,
            patchSeed: rrand(1, 2147483000),
            patchInfo: "",
            patchProfile: nil
        );
        var dexedPatchSeed = dexed[\patchSeed];
        var dexedPatchInfo = "";
        var dexedAvailable = false;
        var sourceEngine = \none;
        var freshPool;
        var avoidPool;
        var alternateRhythms;
        var lane;
        var vital = (
            velocity: self[\rand].value(self, 50, 100).round(1),
            durScale: self[\exprand].value(self, 0.28, 2.5),
            octaveBias: [-12, 0, 0, 12].choose,
            patchSeed: rrand(1, 2147483000),
            patchInfo: "",
            patchProfile: modifier ? \default
        );
        var vitalPatchSeed = vital[\patchSeed];
        var vitalPatchInfo = "";
        var vitalAvailable = false;
        var vcv = (
            velocity: self[\rand].value(self, 48, 102).round(1),
            durScale: self[\exprand].value(self, 0.30, 3.2),
            octaveBias: [-12, 0, 0, 12].choose,
            patchSeed: rrand(1, 2147483000),
            patchInfo: "",
            patchProfile: modifier ? \default
        );
        var vcvPatchSeed = vcv[\patchSeed];
        var vcvPatchInfo = "";
        var vcvAvailable = false;
        var cpuClass = \normal;
        switch(modifier,
            \percussive, {
                materialPool = [\plaits, \plaits, \plaits, \plaits, \rings, \rings, \rings, \passersby, \passersby, \fm7, \fm7];
                register = [[36, 60], [38, 64], [43, 67], [48, 72]].choose;
                minGap = minGap * 0.55;
                gap = self[\rand].value(self, 0.09, 0.42);
                restProb = self[\rand].value(self, 0.02, 0.10);
                volatility = self[\rand].value(self, 0.85, 1.65);
                density = self[\rand].value(self, 0.72, 0.96);
                densitySkew = self[\rand].value(self, 0.92, maxDensity.max(1.20));
                rhythmProfile = self[\rhythmProfilesFor].value(\percussive).choose;
                pulse = [self[\rand].value(self, 0.060, 0.095), self[\rand].value(self, 0.095, 0.145), self[\rand].value(self, 0.145, 0.205)].choose;
                swing = [self[\rand].value(self, 0.00, 0.12), self[\rand].value(self, 0.12, 0.32), self[\rand].value(self, 0.00, 0.05)].choose;
                plaitsModels = Array.fill(1, { self[\plaitsPercussiveModels].choose });
                molly[\oscWaveShape] = [0, 0, 1, 1, 2].choose;
                molly[\envAttack] = self[\exprand].value(self, 0.004, 0.045);
                molly[\envDecay] = self[\exprand].value(self, 0.12, 0.85);
                molly[\envSustain] = self[\rand].value(self, 0.0, 0.10);
                molly[\envRelease] = self[\exprand].value(self, 0.08, 0.70);
                molly[\noiseLevel] = self[\exprand].value(self, 0.002, 0.09);
                molly[\lpFilterModEnv] = self[\rand].value(self, 0.06, 0.28);
                molly[\freqModLfo] = self[\exprand].value(self, 0.0001, 0.018);
                molly[\freqModEnv] = self[\rand].value(self, -0.006, 0.018);
                molly[\ringModMix] = 0;
                molly[\ampMod] = self[\rand].value(self, 0.0, 0.08);
                molly[\subOscLevel] = self[\rand].value(self, 0.0, 0.24);
                passersby[\attack] = self[\exprand].value(self, 0.004, 0.045);
                passersby[\decay] = self[\exprand].value(self, 0.09, 0.75);
                passersby[\peak] = self[\exprand].value(self, 650, 5400);
                passersby[\reverbMix] = self[\rand].value(self, 0.0, 0.08);
                passersby[\body] = self[\rand].value(self, 0.14, 0.58);
                passersby[\foldMix] = self[\rand].value(self, 0.04, 0.34);
                passersby[\air] = self[\exprand].value(self, 0.002, 0.022);
                passersby[\fm1Amount] = self[\rand].value(self, 0.0, 0.10);
                passersby[\fm2Amount] = self[\rand].value(self, 0.0, 0.08);
                fm7[\algorithm] = [0, 1, 2, 6, 7].choose;
                fm7[\ratios] = [[1, 2, 3, 4, 6, 8], [1, 1.5, 2, 3, 5, 7], [0.5, 1, 2, 4, 8, 12]].choose;
                fm7[\opAmps] = [1.0, self[\rand].value(self, 0.38, 0.78), self[\rand].value(self, 0.20, 0.55),
                    self[\rand].value(self, 0.06, 0.34), self[\rand].value(self, 0.02, 0.24), self[\rand].value(self, 0.0, 0.18)];
                fm7[\carriers] = [[1, 0, 0, 0, 0, 0], [1, 1, 0, 0, 0, 0], [1, 0, 1, 0, 0, 0]].choose;
                fm7[\index1] = self[\rand].value(self, 1.2, 5.5);
                fm7[\index2] = self[\rand].value(self, 0.35, 3.2);
                fm7[\index3] = self[\rand].value(self, 0.08, 1.8);
                fm7[\feedback] = self[\rand].value(self, 0.0, 1.6);
                fm7[\attack] = self[\exprand].value(self, 0.002, 0.035);
                fm7[\decay] = self[\exprand].value(self, 0.07, 0.55);
                fm7[\sustain] = self[\rand].value(self, 0.0, 0.12);
                fm7[\release] = self[\exprand].value(self, 0.04, 0.35);
                fm7[\brightness] = self[\rand].value(self, 0.45, 0.98);
                fm7[\grit] = self[\rand].value(self, 0.02, 0.26);
                rings = (
                    model: [0, 0, 1, 2].choose,
                    poly: 1,
                    struct: self[\rand].value(self, 0.20, 0.78),
                    bright: self[\rand].value(self, 0.28, 0.82),
                    damp: self[\rand].value(self, 0.48, 0.94),
                    pos: self[\rand].value(self, 0.10, 0.70),
                    envDecay: self[\exprand].value(self, 0.09, 0.55),
                    envRelease: self[\exprand].value(self, 0.06, 0.24)
                );
                dexed[\velocity] = self[\rand].value(self, 72, 118).round(1);
                dexed[\durScale] = self[\exprand].value(self, 0.10, 0.62);
                dexed[\octaveBias] = [-12, 0, 0, 0, 12].choose;
                dexed[\patchProfile] = \percussive;
                vital[\velocity] = self[\rand].value(self, 68, 118).round(1);
                vital[\durScale] = self[\exprand].value(self, 0.10, 0.55);
                vital[\octaveBias] = [-12, 0, 0, 0, 12].choose;
                vital[\patchProfile] = \percussive;
                vcv[\velocity] = self[\rand].value(self, 70, 118).round(1);
                vcv[\durScale] = self[\exprand].value(self, 0.10, 0.58);
                vcv[\octaveBias] = [-12, 0, 0, 0, 12].choose;
                vcv[\patchProfile] = \percussive;
                if(fx == \clouds, {
                    clouds[\dens] = self[\rand].value(self, 0.45, 0.95);
                    clouds[\size] = self[\rand].value(self, 0.08, 0.35);
                    clouds[\mode] = [0, 1].choose;
                });
            },
            \drone, {
                materialPool = [\rings, \rings, \rings, \passersby, \passersby, \plaits, \molly, \molly, \fm7, \fm7];
                register = [[24, 48], [28, 55], [31, 58]].choose;
                minGap = minGap * 1.35;
                gap = self[\rand].value(self, 0.65, 2.2);
                restProb = self[\rand].value(self, 0.0, 0.035);
                volatility = self[\rand].value(self, 0.45, 0.85);
                density = self[\rand].value(self, 0.48, 0.78);
                densitySkew = self[\rand].value(self, 0.78, 1.08);
                rhythmProfile = [\pulse, \breath, \swell, \ritual].choose;
                pulse = self[\rand].value(self, 0.35, 0.85);
                swing = self[\rand].value(self, 0.0, 0.08);
                plaitsModels = [ [5, 6, 12, 4].choose ];
                passersby[\attack] = self[\exprand].value(self, 0.35, 5.5);
                passersby[\decay] = self[\exprand].value(self, 3.0, 14.0);
                passersby[\reverbMix] = self[\rand].value(self, 0.35, 0.92);
                passersby[\body] = self[\rand].value(self, 0.35, 0.95);
                molly[\envAttack] = self[\exprand].value(self, 0.35, 2.4);
                molly[\envDecay] = self[\exprand].value(self, 1.2, 5.5);
                molly[\envSustain] = self[\rand].value(self, 0.72, 0.98);
                molly[\envRelease] = self[\exprand].value(self, 2.5, 12.0);
                fm7[\algorithm] = [2, 3, 4, 5, 7].choose;
                fm7[\ratios] = [[0.5, 1, 1.5, 2, 3, 4], [1, 1.25, 1.5, 2, 2.5, 3], [0.25, 0.5, 1, 2, 3, 5]].choose;
                fm7[\carriers] = [[1, 1, 0, 0, 0, 0], [1, 0, 1, 0, 0, 0], [1, 1, 0, 1, 0, 0]].choose;
                fm7[\index1] = self[\rand].value(self, 0.18, 1.5);
                fm7[\index2] = self[\rand].value(self, 0.05, 0.8);
                fm7[\index3] = self[\rand].value(self, 0.02, 0.45);
                fm7[\feedback] = self[\rand].value(self, 0.0, 0.55);
                fm7[\attack] = self[\exprand].value(self, 0.35, 3.8);
                fm7[\decay] = self[\exprand].value(self, 2.5, 12.0);
                fm7[\sustain] = self[\rand].value(self, 0.55, 0.96);
                fm7[\release] = self[\exprand].value(self, 2.0, 9.5);
                fm7[\brightness] = self[\rand].value(self, 0.18, 0.74);
                fm7[\grit] = self[\rand].value(self, 0.0, 0.10);
                rings = (
                    model: [0, 1, 2, 2].choose,
                    poly: [1, 2, 2, 4].choose,
                    struct: self[\rand].value(self, 0.18, 0.82),
                    bright: self[\rand].value(self, 0.22, 0.88),
                    damp: self[\rand].value(self, 0.35, 0.92),
                    pos: self[\rand].value(self, 0.08, 0.82),
                    envDecay: self[\exprand].value(self, 3.0, 8.0),
                    envRelease: self[\exprand].value(self, 0.8, 2.5)
                );
                vital[\durScale] = self[\exprand].value(self, 2.0, 7.0);
                vital[\octaveBias] = [-24, -12, -12, 0].choose;
                vital[\patchProfile] = \drone;
                vcv[\durScale] = self[\exprand].value(self, 2.2, 8.0);
                vcv[\octaveBias] = [-24, -12, 0].choose;
                vcv[\patchProfile] = \drone;
                if(fx == \clouds, {
                    clouds[\size] = self[\rand].value(self, 0.55, 0.98);
                    clouds[\dens] = self[\rand].value(self, 0.08, 0.38);
                    clouds[\drywet] = self[\rand].value(self, 0.55, 0.88);
                    clouds[\tex] = self[\rand].value(self, 0.35, 0.92);
                    clouds[\mode] = [1, 2, 2].choose;
                });
            },
            \harmonic, {
                materialPool = [\rings, \rings, \plaits, \plaits, \molly, \molly, \passersby, \fm7, \fm7];
                register = [[36, 62], [40, 67], [45, 72]].choose;
                gap = self[\rand].value(self, 0.18, 1.15);
                restProb = self[\rand].value(self, 0.0, 0.04);
                volatility = self[\rand].value(self, 0.95, 1.55);
                density = self[\rand].value(self, 0.62, 0.92);
                densitySkew = self[\rand].value(self, 0.95, maxDensity.max(1.25));
                rhythmProfile = [\arp, \motif, \pulseHarm, \hymn].choose;
                pulse = self[\rand].value(self, 0.09, 0.24);
                swing = self[\rand].value(self, 0.02, 0.22);
                plaitsModels = [ [4, 5, 6, 12].choose ];
                molly[\envSustain] = self[\rand].value(self, 0.45, 0.92);
                molly[\envRelease] = self[\exprand].value(self, 0.6, 6.0);
                molly[\subOscLevel] = self[\rand].value(self, 0.15, 0.65);
                passersby[\decay] = self[\exprand].value(self, 0.5, 4.5);
                passersby[\reverbMix] = self[\rand].value(self, 0.18, 0.55);
                fm7[\algorithm] = [0, 1, 3, 4, 6].choose;
                fm7[\ratios] = [[1, 2, 3, 4, 5, 6], [1, 1.5, 2, 3, 4, 6], [0.5, 1, 2, 3, 5, 8], [1, 2, 2.01, 3, 4.01, 6]].choose;
                fm7[\carriers] = [[1, 0, 0, 0, 0, 0], [1, 1, 0, 0, 0, 0], [1, 0, 1, 0, 0, 0], [1, 1, 0, 1, 0, 0]].choose;
                fm7[\index1] = self[\rand].value(self, 0.45, 3.4);
                fm7[\index2] = self[\rand].value(self, 0.18, 1.8);
                fm7[\index3] = self[\rand].value(self, 0.04, 1.0);
                fm7[\feedback] = self[\rand].value(self, 0.0, 1.0);
                fm7[\attack] = self[\exprand].value(self, 0.01, 0.55);
                fm7[\decay] = self[\exprand].value(self, 0.4, 3.8);
                fm7[\sustain] = self[\rand].value(self, 0.24, 0.76);
                fm7[\release] = self[\exprand].value(self, 0.5, 5.0);
                fm7[\brightness] = self[\rand].value(self, 0.34, 0.92);
                fm7[\grit] = self[\rand].value(self, 0.0, 0.16);
                vital[\durScale] = self[\exprand].value(self, 0.8, 3.6);
                vital[\octaveBias] = [-12, 0, 0, 12].choose;
                vital[\patchProfile] = \harmonic;
                vcv[\durScale] = self[\exprand].value(self, 0.7, 3.8);
                vcv[\octaveBias] = [-12, 0, 0, 12].choose;
                vcv[\patchProfile] = \harmonic;
                if(fx == \clouds, {
                    clouds[\spread] = self[\rand].value(self, 0.55, 0.98);
                    clouds[\rvb] = self[\rand].value(self, 0.22, 0.62);
                    clouds[\drywet] = self[\rand].value(self, 0.48, 0.82);
                });
            },
            \chaos, {
                materialPool = [\passersby, \passersby, \plaits, \plaits, \rings, \rings, \molly, \fm7, \fm7];
                register = [[24, 96], [28, 88], [31, 84], [36, 96]].choose;
                gap = self[\rand].value(self, 0.06, 0.52);
                restProb = self[\rand].value(self, 0.04, 0.22);
                volatility = self[\rand].value(self, 1.75, 3.4);
                density = self[\rand].value(self, 0.58, 0.88);
                densitySkew = self[\rand].value(self, 0.70, maxDensity.max(1.20));
                rhythmProfile = self[\rhythmProfilesFor].value(\chaos).choose;
                pulse = self[\rand].value(self, 0.02, 0.24);
                swing = self[\rand].value(self, 0.0, 0.38);
                timbreMotion = self[\rand].value(self, 0.42, 0.98);
                plaitsModels = [rrand(0, 11)];
                passersby[\waveShape] = self[\rand].value(self, 0.0, 1.0);
                passersby[\fm1Amount] = self[\rand].value(self, 0.0, 0.72);
                passersby[\fm2Amount] = self[\rand].value(self, 0.0, 0.65);
                passersby[\waveFolds] = self[\rand].value(self, 0.2, 5.5);
                passersby[\foldMix] = self[\rand].value(self, 0.25, 1.0);
                passersby[\attack] = self[\exprand].value(self, 0.001, 0.45);
                passersby[\peak] = self[\exprand].value(self, 180, 12000);
                passersby[\decay] = self[\exprand].value(self, 0.02, 4.5);
                passersby[\air] = self[\exprand].value(self, 0.01, 0.35);
                passersby[\reverbMix] = self[\rand].value(self, 0.0, 0.55);
                molly[\noiseLevel] = self[\exprand].value(self, 0.02, 0.55);
                molly[\freqModLfo] = self[\exprand].value(self, 0.005, 0.45);
                molly[\freqModEnv] = self[\rand].value(self, -0.12, 0.22);
                molly[\ampMod] = self[\rand].value(self, 0.05, 0.72);
                molly[\ringModMix] = self[\rand].value(self, 0.0, 0.45);
                molly[\lpFilterResonance] = self[\rand].value(self, 0.05, 0.82);
                rings[\struct] = self[\rand].value(self, 0.0, 0.98);
                rings[\bright] = self[\rand].value(self, 0.0, 1.0);
                rings[\damp] = self[\rand].value(self, 0.05, 0.98);
                rings[\model] = rrand(0, 3);
                fm7[\algorithm] = rrand(0, 7);
                fm7[\ratios] = [[1, 2, 3, 5, 7, 9], [0.5, 1, 1.5, 2.5, 4, 7], [1, 1.25, 2, 3.5, 5, 8], [0.25, 0.5, 1, 2, 4, 12]].choose;
                fm7[\carriers] = [[1, 0, 0, 0, 0, 0], [1, 1, 0, 0, 0, 0], [1, 0, 1, 1, 0, 0], [1, 1, 0, 1, 1, 0]].choose;
                fm7[\index1] = self[\rand].value(self, 0.5, 7.8);
                fm7[\index2] = self[\rand].value(self, 0.15, 5.2);
                fm7[\index3] = self[\rand].value(self, 0.05, 3.6);
                fm7[\feedback] = self[\rand].value(self, 0.0, 2.2);
                fm7[\attack] = self[\exprand].value(self, 0.001, 0.28);
                fm7[\decay] = self[\exprand].value(self, 0.04, 3.0);
                fm7[\sustain] = self[\rand].value(self, 0.0, 0.55);
                fm7[\release] = self[\exprand].value(self, 0.04, 2.5);
                fm7[\brightness] = self[\rand].value(self, 0.12, 1.0);
                fm7[\grit] = self[\rand].value(self, 0.0, 0.38);
                vital[\velocity] = self[\rand].value(self, 28, 127).round(1);
                vital[\durScale] = self[\exprand].value(self, 0.04, 2.4);
                vital[\octaveBias] = [-36, -24, -12, 0, 12, 24, 36].choose;
                vital[\patchProfile] = \chaos;
                vcv[\velocity] = self[\rand].value(self, 24, 127).round(1);
                vcv[\durScale] = self[\exprand].value(self, 0.04, 2.8);
                vcv[\octaveBias] = [-36, -24, -12, 0, 12, 24, 36].choose;
                vcv[\patchProfile] = \chaos;
                if(fx == \clouds, {
                    clouds[\dens] = self[\rand].value(self, 0.18, 0.98);
                    clouds[\fb] = self[\rand].value(self, 0.05, 0.72);
                    clouds[\mode] = [0, 1, 2].choose;
                    clouds[\lofi] = [0, 1, 1, 1].choose;
                    clouds[\spread] = self[\rand].value(self, 0.25, 0.98);
                    clouds[\drywet] = self[\rand].value(self, 0.35, 0.92);
                });
            }
        );
        if(rhythmProfile.isNil, {
            rhythmProfile = self[\rhythmProfilesFor].value(modifier).choose;
        });
        if(adaptive.notNil and: { enginePreference.isNil }, {
            avoidPool = ((adaptive[\avoidMaterials] ? []) ++ (adaptive[\overusedMaterials] ? []));
            freshPool = materialPool.reject({ |source| avoidPool.includes(source) });
            if(freshPool.notEmpty, {
                materialPool = freshPool ++ freshPool ++ materialPool;
            });
            if((adaptive[\avoidRhythms] ? []).includes(rhythmProfile), {
                alternateRhythms = self[\rhythmProfilesFor].value(modifier).reject({ |profile|
                    (adaptive[\avoidRhythms] ? []).includes(profile);
                });
                if(alternateRhythms.notEmpty, {
                    rhythmProfile = alternateRhythms.choose;
                });
            });
        });
        if(enginePreference.notNil, {
            materialPool = [enginePreference];
        });
        if(enginePreference == \rings, {
            register = switch(modifier,
                \percussive, { [[48, 72], [52, 79], [55, 84]].choose },
                \drone, { [[40, 67], [45, 72], [48, 76]].choose },
                \harmonic, { [[48, 72], [52, 79], [55, 84]].choose },
                \chaos, { [[50, 79], [55, 84], [60, 88]].choose },
                { [[48, 72], [52, 79], [55, 84]].choose }
            );
            gap = switch(modifier,
                \percussive, { self[\rand].value(self, 0.08, 0.24) },
                \drone, { self[\rand].value(self, 0.22, 0.58) },
                \harmonic, { self[\rand].value(self, 0.10, 0.30) },
                \chaos, { self[\rand].value(self, 0.05, 0.16) },
                { gap }
            );
            pulse = switch(modifier,
                \percussive, { self[\rand].value(self, 0.055, 0.12) },
                \drone, { self[\rand].value(self, 0.18, 0.42) },
                \harmonic, { self[\rand].value(self, 0.08, 0.18) },
                \chaos, { self[\rand].value(self, 0.03, 0.11) },
                { pulse }
            );
            restProb = switch(modifier,
                \percussive, { self[\rand].value(self, 0.0, 0.05) },
                \drone, { self[\rand].value(self, 0.0, 0.02) },
                \harmonic, { self[\rand].value(self, 0.0, 0.03) },
                \chaos, { self[\rand].value(self, 0.01, 0.07) },
                { restProb.min(0.04) }
            );
            density = switch(modifier,
                \percussive, { self[\rand].value(self, 0.82, 0.98) },
                \drone, { self[\rand].value(self, 0.68, 0.88) },
                \harmonic, { self[\rand].value(self, 0.76, 0.96) },
                \chaos, { self[\rand].value(self, 0.82, 0.98) },
                { density.max(0.75) }
            );
            densitySkew = switch(modifier,
                \percussive, { self[\rand].value(self, 1.0, 1.35) },
                \drone, { self[\rand].value(self, 0.95, 1.18) },
                \harmonic, { self[\rand].value(self, 1.0, 1.28) },
                \chaos, { self[\rand].value(self, 0.92, 1.18) },
                { densitySkew.max(0.95) }
            );
            swing = switch(modifier,
                \percussive, { self[\rand].value(self, 0.0, 0.18) },
                \drone, { self[\rand].value(self, 0.0, 0.06) },
                \harmonic, { self[\rand].value(self, 0.02, 0.16) },
                \chaos, { self[\rand].value(self, 0.0, 0.18) },
                { swing }
            );
            rhythmProfile = switch(modifier,
                \percussive, { [\grid16, \shuffle16, \euclid, \rotateEuclid, \layeredEuclid, \weightedHits, \clusterCompress].choose },
                \drone, { [\pulse, \swell].choose },
                \harmonic, { [\motif, \pulseHarm, \arp].choose },
                \chaos, { [\stutter, \flare, \grainCloud, \microCluster, \caSnapshot, \deBruijnGlitch, \logisticSwarm].choose },
                { rhythmProfile }
            );
            rings = (
                model: switch(modifier,
                    \percussive, { [0, 1, 2].choose },
                    \drone, { [1, 2, 2].choose },
                    \harmonic, { [0, 1, 2].choose },
                    \chaos, { [0, 1, 2, 3].choose },
                    { rings[\model] }
                ),
                poly: switch(modifier,
                    \percussive, { 1 },
                    \drone, { [2, 2, 4].choose },
                    \harmonic, { [1, 2, 2, 4].choose },
                    \chaos, { [1, 2].choose },
                    { rings[\poly] }
                ),
                struct: switch(modifier,
                    \percussive, { self[\rand].value(self, 0.28, 0.72) },
                    \drone, { self[\rand].value(self, 0.24, 0.66) },
                    \harmonic, { self[\rand].value(self, 0.30, 0.74) },
                    \chaos, { self[\rand].value(self, 0.22, 0.82) },
                    { rings[\struct] }
                ),
                bright: switch(modifier,
                    \percussive, { self[\rand].value(self, 0.55, 0.92) },
                    \drone, { self[\rand].value(self, 0.42, 0.78) },
                    \harmonic, { self[\rand].value(self, 0.50, 0.88) },
                    \chaos, { self[\rand].value(self, 0.48, 0.95) },
                    { rings[\bright] }
                ),
                damp: switch(modifier,
                    \percussive, { self[\rand].value(self, 0.34, 0.72) },
                    \drone, { self[\rand].value(self, 0.42, 0.82) },
                    \harmonic, { self[\rand].value(self, 0.36, 0.74) },
                    \chaos, { self[\rand].value(self, 0.28, 0.78) },
                    { rings[\damp] }
                ),
                pos: switch(modifier,
                    \percussive, { self[\rand].value(self, 0.18, 0.58) },
                    \drone, { self[\rand].value(self, 0.20, 0.68) },
                    \harmonic, { self[\rand].value(self, 0.20, 0.64) },
                    \chaos, { self[\rand].value(self, 0.16, 0.72) },
                    { rings[\pos] }
                ),
                envDecay: switch(modifier,
                    \percussive, { self[\exprand].value(self, 0.10, 0.55) },
                    \drone, { self[\exprand].value(self, 4.5, 12.0) },
                    \harmonic, { self[\exprand].value(self, 0.75, 3.2) },
                    \chaos, { self[\exprand].value(self, 0.20, 1.5) },
                    { rings[\envDecay] }
                ),
                envRelease: switch(modifier,
                    \percussive, { self[\exprand].value(self, 0.06, 0.22) },
                    \drone, { self[\exprand].value(self, 1.2, 3.6) },
                    \harmonic, { self[\exprand].value(self, 0.35, 1.4) },
                    \chaos, { self[\exprand].value(self, 0.08, 0.55) },
                    { rings[\envRelease] }
                )
            );
        });
        materials = if(materialPool.isEmpty, { [] }, { [materialPool.choose] });
        materials = materials.reject({ |source| [\dexed, \vital, \vcv].includes(source) });
        if(materials.isEmpty, {
            materials = [\fm7];
        });
        if(enginePreference.isNil and: { (modifier != \drone) and: { modifier != \harmonic } }, {
            materials = materials.reject({ |source| source == \molly });
            while({ materials.isEmpty and: { materialPool.notEmpty } }, {
                materials = materials.add(materialPool.choose);
                materials = materials.reject({ |source| source == \molly });
            });
        });
        if(modifier == \chaos and: { materials.includes(\rings) }, {
            densitySkew = densitySkew.min(0.62);
            density = density.max(0.70);
            restProb = restProb.clip(0.08, 0.16);
            rings[\poly] = 1;
            rings[\damp] = rings[\damp].max(0.42);
        });
        cpuClass = if(fx == \clouds, {
            \heavy;
        }, {
            switch(modifier,
                \percussive, { \medium },
                \chaos, { \medium },
                { \normal }
            );
        });
        if(materials.includes(\vcv), {
            vcvPatchInfo = self[\loadVcvPatch].value(self, vcvPatchSeed, index, vcv[\patchProfile]);
            vcv[\patchInfo] = vcvPatchInfo;
            if(vcvPatchInfo.asString.contains("failed"), {
                materials = materials.reject({ |source| source == \vcv });
                if(enginePreference == \vcv, {
                    "EAP selected engine vcv failed to load; no fallback source".postln;
                });
            });
        });
        if((materials.includes(\dexed) or: { materials.includes(\vital) } or: { materials.includes(\vcv) }) and: { fx == \clouds }, {
            "EAP external scene using pedalboard instead of Clouds for Pi CPU headroom".postln;
            fx = \pedalboard;
        });
        if(adaptive.notNil and: { (adaptive[\avoidFx] ? []).includes(fx) }, {
            if(fx == \clouds, {
                fx = \pedalboard;
            }, {
                if(total <= 2 and: { self[\hasActiveCloud].value(self).not and: { [\drone, \harmonic].includes(modifier) } }, {
                    fx = \clouds;
                });
            });
        });
        sourceEngine = enginePreference ? \none;
        lane = (
            index: index,
            slot: index,
            total: total,
            soundModifier: modifier,
            sourceEngine: sourceEngine,
            materials: materials,
            fx: fx,
            scale: self[\scales].wrapAt(self[\scaleIndex]).copy,
            lastDegree: nil,
            register: register,
            phase: phase,
            gap: gap,
            densitySkew: densitySkew,
            restProb: restProb,
            volatility: volatility,
            rhythmProfile: rhythmProfile,
            pulse: pulse,
            swing: swing,
            cpuClass: cpuClass,
            level: 1.0,
            pan: 0.0,
            density: density,
            timbreMotion: timbreMotion,
            reverbSend: 0.5,
            transpose: 0,
            amp: (0.28 / total.sqrt).clip(0.10, 0.26),
            plaitsModels: plaitsModels,
            ringsModel: rings[\model],
            rings: rings,
            molly: molly,
            passersby: passersby,
            fm7: fm7,
            harmonium: harmonium,
            dexed: dexed,
            vital: vital,
            vcv: vcv,
            clouds: clouds,
            state: \blank
        );
        self[\applyAdaptiveBias].value(self, lane, adaptive);
        lane;
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
                \in, currentIn, \out, self[\masterBus].index, \sendOut, self[\reverbBus].index,
                \gridOut, self[\gridFxBus].index,
                \pit, c[\pit], \pos, c[\pos], \size, c[\size], \dens, c[\dens],
                \tex, c[\tex], \drywet, c[\drywet], \spread, c[\spread],
                \rvb, c[\rvb], \fb, c[\fb], \mode, c[\mode], \lofi, c[\lofi],
                \amp, lane[\level] ? 1.0, \pan, lane[\pan] ? 0.0,
                \send, lane[\reverbSend] ? 0.5
            ]);
            lane[\outSynth] = synth;
            lane[\synths].add(synth);
        } {
            var chain = self[\choosePedalsForLane].value(self, lane);
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
            outSynth = Synth.new(\eapLaneOut, [
                \in, currentIn, \out, self[\masterBus].index, \sendOut, self[\reverbBus].index,
                \gridOut, self[\gridFxBus].index,
                \amp, lane[\level] ? 1.0, \pan, lane[\pan] ? 0.0,
                \send, lane[\reverbSend] ? 0.5
            ], target, \addAfter);
            lane[\synths].add(outSynth);
            lane[\outSynth] = outSynth;
            lane[\pedals] = chain;
        };
    };

    ~laneGridFxSelected = { |self, lane|
        var slot = if(lane.notNil, { (lane[\slot] ? 0).asInteger }, { 0 });
        var scenes = self[\gridFxScenes];
        slot > 0 and: { scenes.notNil and: { scenes[slot - 1] == true } };
    };

    ~applyLaneOutput = { |self, lane|
        if(lane.notNil and: { lane[\outSynth].notNil }) {
            var routedToGrid = (self[\gridFxActive] ? false).asBoolean and: {
                self[\laneGridFxSelected].value(self, lane)
            };
            var audible = lane[\state] == \active;
            lane[\outSynth].set(
                \amp, if(audible, { lane[\level] ? 1.0 }, { 0.0 }),
                \pan, lane[\pan] ? 0.0,
                \send, lane[\reverbSend] ? 0.5,
                \dryAmp, if(routedToGrid, { 0.0 }, { 1.0 }),
                \gridSend, if(routedToGrid, { 1.0 }, { 0.0 })
            );
        };
        lane;
    };

    ~applyGridFxRouting = { |self|
        self[\slots].do({ |lane|
            if(lane.notNil and: { lane[\state] == \active }) {
                self[\applyLaneOutput].value(self, lane);
            };
        });
    };

    ~primeLane = { |self, lane|
        var modifier = lane[\soundModifier] ? \harmonic;
        var hasRings = (lane[\materials] ? []).includes(\rings);
        var events = if(hasRings, {
            switch(modifier,
                \drone, { [
                    (sourceCount: 1, accent: 1.7, scaleStep: 0, panBias: 0.0, decayScale: 1.3, sustain: 1, prime: 1),
                    (sourceCount: 1, accent: 1.25, scaleStep: 2, panBias: -0.08, decayScale: 0.9, prime: 1)
                ] },
                \percussive, { [
                    (sourceCount: 1, accent: 1.8, scaleStep: 0, panBias: 0.0, decayScale: 0.95, prime: 1),
                    (sourceCount: 1, accent: 1.35, scaleStep: 2, panBias: -0.12, decayScale: 0.75, prime: 1),
                    (sourceCount: 1, accent: 1.2, scaleStep: -1, panBias: 0.14, decayScale: 0.8, prime: 1)
                ] },
                \chaos, { [
                    (sourceCount: 1, accent: 1.55, scaleStep: 0, panBias: 0.0, decayScale: 0.65, prime: 1),
                    (sourceCount: 1, accent: 1.2, scaleStep: 3, panBias: 0.18, decayScale: 0.5, prime: 1)
                ] },
                { [
                    (sourceCount: 1, accent: 1.6, scaleStep: 0, panBias: 0.0, decayScale: 1.0, prime: 1),
                    (sourceCount: 1, accent: 1.2, scaleStep: 2, panBias: 0.10, decayScale: 0.82, prime: 1)
                ] }
            );
        }, {
            switch(modifier,
                \drone, { [
                    (sourceCount: 1, accent: 1.45, scaleStep: 0, panBias: 0.0, decayScale: 1.6, sustain: 1)
                ] },
                \percussive, { [
                    (sourceCount: 1, accent: 1.65, scaleStep: 0, panBias: 0.0, decayScale: 1.05),
                    (sourceCount: 1, accent: 1.20, scaleStep: 2, panBias: -0.16, decayScale: 0.85),
                    (sourceCount: 1, accent: 1.10, scaleStep: -1, panBias: 0.18, decayScale: 0.95)
                ] },
                \chaos, { [
                    (sourceCount: 1, accent: 1.35, scaleStep: 0, panBias: 0.0, decayScale: 0.7),
                    (sourceCount: 1, accent: 1.10, scaleStep: 3, panBias: 0.22, decayScale: 0.55)
                ] },
                { [
                    (sourceCount: 1, accent: 1.35, scaleStep: 0, panBias: 0.0, decayScale: 1.15),
                    (sourceCount: 1, accent: 1.05, scaleStep: 1, panBias: 0.12, decayScale: 0.95)
                ] }
            );
        });
        Routine({
            events.do({ |event, i|
                if(i > 0, { if(hasRings, { [0.12, 0.18, 0.24].wrapAt(i - 1) }, { [0.16, 0.22, 0.28].wrapAt(i - 1) }).wait; });
                if(lane.notNil and: { lane[\state] == \active }, {
                    self[\triggerLane].value(self, lane, event);
                });
            });
        }).play(SystemClock);
        self;
    };

    ~stopLaneRoutine = { |lane|
        lane[\routine] = nil;
        lane[\routineToken] = (lane[\routineToken] ? 0) + 1;
        lane;
    };

    ~restartLaneRoutine = { |self, lane, waitPhase = false|
        ~stopLaneRoutine.value(lane);
        if(lane[\group].notNil) {
            lane[\routineToken] = (lane[\routineToken] ? 0) + 1;
            lane[\routine] = lane[\routineToken];
            lane[\routineStartedAt] = Main.elapsedTime;
            lane[\eventStream] = nil;
            self[\syncSubsequenceLane].value(self, lane, true);
        };
        lane;
    };

    ~triggerLane = { |self, lane, event = nil|
        var ev = event ? ();
        var materials = lane[\materials] ? [];
        var sourceCount = (ev[\sourceCount] ? 1).asInteger.clip(1, 2);
        var sources = if(materials.isEmpty, { [] }, {
            if(sourceCount <= 1, { [materials.choose] }, { materials.scramble.keep(sourceCount.min(materials.size)) });
        });
        var accent = (ev[\accent] ? 1).asFloat.clip(0.2, 2.0);
        var scaleStep = (ev[\scaleStep] ? 0).asInteger;
        var panBias = (ev[\panBias] ? 0).asFloat.clip(-0.5, 0.5);
        var isDrone = lane[\soundModifier] == \drone;
        var isPerc = lane[\soundModifier] == \percussive;
        var isChaos = lane[\soundModifier] == \chaos;
        var decayScale = if(isDrone,
            { (ev[\decayScale] ? 1).asFloat.clip(1.5, 8.0) },
            if(isPerc,
                { (ev[\decayScale] ? 1).asFloat.clip(0.45, 2.4) },
                if(isChaos,
                    { (ev[\decayScale] ? 1).asFloat.clip(0.02, 3.5) },
                    { (ev[\decayScale] ? 1).asFloat.clip(0.35, 2.4) }
                )
            )
        );
        var pitch = if(isChaos,
            { self[\chooseChaosPitch].value(self, lane, scaleStep) },
            { self[\choosePitch].value(self, lane, scaleStep) }
        );
        var timbreMotion = (lane[\timbreMotion] ? 0.0).asFloat.clip(0, 1);
        var motionStage = (timbreMotion * 7).round(1).asInteger.clip(0, 7);
        var modDepth = [0.0, 0.035, 0.07, 0.12, 0.18, 0.26, 0.36, 0.50][motionStage];
        var modRate = [0.05, 0.08, 0.13, 0.21, 0.34, 0.55, 0.89, 1.44][motionStage]
            * self[\exprand].value(self, 0.78, 1.28);
        var modShape = [0, 0, 1, 1, 2, 2, 3, 3][motionStage];
        var modRand = [0.0, 0.0, 0.03, 0.06, 0.10, 0.16, 0.24, 0.34][motionStage];
        var sustainEvent = ev[\sustain] ? true;
        var isPrime = (ev[\prime] ? 0).asInteger == 1;
        var sustainScale = if(isDrone or: { sustainEvent }, { 1.0 }, { self[\sustainLoadScale].value(self) });
        if(isChaos, {
            modDepth = self[\rand].value(self, 0.12, 0.72);
            modRate = self[\exprand].value(self, 0.04, 3.2);
            modShape = [0, 1, 2, 3, 4].choose;
            modRand = self[\rand].value(self, 0.08, 0.62);
        });
        lane[\triggerCount] = (lane[\triggerCount] ? 0) + 1;
        if(lane[\triggerLog].isNil, {
            lane[\triggerLog] = true;
            ("EAP lane " ++ (lane[\slot] ? lane[\index] ? "?") ++ " first trigger").postln;
        });
        sources.do({ |source|
            if(source == \plaits) {
                Synth.head(lane[\group], \eapLanePlaitsNote, [
                    \out, lane[\sourceBus].index,
                    \pitch, pitch,
                    \engine, lane[\plaitsModels].choose,
                    \harm, if(isPerc, { self[\rand].value(self, 0.04, 0.68) }, { if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { self[\rand].value(self, 0.05, 0.95) }) }),
                    \timbre, if(isPerc, { self[\rand].value(self, 0.18, 0.78) }, { if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { self[\rand].value(self, 0.10, 0.98) }) }),
                    \morph, if(isPerc, { self[\rand].value(self, 0.08, 0.70) }, { if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { self[\rand].value(self, 0.08, 0.98) }) }),
                    \decay, (if(isDrone, { self[\exprand].value(self, 3.0, 14.0) }, { if(isPerc, { self[\exprand].value(self, 0.045, 0.42) }, { if(isChaos, { self[\exprand].value(self, 0.008, 4.5) }, { self[\exprand].value(self, 0.08, 3.2) }) }) })) * decayScale * sustainScale,
                    \colour, if(isPerc, { self[\rand].value(self, 0.28, 0.82) }, { if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { self[\rand].value(self, 0.15, 0.90) }) }),
                    \amp, lane[\amp] * accent * (if(isChaos, { self[\rand].value(self, 0.35, 1.45) }, { 1.0 })),
                    \pan, (self[\rand].value(self, if(isChaos, { -0.95 }, { -0.75 }), if(isChaos, { 0.95 }, { 0.75 })) + panBias).clip(-1, 1),
                    \envTail, if(isDrone, { self[\rand].value(self, 1.0, 4.5) }, { if(isPerc, { 0.075 }, { if(isChaos, { self[\rand].value(self, 0.02, 1.2) }, { 0.25 }) }) }),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \rings) {
                var baseR = lane[\rings] ? (
                    model: lane[\ringsModel] ? 0,
                    poly: 2,
                    struct: 0.45,
                    bright: 0.58,
                    damp: 0.62,
                    pos: 0.42,
                    envDecay: if(isDrone, { 12.0 }, { 5.0 }),
                    envRelease: if(isDrone, { 2.5 }, { 0.8 })
                );
                var r = (
                    model: if(isChaos, { rrand(0, 3) }, { lane[\ringsModel] }),
                    poly: baseR[\poly] ? 1,
                    struct: if(isChaos, {
                        self[\rand].value(self, 0.0, 1.0)
                    }, {
                        ((baseR[\struct] ? 0.45) + self[\rand].value(self, -0.14, 0.14)).clip(0.16, 0.84)
                    }),
                    bright: if(isChaos, {
                        self[\rand].value(self, 0.0, 1.0)
                    }, {
                        ((baseR[\bright] ? 0.58) + self[\rand].value(self, -0.10, 0.16)).clip(if(isPrime, { 0.42 }, { 0.28 }), 0.96)
                    }),
                    damp: if(isChaos, {
                        self[\rand].value(self, 0.02, 0.99)
                    }, {
                        ((baseR[\damp] ? 0.62) + self[\rand].value(self, -0.16, 0.10)).clip(0.28, if(isPrime, { 0.84 }, { 0.92 }))
                    }),
                    pos: if(isChaos, {
                        self[\rand].value(self, 0.0, 1.0)
                    }, {
                        ((baseR[\pos] ? 0.42) + self[\rand].value(self, -0.12, 0.12)).clip(0.12, 0.78)
                    }),
                    envDecay: (((baseR[\envDecay] ? if(isDrone, { 12.0 }, { 5.0 })) * if(isPrime, { 0.72 }, { 1.0 }))
                        .clip(if(isPerc, { 0.07 }, { 0.3 }), if(isDrone, { 8.0 }, { 10.0 }))) * sustainScale,
                    envRelease: (((baseR[\envRelease] ? if(isDrone, { 2.5 }, { 0.8 })) * if(isPrime, { 0.78 }, { 1.0 }))
                        .clip(0.05, if(isDrone, { 4.0 }, { 2.2 }))) * sustainScale
                );
                Synth.head(lane[\group], \eapLaneRingsNote, [
                    \out, lane[\sourceBus].index,
                    \pitch, (pitch + if(isPrime and: { pitch < 40 }, { 12 }, { 0 })).clip(0, 127),
                    \struct, r[\struct], \bright, r[\bright], \damp, r[\damp], \pos, r[\pos],
                    \model, r[\model], \poly, r[\poly],
                    \envDecay, (r[\envDecay] * decayScale).clip(if(isPerc, { 0.07 }, { 0.3 }), if(isDrone, { 12.0 }, { if(isPerc, { 1.2 }, { if(isChaos, { 2.0 }, { 6.0 }) }) })),
                    \envRelease, (r[\envRelease] * if(isDrone, { 1.4 }, { 1.0 })).clip(0.04, if(isDrone, { 3.5 }, { 2.2 })),
                    \amp, lane[\amp] * accent * (if(isPerc, { self[\rand].value(self, 0.85, 1.35) }, { if(isChaos, { self[\rand].value(self, 0.25, 1.55) }, { self[\rand].value(self, 0.70, 1.25) }) })),
                    \pan, (self[\rand].value(self, if(isChaos, { -0.95 }, { -0.65 }), if(isChaos, { 0.95 }, { 0.65 })) + panBias).clip(-1, 1),
                    \strike, if(isPrime, { if(isDrone, { 1.3 }, { 1.55 }) }, { if(isPerc, { 1.18 }, { if(isDrone, { 1.05 }, { 1.12 }) }) }),
                    \exciterDecay, if(isPrime, { if(isPerc, { 0.06 }, { 0.10 }) }, { if(isPerc, { 0.045 }, { 0.08 }) }),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \harmonium) {
                var h = lane[\harmonium] ? ();
                var baseDecay = (h[\envDecay] ? 2.5) * decayScale * sustainScale;
                var baseRelease = (h[\envRelease] ? 1.2) * sustainScale;
                Synth.head(lane[\group], \eapLaneHarmoniumNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \source, if(isChaos, { rrand(0, 6) }, { h[\source] ? 4 }),
                    \formation, if(isChaos, { rrand(0, 2) }, { h[\formation] ? 0 }),
                    \num, (h[\num] ? 10).asInteger.clip(3, 10),
                    \rolloff, (h[\rolloff] ? 1.0),
                    \rq, (h[\rq] ? 0.02), \bandRes, (h[\bandRes] ? 0.3),
                    \timbre, if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { (h[\timbre] ? 0.5) }),
                    \ouMode, (h[\ouMode] ? 0), \pulseWidth, (h[\pulseWidth] ? 0.5),
                    \rmMix, if(isChaos, { self[\rand].value(self, 0.0, 0.6) }, { (h[\rmMix] ? 0) }),
                    \rmHz, (h[\rmHz] ? 30), \rmRatio, (h[\rmRatio] ? 1), \rmTrack, (h[\rmTrack] ? 0),
                    \fmMix, if(isChaos, { self[\rand].value(self, 0.0, 0.5) }, { (h[\fmMix] ? 0) }),
                    \fmIndex, (h[\fmIndex] ? 0.1), \fmRatio, (h[\fmRatio] ? 1),
                    \subAmp, (h[\subAmp] ? 0), \subOct1, (h[\subOct1] ? 0), \subOct2, (h[\subOct2] ? 0),
                    \swirlDepth, (h[\swirlDepth] ? 0.4), \swirlRate, (h[\swirlRate] ? 0.05),
                    \ampShimmer, (h[\ampShimmer] ? 0.3), \wet, (h[\wet] ? 0.6),
                    \envAttack, if(isDrone, { self[\rand].value(self, 0.15, 0.9) }, { if(isPerc, { 0.004 }, { self[\rand].value(self, 0.01, 0.12) }) }),
                    \envDecay, baseDecay.clip(if(isPerc, { 0.08 }, { 0.3 }), if(isDrone, { 10.0 }, { if(isPerc, { 0.9 }, { if(isChaos, { 2.5 }, { 6.0 }) }) })),
                    \envRelease, baseRelease.clip(0.05, if(isDrone, { 4.0 }, { 2.5 })),
                    \amp, lane[\amp] * accent * (if(isPerc, { 0.92 }, { if(isChaos, { self[\rand].value(self, 0.4, 1.1) }, { 0.85 }) })),
                    \pan, (self[\rand].value(self, if(isChaos, { -0.9 }, { -0.6 }), if(isChaos, { 0.9 }, { 0.6 })) + panBias).clip(-1, 1),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \molly) {
                var m = lane[\molly];
                Synth.head(lane[\group], \eapLaneMollyNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \oscWaveShape, if(isChaos, { rrand(0, 2) }, { (m[\oscWaveShape] + (modRand * self[\rand].value(self, -0.8, 0.8))).clip(0, 2) }),
                    \pwMod, if(isChaos, { self[\rand].value(self, 0.0, 0.65) }, { (m[\pwMod] + (modDepth * 0.55)).clip(0, 1) }),
                    \freqModLfo, if(isChaos, { self[\exprand].value(self, 0.002, 0.75) }, { (m[\freqModLfo] + (modDepth * 0.32)).clip(0, 0.7) }),
                    \freqModEnv, if(isChaos, { self[\rand].value(self, -0.18, 0.28) }, { (m[\freqModEnv] + (modRand * 0.18)).clip(0, 0.8) }),
                    \mainOscLevel, m[\mainOscLevel], \subOscLevel, if(isChaos, { self[\rand].value(self, 0.0, 0.75) }, { m[\subOscLevel] }),
                    \subOscDetune, if(isChaos, { self[\rand].value(self, -0.25, 0.25) }, { m[\subOscDetune] }),
                    \noiseLevel, if(isChaos, { self[\exprand].value(self, 0.01, 0.65) }, { (m[\noiseLevel] + (modRand * 0.12)).clip(0, 0.45) }),
                    \hpFilterCutoff, if(isChaos, { self[\exprand].value(self, 8, 2200) }, { m[\hpFilterCutoff] }),
                    \lpFilterCutoff, if(isChaos, { self[\exprand].value(self, 120, 14000) }, { m[\lpFilterCutoff] }),
                    \lpFilterResonance, if(isChaos, { self[\rand].value(self, 0.02, 0.92) }, { (m[\lpFilterResonance] + (modDepth * 0.28)).clip(0, 1) }),
                    \lpFilterModEnv, if(isChaos, { self[\rand].value(self, 0.0, 0.95) }, { (m[\lpFilterModEnv] + (modDepth * 0.55)).clip(0, 1) }),
                    \lpFilterTracking, m[\lpFilterTracking], \lfoFreq, if(isChaos, { self[\exprand].value(self, 0.02, 8.0) }, { modRate }),
                    \lfoWaveShape, if(isChaos, { rrand(0, 4) }, { modShape.clip(0, 4) }),
                    \envAttack, if(isChaos, { self[\exprand].value(self, 0.001, 0.35) }, { m[\envAttack] }),
                    \envDecay, if(isChaos, { self[\exprand].value(self, 0.02, 3.5) }, { m[\envDecay] }) * sustainScale,
                    \envSustain, if(isChaos, { self[\rand].value(self, 0.0, 0.55) }, { (m[\envSustain] * sustainScale).clip(0, 0.78) }),
                    \envRelease, if(isChaos, { self[\exprand].value(self, 0.03, 4.5) }, { m[\envRelease] }) * sustainScale,
                    \ringModFreq, if(isChaos, { self[\exprand].value(self, 0.25, 12.0) }, { m[\ringModFreq] }),
                    \ringModMix, if(isChaos, { self[\rand].value(self, 0.0, 0.85) }, { (m[\ringModMix] + (modRand * 0.22)).clip(0, 1) }),
                    \ampMod, if(isChaos, { self[\rand].value(self, 0.0, 0.85) }, { (m[\ampMod] + (modDepth * 0.45)).clip(0, 0.9) }),
                    \amp, lane[\amp] * accent * (if(isChaos, { self[\rand].value(self, 0.35, 1.1) }, { 0.85 })),
                    \pan, (self[\rand].value(self, if(isChaos, { -0.95 }, { -0.70 }), if(isChaos, { 0.95 }, { 0.70 })) + panBias).clip(-1, 1)
                ]);
            };
            if(source == \passersby) {
                var p = lane[\passersby];
                Synth.head(lane[\group], \eapLanePassersbyNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \waveShape, if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { p[\waveShape] }),
                    \waveFolds, if(isChaos, { self[\rand].value(self, 0.0, 6.5) }, { p[\waveFolds] }),
                    \fm1Ratio, if(isChaos, { self[\exprand].value(self, 0.25, 8.0) }, { p[\fm1Ratio] }),
                    \fm2Ratio, if(isChaos, { self[\exprand].value(self, 0.5, 12.0) }, { p[\fm2Ratio] }),
                    \fm1Amount, if(isChaos, { self[\rand].value(self, 0.0, 0.85) }, { p[\fm1Amount] }),
                    \fm2Amount, if(isChaos, { self[\rand].value(self, 0.0, 0.78) }, { p[\fm2Amount] }),
                    \attack, if(isChaos, { self[\exprand].value(self, 0.001, 0.55) }, { p[\attack] }),
                    \peak, if(isChaos, { self[\exprand].value(self, 120, 14000) }, { p[\peak] }),
                    \decay, (if(isChaos, { self[\exprand].value(self, 0.015, 5.5) }, { p[\decay] })) * decayScale * sustainScale,
                    \reverbMix, if(isChaos, { self[\rand].value(self, 0.0, 0.65) }, { p[\reverbMix] }),
                    \foldMix, if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { p[\foldMix] }),
                    \body, if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { p[\body] }),
                    \air, if(isChaos, { self[\exprand].value(self, 0.005, 0.45) }, { p[\air] }),
                    \filterRq, if(isChaos, { self[\rand].value(self, 0.05, 0.98) }, { p[\filterRq] }),
                    \toneTilt, if(isChaos, { self[\rand].value(self, 0.0, 1.0) }, { p[\toneTilt] }),
                    \amp, lane[\amp] * accent * (if(isChaos, { self[\rand].value(self, 0.35, 1.15) }, { 0.85 })),
                    \pan, (self[\rand].value(self, if(isChaos, { -0.95 }, { -0.70 }), if(isChaos, { 0.95 }, { 0.70 })) + panBias).clip(-1, 1),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \fm7) {
                var f = lane[\fm7];
                var ratios = f[\ratios] ? [1, 2, 3, 4, 5, 6];
                var opAmps = f[\opAmps] ? [1, 0.45, 0.28, 0.2, 0.16, 0.1];
                var carriers = f[\carriers] ? [1, 0, 0, 0, 0, 0];
                Synth.head(lane[\group], \eapLaneFM7Note, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \algorithm, if(isChaos, { rrand(0, 7) }, { f[\algorithm] }),
                    \ratio1, ratios[0], \ratio2, ratios[1], \ratio3, ratios[2],
                    \ratio4, ratios[3], \ratio5, ratios[4], \ratio6, ratios[5],
                    \opAmp1, opAmps[0], \opAmp2, opAmps[1], \opAmp3, opAmps[2],
                    \opAmp4, opAmps[3], \opAmp5, opAmps[4], \opAmp6, opAmps[5],
                    \carrier1, carriers[0], \carrier2, carriers[1], \carrier3, carriers[2],
                    \carrier4, carriers[3], \carrier5, carriers[4], \carrier6, carriers[5],
                    \index1, if(isChaos, { (f[\index1] * self[\rand].value(self, 0.65, 1.45)).clip(0, 8.5) }, { f[\index1] }),
                    \index2, if(isChaos, { (f[\index2] * self[\rand].value(self, 0.55, 1.65)).clip(0, 6.0) }, { f[\index2] }),
                    \index3, if(isChaos, { (f[\index3] * self[\rand].value(self, 0.45, 1.8)).clip(0, 4.0) }, { f[\index3] }),
                    \feedback, if(isChaos, { (f[\feedback] + self[\rand].value(self, 0.0, 0.8)).clip(0, 2.6) }, { f[\feedback] }),
                    \attack, if(isChaos, { self[\exprand].value(self, 0.001, 0.22) }, { f[\attack] }),
                    \decay, (if(isChaos, { self[\exprand].value(self, 0.035, 2.6) }, { f[\decay] })) * decayScale * sustainScale,
                    \sustain, if(isPerc, { (f[\sustain] ? 0.05).clip(0, 0.18) }, { f[\sustain] }),
                    \release, (if(isChaos, { self[\exprand].value(self, 0.035, 2.2) }, { f[\release] })) * sustainScale,
                    \brightness, if(isChaos, { self[\rand].value(self, 0.12, 1.0) }, { f[\brightness] }),
                    \grit, if(isChaos, { (f[\grit] + self[\rand].value(self, 0.0, 0.22)).clip(0, 0.48) }, { f[\grit] }),
                    \amp, lane[\amp] * accent * (if(isPerc, { 0.82 }, { if(isChaos, { self[\rand].value(self, 0.25, 0.95) }, { 0.72 }) })),
                    \pan, (self[\rand].value(self, if(isChaos, { -0.95 }, { -0.72 }), if(isChaos, { 0.95 }, { 0.72 })) + panBias).clip(-1, 1),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \dexed) {
                var d = lane[\dexed];
                var noteDur = lane[\gap] * (d[\durScale] ? 1.0) * decayScale;
                noteDur = if(isPerc, { noteDur.clip(0.06, 0.85) }, { if(isDrone, { noteDur.clip(2.0, 18.0) }, { if(isChaos, { noteDur.clip(0.02, 6.5) }, { noteDur.clip(0.08, 8.0) }) }) });
                self[\sendDexedNote].value(self,
                    d[\channel] ? 0,
                    (pitch + (d[\octaveBias] ? 0)).clip(0, 127),
                    ((d[\velocity] ? 82) * accent).clip(if(isChaos, { 18 }, { 24 }), 126),
                    noteDur
                );
                self[\pulseExternalInput].value(self, lane, \dexed, noteDur);
            };
            if(source == \vital) {
                var v = lane[\vital];
                var noteDur = lane[\gap] * (v[\durScale] ? 1.0) * decayScale;
                noteDur = if(isPerc, { noteDur.clip(0.06, 0.72) }, { if(isDrone, { noteDur.clip(2.5, 20.0) }, { if(isChaos, { noteDur.clip(0.02, 8.0) }, { noteDur.clip(0.08, 10.0) }) }) });
                self[\sendVitalNote].value(self,
                    (pitch + (v[\octaveBias] ? 0)).clip(0, 127),
                    ((v[\velocity] ? 82) * accent).clip(if(isChaos, { 16 }, { 24 }), 126),
                    noteDur
                );
                self[\pulseExternalInput].value(self, lane, \vital, noteDur);
            };
            if(source == \vcv) {
                var v = lane[\vcv];
                var noteDur = lane[\gap] * (v[\durScale] ? 1.0) * decayScale;
                noteDur = if(isPerc, { noteDur.clip(0.06, 0.82) }, { if(isDrone, { noteDur.clip(2.5, 20.0) }, { if(isChaos, { noteDur.clip(0.02, 8.5) }, { noteDur.clip(0.08, 10.0) }) }) });
                self[\sendVcvNote].value(self,
                    (pitch + (v[\octaveBias] ? 0)).clip(0, 127),
                    ((v[\velocity] ? 82) * accent).clip(if(isChaos, { 16 }, { 24 }), 126),
                    noteDur
                );
                self[\pulseExternalInput].value(self, lane, \vcv, noteDur);
            };
        });
    };

    ~startLane = { |self, lane|
        if(lane[\state] != \active) {
            var wasBlank = lane[\state] == \blank;
            var wasMuted = lane[\state] == \muted;
            lane[\teardownToken] = (lane[\teardownToken] ? 0) + 1;
            lane[\group] = Group.head(self[\group]);
            lane[\sourceBus] = Bus.audio(s, 2);
            lane[\buses] = List.new;
            lane[\buses].add(lane[\sourceBus]);
            lane[\synths] = List.new;
            self[\buildFx].value(self, lane, lane[\sourceBus]);
            lane[\state] = \active;
            lane[\mutedMode] = nil;
            if(wasMuted, { self[\restoreExternalEngineForLane].value(self, lane); });
            self[\applyLaneOutput].value(self, lane);
            self[\restartLaneRoutine].value(self, lane, wasMuted);
            if(lane[\routine].isNil, {
                ("EAP lane " ++ (lane[\slot] ? lane[\index] ? "?")
                    ++ " rhythm did not start — retrying").postln;
                self[\restartLaneRoutine].value(self, lane, wasMuted);
            }, {
                if(wasBlank, { self[\primeLane].value(self, lane); });
            });
        };
        lane;
    };

    ~slotUiState = { |lane|
        if(lane.isNil or: { lane[\state] == \blank }, { 0 }, {
            if(lane[\state] == \active, { 1 }, { 2 })
        });
    };

    ~replySlotStates = { |self, addr|
        if(addr.notNil, {
            var states = self[\slots].collect({ |lane| self[\slotUiState].value(lane) });
            var densities = self[\slots].collect({ |lane| self[\displayDensityForLane].value(self, lane) });
            addr.sendMsg('/eap/slots/state', *states);
            addr.sendMsg('/eap/slots/density', *densities);
        });
        self;
    };

    ~stopLane = { |self, lane, nextState = \muted|
        if(lane.notNil) {
            var group = lane[\group];
            var buses = lane[\buses];
            var outSynth = lane[\outSynth];
            var fadeTime = if(nextState == \blank, { 1.2 }, { if(nextState == \muted, { 0.45 }, { 2.8 }) });
            var teardownToken;
            if(lane[\routine].notNil) {
                ~stopLaneRoutine.value(lane);
                self[\syncSubsequenceLane].value(self, lane, false);
            };
            if(outSynth.notNil) { outSynth.set(\fadeTime, fadeTime, \amp, 0); };
            lane[\teardownToken] = (lane[\teardownToken] ? 0) + 1;
            teardownToken = lane[\teardownToken];
            if(group.notNil) {
                Routine({
                    fadeTime.wait;
                    if(lane[\teardownToken] == teardownToken) {
                        group.free;
                        if(buses.notNil) { buses.do({ |bus| bus.free; }); };
                    };
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
            lane[\mutedMode] = if(nextState == \muted, { \refresh }, { nil });
            self[\muteExternalInput].value(self);
            self[\syncExternalEngines].value(self);
        };
        lane;
    };

    ~outputMuteLane = { |self, lane|
        if(lane.notNil and: { lane[\state] == \active }) {
            lane[\state] = \muted;
            lane[\mutedMode] = \output;
            if(lane[\outSynth].notNil) {
                lane[\outSynth].set(\fadeTime, 0.45, \amp, 0.0);
            };
            self[\syncExternalEngines].value(self);
        };
        lane;
    };

    ~outputUnmuteLane = { |self, lane|
        if(lane.notNil and: { lane[\state] == \muted and: { lane[\mutedMode] == \output } }) {
            lane[\state] = \active;
            lane[\mutedMode] = nil;
            self[\applyLaneOutput].value(self, lane);
            self[\syncExternalEngines].value(self);
        };
        lane;
    };

    ~syncLoad = { |self|
        var total = self[\activeCount].value(self).max(1);
        self[\slots].do({ |lane|
            if(lane.notNil) {
                if(total > 1 and: { lane[\state] == \active and: { lane[\fx] == \clouds } }) {
                    ("EAP lane " ++ (lane[\slot] ? lane[\index] ? "?") ++ " clouds disabled under load").postln;
                    self[\stopLane].value(self, lane, \muted);
                    lane[\fx] = \pedalboard;
                    lane[\cpuClass] = \normal;
                    self[\startLane].value(self, lane);
                };
                lane[\total] = total;
                lane[\amp] = (0.28 / total.sqrt).clip(0.10, 0.26);
                self[\applyLaneOutput].value(self, lane);
            };
        });
        if(self[\masterSynth].notNil, {
            var wetScale = switch(total,
                5, { 0.50 },
                4, { 0.62 },
                3, { 0.78 },
                { 1.0 }
            );
            var wet = ((self[\reverbValues][0] ? 0.24) * wetScale).clip(0, 0.9);
            self[\masterSynth].set(\wet, wet);
        });
        self[\syncExternalEngines].value(self);
    };

    ~setSlotVolume = { |self, slot, value|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        var level = value.asFloat.clip(0, 1);
        if(lane.notNil, {
            lane[\level] = level;
            self[\applyLaneOutput].value(self, lane);
            ("EAP slot " ++ index ++ " volume=" ++ level.round(0.001)).postln;
            1;
        }, {
            0;
        });
    };

    ~setSlotPan = { |self, slot, value|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        var pan = value.asFloat.clip(-1, 1);
        if(lane.notNil, {
            lane[\pan] = pan;
            self[\applyLaneOutput].value(self, lane);
            ("EAP slot " ++ index ++ " pan=" ++ pan.round(0.001)).postln;
            1;
        }, {
            0;
        });
    };

    ~setSlotDensity = { |self, slot, value|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        var density = value.asFloat.clip(0.05, 1.0);
        if(lane.notNil, {
            lane[\density] = density;
            self[\syncSubsequenceDensity].value(self, index, density);
            ("EAP slot " ++ index ++ " density=" ++ density.round(0.001)).postln;
            1;
        }, {
            0;
        });
    };

    ~setSlotTimbreMotion = { |self, slot, value|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        var motion = value.asFloat.clip(0.0, 1.0);
        if(lane.notNil, {
            lane[\timbreMotion] = motion;
            ("EAP slot " ++ index ++ " timbreMotion=" ++ motion.round(0.001)).postln;
            1;
        }, {
            0;
        });
    };

    ~setSlotReverbSend = { |self, slot, value|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        var send = value.asFloat.clip(0.0, 1.0);
        if(lane.notNil, {
            lane[\reverbSend] = send;
            self[\applyLaneOutput].value(self, lane);
            ("EAP slot " ++ index ++ " reverbSend=" ++ send.round(0.001)).postln;
            1;
        }, {
            0;
        });
    };

    ~setSlotTranspose = { |self, slot, semitones|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        var transpose = semitones.asInteger.clip(-36, 36);
        if(lane.notNil, {
            lane[\transpose] = transpose;
            ("EAP slot " ++ index ++ " transpose=" ++ transpose).postln;
            1;
        }, {
            0;
        });
    };

    ~setGridFxActive = { |self, active|
        var enabled = active.asBoolean;
        self[\gridFxActive] = enabled;
        if(self[\gridFxSendSynth].notNil, {
            self[\gridFxSendSynth].set(\amp, if(enabled, { 1.0 }, { 0.0 }));
        });
        if(self[\masterSynth].notNil, {
            self[\masterSynth].set(\gridActive, if(enabled, { 1 }, { 0 }));
        });
        self[\applyGridFxRouting].value(self);
        ("EAP Airwindows grid FX active=" ++ enabled).postln;
        enabled;
    };

    ~processGridFxQueue = { |self|
        if((self[\gridFxProcessing] ? false).not, {
            self[\gridFxProcessing] = true;
            Routine({
                while({ self[\gridFxQueue].size > 0 }, {
                    var cmd = self[\gridFxQueue].removeAt(0);
                    var result, active, wasActive;
                    wasActive = (self[\gridFxActive] ? false).asBoolean;
                    // The airwindows host accepts chain edits live over UDP,
                    // so a per-FX toggle does not disturb the JACK chain or
                    // the SC-side routing. No pre/post mute is needed.
                    result = cmd.unixCmdGetStdOut.stripWhiteSpace;
                    active = result.contains("active=1") or: { result.contains("active=2") or: { result.contains("active=3") } };
                    if(result.notEmpty, { ("EAP " ++ result).postln; });
                    // Re-route lanes only on the empty<->non-empty transition:
                    // - empty -> first FX: switch grid-selected scenes from dry to grid
                    // - last FX -> empty: switch them back to dry
                    // Toggles between two non-empty chain states are pure UDP.
                    if(active != wasActive, {
                        self[\setGridFxActive].value(self, active);
                    });
                });
                self[\gridFxProcessing] = false;
            }).play(SystemClock);
        });
    };

    ~setGridFx = { |self, index, enabled|
        var fxIndex = index.asInteger.clip(1, 30);
        var state = if(enabled.asInteger > 0, { 1 }, { 0 });
        self[\gridFxQueue].add("/usr/local/bin/eap-airwindows-grid-fx --set " ++ fxIndex ++ " " ++ state);
        self[\processGridFxQueue].value(self);
        true;
    };

    ~setGridFxLock = { |self, index, locked|
        var fxIndex = index.asInteger.clip(1, 30);
        var state = if(locked.asInteger > 0, { 1 }, { 0 });
        self[\gridFxQueue].add("/usr/local/bin/eap-airwindows-grid-fx --lock " ++ fxIndex ++ " " ++ state);
        self[\processGridFxQueue].value(self);
        true;
    };

    ~setGridFxScene = { |self, slot, enabled|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var state = enabled.asInteger > 0;
        if(self[\gridFxScenes].isNil, {
            self[\gridFxScenes] = Array.fill(self[\maxScenes], { false });
        });
        self[\gridFxScenes][index - 1] = state;
        self[\applyGridFxRouting].value(self);
        ("EAP Airwindows grid FX scene " ++ index ++ " selected=" ++ state).postln;
        state;
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
            5, { [\compProfile, (v * 8).round(1).asInteger.clip(0, 8)] },
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

    ~setTuning = { |self, scaleIndex = nil, rootNote = nil|
        if(scaleIndex.notNil) {
            self[\scaleIndex] = scaleIndex.asInteger.clip(0, self[\scales].size - 1);
        };
        if(rootNote.notNil) {
            self[\rootNote] = rootNote.asInteger.clip(0, 11);
        };
        self[\slots].do({ |lane|
            if(lane.notNil and: { lane[\state] == \active }) {
                lane[\scale] = self[\scales].wrapAt(self[\scaleIndex]).copy;
                lane[\lastDegree] = nil;
            };
        });
        self[\playTuningPreview].value(self);
        self[\syncSubsequenceTuning].value(self);
        ("EAP tuning scale=" ++ self[\scaleIndex] ++ " root=" ++ self[\rootNote]).postln;
        1;
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
                rhythmProfile: lane[\rhythmProfile], pulse: lane[\pulse], swing: lane[\swing],
                amp: lane[\amp], level: lane[\level], pan: lane[\pan], density: lane[\density],
                timbreMotion: lane[\timbreMotion], reverbSend: lane[\reverbSend],
                transpose: lane[\transpose],
                cpuClass: lane[\cpuClass],
                plaitsModels: lane[\plaitsModels].copy,
                ringsModel: lane[\ringsModel], rings: if(lane[\rings].notNil, { lane[\rings].copy }, { nil }),
                soundModifier: lane[\soundModifier], lastDegree: lane[\lastDegree],
                sourceEngine: lane[\sourceEngine], adaptive: if(lane[\adaptive].notNil, { lane[\adaptive].copy }, { nil }),
                molly: lane[\molly].copy, passersby: lane[\passersby].copy, fm7: lane[\fm7].copy,
                harmonium: if(lane[\harmonium].notNil, { lane[\harmonium].copy }, { nil }),
                dexed: lane[\dexed].copy, vital: lane[\vital].copy, vcv: lane[\vcv].copy,
                clouds: lane[\clouds].copy, state: lane[\state]
            );
        });
    };

    ~prepareLoadedLane = { |self, lane, index|
        var m = lane[\molly];
        var p = lane[\passersby];
        var f = lane[\fm7];
        var d = lane[\dexed];
        var v = lane[\vital];
        var r = lane[\vcv];
        lane[\index] = index + 1;
        lane[\slot] = index + 1;
        if(lane[\materials].notNil and: { lane[\materials].size > 1 }, {
            lane[\materials] = [lane[\materials][0]];
        });
        lane[\materials] = (lane[\materials] ? [\fm7]).reject({ |source| [\dexed, \vital, \vcv].includes(source) });
        if(lane[\materials].isEmpty, { lane[\materials] = [\fm7]; });
        lane[\group] = nil;
        lane[\sourceBus] = nil;
        lane[\buses] = nil;
        lane[\synths] = nil;
        lane[\pedals] = nil;
        lane[\outSynth] = nil;
        lane[\routine] = nil;
        lane[\triggerTimes] = nil;
        lane[\restProb] = lane[\restProb] ? 0.18;
        lane[\volatility] = lane[\volatility] ? 1.0;
        lane[\scale] = self[\scales].wrapAt(self[\scaleIndex]).copy;
        lane[\lastDegree] = nil;
        lane[\eventStream] = nil;
        lane[\rhythmProfile] = lane[\rhythmProfile] ? self[\rhythmProfilesFor].value(lane[\soundModifier]).choose;
        lane[\pulse] = lane[\pulse] ? 0.12;
        lane[\swing] = lane[\swing] ? 0.0;
        lane[\level] = lane[\level] ? 1.0;
        lane[\pan] = lane[\pan] ? 0.0;
        lane[\density] = lane[\density] ? 1.0;
        lane[\timbreMotion] = lane[\timbreMotion] ? 0.0;
        lane[\reverbSend] = lane[\reverbSend] ? 0.5;
        lane[\transpose] = (lane[\transpose] ? 0).asInteger.clip(-36, 36);
        lane[\sourceEngine] = if(self[\sourceEngineSymbols].includes(lane[\sourceEngine]), { lane[\sourceEngine] }, { \fm7 });
        lane[\adaptive] = lane[\adaptive] ? (
            siblingCount: 0,
            avoidMaterials: [],
            overusedMaterials: [],
            avoidRhythms: [],
            avoidFx: [],
            registerBand: self[\registerBandFor].value(self, lane[\register])
        );
        lane[\cpuClass] = lane[\cpuClass] ? \normal;
        lane[\plaitsModels] = (lane[\plaitsModels] ? [0]).collect({ |model|
            if(self[\plaitsModelPool].includes(model), { model }, { self[\plaitsModelPool].choose });
        });
        if(lane[\rings].isNil, {
            lane[\rings] = (
                model: lane[\ringsModel] ? 0,
                poly: 2,
                struct: 0.4,
                bright: 0.5,
                damp: 0.7,
                pos: 0.4,
                envDecay: 8.0,
                envRelease: 1.2
            );
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
        if(f.isNil, {
            lane[\fm7] = (
                algorithm: 0, ratios: [1, 2, 3, 4, 5, 6], opAmps: [1, 0.45, 0.28, 0.2, 0.16, 0.1],
                carriers: [1, 0, 0, 0, 0, 0], index1: 1.2, index2: 0.45, index3: 0.16,
                feedback: 0.0, attack: 0.01, decay: 0.8, sustain: 0.35, release: 0.6,
                brightness: 0.55, grit: 0.08
            );
            f = lane[\fm7];
        });
        f[\algorithm] = (f[\algorithm] ? 0).asInteger.clip(0, 7);
        f[\ratios] = (f[\ratios] ? [1, 2, 3, 4, 5, 6]).collect({ |ratio| ratio.asFloat.clip(0.125, 16) });
        while({ f[\ratios].size < 6 }, { f[\ratios] = f[\ratios].add(1); });
        f[\opAmps] = (f[\opAmps] ? [1, 0.45, 0.28, 0.2, 0.16, 0.1]).collect({ |opAmp| opAmp.asFloat.clip(0, 1.4) });
        while({ f[\opAmps].size < 6 }, { f[\opAmps] = f[\opAmps].add(0.1); });
        f[\carriers] = (f[\carriers] ? [1, 0, 0, 0, 0, 0]).collect({ |carrier| carrier.asFloat.clip(0, 1) });
        while({ f[\carriers].size < 6 }, { f[\carriers] = f[\carriers].add(0); });
        if(f[\carriers].sum <= 0, { f[\carriers][0] = 1; });
        f[\index1] = (f[\index1] ? 1.2).clip(0, 8.5);
        f[\index2] = (f[\index2] ? 0.45).clip(0, 6.0);
        f[\index3] = (f[\index3] ? 0.16).clip(0, 4.0);
        f[\feedback] = (f[\feedback] ? 0).clip(0, 2.6);
        f[\attack] = (f[\attack] ? 0.01).clip(0.001, 4.0);
        f[\decay] = (f[\decay] ? 0.8).clip(0.02, 12.0);
        f[\sustain] = (f[\sustain] ? 0.35).clip(0, 1);
        f[\release] = (f[\release] ? 0.6).clip(0.02, 10.0);
        f[\brightness] = (f[\brightness] ? 0.55).clip(0, 1);
        f[\grit] = (f[\grit] ? 0.08).clip(0, 0.5);
        if(lane[\harmonium].isNil, {
            lane[\harmonium] = (
                source: 4, formation: 0, num: 10, rolloff: 1.0, rq: 0.02, bandRes: 0.3,
                timbre: 0.5, ouMode: 0, pulseWidth: 0.5, rmMix: 0.0, rmHz: 30, rmRatio: 1.0,
                rmTrack: 0, fmMix: 0.0, fmIndex: 0.1, fmRatio: 1.0, subAmp: 0.0, subOct1: 0,
                subOct2: 0, swirlDepth: 0.4, swirlRate: 0.05, ampShimmer: 0.3, wet: 0.6,
                envDecay: 2.5, envRelease: 1.2
            );
        });
        if(d.notNil) {
            d[\channel] = (d[\channel] ? index).clip(0, 15);
            d[\velocity] = (d[\velocity] ? 82).clip(24, 126);
            d[\durScale] = (d[\durScale] ? 1.0).clip(0.25, 3.5);
            d[\octaveBias] = if([-12, 0, 12].includes(d[\octaveBias]), { d[\octaveBias] }, { 0 });
            d[\patchSeed] = d[\patchSeed] ? 0;
            d[\patchInfo] = d[\patchInfo] ? "";
        };
        if(v.notNil) {
            v[\velocity] = (v[\velocity] ? 82).clip(24, 126);
            v[\durScale] = (v[\durScale] ? 1.0).clip(0.04, 10.0);
            v[\octaveBias] = if([-24, -12, 0, 12, 24].includes(v[\octaveBias]), { v[\octaveBias] }, { 0 });
            v[\patchSeed] = v[\patchSeed] ? 0;
            v[\patchProfile] = v[\patchProfile] ? \default;
            v[\patchInfo] = v[\patchInfo] ? "";
        };
        if(r.notNil) {
            r[\velocity] = (r[\velocity] ? 82).clip(24, 126);
            r[\durScale] = (r[\durScale] ? 1.0).clip(0.04, 10.0);
            r[\octaveBias] = if([-24, -12, 0, 12, 24].includes(r[\octaveBias]), { r[\octaveBias] }, { 0 });
            r[\patchSeed] = r[\patchSeed] ? 0;
            r[\patchProfile] = r[\patchProfile] ? \default;
            r[\patchInfo] = r[\patchInfo] ? "";
        };
        lane;
    };

    ~sessionSnapshot = { |self|
        (
            reverbValues: self[\reverbValues].copy,
            masterValues: self[\masterValues].copy,
            scaleIndex: self[\scaleIndex],
            rootNote: self[\rootNote],
            muteMode: self[\muteModeCode].value(self),
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
        var loadedActive = 0;
        var maxLoadedActive = 3;
        if(File.exists(path).not, {
            ("EAP session " ++ index ++ " is blank").postln;
            0;
        }, {
            snapshot = Object.readArchive(path);
            self[\clear].value(self);
            self[\reverbValues] = snapshot[\reverbValues].copy;
            self[\masterValues] = snapshot[\masterValues].copy;
            self[\setMuteMode].value(self, snapshot[\muteMode] ? self[\muteModeCode].value(self));
            self[\setTuning].value(self, snapshot[\scaleIndex] ? self[\scaleIndex], snapshot[\rootNote] ? self[\rootNote]);
            self[\applyReverb].value(self);
            self[\applyMaster].value(self);
            snapshot[\slots].do({ |lane, laneIndex|
                if(lane.notNil) {
                    self[\prepareLoadedLane].value(self, lane, laneIndex);
                    self[\slots][laneIndex] = lane;
                    self[\lanes].add(lane);
                    if(lane[\state] == \active) {
                        if(loadedActive < maxLoadedActive, {
                            loadedActive = loadedActive + 1;
                            lane[\state] = \muted;
                            self[\startLane].value(self, lane);
                        }, {
                            lane[\state] = \muted;
                            ("EAP session " ++ index ++ " loaded slot " ++ (laneIndex + 1)
                                ++ " muted: active lane cap").postln;
                        });
                    };
                };
            });
            self[\syncLoad].value(self);
            ("EAP session " ++ index ++ " loaded").postln;
            1;
        });
    };

    ~clear = { |self|
        self[\syncSubsequenceAllLanes].value(self, false);
        self[\slots].do({ |lane| self[\stopLane].value(self, lane, \blank); });
        self[\lanes].clear;
        self[\slots] = Array.fill(self[\maxScenes], { nil });
        self[\cloudLaneIndex] = nil;
        self[\adaptiveJournal].clear;
        self[\adaptiveSerial] = 0;
        self[\syncExternalEngines].value(self);
    };

    ~slotStatus = { |self, slot|
        var lane = self[\slots].wrapAt(slot - 1);
        if(lane.isNil, {
            0;
        }, {
            if(lane[\state] == \active, { 1 }, { 2 });
        });
    };

    ~performanceStateForLane = { |lane|
        if(lane.isNil, {
            nil;
        }, {
            (
                level: lane[\level] ? 1.0,
                pan: lane[\pan] ? 0.0,
                density: lane[\density] ? 1.0,
                timbreMotion: lane[\timbreMotion] ? 0.0,
                reverbSend: lane[\reverbSend] ? 0.5,
                transpose: lane[\transpose] ? 0
            );
        });
    };

    ~applyPerformanceState = { |self, lane, state|
        if(lane.notNil and: { state.notNil }) {
            lane[\level] = (state[\level] ? 1.0).asFloat.clip(0.0, 1.0);
            lane[\pan] = (state[\pan] ? 0.0).asFloat.clip(-1.0, 1.0);
            lane[\density] = (state[\density] ? 1.0).asFloat.clip(0.05, 1.0);
            lane[\timbreMotion] = (state[\timbreMotion] ? 0.0).asFloat.clip(0.0, 1.0);
            lane[\reverbSend] = (state[\reverbSend] ? 0.5).asFloat.clip(0.0, 1.0);
            lane[\transpose] = (state[\transpose] ? 0).asInteger.clip(-36, 36);
            self[\applyLaneOutput].value(self, lane);
        };
        lane;
    };

    ~generateSlot = { |self, slot, total = nil, modifier = nil|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var activeTotal;
        var oldLane = self[\slots][index - 1];
        var performanceState = self[\performanceStateForLane].value(oldLane);
        var adaptive;
        var action;
        var lane;
        if(modifier.isNil, {
            ("EAP slot " ++ index ++ " generation ignored: modifier required").postln;
            0;
        }, {
            if(self[\sourceEnginePreference].isNil, {
                ("EAP slot " ++ index ++ " generation ignored: source engine required").postln;
                0;
            }, {
            adaptive = self[\adaptiveContextForSlot].value(self, index, modifier);
            action = if(oldLane.notNil and: { oldLane[\state] != \blank }, { \regenerate }, { \generate });
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
            lane = self[\randomLane].value(self, index, activeTotal, modifier, adaptive);
            self[\applyPerformanceState].value(self, lane, performanceState);
            self[\slots][index - 1] = lane;
            self[\startLane].value(self, lane);
            self[\lanes].add(lane);
            self[\syncLoad].value(self);
            self[\recordAdaptiveScene].value(self, lane, action);
            ("EAP slot " ++ index ++ " generated materials=" ++ lane[\materials].asString ++
                " fx=" ++ lane[\fx] ++ " modifier=" ++ (lane[\soundModifier] ? \default)
                ++ " sourceEngine=" ++ (self[\sourceEnginePreference] ? \none)
                ++ " rhythm=" ++ (lane[\rhythmProfile] ? \unknown)
                ++ " adaptiveSiblings=" ++ ((lane[\adaptive] ? ())[\siblingCount] ? 0)
                ++ " adaptiveRegister=" ++ ((lane[\adaptive] ? ())[\registerBand] ? \mid)
                ++ " level=" ++ (lane[\level] ? 1.0).round(0.001)
                ++ " pan=" ++ (lane[\pan] ? 0.0).round(0.001)
                ++ " density=" ++ (lane[\density] ? 1.0).round(0.001)
                ++ " timbreMotion=" ++ (lane[\timbreMotion] ? 0.0).round(0.001)
                ++ " reverbSend=" ++ (lane[\reverbSend] ? 0.5).round(0.001)
                ++ " transpose=" ++ (lane[\transpose] ? 0)
                ++ " plaits=" ++ lane[\plaitsModels].asString
                ++ " fm7Alg=" ++ ((lane[\fm7] ? ())[\algorithm] ? \none)).postln;
                1;
            });
        });
    };

    ~toggleSlot = { |self, slot, modifier = nil|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        var result = if(lane.isNil or: { lane[\state] == \blank }, {
            ("EAP slot " ++ index ++ " toggle ignored: blank slot").postln;
            0;
        }, {
            if(lane[\state] == \active, {
                if(self[\muteMode] == \output, {
                    self[\outputMuteLane].value(self, lane);
                }, {
                    self[\stopLane].value(self, lane, \muted);
                });
                self[\syncLoad].value(self);
                ("EAP slot " ++ index ++ " muted mode=" ++ self[\muteMode]).postln;
                2;
            }, {
                if(lane[\mutedMode] == \output, {
                    self[\outputUnmuteLane].value(self, lane);
                }, {
                    self[\startLane].value(self, lane);
                });
                self[\syncLoad].value(self);
                ("EAP slot " ++ index ++ " active").postln;
                1;
            });
        });
        result;
    };

    ~seed = { |self, count = 1, modifier = nil|
        var n = count.asInteger.clip(1, self[\maxScenes]);
        if(self[\sourceEnginePreference].isNil, {
            "EAP random scene set ignored: source engine required".postln;
            0;
        }, {
            self[\clear].value(self);
            self[\cloudLaneIndex] = if(n >= 5, { [0, rrand(1, n)].choose }, { nil });
            n.do({ |index|
                var laneModifier = modifier ? self[\soundModifierSymbols].choose;
                var adaptive = self[\adaptiveContextForSlot].value(self, index + 1, laneModifier);
                var lane = self[\randomLane].value(self, index + 1, n, laneModifier, adaptive);
                self[\startLane].value(self, lane);
                self[\lanes].add(lane);
                self[\slots][index] = lane;
                self[\recordAdaptiveScene].value(self, lane, \seed);
                ("EAP random lane " ++ (index + 1) ++ "/" ++ n ++
                    " materials=" ++ lane[\materials].asString ++
                    " fx=" ++ lane[\fx] ++
                    " modifier=" ++ (lane[\soundModifier] ? \default)
                    ++ " sourceEngine=" ++ (self[\sourceEnginePreference] ? \none)
                    ++ " adaptiveSiblings=" ++ ((lane[\adaptive] ? ())[\siblingCount] ? 0)
                    ++ " plaits=" ++ lane[\plaitsModels].asString
                    ++ " fm7Alg=" ++ ((lane[\fm7] ? ())[\algorithm] ? \none)).postln;
            });
            ("EAP random scene set active: " ++ n ++ " independent lanes").postln;
            1;
        });
    };

    ~start = { |self|
        if(self[\group].notNil) { self[\stop].value(self); };
        self[\group] = Group.tail(s);
        self[\masterBus] = Bus.audio(s, 2);
        self[\gridFxBus] = Bus.audio(s, 2);
        self[\reverbBus] = Bus.audio(s, 2);
        self[\makeSynthDefs].value(self);
        s.sync;
        self[\reverbValues] = [0.24, 0.55, 0.45, 0.36, 0.25, 0.74, 0.24, 0.62];
        self[\masterValues] = [0.82, 0.0, 1.0, 0.12, 0.0];
        self[\masterGroup] = Group.after(self[\group]);
        self[\gridFxActive] = false;
        self[\gridFxScenes] = Array.fill(self[\maxScenes], { false });
        self[\gridFxQueue].clear;
        self[\gridFxProcessing] = false;
        self[\gridFxSendSynth] = Synth.head(self[\masterGroup], \eapGridFxSend, [\in, self[\gridFxBus].index, \out, 2, \amp, 0.0]);
        self[\externalInputSynth] = nil;
        self[\masterSynth] = Synth.tail(self[\masterGroup], \eapSceneMaster, [
            \in, self[\masterBus].index, \reverbIn, self[\reverbBus].index, \out, 0
        ]);
        // Clear any stale state from a prior session, then pre-warm the
        // airwindows host. The host stays alive in bypass mode until the user
        // engages a grid FX, so the first toggle hits the fast UDP path
        // instead of paying the ~3 s host-spawn + JACK-wire cost.
        { "/usr/local/bin/eap-airwindows-grid-fx --clear && /usr/local/bin/eap-airwindows-grid-fx --prewarm".unixCmd; }.defer(0.05);
        self[\applyReverb].value(self);
        self[\applyMaster].value(self);
        self[\slots] = Array.fill(self[\maxScenes], { nil });
        self[\lanes].clear;
        self[\adaptiveJournal].clear;
        self[\adaptiveSerial] = 0;
        "EAP RandomScenes: started with blank slots".postln;
    };

    ~stop = { |self|
        self[\clear].value(self);
        self[\gridFxQueue].clear;
        self[\gridFxProcessing] = false;
        { "/usr/local/bin/eap-airwindows-grid-fx --clear".unixCmd; }.defer(0.05);
        if(self[\externalInputSynth].notNil) { self[\externalInputSynth].free; self[\externalInputSynth] = nil; };
        if(self[\gridFxSendSynth].notNil) { self[\gridFxSendSynth].free; self[\gridFxSendSynth] = nil; };
        if(self[\masterSynth].notNil) { self[\masterSynth].free; self[\masterSynth] = nil; };
        if(self[\masterBus].notNil) { self[\masterBus].free; self[\masterBus] = nil; };
        if(self[\gridFxBus].notNil) { self[\gridFxBus].free; self[\gridFxBus] = nil; };
        if(self[\reverbBus].notNil) { self[\reverbBus].free; self[\reverbBus] = nil; };
        if(self[\masterGroup].notNil) { self[\masterGroup].free; self[\masterGroup] = nil; };
        if(self[\group].notNil) { self[\group].free; self[\group] = nil; };
    };
}).know_(true);
