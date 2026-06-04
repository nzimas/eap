// Electroacoustic Playground random independent scene lanes.
// A manual seed creates N autonomous lanes, each with its own source materials, parameters, buses, and FX.

~eap = ~eap ? IdentityDictionary.new;

~eapScenes = Environment.make({
    ~maxScenes = 8;
    ~maxSourcesPerScene = 2;
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
    ~reverbValues = nil;
    ~masterValues = nil;
    ~dexedMidi = nil;
    ~dexedAvailable = false;
    ~vitalMidi = nil;
    ~vitalAvailable = false;
    ~scaleIndex = 0;
    ~rootNote = 0;
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
    ~plaitsPercussiveModels = [11, 11, 12, 12, 3, 1];

    ~pedalCandidates = [
        \chorus, \phaser, \vibrato, \tremolo, \delay, \reverb,
        \lofi, \wavefolder, \bitcrusher, \ringmod, \autowah
    ];

    ~soundModifierSymbols = [\percussive, \drone, \harmonic, \chaos];
    ~sourceEngineSymbols = [nil, \plaits, \rings, \passersby, \molly, \fold, \dexed, \vital];

    ~modifierFromCode = { |self, code|
        var index = code.asInteger;
        if((index >= 1) and: { index <= 4 }, { self[\soundModifierSymbols][index - 1] }, { nil });
    };

    ~sourceEngineFromCode = { |self, code|
        var index = code.asInteger.clip(0, self[\sourceEngineSymbols].size - 1);
        self[\sourceEngineSymbols][index];
    };

    ~setSourceEnginePreference = { |self, code|
        var engine = self[\sourceEngineFromCode].value(self, code);
        self[\sourceEnginePreference] = engine;
        ("EAP future source engine=" ++ (engine ? \any)).postln;
        engine;
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

    ~scaleStepsForLane = { |self, lane|
        switch(lane[\soundModifier],
            \percussive, { [-2, -1, 0, 0, 0, 0, 1, 1, 2, 3] },
            \drone, { [0, 0, 0, 1, 1, 2, 2, 4, -1] },
            \harmonic, { [-2, -1, 0, 0, 0, 1, 1, 2, 3, 4] },
            \chaos, { [-4, -3, -2, -1, 0, 1, 2, 3, 4, 5] },
            { [-2, -1, 0, 0, 0, 1, 2, 3, 4] }
        );
    };

    ~euclideanHits = { |steps, hits|
        var pattern = Array.fill(steps, { 0 });
        var bucket = 0;
        hits = hits.asInteger.clip(1, steps - 1);
        steps.do({ |i|
            bucket = bucket + hits;
            if(bucket >= steps) {
                bucket = bucket - steps;
                pattern[i] = 1;
            };
        });
        pattern;
    };

    ~breakbeatSlices = { |self, pulse|
        var skeleton = [1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 2, 1, 1, 3, 1, 2, 1, 1, 2, 1];
        skeleton.scramble.collect({ |n| pulse * n * [0.42, 0.58, 0.72, 1.0, 1.2].choose });
    };

    ~rhythmProfilesFor = { |modifier|
        switch(modifier,
            \percussive, { [\grid16, \shuffle16, \euclid, \burst, \poly23, \breakbeat, \clave, \tresillo] },
            \drone, { [\pulse, \breath, \swell, \ritual] },
            \harmonic, { [\arp, \motif, \canon, \hymn, \pulseHarm] },
            \chaos, { [\stutter, \wander, \flare, \glitch] },
            { [\steady, \flow] }
        );
    };

    ~patternForLane = { |self, lane|
        var mod = lane[\soundModifier];
        var matN = lane[\materials].size.max(1);
        var profile = lane[\rhythmProfile] ? self[\rhythmProfilesFor].value(mod).choose;
        lane[\patternProfile] = profile;
        switch(mod,
            \percussive, {
                Pbind(
                    \delta, Pxrand([
                        Pseq([0.18, 0.09, 0.09, 0.18, 0.12, 0.06, 0.12, 0.18], 1),
                        Pseq([0.12, 0.12, 0.06, 0.18, 0.06, 0.12, 0.24], 1),
                        Pseq([0.09, 0.09, 0.18, 0.09, 0.27, 0.09], 1),
                        Pshuf([0.06, 0.09, 0.12, 0.12, 0.18, 0.24], 1)
                    ], inf),
                    \isRest, Pwrand([0, 0, 0, 1], [0.86, 0.08, 0.04, 0.02], inf),
                    \accent, Pseq([1.7, 0.9, 1.15, 0.82, 1.35, 0.95, 1.1, 0.78], inf),
                    \scaleStep, Pwrand([0, 0, 1, -1, 2, -2, 3], [0.38, 0.18, 0.14, 0.10, 0.08, 0.06, 0.06], inf),
                    \sourceCount, 1,
                    \panBias, Pwhite(-0.45, 0.45, inf),
                    \decayScale, Pwhite(0.28, 0.85, inf),
                    \hits, Pwrand([1, 1, 2], [0.72, 0.18, 0.10], inf)
                )
            },
            \drone, {
                Pbind(
                    \delta, Pxrand([
                        Pseq([1.6, 2.4, 1.2, 3.0], 1),
                        Pseq([2.2, 1.8, 2.8], 1),
                        Pwhite(1.1, 3.2, 4)
                    ], inf),
                    \isRest, Pwrand([0, 1], [0.82, 0.18], inf),
                    \accent, Pwhite(0.62, 1.05, inf),
                    \scaleStep, Pwrand([0, 0, 0, 1, 2, -1, 4], [0.42, 0.20, 0.12, 0.10, 0.07, 0.05, 0.04], inf),
                    \sourceCount, Pwrand([1, matN.min(2)], [0.55, 0.45], inf),
                    \panBias, Pwhite(-0.25, 0.25, inf),
                    \decayScale, Pwhite(1.45, 2.4, inf),
                    \hits, 1
                )
            },
            \harmonic, {
                Pbind(
                    \delta, Pxrand([
                        Pseq([0.46, 0.46, 0.92, 0.46, 0.69, 0.23], 1),
                        Pseq([0.34, 0.34, 0.68, 1.02], 1),
                        Pseq([0.58, 0.29, 0.29, 0.58, 1.16], 1),
                        Pshuf([0.38, 0.38, 0.76, 1.14], 1)
                    ], inf),
                    \isRest, Pwrand([0, 0, 1], [0.78, 0.16, 0.06], inf),
                    \accent, Pseq([1.22, 0.92, 1.05, 0.86, 1.12, 0.95], inf),
                    \scaleStep, Pseq([0, 2, 4, 2, 5, 4, 2, 1, 0, -1, 0, 2], inf),
                    \sourceCount, Pwrand([1, matN.min(2)], [0.62, 0.38], inf),
                    \panBias, Pwhite(-0.32, 0.32, inf),
                    \decayScale, Pwhite(0.85, 1.65, inf),
                    \hits, 1
                )
            },
            \chaos, {
                Pbind(
                    \delta, Pxrand([
                        Pseq([0.08, 0.16, 0.05, 0.24, 0.11, 0.31], 1),
                        Pshuf([0.07, 0.09, 0.13, 0.21, 0.34], 1),
                        Pwhite(0.06, 0.42, 6)
                    ], inf),
                    \isRest, Pwrand([0, 0, 0, 1], [0.72, 0.14, 0.08, 0.06], inf),
                    \accent, Pexprand(0.55, 2.05, inf),
                    \scaleStep, Pwrand([-7, -5, -3, -2, 0, 1, 4, 6], [0.10, 0.12, 0.14, 0.12, 0.18, 0.10, 0.12, 0.12], inf),
                    \sourceCount, Pwrand([1, matN.min(2)], [0.58, 0.42], inf),
                    \panBias, Pwhite(-0.65, 0.65, inf),
                    \decayScale, Pwhite(0.25, 1.45, inf),
                    \hits, Pwrand([1, 1, 2, 3], [0.62, 0.18, 0.14, 0.06], inf)
                )
            },
            {
                Pbind(
                    \delta, Pshuf([0.42, 0.58, 0.84, 1.1], inf),
                    \isRest, Pwrand([0, 1], [0.84, 0.16], inf),
                    \accent, Pwhite(0.75, 1.25, inf),
                    \scaleStep, Pseq([0, 1, 2, 0, -1, 0, 3], inf),
                    \sourceCount, 1,
                    \panBias, Pwhite(-0.35, 0.35, inf),
                    \decayScale, Pwhite(0.7, 1.5, inf),
                    \hits, 1
                )
            }
        );
    };

    ~nextPatternEvent = { |self, lane|
        var stream = lane[\eventStream];
        var event;
        if(stream.isNil, {
            stream = self[\patternForLane].value(self, lane).asStream;
            lane[\eventStream] = stream;
        });
        event = stream.next(Event.new);
        if(event.isNil, {
            stream = self[\patternForLane].value(self, lane).asStream;
            lane[\eventStream] = stream;
            event = stream.next(Event.new);
        });
        event;
    };

    ~initRhythmState = { |self, lane|
        var mod = lane[\soundModifier];
        var profiles = self[\rhythmProfilesFor].value(mod);
        var steps = switch(mod,
            \percussive, { [12, 16, 16, 24].choose },
            \chaos, { [11, 13, 16, 19].choose },
            \harmonic, { [8, 12, 16].choose },
            { [8, 12, 16].choose }
        );
        var hitLo = (steps * switch(mod, \percussive, { 0.5 }, \chaos, { 0.48 }, \harmonic, { 0.38 }, { 0.3 })).floor.asInteger;
        var hitHi = (steps * switch(mod, \percussive, { 0.94 }, \chaos, { 0.92 }, \harmonic, { 0.78 }, { 0.62 })).floor.asInteger;
        var hits = rrand(hitLo, hitHi).clip(2, steps - 1);
        var pulse = if(lane[\pulse].notNil, { lane[\pulse].asFloat }, { self[\rand].value(self, 0.06, 0.2) });
        var swing = if(lane[\swing].notNil, { lane[\swing].asFloat }, { 0.0 });
        (
            profile: lane[\rhythmProfile] ? profiles.choose,
            step: 0,
            steps: steps,
            pulse: pulse,
            swing: swing,
            density: (1.0 - (lane[\restProb] ? 0.2)).clip(0.35, 1.0),
            clusterLeft: 0,
            grid: self[\euclideanHits].value(steps, hits),
            accentMask: Array.fill(steps, { |i|
                var div = (steps / 4).max(1).asInteger;
                if(i % div == 0, { 2 }, { [0, 0, 1].choose });
            }),
            motif: Array.fill([5, 7, 8, 11].choose, { [-2, -1, 0, 0, 0, 1, 2, 3].choose }),
            motifPos: 0,
            phraseStep: 0,
            phraseLen: switch(mod, \percussive, { [16, 24, 32].choose }, { [12, 16, 24].choose }),
            breakSlices: self[\breakbeatSlices].value(self, pulse),
            breakPos: 0,
            restStreak: 0,
            swellPhase: 0,
            twinPulse: [3, 4, 5].choose,
            twinFlip: false,
            arpDir: [-1, 1].choose
        );
    };

    ~rhythmEventPerc = { |self, lane, st|
        var event = (
            delta: st[\pulse], isRest: 0, accent: 1.0, scaleStep: 0,
            sourceCount: 1, panBias: 0.0, decayScale: 1.0, hits: 1
        );
        var idx = st[\step] % st[\steps];
        var matN = lane[\materials].size.max(1);
        var pickStep = {
            st[\motif][st[\motifPos] % st[\motif].size];
        };
        switch(st[\profile],
            \grid16, {
                var hit = st[\grid][idx];
                event[\isRest] = if(hit == 1, { 0 }, { if(0.08.coin, { 0 }, { 1 }) });
                event[\accent] = if(st[\accentMask][idx] == 2, {
                    self[\exprand].value(self, 1.15, 1.85);
                }, {
                    if(hit == 1, { self[\rand].value(self, 0.72, 1.2) }, { 0.0 });
                });
                event[\delta] = st[\pulse] * [1, 1, 0.5, 1, 1, 0.5, 1, 1].wrapAt(idx);
                if(st[\swing] > 0.02, {
                    event[\delta] = event[\delta] * (if(idx % 2 == 1, { 1 + st[\swing] }, { 1 - (st[\swing] * 0.5) }));
                });
                event[\scaleStep] = if(event[\accent] > 1.05, { [-2, -1, 0, 1, 2, 3].choose }, { [0, 0, 0, 1].choose });
                event[\sourceCount] = if(event[\accent] > 1.02, { matN.min(2) }, { if(0.5.coin, { 2 }, { 1 }) });
                event[\decayScale] = self[\rand].value(self, 0.35, 0.88);
            },
            \shuffle16, {
                var longShort = idx % 2;
                event[\delta] = st[\pulse] * (if(longShort == 0, { 0.66 }, { 1.34 }) * (1 + (st[\swing] * 0.35)));
                event[\isRest] = if(st[\grid][idx] == 1, { 0 }, { if(0.15.coin, { 0 }, { 1 }) });
                event[\accent] = if(longShort == 0 and: { st[\grid][idx] == 1 }, {
                    self[\exprand].value(self, 1.0, 1.7);
                }, { self[\rand].value(self, 0.65, 1.1) });
                event[\scaleStep] = pickStep.value;
                st[\motifPos] = st[\motifPos] + 1;
                event[\sourceCount] = if(0.62.coin, { matN.min(2) }, { 1 });
            },
            \euclid, {
                event[\isRest] = if(st[\grid][idx] == 1, 0, 1);
                if(event[\isRest] == 0, {
                    event[\accent] = self[\exprand].value(self, 0.88, 1.65);
                    event[\scaleStep] = pickStep.value;
                    st[\motifPos] = st[\motifPos] + 1;
                    event[\sourceCount] = if(0.58.coin, { matN.min(2) }, { 1 });
                    event[\panBias] = self[\rand].value(self, -0.45, 0.45);
                });
                event[\delta] = st[\pulse] * (if(st[\steps] == 16, { 1.0 }, { 1.25 }));
            },
            \burst, {
                if(st[\clusterLeft] > 0, {
                    event[\delta] = st[\pulse] * self[\rand].value(self, 0.18, 0.52);
                    event[\accent] = self[\exprand].value(self, 0.92, 1.75);
                    event[\scaleStep] = [-2, -1, 0, 0, 1, 2].choose;
                    event[\sourceCount] = matN.min(2);
                    event[\decayScale] = self[\rand].value(self, 0.28, 0.72);
                    event[\hits] = if(0.22.coin, { 2 }, { 1 });
                    st[\clusterLeft] = st[\clusterLeft] - 1;
                }, {
                    event[\delta] = st[\pulse] * self[\rand].value(self, 2.2, 7.5);
                    event[\isRest] = if(0.18.coin, { 1 }, { 0 });
                    if(0.62.coin, { st[\clusterLeft] = rrand(4, 7); });
                });
            },
            \poly23, {
                var unit = st[\pulse] * if(st[\twinFlip], { 1.5 }, { 1.0 });
                st[\twinFlip] = if(st[\twinFlip], { false }, { true });
                event[\delta] = unit * [1, 1, 1.33, 0.75, 1, 1.5].wrapAt(idx);
                event[\isRest] = if(st[\grid][idx] == 1, { 0 }, { if(0.1.coin, { 0 }, { 1 }) });
                event[\accent] = self[\rand].value(self, 0.75, 1.45);
                event[\scaleStep] = pickStep.value;
                st[\motifPos] = st[\motifPos] + 1;
                event[\sourceCount] = if(idx % st[\twinPulse] == 0, { matN.min(2) }, { 1 });
            },
            \breakbeat, {
                event[\delta] = st[\breakSlices][st[\breakPos] % st[\breakSlices].size];
                st[\breakPos] = st[\breakPos] + 1;
                event[\isRest] = if(0.06.coin, { 1 }, { 0 });
                event[\accent] = self[\exprand].value(self, 0.82, 1.8);
                event[\scaleStep] = [-2, -1, 0, 0, 1, 2, 3].choose;
                event[\sourceCount] = if(0.7.coin, { matN.min(2) }, { 1 });
                event[\panBias] = self[\rand].value(self, -0.55, 0.55);
                event[\decayScale] = self[\rand].value(self, 0.3, 0.82);
            },
            \clave, {
                var pattern = [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 1];
                var hit = pattern.wrapAt(idx);
                event[\isRest] = if(hit == 1, 0, 1);
                event[\delta] = st[\pulse] * [1.5, 1, 1, 1.5, 1, 1, 1.5, 1].wrapAt(idx);
                if(hit == 1, {
                    event[\accent] = self[\exprand].value(self, 1.05, 1.75);
                    event[\scaleStep] = [0, 2, 4, 7].choose;
                    event[\sourceCount] = if(0.45.coin, { 2 }, { 1 });
                });
            },
            \tresillo, {
                var pattern = [1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1];
                var hit = pattern.wrapAt(idx);
                event[\isRest] = if(hit == 1, 0, 1);
                event[\delta] = st[\pulse] * 1.33;
                if(hit == 1, {
                    event[\accent] = self[\rand].value(self, 0.9, 1.55);
                    event[\scaleStep] = pickStep.value;
                    st[\motifPos] = st[\motifPos] + 1;
                });
            },
            {
                event[\delta] = st[\pulse] * self[\rand].value(self, 0.35, 1.2);
                event[\isRest] = if(0.12.coin, { 1 }, { 0 });
                event[\accent] = self[\rand].value(self, 0.8, 1.4);
            }
        );
        st[\step] = st[\step] + 1;
        event;
    };

    ~rhythmEventDrone = { |self, lane, st|
        var event = (
            delta: lane[\gap], isRest: 0, accent: 1.0, scaleStep: 0,
            sourceCount: 1, panBias: 0.0, decayScale: 1.2, hits: 1
        );
        var idx = st[\step] % st[\steps];
        var matN = lane[\materials].size.max(1);
        switch(st[\profile],
            \pulse, {
                var hit = st[\grid][idx];
                event[\isRest] = if(hit == 1, 0, 1);
                event[\delta] = st[\pulse] * [2, 2, 3, 2, 4, 2, 3, 2].wrapAt(idx);
                if(hit == 1, {
                    event[\accent] = self[\rand].value(self, 0.85, 1.35);
                    event[\scaleStep] = [0, 0, 1, 2].choose;
                    event[\sourceCount] = if(idx % 4 == 0, { matN.min(2) }, { 1 });
                });
            },
            \breath, {
                event[\delta] = st[\pulse] * self[\rand].value(self, 4.5, 14.0);
                event[\isRest] = if(0.35.coin, { 1 }, { 0 });
                event[\accent] = self[\rand].value(self, 0.7, 1.2);
                event[\scaleStep] = [0, 1, 2, 4].choose;
                event[\decayScale] = self[\exprand].value(self, 1.0, 2.2);
            },
            \swell, {
                var wave = (sin(st[\swellPhase] / st[\steps] * 2pi) + 1) * 0.5;
                event[\delta] = st[\pulse] * (1.5 + (wave * 6));
                event[\isRest] = if(wave < 0.25, { if(0.55.coin, { 1 }, { 0 }) }, { 0 });
                event[\accent] = 0.75 + (wave * 0.55);
                event[\scaleStep] = if(wave > 0.7, { [1, 2, 3].choose }, { 0 });
                st[\swellPhase] = st[\swellPhase] + 1;
            },
            \ritual, {
                event[\delta] = st[\pulse] * [3, 3, 5, 2, 7, 2, 4].wrapAt(idx);
                event[\isRest] = if(st[\grid][idx] == 1, { 0 }, { if(0.25.coin, { 0 }, { 1 }) });
                event[\accent] = if(idx % 5 == 0, { 1.35 }, { 0.88 });
                event[\scaleStep] = st[\motif][st[\motifPos] % st[\motif].size];
                st[\motifPos] = st[\motifPos] + 1;
                event[\sourceCount] = if(idx % 7 == 0, { matN.min(2) }, { 1 });
            },
            {
                event[\delta] = st[\pulse] * 3.5;
                event[\isRest] = if(0.2.coin, { 1 }, { 0 });
            }
        );
        st[\step] = st[\step] + 1;
        event;
    };

    ~rhythmEventHarmonic = { |self, lane, st|
        var event = (
            delta: st[\pulse], isRest: 0, accent: 1.0, scaleStep: 0,
            sourceCount: 1, panBias: 0.0, decayScale: 1.0, hits: 1
        );
        var idx = st[\step] % st[\steps];
        var matN = lane[\materials].size.max(1);
        var pickStep = {
            st[\motif][st[\motifPos] % st[\motif].size];
        };
        switch(st[\profile],
            \arp, {
                event[\isRest] = 0;
                event[\delta] = st[\pulse] * [0.5, 0.5, 0.75, 0.5, 1, 0.5, 0.5, 0.75].wrapAt(idx);
                event[\scaleStep] = st[\arpDir];
                st[\arpDir] = st[\arpDir] * -1;
                event[\accent] = if(idx % 4 == 0, { 1.25 }, { self[\rand].value(self, 0.78, 1.1) });
                event[\sourceCount] = if(idx % 3 == 0, { matN.min(2) }, { 1 });
                event[\decayScale] = self[\rand].value(self, 0.55, 1.1);
            },
            \motif, {
                event[\isRest] = if(st[\grid][idx] == 1, { 0 }, { if(0.12.coin, { 0 }, { 1 }) });
                event[\delta] = st[\pulse] * [1, 1, 1.5, 1, 2, 1, 1, 1.5].wrapAt(idx);
                if(event[\isRest] == 0, {
                    event[\scaleStep] = pickStep.value;
                    st[\motifPos] = st[\motifPos] + 1;
                    event[\accent] = self[\rand].value(self, 0.82, 1.45);
                });
            },
            \canon, {
                event[\delta] = st[\pulse] * (1 + (idx % 3));
                event[\isRest] = if((idx % 5) == 4, { if(0.35.coin, { 1 }, { 0 }) }, { if(st[\grid][idx] == 1, 0, 1) });
                event[\scaleStep] = pickStep.value;
                st[\motifPos] = st[\motifPos] + 1;
                event[\accent] = if((idx % st[\steps]) < (st[\steps] / 2), { 0.9 }, { 1.2 });
                event[\panBias] = self[\rand].value(self, -0.3, 0.3);
            },
            \hymn, {
                event[\delta] = st[\pulse] * [2, 2, 2, 3, 2, 2, 4].wrapAt(idx);
                event[\isRest] = if(idx % 7 == 6, { if(0.4.coin, { 1 }, { 0 }) }, { 0 });
                event[\scaleStep] = [0, 0, 2, 4, 2, 0].wrapAt(st[\phraseStep]);
                st[\phraseStep] = st[\phraseStep] + 1;
                event[\accent] = if(idx % 4 == 0, { 1.3 }, { 0.95 });
                event[\decayScale] = self[\exprand].value(self, 0.7, 1.6);
            },
            \pulseHarm, {
                event[\delta] = st[\pulse] * [1, 0.5, 1, 0.5, 1.5, 1, 0.5, 1].wrapAt(idx);
                event[\isRest] = if(st[\grid][idx] == 1, 0, 1);
                event[\scaleStep] = pickStep.value;
                st[\motifPos] = st[\motifPos] + 1;
                event[\accent] = self[\rand].value(self, 0.85, 1.35);
            },
            {
                event[\delta] = st[\pulse] * 1.5;
                event[\scaleStep] = pickStep.value;
                st[\motifPos] = st[\motifPos] + 1;
            }
        );
        st[\step] = st[\step] + 1;
        event;
    };

    ~rhythmEventChaos = { |self, lane, st|
        var event = (
            delta: st[\pulse], isRest: 0, accent: 1.0, scaleStep: 0,
            sourceCount: 1, panBias: 0.0, decayScale: 1.0, hits: 1
        );
        var idx = st[\step] % st[\steps];
        var matN = lane[\materials].size.max(1);
        switch(st[\profile],
            \stutter, {
                if(st[\clusterLeft] > 0, {
                    event[\delta] = st[\pulse] * self[\rand].value(self, 0.12, 0.38);
                    event[\accent] = self[\exprand].value(self, 1.0, 1.9);
                    event[\scaleStep] = [-3, -2, -1, 0, 1, 2, 3, 4].choose;
                    event[\sourceCount] = matN.min(2);
                    event[\hits] = rrand(1, 3);
                    st[\clusterLeft] = st[\clusterLeft] - 1;
                }, {
                    event[\delta] = st[\pulse] * self[\rand].value(self, 0.5, 3.5);
                    event[\isRest] = if(0.2.coin, { 1 }, { 0 });
                    if(0.7.coin, { st[\clusterLeft] = rrand(3, 8); });
                });
            },
            \wander, {
                event[\delta] = st[\pulse] * self[\rand].value(self, 0.25, 4.5);
                event[\isRest] = if(0.18.coin, { 1 }, { 0 });
                event[\accent] = self[\exprand].value(self, 0.65, 1.85);
                event[\scaleStep] = [-4, -2, -1, 0, 1, 2, 4, 5].choose;
                event[\panBias] = self[\rand].value(self, -0.55, 0.55);
                event[\sourceCount] = [1, 1, matN.min(2)].choose;
            },
            \flare, {
                var hot = (idx % 6) < 4;
                event[\delta] = st[\pulse] * (if(hot, { self[\rand].value(self, 0.2, 0.65) }, { self[\rand].value(self, 1.2, 4.0) }));
                event[\isRest] = if(hot, { 0 }, { if(0.35.coin, { 1 }, { 0 }) });
                event[\accent] = if(hot, { self[\exprand].value(self, 1.1, 1.95) }, { 0.75 });
                event[\scaleStep] = if(hot, { [-2, -1, 0, 1, 2, 3].choose }, { 0 });
                event[\decayScale] = if(hot, { self[\rand].value(self, 0.25, 0.75) }, { 1.2 });
            },
            \glitch, {
                event[\delta] = st[\breakSlices][st[\breakPos] % st[\breakSlices].size] * [0.5, 1, 1.5, 2].choose;
                st[\breakPos] = st[\breakPos] + 1;
                event[\isRest] = if(0.1.coin, { 1 }, { 0 });
                event[\accent] = self[\exprand].value(self, 0.9, 2.0);
                event[\scaleStep] = [-5, -3, -1, 0, 2, 4, 5].choose;
                event[\sourceCount] = matN.min(2);
                event[\panBias] = self[\rand].value(self, -0.65, 0.65);
            },
            {
                event[\delta] = st[\pulse] * self[\rand].value(self, 0.3, 2.0);
                event[\scaleStep] = [-2, 0, 1, 3].choose;
            }
        );
        st[\step] = st[\step] + 1;
        event;
    };

    ~rhythmEventDefault = { |self, lane, st|
        var idx = st[\step] % st[\steps];
        var event = (
            delta: st[\pulse] * [1, 1, 1.5, 2].wrapAt(idx),
            isRest: if(st[\grid][idx] == 1, 0, 1),
            accent: self[\rand].value(self, 0.75, 1.3),
            scaleStep: st[\motif][st[\motifPos] % st[\motif].size],
            sourceCount: 1, panBias: 0.0, decayScale: 1.0, hits: 1
        );
        st[\motifPos] = st[\motifPos] + 1;
        st[\step] = st[\step] + 1;
        event;
    };

    ~nextLaneEvent = { |self, lane|
        var mod = lane[\soundModifier];
        var event = self[\nextPatternEvent].value(self, lane);
        var result;
        result = if(event.isNil, {
            (
                delta: (lane[\gap] ? 0.12).asFloat,
                isRest: 0,
                accent: 1.0,
                scaleStep: 0,
                sourceCount: 1,
                panBias: 0.0,
                decayScale: 1.0,
                hits: 1
            );
        }, {
            var voices = (event[\sourceCount] ? 1).asInteger;
            var minDelta = self[\minDeltaForLane].value(self, lane);
            var maxDelta = self[\maxDeltaForLane].value(self, lane);
            var loadN = self[\activeCount].value(self);
            var isRest = (event[\isRest] ? 0).asInteger;
            var density = (lane[\density] ? 1.0).asFloat.clip(0.05, 1.0);
            if(isRest == 0 and: { density.coin.not }) {
                isRest = 1;
            };
            (
                delta: (event[\delta] ? lane[\gap] ? 0.12).asFloat.clip(minDelta, maxDelta),
                isRest: isRest,
                accent: (event[\accent] ? 1.0).asFloat.clip(0.0, 2.2),
                scaleStep: (event[\scaleStep] ? 0).asInteger,
                sourceCount: if(mod == \percussive, { 1 }, {
                    if(loadN >= 2, { 1 }, { voices.clip(1, lane[\materials].size.max(1)) });
                }),
                panBias: (event[\panBias] ? 0.0).asFloat.clip(-0.55, 0.55),
                decayScale: if(mod == \percussive, {
                    (event[\decayScale] ? 0.5).asFloat.clip(0.18, 0.58);
                }, {
                    (event[\decayScale] ? 1.0).asFloat.clip(0.25, if(loadN >= 3, { 1.15 }, { 1.8 }));
                }),
                hits: if(loadN >= 3, { 1 }, { (event[\hits] ? 1).asInteger.clip(1, 4) })
            );
        });
        result;
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

    ~activeCount = { |self|
        self[\slots].count({ |lane| lane.notNil and: { lane[\state] == \active } });
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
            \chaos, { [6, 4, 3, 2, 1, 1][idx] },
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
            var profile, threshold, slopeAbove, clampTime, relaxTime, makeup;
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

        SynthDef(\eapGridFxSend, { |in = 0, out = 2, amp = 0, fadeTime = 0.08|
            var sig = LeakDC.ar(In.ar(in, 2));
            Out.ar(out, Limiter.ar(sig * Lag.kr(amp, fadeTime).clip(0, 1), 0.95, 0.01));
        }).add;

        SynthDef(\eapExternalInput, { |out = 0, amp = 0.0, fadeTime = 0.08|
            var sig = SoundIn.ar([2, 3]);
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
            env = EnvGen.kr(Env.linen(0.002, decay.max(0.015), envTail.clip(0.01, 0.3)), doneAction: 2);
            sig = Balance2.ar(sig[0], sig[1], pan, amp) * env;
            Out.ar(out, LeakDC.ar(sig));
        }).add;

        SynthDef(\eapLaneRingsNote, { |out = 0, pitch = 60, struct = 0.4,
            bright = 0.5, damp = 0.7, pos = 0.4, model = 0, poly = 2,
            envDecay = 8.0, envRelease = 1.2, amp = 0.12, pan = 0,
            modDepth = 0, modRate = 0.2, modShape = 0, modRand = 0|
            var trig, exciter, sig, env, lfo, drift, st, br, da, po;
            trig = Trig1.kr(1, 0.01);
            lfo = Select.kr(modShape.clip(0, 3), [
                SinOsc.kr(modRate), LFTri.kr(modRate), LFSaw.kr(modRate), LFNoise2.kr(modRate)
            ]);
            drift = LFNoise1.kr((modRate * 0.4).max(0.04));
            st = (struct + (lfo * modDepth * 0.24) + (drift * modRand * 0.18)).clip(0, 1);
            br = (bright + (lfo * modDepth * 0.28) + (drift * modRand * 0.22)).clip(0, 1);
            da = (damp + (lfo * modDepth * 0.20) + (drift * modRand * 0.18)).clip(0, 1);
            po = (pos + (lfo * modDepth * 0.30) + (drift * modRand * 0.22)).clip(0, 1);
            exciter = PinkNoise.ar(0.03) * Decay2.kr(trig, 0.004, 0.09);
            sig = MiRings.ar(exciter, trig, pitch, st, br, da, po, model, poly, 1, 0);
            env = EnvGen.kr(Env.linen(0.002, envDecay.max(0.04), envRelease.max(0.02)), doneAction: 2);
            sig = Balance2.ar(sig[0], sig[1], pan, amp) * env;
            Out.ar(out, LeakDC.ar(sig));
        }).add;

        SynthDef(\eapLaneFoldNote, { |out = 0, freq = 220, fold = 1.0, fm = 0.1,
            cutoff = 2200, decay = 1.0, amp = 0.1, pan = 0,
            modDepth = 0, modRate = 0.2, modShape = 0, modRand = 0|
            var env, mod, sig, lfo, drift, f, fmAmt, cut;
            env = EnvGen.kr(Env.perc(0.004, decay, curve: -4), doneAction: 2);
            lfo = Select.kr(modShape.clip(0, 3), [
                SinOsc.kr(modRate), LFTri.kr(modRate), LFSaw.kr(modRate), LFNoise2.kr(modRate)
            ]);
            drift = LFNoise1.kr((modRate * 0.7).max(0.06));
            f = (fold + (lfo * modDepth * 1.6) + (drift * modRand * 1.2)).clip(0.05, 4.0);
            fmAmt = (fm + (lfo * modDepth * 0.22) + (drift * modRand * 0.18)).clip(0, 1.2);
            cut = (cutoff * (1 + (lfo * modDepth * 1.2) + (drift * modRand * 0.8))).clip(120, 12000);
            mod = SinOsc.ar(freq * [1.5, 2, 3].choose, 0, freq * fmAmt);
            sig = VarSaw.ar(freq + mod, 0, 0.45) + SinOsc.ar(freq * 0.5, 0, 0.25);
            sig = Fold.ar(sig * (1 + (f * 3)), -0.7, 0.7);
            sig = RLPF.ar(sig, cut, 0.72);
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
                    ++ " routine=" ++ (lane[\state] == \active and: { lane[\routine].notNil })
                    ++ " ticks=" ++ (lane[\tickCount] ? 0)
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

    ~sendDexedNote = { |self, channel = 0, note = 60, velocity = 80, duration = 0.6|
        var midi = self[\dexedMidi];
        if(midi.isNil, { self[\refreshDexed].value(self); midi = self[\dexedMidi]; });
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
        var cmd = "/usr/local/bin/eap-dexed-patch --seed " ++ seed.asInteger.asString
            ++ " --channel " ++ channel.asInteger.clip(0, 15).asString
            ++ if(profile.notNil, { " --profile " ++ profile.asSymbol.asString }, { "" });
        var result = cmd.unixCmdGetStdOut.stripWhiteSpace;
        if(result.notEmpty, { ("EAP " ++ result).postln; });
        result;
    };

    ~vitalRuntimeAvailable = { |self|
        "sh -lc '[ \"${EAP_ENABLE_VITAL:-0}\" = \"1\" ] && command -v jalv >/dev/null 2>&1 && lv2ls 2>/dev/null | grep -qx \"urn:distrho:vitalium\" && echo yes'".unixCmdGetStdOut.contains("yes");
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
        var cmd = "/usr/local/bin/eap-vital-preset --seed " ++ seed.asInteger.asString
            ++ " --slot " ++ slot.asInteger.clip(1, self[\maxScenes]).asString
            ++ " --profile " ++ (profile ? \default).asSymbol.asString;
        var result = cmd.unixCmdGetStdOut.stripWhiteSpace;
        if(result.notEmpty, { ("EAP " ++ result).postln; });
        "/usr/local/bin/eap-connect-vital-jack 30 0.25".unixCmdGetStdOut;
        self[\refreshVital].value(self);
        result;
    };

    ~sendVitalNote = { |self, note = 60, velocity = 80, duration = 0.6|
        var midi = self[\vitalMidi];
        if(midi.isNil, { self[\refreshVital].value(self); midi = self[\vitalMidi]; });
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
        var pedalCount = if(lane[\total] >= 5, { 1 }, {
            if(lane[\total] >= 3, { 1 }, { rrand(1, self[\maxFxPerScene]) });
        });
        var pool;
        var chain;
        pool = switch(modifier,
            \percussive, { [\bitcrusher, \tremolo, \autowah, \ringmod, \wavefolder] },
            \drone, { [\reverb, \lofi, \chorus, \delay, \vibrato, \phaser] },
            \harmonic, { [\chorus, \vibrato, \reverb, \phaser, \delay, \tremolo] },
            \chaos, { [\ringmod, \wavefolder, \bitcrusher, \lofi, \autowah, \delay, \reverb] },
            { self[\pedalCandidates] }
        );
        chain = Array.fill(pedalCount, { pool.choose });
        if(modifier == \chaos and: { chain.size < self[\maxFxPerScene] and: { 0.45.coin } }, {
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
            sourceEngine: lane[\sourceEngine] ? (self[\sourceEnginePreference] ? \any),
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
        var materialPool = [\plaits, \plaits, \rings, \rings, \fold, \passersby, \passersby];
        var maxMaterials = self[\maxSourcesPerScene];
        var materialCount = if(total >= 7, { 1 }, { rrand(1, maxMaterials) });
        var materials;
        var fx = self[\chooseFxBackend].value(self, index, total, modifier);
        var register = [[31, 52], [36, 62], [45, 72], [52, 84]].choose;
        var minGap = if(total >= 7, { 1.15 }, { if(total >= 5, { 0.65 }, { 0.18 }) });
        var maxDensity = if(total >= 7, { 1.0 }, { if(total >= 5, { 1.15 }, { 1.45 }) });
        var phase = if(total >= 5, { self[\rand].value(self, 0.0, total * 0.35) }, { self[\rand].value(self, 0.0, 0.25) });
        var restProb = self[\rand].value(self, 0.04, 0.38);
        var volatility = self[\rand].value(self, 0.65, 1.6);
        var densitySkew = self[\rand].value(self, 0.72, maxDensity);
        var gap = self[\rand].value(self, minGap, 7.0);
        var rhythmProfile;
        var pulse = self[\rand].value(self, 0.1, 0.35);
        var swing = self[\rand].value(self, 0.0, 0.15);
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
        var plaitsModels = Array.fill(rrand(1, 3), { self[\plaitsModelPool].choose });
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
        var dexedAvailable = if(enginePreference == \dexed, { self[\refreshDexed].value(self) }, { false });
        var sourceEngine = \any;
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
        var vitalAvailable = if(enginePreference == \vital, { self[\vitalRuntimeAvailable].value(self) }, { self[\refreshVital].value(self) });
        var cpuClass = \normal;
        if(dexedAvailable, {
            materialPool = materialPool ++ [\dexed, \dexed];
        });
        if(vitalAvailable, {
            materialPool = materialPool ++ [\vital, \vital];
        });
        switch(modifier,
            \percussive, {
                materialPool = [\fold, \fold, \fold, \plaits, \plaits, \plaits, \plaits, \passersby];
                register = [[36, 72], [40, 76], [45, 84], [48, 88]].choose;
                minGap = minGap * 0.35;
                gap = self[\rand].value(self, 0.06, 0.32);
                restProb = self[\rand].value(self, 0.0, 0.04);
                volatility = self[\rand].value(self, 1.35, 2.35);
                densitySkew = self[\rand].value(self, 1.35, maxDensity.max(1.85));
                rhythmProfile = [\grid16, \shuffle16, \euclid, \breakbeat, \clave].choose;
                pulse = self[\rand].value(self, 0.055, 0.12);
                swing = self[\rand].value(self, 0.08, 0.48);
                materialCount = 1;
                plaitsModels = Array.fill(1, { self[\plaitsPercussiveModels].choose });
                molly[\oscWaveShape] = [0, 0, 1, 1, 2].choose;
                molly[\envAttack] = self[\exprand].value(self, 0.001, 0.02);
                molly[\envDecay] = self[\exprand].value(self, 0.05, 0.55);
                molly[\envSustain] = self[\rand].value(self, 0.0, 0.12);
                molly[\envRelease] = self[\exprand].value(self, 0.04, 0.45);
                molly[\noiseLevel] = self[\exprand].value(self, 0.01, 0.22);
                molly[\lpFilterModEnv] = self[\rand].value(self, 0.12, 0.42);
                molly[\subOscLevel] = self[\rand].value(self, 0.0, 0.35);
                passersby[\attack] = self[\exprand].value(self, 0.001, 0.025);
                passersby[\decay] = self[\exprand].value(self, 0.035, 0.26);
                passersby[\peak] = self[\exprand].value(self, 700, 7200);
                passersby[\reverbMix] = self[\rand].value(self, 0.0, 0.04);
                passersby[\body] = self[\rand].value(self, 0.0, 0.16);
                passersby[\foldMix] = self[\rand].value(self, 0.18, 0.72);
                passersby[\air] = self[\exprand].value(self, 0.004, 0.035);
                rings = (
                    model: [0, 1, 0, 1].choose,
                    poly: 1,
                    struct: self[\rand].value(self, 0.58, 0.98),
                    bright: self[\rand].value(self, 0.35, 0.92),
                    damp: self[\rand].value(self, 0.58, 0.98),
                    pos: self[\rand].value(self, 0.12, 0.78),
                    envDecay: self[\exprand].value(self, 0.035, 0.22),
                    envRelease: self[\exprand].value(self, 0.02, 0.12)
                );
                dexed[\velocity] = self[\rand].value(self, 72, 118).round(1);
                dexed[\durScale] = self[\exprand].value(self, 0.06, 0.42);
                dexed[\octaveBias] = [-12, 0, 0, 12].choose;
                dexed[\patchProfile] = \percussive;
                vital[\velocity] = self[\rand].value(self, 68, 118).round(1);
                vital[\durScale] = self[\exprand].value(self, 0.06, 0.38);
                vital[\octaveBias] = [-12, 0, 0, 12].choose;
                vital[\patchProfile] = \percussive;
                if(fx == \clouds, {
                    clouds[\dens] = self[\rand].value(self, 0.45, 0.95);
                    clouds[\size] = self[\rand].value(self, 0.08, 0.35);
                    clouds[\mode] = [0, 1].choose;
                });
            },
            \drone, {
                materialPool = [\rings, \rings, \rings, \passersby, \passersby, \plaits, \molly, \molly];
                register = [[24, 48], [28, 55], [31, 58]].choose;
                minGap = minGap * 1.1;
                gap = self[\rand].value(self, 0.8, 2.6);
                restProb = self[\rand].value(self, 0.04, 0.14);
                volatility = self[\rand].value(self, 0.55, 1.05);
                densitySkew = self[\rand].value(self, 0.65, 1.05);
                rhythmProfile = [\pulse, \swell, \ritual].choose;
                pulse = self[\rand].value(self, 0.22, 0.58);
                swing = self[\rand].value(self, 0.0, 0.12);
                materialCount = 2;
                plaitsModels = Array.fill(rrand(1, 2), { [5, 6, 12, 4].choose });
                passersby[\attack] = self[\exprand].value(self, 0.08, 4.5);
                passersby[\decay] = self[\exprand].value(self, 1.5, 10.0);
                passersby[\reverbMix] = self[\rand].value(self, 0.35, 0.92);
                passersby[\body] = self[\rand].value(self, 0.35, 0.95);
                molly[\envAttack] = self[\exprand].value(self, 0.12, 1.8);
                molly[\envSustain] = self[\rand].value(self, 0.55, 0.95);
                molly[\envRelease] = self[\exprand].value(self, 1.2, 8.0);
                vital[\durScale] = self[\exprand].value(self, 2.0, 7.0);
                vital[\octaveBias] = [-24, -12, -12, 0].choose;
                vital[\patchProfile] = \drone;
                if(fx == \clouds, {
                    clouds[\size] = self[\rand].value(self, 0.55, 0.98);
                    clouds[\dens] = self[\rand].value(self, 0.08, 0.38);
                    clouds[\drywet] = self[\rand].value(self, 0.55, 0.88);
                    clouds[\tex] = self[\rand].value(self, 0.35, 0.92);
                    clouds[\mode] = [1, 2, 2].choose;
                });
            },
            \harmonic, {
                materialPool = [\rings, \rings, \plaits, \plaits, \molly, \molly, \passersby];
                register = [[36, 62], [40, 67], [45, 72]].choose;
                gap = self[\rand].value(self, 0.18, 1.15);
                restProb = self[\rand].value(self, 0.0, 0.06);
                volatility = self[\rand].value(self, 0.95, 1.55);
                densitySkew = self[\rand].value(self, 1.0, maxDensity.max(1.35));
                rhythmProfile = [\arp, \motif, \pulseHarm, \hymn].choose;
                pulse = self[\rand].value(self, 0.09, 0.24);
                swing = self[\rand].value(self, 0.02, 0.22);
                materialCount = 2;
                plaitsModels = Array.fill(rrand(1, 3), { [4, 5, 6, 12].choose });
                molly[\envSustain] = self[\rand].value(self, 0.45, 0.92);
                molly[\envRelease] = self[\exprand].value(self, 0.6, 6.0);
                molly[\subOscLevel] = self[\rand].value(self, 0.15, 0.65);
                passersby[\decay] = self[\exprand].value(self, 0.5, 4.5);
                passersby[\reverbMix] = self[\rand].value(self, 0.18, 0.55);
                vital[\durScale] = self[\exprand].value(self, 0.8, 3.6);
                vital[\octaveBias] = [-12, 0, 0, 12].choose;
                vital[\patchProfile] = \harmonic;
                if(fx == \clouds, {
                    clouds[\spread] = self[\rand].value(self, 0.55, 0.98);
                    clouds[\rvb] = self[\rand].value(self, 0.22, 0.62);
                    clouds[\drywet] = self[\rand].value(self, 0.48, 0.82);
                });
            },
            \chaos, {
                materialPool = [\fold, \fold, \passersby, \plaits, \rings, \passersby, \plaits];
                register = [[31, 76], [36, 84], [40, 79]].choose;
                gap = self[\rand].value(self, 0.08, 0.62);
                restProb = self[\rand].value(self, 0.0, 0.10);
                volatility = self[\rand].value(self, 1.55, 2.5);
                densitySkew = self[\rand].value(self, 1.1, maxDensity.max(1.65));
                rhythmProfile = [\stutter, \wander, \flare, \glitch].choose;
                pulse = self[\rand].value(self, 0.06, 0.16);
                swing = self[\rand].value(self, 0.0, 0.28);
                materialCount = 2;
                passersby[\fm1Amount] = self[\rand].value(self, 0.12, 0.42);
                passersby[\fm2Amount] = self[\rand].value(self, 0.10, 0.38);
                passersby[\waveFolds] = self[\rand].value(self, 0.8, 3.2);
                passersby[\foldMix] = self[\rand].value(self, 0.45, 1.0);
                passersby[\air] = self[\exprand].value(self, 0.02, 0.12);
                molly[\noiseLevel] = self[\exprand].value(self, 0.04, 0.28);
                molly[\freqModLfo] = self[\exprand].value(self, 0.01, 0.12);
                molly[\ampMod] = self[\rand].value(self, 0.08, 0.42);
                vital[\velocity] = self[\rand].value(self, 45, 120).round(1);
                vital[\durScale] = self[\exprand].value(self, 0.08, 1.6);
                vital[\octaveBias] = [-24, -12, 0, 12, 24].choose;
                vital[\patchProfile] = \chaos;
                if(fx == \clouds, {
                    clouds[\dens] = self[\rand].value(self, 0.35, 0.92);
                    clouds[\fb] = self[\rand].value(self, 0.12, 0.55);
                    clouds[\mode] = [0, 1, 2].choose;
                    clouds[\lofi] = [1, 1, 0].choose;
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
            if(enginePreference == \dexed and: { dexedAvailable.not }, {
                "EAP future source engine dexed unavailable; using modifier material pool".postln;
            }, {
                if(enginePreference == \vital and: { vitalAvailable.not }, {
                    "EAP future source engine vital unavailable; using modifier material pool".postln;
                }, {
                    materialPool = [enginePreference];
                });
            });
        });
        materials = Array.fill(materialCount, { materialPool.choose });
        if(enginePreference.isNil and: { (modifier != \drone) and: { modifier != \harmonic } }, {
            materials = materials.reject({ |source| source == \molly });
            while({ materials.isEmpty and: { materialPool.notEmpty } }, {
                materials = materials.add(materialPool.choose);
                materials = materials.reject({ |source| source == \molly });
            });
        });
        if(enginePreference != \dexed and: { materials.select({ |source| source != \dexed }).isEmpty }, {
            materials[0] = switch(modifier,
                \percussive, { [\fold, \plaits, \passersby].choose },
                \chaos, { [\fold, \passersby, \plaits].choose },
                \drone, { [\rings, \passersby, \molly].choose },
                \harmonic, { [\rings, \plaits, \molly].choose },
                { [\plaits, \rings, \fold, \passersby].choose }
            );
        });
        if(enginePreference != \vital and: { materials.select({ |source| source != \vital }).isEmpty }, {
            materials[0] = switch(modifier,
                \percussive, { [\fold, \plaits, \passersby].choose },
                \chaos, { [\fold, \passersby, \plaits].choose },
                \drone, { [\rings, \passersby, \molly].choose },
                \harmonic, { [\rings, \plaits, \molly].choose },
                { [\plaits, \rings, \fold, \passersby].choose }
            );
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
        if(materials.includes(\dexed), {
            dexedPatchInfo = self[\loadDexedPatch].value(self, dexedPatchSeed, index - 1, dexed[\patchProfile]);
            dexed[\patchInfo] = dexedPatchInfo;
        });
        if(materials.includes(\vital), {
            vitalPatchInfo = self[\loadVitalPatch].value(self, vitalPatchSeed, index, vital[\patchProfile]);
            vital[\patchInfo] = vitalPatchInfo;
        });
        if(materials.includes(\vital) and: { fx == \clouds }, {
            "EAP Vital scene using pedalboard instead of Clouds for Pi CPU headroom".postln;
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
        sourceEngine = if(enginePreference.notNil and: { materials.includes(enginePreference) }, { enginePreference }, { \any });
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
            density: 1.0,
            timbreMotion: 0.0,
            reverbSend: 0.5,
            transpose: 0,
            amp: (0.28 / total.sqrt).clip(0.10, 0.26),
            plaitsModels: plaitsModels,
            ringsModel: rings[\model],
            rings: rings,
            molly: molly,
            passersby: passersby,
            dexed: dexed,
            vital: vital,
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
                \amp, lane[\amp] * (lane[\level] ? 1.0), \pan, lane[\pan] ? 0.0,
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
                \amp, lane[\amp] * (lane[\level] ? 1.0), \pan, lane[\pan] ? 0.0,
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
            lane[\outSynth].set(
                \amp, (lane[\amp] ? 0.18) * (lane[\level] ? 1.0),
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

    ~lanePattern = { |self, lane|
        Pfunc({ self[\nextLaneEvent].value(self, lane) });
    };

    ~stopLaneRoutine = { |lane|
        var token = lane[\routine];
        lane[\routine] = nil;
        lane[\routineToken] = (lane[\routineToken] ? 0) + 1;
        token;
    };

    ~restartLaneRoutine = { |self, lane, waitPhase = false|
        var token, tick, initialDelay;
        ~stopLaneRoutine.value(lane);
        if(lane[\group].notNil) {
            if(waitPhase) { lane[\rhythmState] = nil; };
            token = (lane[\routineToken] ? 0) + 1;
            lane[\routineToken] = token;
            lane[\routine] = token;
            tick = {
                var event, delta, voices;
                if(lane[\routine] != token or: { lane[\state] != \active or: { lane[\group].isNil } }, {
                    nil
                }, {
                    lane[\tickCount] = (lane[\tickCount] ? 0) + 1;
                    event = self[\nextLaneEvent].value(self, lane);
                    if(event.isNil, {
                        event = (
                            delta: self[\tickIntervalForLane].value(self, lane),
                            isRest: 0,
                            accent: switch(lane[\soundModifier],
                                \percussive, { self[\rand].value(self, 0.9, 1.55) },
                                \chaos, { self[\rand].value(self, 0.75, 1.7) },
                                { self[\rand].value(self, 0.72, 1.25) }
                            ),
                            scaleStep: self[\scaleStepsForLane].value(self, lane).choose,
                            sourceCount: 1,
                            panBias: self[\rand].value(self, -0.35, 0.35),
                            decayScale: switch(lane[\soundModifier],
                                \percussive, { self[\rand].value(self, 0.35, 0.85) },
                                \drone, { self[\rand].value(self, 1.2, 2.2) },
                                { self[\rand].value(self, 0.7, 1.25) }
                            ),
                            hits: 1
                        );
                    });
                    delta = (event[\delta] ? self[\tickIntervalForLane].value(self, lane)).asFloat
                        .clip(self[\minDeltaForLane].value(self, lane), self[\maxDeltaForLane].value(self, lane));
                    SystemClock.sched(delta, { tick.value; nil });
                    if(event.notNil) {
                        if(lane[\group].notNil) {
                            voices = (event[\sourceCount] ? 1).asInteger.clip(1, 4);
                            if((event[\isRest] ? 0).asInteger == 0) {
                                if(self[\laneMayTrigger].value(self, lane, voices)) {
                                    self[\triggerLane].value(self, lane, event);
                                };
                            };
                        };
                    };
                    nil
                })
            };
            initialDelay = if(waitPhase, {
                (lane[\phase] ? self[\tickIntervalForLane].value(self, lane)).asFloat.max(0.25);
            }, {
                0.0;
            });
            SystemClock.sched(initialDelay, tick);
            lane[\routineStartedAt] = Main.elapsedTime;
            if(lane[\routine].isNil, {
                ("EAP lane " ++ (lane[\slot] ? lane[\index] ? "?") ++ " rhythm player missing").postln;
            });
        };
        lane;
    };

    ~triggerLane = { |self, lane, event = nil|
        var ev = event ? ();
        var materialCount = lane[\materials].size.max(1);
        var sourceCount = (ev[\sourceCount] ? materialCount).asInteger.clip(1, materialCount);
        var sources = lane[\materials].scramble.keep(sourceCount);
        var accent = (ev[\accent] ? 1).asFloat.clip(0.2, 2.0);
        var scaleStep = (ev[\scaleStep] ? 0).asInteger;
        var panBias = (ev[\panBias] ? 0).asFloat.clip(-0.5, 0.5);
        var decayScale = (ev[\decayScale] ? 1).asFloat.clip(0.35, 2.4);
        var isPerc = lane[\soundModifier] == \percussive;
        var pitch = self[\choosePitch].value(self, lane, scaleStep);
        var timbreMotion = (lane[\timbreMotion] ? 0.0).asFloat.clip(0, 1);
        var motionStage = (timbreMotion * 7).round(1).asInteger.clip(0, 7);
        var modDepth = [0.0, 0.035, 0.07, 0.12, 0.18, 0.26, 0.36, 0.50][motionStage];
        var modRate = [0.05, 0.08, 0.13, 0.21, 0.34, 0.55, 0.89, 1.44][motionStage]
            * self[\exprand].value(self, 0.78, 1.28);
        var modShape = [0, 0, 1, 1, 2, 2, 3, 3][motionStage];
        var modRand = [0.0, 0.0, 0.03, 0.06, 0.10, 0.16, 0.24, 0.34][motionStage];
        var sustainScale = self[\sustainLoadScale].value(self);
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
                    \harm, if(isPerc, { self[\rand].value(self, 0.02, 0.55) }, { self[\rand].value(self, 0.05, 0.95) }),
                    \timbre, if(isPerc, { self[\rand].value(self, 0.22, 0.88) }, { self[\rand].value(self, 0.10, 0.98) }),
                    \morph, if(isPerc, { self[\rand].value(self, 0.05, 0.58) }, { self[\rand].value(self, 0.08, 0.98) }),
                    \decay, (if(isPerc, { self[\exprand].value(self, 0.018, 0.24) }, { self[\exprand].value(self, 0.08, 3.2) })) * decayScale * sustainScale,
                    \colour, if(isPerc, { self[\rand].value(self, 0.35, 0.92) }, { self[\rand].value(self, 0.15, 0.90) }),
                    \amp, lane[\amp] * accent,
                    \pan, (self[\rand].value(self, -0.75, 0.75) + panBias).clip(-1, 1),
                    \envTail, if(isPerc, { 0.035 }, { 0.25 }),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \rings) {
                var r = lane[\rings] ? (
                    model: lane[\ringsModel],
                    poly: [1, 2, 4].choose,
                    struct: self[\rand].value(self, 0.12, 0.88),
                    bright: self[\rand].value(self, 0.18, 0.95),
                    damp: self[\rand].value(self, 0.25, 0.96),
                    pos: self[\rand].value(self, 0.10, 0.88),
                    envDecay: 5.0 * sustainScale,
                    envRelease: 0.8 * sustainScale
                );
                Synth.head(lane[\group], \eapLaneRingsNote, [
                    \out, lane[\sourceBus].index, \pitch, pitch,
                    \struct, r[\struct], \bright, r[\bright], \damp, r[\damp], \pos, r[\pos],
                    \model, r[\model], \poly, r[\poly],
                    \envDecay, r[\envDecay] * decayScale, \envRelease, r[\envRelease],
                    \amp, lane[\amp] * accent * (if(isPerc, { self[\rand].value(self, 0.85, 1.35) }, { self[\rand].value(self, 0.70, 1.25) })),
                    \pan, (self[\rand].value(self, -0.65, 0.65) + panBias).clip(-1, 1),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \fold) {
                Synth.head(lane[\group], \eapLaneFoldNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \fold, if(isPerc, { self[\rand].value(self, 0.45, 2.6) }, { self[\rand].value(self, 0.25, 2.8) }),
                    \fm, if(isPerc, { self[\rand].value(self, 0.08, 0.75) }, { self[\rand].value(self, 0.02, 0.60) }),
                    \cutoff, if(isPerc, { self[\exprand].value(self, 900, 9500) }, { self[\exprand].value(self, 450, 9000) }),
                    \decay, (if(isPerc, { self[\exprand].value(self, 0.025, 0.22) }, { self[\exprand].value(self, 0.10, 2.4) })) * decayScale * sustainScale,
                    \amp, lane[\amp] * accent * (if(isPerc, { 0.88 }, { 0.75 })),
                    \pan, (self[\rand].value(self, -0.70, 0.70) + panBias).clip(-1, 1),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \molly) {
                var m = lane[\molly];
                Synth.head(lane[\group], \eapLaneMollyNote, [
                    \out, lane[\sourceBus].index, \freq, pitch.midicps,
                    \oscWaveShape, (m[\oscWaveShape] + (modRand * self[\rand].value(self, -0.8, 0.8))).clip(0, 2),
                    \pwMod, (m[\pwMod] + (modDepth * 0.55)).clip(0, 1),
                    \freqModLfo, (m[\freqModLfo] + (modDepth * 0.32)).clip(0, 0.7),
                    \freqModEnv, (m[\freqModEnv] + (modRand * 0.18)).clip(0, 0.8),
                    \mainOscLevel, m[\mainOscLevel], \subOscLevel, m[\subOscLevel],
                    \subOscDetune, m[\subOscDetune], \noiseLevel, (m[\noiseLevel] + (modRand * 0.12)).clip(0, 0.45),
                    \hpFilterCutoff, m[\hpFilterCutoff], \lpFilterCutoff, m[\lpFilterCutoff],
                    \lpFilterResonance, (m[\lpFilterResonance] + (modDepth * 0.28)).clip(0, 1),
                    \lpFilterModEnv, (m[\lpFilterModEnv] + (modDepth * 0.55)).clip(0, 1),
                    \lpFilterTracking, m[\lpFilterTracking], \lfoFreq, modRate,
                    \lfoWaveShape, modShape.clip(0, 4), \envAttack, m[\envAttack],
                    \envDecay, m[\envDecay] * sustainScale, \envSustain, (m[\envSustain] * sustainScale).clip(0, 0.78),
                    \envRelease, m[\envRelease] * sustainScale, \ringModFreq, m[\ringModFreq],
                    \ringModMix, (m[\ringModMix] + (modRand * 0.22)).clip(0, 1),
                    \ampMod, (m[\ampMod] + (modDepth * 0.45)).clip(0, 0.9),
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
                    \attack, p[\attack], \peak, p[\peak], \decay, p[\decay] * decayScale * sustainScale,
                    \reverbMix, p[\reverbMix], \foldMix, p[\foldMix], \body, p[\body],
                    \air, p[\air], \filterRq, p[\filterRq], \toneTilt, p[\toneTilt],
                    \amp, lane[\amp] * accent * 0.85,
                    \pan, (self[\rand].value(self, -0.70, 0.70) + panBias).clip(-1, 1),
                    \modDepth, modDepth, \modRate, modRate, \modShape, modShape, \modRand, modRand
                ]);
            };
            if(source == \dexed) {
                var d = lane[\dexed];
                var noteDur = lane[\gap] * (d[\durScale] ? 1.0) * decayScale;
                if(self[\externalInputSynth].notNil, {
                    self[\externalInputSynth].set(\amp, 0.70, \fadeTime, 0.03);
                    SystemClock.sched(noteDur.clip(0.08, 8.0) + 0.25, {
                        if(self[\externalInputSynth].notNil, {
                            self[\externalInputSynth].set(\amp, 0.0, \fadeTime, 0.12);
                        });
                        nil;
                    });
                });
                self[\sendDexedNote].value(self,
                    d[\channel] ? 0,
                    (pitch + (d[\octaveBias] ? 0)).clip(0, 127),
                    ((d[\velocity] ? 82) * accent).clip(24, 126),
                    if(isPerc, { noteDur.clip(0.04, 0.65) }, { noteDur.clip(0.08, 8.0) })
                );
            };
            if(source == \vital) {
                var v = lane[\vital];
                var noteDur = lane[\gap] * (v[\durScale] ? 1.0) * decayScale;
                if(self[\externalInputSynth].notNil, {
                    self[\externalInputSynth].set(\amp, 0.66, \fadeTime, 0.03);
                    SystemClock.sched(noteDur.clip(0.06, 10.0) + 0.25, {
                        if(self[\externalInputSynth].notNil, {
                            self[\externalInputSynth].set(\amp, 0.0, \fadeTime, 0.12);
                        });
                        nil;
                    });
                });
                self[\sendVitalNote].value(self,
                    (pitch + (v[\octaveBias] ? 0)).clip(0, 127),
                    ((v[\velocity] ? 82) * accent).clip(24, 126),
                    if(isPerc, { noteDur.clip(0.04, 0.55) }, { noteDur.clip(0.08, 10.0) })
                );
            };
        });
    };

    ~startLane = { |self, lane|
        if(lane[\state] != \active) {
            var wasBlank = lane[\state] == \blank;
            var wasMuted = lane[\state] == \muted;
            lane[\group] = Group.head(self[\group]);
            lane[\sourceBus] = Bus.audio(s, 2);
            lane[\buses] = List.new;
            lane[\buses].add(lane[\sourceBus]);
            lane[\synths] = List.new;
            self[\buildFx].value(self, lane, lane[\sourceBus]);
            lane[\state] = \active;
            self[\applyLaneOutput].value(self, lane);
            self[\restartLaneRoutine].value(self, lane, wasMuted);
            if(lane[\routine].isNil, {
                ("EAP lane " ++ (lane[\slot] ? lane[\index] ? "?")
                    ++ " rhythm did not start — retrying").postln;
                self[\restartLaneRoutine].value(self, lane, wasMuted);
            }, {
                if(wasBlank, {
                    self[\triggerLane].value(self, lane, (
                        sourceCount: 1, accent: 1.0, scaleStep: 0,
                        panBias: 0.0, decayScale: 0.85
                    ));
                });
            });
        };
        lane;
    };

    ~stopLane = { |self, lane, nextState = \muted|
        if(lane.notNil) {
            var group = lane[\group];
            var buses = lane[\buses];
            var outSynth = lane[\outSynth];
            var fadeTime = if(nextState == \muted, { 2.8 }, { 1.2 });
            if(lane[\routine].notNil) { ~stopLaneRoutine.value(lane); };
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
                if(total > 2 and: { lane[\state] == \active and: { lane[\fx] == \clouds } }) {
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
                    var result, active;
                    self[\setGridFxActive].value(self, false);
                    0.22.wait;
                    result = cmd.unixCmdGetStdOut.stripWhiteSpace;
                    active = result.contains("active=1") or: { result.contains("active=2") or: { result.contains("active=3") } };
                    if(result.notEmpty, { ("EAP " ++ result).postln; });
                    0.12.wait;
                    self[\setGridFxActive].value(self, active);
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
                molly: lane[\molly].copy, passersby: lane[\passersby].copy,
                dexed: lane[\dexed].copy, vital: lane[\vital].copy,
                clouds: lane[\clouds].copy, state: lane[\state]
            );
        });
    };

    ~prepareLoadedLane = { |self, lane, index|
        var m = lane[\molly];
        var p = lane[\passersby];
        var d = lane[\dexed];
        var v = lane[\vital];
        lane[\index] = index + 1;
        lane[\slot] = index + 1;
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
        lane[\rhythmState] = nil;
        lane[\rhythmProfile] = lane[\rhythmProfile] ? self[\rhythmProfilesFor].value(lane[\soundModifier]).choose;
        lane[\pulse] = lane[\pulse] ? 0.12;
        lane[\swing] = lane[\swing] ? 0.0;
        lane[\level] = lane[\level] ? 1.0;
        lane[\pan] = lane[\pan] ? 0.0;
        lane[\density] = lane[\density] ? 1.0;
        lane[\timbreMotion] = lane[\timbreMotion] ? 0.0;
        lane[\reverbSend] = lane[\reverbSend] ? 0.5;
        lane[\transpose] = (lane[\transpose] ? 0).asInteger.clip(-36, 36);
        lane[\sourceEngine] = lane[\sourceEngine] ? \any;
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
        lane;
    };

    ~sessionSnapshot = { |self|
        (
            reverbValues: self[\reverbValues].copy,
            masterValues: self[\masterValues].copy,
            scaleIndex: self[\scaleIndex],
            rootNote: self[\rootNote],
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
        self[\slots].do({ |lane| self[\stopLane].value(self, lane, \blank); });
        self[\lanes].clear;
        self[\slots] = Array.fill(self[\maxScenes], { nil });
        self[\cloudLaneIndex] = nil;
        self[\adaptiveJournal].clear;
        self[\adaptiveSerial] = 0;
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
                ++ " sourceEngine=" ++ (self[\sourceEnginePreference] ? \any)
                ++ " rhythm=" ++ (lane[\rhythmProfile] ? \unknown)
                ++ " adaptiveSiblings=" ++ ((lane[\adaptive] ? ())[\siblingCount] ? 0)
                ++ " adaptiveRegister=" ++ ((lane[\adaptive] ? ())[\registerBand] ? \mid)
                ++ " level=" ++ (lane[\level] ? 1.0).round(0.001)
                ++ " pan=" ++ (lane[\pan] ? 0.0).round(0.001)
                ++ " density=" ++ (lane[\density] ? 1.0).round(0.001)
                ++ " timbreMotion=" ++ (lane[\timbreMotion] ? 0.0).round(0.001)
                ++ " reverbSend=" ++ (lane[\reverbSend] ? 0.5).round(0.001)
                ++ " transpose=" ++ (lane[\transpose] ? 0)
                ++ " plaits=" ++ lane[\plaitsModels].asString).postln;
            1;
        });
    };

    ~toggleSlot = { |self, slot, modifier = nil|
        var index = slot.asInteger.clip(1, self[\maxScenes]);
        var lane = self[\slots][index - 1];
        if(lane.isNil or: { lane[\state] == \blank }, {
            if(modifier.isNil, {
                ("EAP slot " ++ index ++ " toggle ignored: modifier required").postln;
                0;
            }, {
                self[\generateSlot].value(self, index, nil, modifier);
            });
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

    ~seed = { |self, count = 1, modifier = nil|
        var n = count.asInteger.clip(1, self[\maxScenes]);
        if(modifier.isNil, {
            "EAP random scene seed ignored: modifier required".postln;
            0;
        }, {
            self[\clear].value(self);
            self[\cloudLaneIndex] = if(n >= 5, { [0, rrand(1, n)].choose }, { nil });
            n.do({ |index|
                var adaptive = self[\adaptiveContextForSlot].value(self, index + 1, modifier);
                var lane = self[\randomLane].value(self, index + 1, n, modifier, adaptive);
                lane[\state] = \muted;
                self[\startLane].value(self, lane);
                self[\lanes].add(lane);
                self[\slots][index] = lane;
                self[\recordAdaptiveScene].value(self, lane, \seed);
                ("EAP random lane " ++ (index + 1) ++ "/" ++ n ++
                    " materials=" ++ lane[\materials].asString ++
                    " fx=" ++ lane[\fx] ++
                    " adaptiveSiblings=" ++ ((lane[\adaptive] ? ())[\siblingCount] ? 0) ++
                    " plaits=" ++ lane[\plaitsModels].asString).postln;
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
        self[\refreshDexed].value(self);
        self[\reverbValues] = [0.24, 0.55, 0.45, 0.36, 0.25, 0.74, 0.24, 0.62];
        self[\masterValues] = [0.82, 0.0, 1.0, 0.12, 0.0];
        self[\masterGroup] = Group.after(self[\group]);
        self[\gridFxActive] = false;
        self[\gridFxScenes] = Array.fill(self[\maxScenes], { false });
        self[\gridFxQueue].clear;
        self[\gridFxProcessing] = false;
        self[\gridFxSendSynth] = Synth.head(self[\masterGroup], \eapGridFxSend, [\in, self[\gridFxBus].index, \out, 2, \amp, 0.0]);
        self[\externalInputSynth] = Synth.head(self[\masterGroup], \eapExternalInput, [\out, self[\masterBus].index, \amp, 0.0]);
        self[\masterSynth] = Synth.tail(self[\masterGroup], \eapSceneMaster, [
            \in, self[\masterBus].index, \reverbIn, self[\reverbBus].index, \out, 0
        ]);
        "/usr/local/bin/eap-airwindows-grid-fx --clear".unixCmdGetStdOut;
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
        "/usr/local/bin/eap-airwindows-grid-fx --clear".unixCmdGetStdOut;
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
