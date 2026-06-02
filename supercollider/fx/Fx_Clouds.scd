// Electroacoustic Playground Mutable Instruments Clouds FX backend.
// Uses MiClouds from v7b1/mi-UGens. This backend is mutually exclusive with pedalboard per scene.

~eap = ~eap ? IdentityDictionary.new;
~eapFx = ~eapFx ? IdentityDictionary.new;

~eapFx[\clouds] = Environment.make({
    ~name = \clouds;
    ~inputBus = nil;
    ~group = nil;
    ~synth = nil;
    ~outputBus = 0;
    ~sceneName = \clear;

    ~profiles = IdentityDictionary[
        \mineral -> (
            pit: -12, pos: 0.18, size: 0.68, dens: 0.34, tex: 0.42,
            drywet: 0.62, in_gain: 1.05, spread: 0.72, rvb: 0.34, fb: 0.18,
            freeze: 0, mode: 0, lofi: 0
        ),
        \reed -> (
            pit: 7, pos: 0.46, size: 0.34, dens: 0.44, tex: 0.55,
            drywet: 0.52, in_gain: 1.0, spread: 0.62, rvb: 0.22, fb: 0.10,
            freeze: 0, mode: 1, lofi: 0
        ),
        \ember -> (
            pit: 12, pos: 0.72, size: 0.18, dens: 0.72, tex: 0.78,
            drywet: 0.48, in_gain: 0.95, spread: 0.56, rvb: 0.18, fb: 0.08,
            freeze: 0, mode: 2, lofi: 1
        ),
        \tide -> (
            pit: -5, pos: 0.38, size: 0.86, dens: 0.26, tex: 0.30,
            drywet: 0.70, in_gain: 1.05, spread: 0.82, rvb: 0.46, fb: 0.24,
            freeze: 0, mode: 0, lofi: 0
        )
    ];

    ~makeSynthDefs = { |self|
        SynthDef(\eapCloudsFx, { |in = 0, out = 0, pit = 0, pos = 0.5, size = 0.25,
            dens = 0.4, tex = 0.5, drywet = 0.5, in_gain = 1, spread = 0.5,
            rvb = 0, fb = 0, freeze = 0, mode = 0, lofi = 0, trig = 0, amp = 0.92|
            var source, wet;
            source = LeakDC.ar(In.ar(in, 2));
            wet = MiClouds.ar(source, pit, pos, size, dens, tex, drywet, in_gain,
                spread, rvb, fb, freeze, mode, lofi, trig);
            Out.ar(out, Limiter.ar(LeakDC.ar(wet) * amp, 0.92, 0.01));
        }).add;
    };

    ~clear = { |self|
        if(self[\synth].notNil) { self[\synth].free; self[\synth] = nil; };
        self[\sceneName] = \clear;
    };

    ~seedScene = { |self, sceneName = \mineral|
        var profile = self[\profiles][sceneName] ? self[\profiles][\mineral];
        self[\clear].value(self);
        self[\sceneName] = sceneName;
        self[\synth] = Synth.tail(self[\group], \eapCloudsFx, [
            \in, self[\inputBus].index, \out, self[\outputBus],
            \pit, profile[\pit], \pos, profile[\pos], \size, profile[\size],
            \dens, profile[\dens], \tex, profile[\tex], \drywet, profile[\drywet],
            \in_gain, profile[\in_gain], \spread, profile[\spread], \rvb, profile[\rvb],
            \fb, profile[\fb], \freeze, profile[\freeze], \mode, profile[\mode],
            \lofi, profile[\lofi], \amp, 0.94
        ]);
        ("EAP Clouds active scene " ++ sceneName ++ ": " ++ profile.asString).postln;
    };

    ~start = { |self|
        if(self[\group].notNil) { self[\stop].value(self); };
        self[\group] = Group.tail(s);
        self[\inputBus] = Bus.audio(s, 2);
        self[\makeSynthDefs].value(self);
        s.sync;
        "EAP Clouds: started".postln;
    };

    ~stop = { |self|
        self[\clear].value(self);
        if(self[\inputBus].notNil) { self[\inputBus].free; self[\inputBus] = nil; };
        if(self[\group].notNil) { self[\group].free; self[\group] = nil; };
    };
}).know_(true);
