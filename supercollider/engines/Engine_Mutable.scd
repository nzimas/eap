// Electroacoustic Playground Mutable Instruments source engine.
// Uses MiPlaits and MiRings from v7b1/mi-UGens as scene-shaped sound sources.

~eap = ~eap ? IdentityDictionary.new;
~eapEngines = ~eapEngines ? IdentityDictionary.new;

~eapEngines[\mutable] = Environment.make({
    ~name = \mutable;
    ~outBus = 0;
    ~rootMidi = 48;
    ~sceneNames = [\mineral, \reed, \ember, \tide];
    ~currentScene = \mineral;
    ~group = nil;
    ~routine = nil;

    ~profiles = IdentityDictionary[
        \mineral -> (
            register: [36, 58], scale: [0, 2, 3, 7, 9], gap: [1.8, 6.5],
            plaitsModels: [8, 11, 14], plaitsVoices: [1, 2], plaitsAmp: 0.14,
            harm: [0.20, 0.54], timbre: [0.32, 0.68], morph: [0.18, 0.55],
            decay: [0.45, 2.6], ringsChance: 0.45, ringsAmp: 0.16,
            ringsModel: [0, 2], ringsStruct: [0.22, 0.55], ringsBright: [0.30, 0.62],
            ringsDamp: [0.62, 0.88], ringsPos: [0.22, 0.58]
        ),
        \reed -> (
            register: [47, 69], scale: [0, 2, 5, 7, 10], gap: [0.9, 3.8],
            plaitsModels: [11, 13, 15], plaitsVoices: [1, 2], plaitsAmp: 0.12,
            harm: [0.36, 0.78], timbre: [0.42, 0.82], morph: [0.34, 0.72],
            decay: [0.8, 3.8], ringsChance: 0.65, ringsAmp: 0.15,
            ringsModel: [1, 2], ringsStruct: [0.35, 0.76], ringsBright: [0.45, 0.82],
            ringsDamp: [0.48, 0.78], ringsPos: [0.35, 0.74]
        ),
        \ember -> (
            register: [54, 82], scale: [0, 1, 3, 6, 7, 10], gap: [0.18, 1.4],
            plaitsModels: [2, 3, 5, 9, 10], plaitsVoices: [1, 2], plaitsAmp: 0.10,
            harm: [0.45, 0.95], timbre: [0.52, 0.98], morph: [0.42, 0.95],
            decay: [0.08, 0.72], ringsChance: 0.18, ringsAmp: 0.11,
            ringsModel: [0, 1], ringsStruct: [0.48, 0.88], ringsBright: [0.62, 0.95],
            ringsDamp: [0.18, 0.48], ringsPos: [0.12, 0.42]
        ),
        \tide -> (
            register: [31, 52], scale: [0, 2, 5, 7, 9], gap: [2.8, 9.5],
            plaitsModels: [4, 6, 8, 11], plaitsVoices: [1, 1, 2], plaitsAmp: 0.13,
            harm: [0.12, 0.48], timbre: [0.18, 0.58], morph: [0.16, 0.64],
            decay: [1.4, 6.8], ringsChance: 0.70, ringsAmp: 0.17,
            ringsModel: [0, 2], ringsStruct: [0.18, 0.50], ringsBright: [0.22, 0.58],
            ringsDamp: [0.70, 0.95], ringsPos: [0.28, 0.70]
        )
    ];

    ~rangeRand = { |self, range| rrand(range[0].asFloat, range[1].asFloat) };

    ~choosePitch = { |self, profile|
        var reg = profile[\register];
        var octave = rrand((reg[0] / 12).floor, (reg[1] / 12).floor);
        var degree = profile[\scale].choose;
        ((octave * 12) + degree + [0, 0, 0, 7, 12, -12].choose).clip(reg[0], reg[1]);
    };

    ~makeSynthDefs = { |self|
        SynthDef(\eapMiPlaitsNote, { |out = 0, pitch = 60, engine = 0, harm = 0.4,
            timbre = 0.5, morph = 0.5, level = 0.8, decay = 0.8, amp = 0.12, pan = 0|
            var trig, sig, life;
            trig = Trig1.kr(1, 0.01);
            sig = MiPlaits.ar(pitch, engine, harm, timbre, morph, trig, level, 0, 0, 0, decay, 0.5);
            sig = LeakDC.ar(sig) * EnvGen.kr(Env.linen(0.002, decay.max(0.05) + 0.2, 0.25), doneAction: 2);
            sig = Balance2.ar(sig[0], sig[1], pan, amp);
            Out.ar(out, sig);
        }).add;

        SynthDef(\eapMiRingsNote, { |out = 0, pitch = 60, struct = 0.4, bright = 0.5,
            damp = 0.7, pos = 0.4, model = 0, poly = 2, amp = 0.14, pan = 0|
            var trig, exciter, sig, life;
            trig = Trig1.kr(1, 0.01);
            exciter = PinkNoise.ar(0.025) * Decay2.kr(trig, 0.004, 0.08);
            sig = MiRings.ar(exciter, trig, pitch, struct, bright, damp, pos, model, poly, 1, 0);
            life = EnvGen.kr(Env.linen(0.002, 7.5, 1.2), doneAction: 2);
            sig = LeakDC.ar(sig) * life;
            sig = Balance2.ar(sig[0], sig[1], pan, amp);
            Out.ar(out, sig);
        }).add;
    };

    ~triggerEvent = { |self|
        var profile = self.profiles[self.currentScene];
        var pitch = self.choosePitch(profile);
        var voices = profile[\plaitsVoices].choose.clip(1, 2);
        voices.do({ |index|
            Synth.tail(self.group, \eapMiPlaitsNote, [
                \out, self.outBus,
                \pitch, (pitch + [0, 0, 7, 12].choose).clip(profile[\register][0], profile[\register][1]),
                \engine, profile[\plaitsModels].choose,
                \harm, self.rangeRand(profile[\harm]),
                \timbre, self.rangeRand(profile[\timbre]),
                \morph, self.rangeRand(profile[\morph]),
                \decay, self.rangeRand(profile[\decay]),
                \amp, profile[\plaitsAmp] / voices,
                \pan, rrand(-0.55, 0.55)
            ]);
        });
        if(profile[\ringsChance].coin) {
            Synth.tail(self.group, \eapMiRingsNote, [
                \out, self.outBus, \pitch, pitch,
                \struct, self.rangeRand(profile[\ringsStruct]),
                \bright, self.rangeRand(profile[\ringsBright]),
                \damp, self.rangeRand(profile[\ringsDamp]),
                \pos, self.rangeRand(profile[\ringsPos]),
                \model, profile[\ringsModel].choose,
                \poly, [1, 2, 4].choose,
                \amp, profile[\ringsAmp],
                \pan, rrand(-0.45, 0.45)
            ]);
        };
    };

    ~applyScene = { |self, sceneName|
        self.currentScene = sceneName;
        ("EAP Mutable active scene " ++ sceneName).postln;
    };

    ~auditionScene = { |self, sceneName|
        self.applyScene(sceneName);
        2.do({ self.triggerEvent; });
    };

    ~setOutBus = { |self, bus| self.outBus = bus; };

    ~start = { |self|
        self.stop;
        self.group = Group.tail(s);
        self.makeSynthDefs;
        s.sync;
        self.applyScene(self.currentScene);
        self.routine = Routine({
            var profile, gap;
            loop {
                profile = self.profiles[self.currentScene];
                self.triggerEvent;
                gap = self.rangeRand(profile[\gap]);
                gap.wait;
            };
        }).play(SystemClock);
        "EAP Mutable: started".postln;
    };

    ~stop = { |self|
        if(self.routine.notNil) { self.routine.stop; self.routine = nil; };
        if(self.group.notNil) { self.group.free; self.group = nil; };
    };
}).know_(true);
