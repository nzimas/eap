// Electroacoustic Playground SuperCollider boot.
// Starts the random independent scene-lane generator.

"Electroacoustic Playground: loading boot.scd".postln;

s = Server.default;
s.options.numInputBusChannels = 2;
s.options.numOutputBusChannels = 2;
s.options.sampleRate = 48000;
s.options.blockSize = 128;
s.options.hardwareBufferSize = 128;
s.options.memSize = 262144;
s.options.numWireBufs = 256;
s.options.maxNodes = 8192;
s.options.maxSynthDefs = 2048;
s.latency = 0.05;

s.waitForBoot({
    "Electroacoustic Playground: server booted".postln;
    thisProcess.interpreter.executeFile("/opt/electroacoustic-playground/supercollider/fx/Fx_Pedalboard.scd");
    thisProcess.interpreter.executeFile("/opt/electroacoustic-playground/supercollider/Scene_RandomLanes.scd");
    s.sync;

    ~eapScenes[\start].value(~eapScenes);

    OSCdef(\eapRandomScenes, { |msg|
        var count = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        ~eapScenes[\seed].value(~eapScenes, count);
        ("EAP manual random scene set: " ++ count).postln;
    }, '/eap/scenes');

    OSCdef(\eapSceneSlot, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var action = (msg[2] ? 0).asInteger;
        var state;
        if(action == 1, {
            state = ~eapScenes[\generateSlot].value(~eapScenes, slot);
            ("EAP slot OSC regenerate: " ++ slot ++ " state=" ++ state).postln;
        }, {
            state = ~eapScenes[\toggleSlot].value(~eapScenes, slot);
            ("EAP slot OSC toggle: " ++ slot ++ " state=" ++ state).postln;
        });
    }, '/eap/slot');

    OSCdef(\eapMasterReverb, { |msg|
        var param = (msg[1] ? 1).asInteger.clip(1, 8);
        var value = ((msg[2] ? 0).asInteger / 127).clip(0, 1);
        ~eapScenes[\setReverb].value(~eapScenes, param, value);
    }, '/eap/reverb');

    OSCdef(\eapMasterDynamics, { |msg|
        var param = (msg[1] ? 1).asInteger.clip(1, 5);
        var value = ((msg[2] ? 0).asInteger / 127).clip(0, 1);
        ~eapScenes[\setMaster].value(~eapScenes, param, value);
    }, '/eap/master');

    OSCdef(\eapSession, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, 64);
        var action = (msg[2] ? 0).asInteger;
        var result;
        if(action == 1, {
            result = ~eapScenes[\saveSession].value(~eapScenes, slot);
            ("EAP session OSC save: " ++ slot ++ " result=" ++ result).postln;
        }, {
            result = ~eapScenes[\loadSession].value(~eapScenes, slot);
            ("EAP session OSC load: " ++ slot ++ " result=" ++ result).postln;
        });
    }, '/eap/session');

    // Backward-compatible controls: names are intentionally ignored.
    OSCdef(\eapSceneTrigger, { |msg|
        var count = (msg[2] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        ~eapScenes[\seed].value(~eapScenes, count);
        ("EAP legacy scene trigger mapped to random scene set: " ++ count).postln;
    }, '/eap/scene');

    OSCdef(\eapSceneRandom, { |msg|
        var count = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        ~eapScenes[\seed].value(~eapScenes, count);
        ("EAP legacy random trigger mapped to random scene set: " ++ count).postln;
    }, '/eap/scene/random');

    "Electroacoustic Playground: random scene lanes ready".postln;
});

s.boot;

// Keep non-interactive sclang alive under systemd.
Routine({ loop { 60.wait; } }).play(SystemClock);
