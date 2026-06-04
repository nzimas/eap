// Electroacoustic Playground SuperCollider boot.
// Starts the random independent scene-lane generator.

"Electroacoustic Playground: loading boot.scd".postln;

s = Server.default;
s.options.numInputBusChannels = 4;
s.options.numOutputBusChannels = 4;
s.options.sampleRate = 48000;
s.options.blockSize = 512;
s.options.hardwareBufferSize = 1024;
s.options.memSize = 262144;
s.options.numWireBufs = 256;
s.options.maxNodes = 8192;
s.options.maxSynthDefs = 2048;
s.latency = 0.1;

s.waitForBoot({
    "Electroacoustic Playground: server booted".postln;
    thisProcess.interpreter.executeFile("/opt/electroacoustic-playground/supercollider/fx/Fx_Pedalboard.scd");
    thisProcess.interpreter.executeFile("/opt/electroacoustic-playground/supercollider/Scene_RandomLanes.scd");
    s.sync;

    ~eapScenes[\start].value(~eapScenes);

    ~eapConnectJackOut = {
        var ok = "/usr/local/bin/eap-connect-sc-jack 8 0.25".unixCmdGetStdOut.contains("connected");
        if(ok.not, {
            [
                "jack_disconnect SuperCollider:out_1 system:playback_1",
                "jack_disconnect SuperCollider:out_1 system:playback_2",
                "jack_disconnect SuperCollider:out_1 SuperCollider:in_1",
                "jack_disconnect SuperCollider:out_1 SuperCollider:in_2",
                "jack_disconnect SuperCollider:out_1 SuperCollider:in_3",
                "jack_disconnect SuperCollider:out_1 SuperCollider:in_4",
                "jack_disconnect SuperCollider:out_2 system:playback_1",
                "jack_disconnect SuperCollider:out_2 system:playback_2",
                "jack_disconnect SuperCollider:out_2 SuperCollider:in_1",
                "jack_disconnect SuperCollider:out_2 SuperCollider:in_2",
                "jack_disconnect SuperCollider:out_2 SuperCollider:in_3",
                "jack_disconnect SuperCollider:out_2 SuperCollider:in_4",
                "jack_disconnect SuperCollider:out_3 system:playback_1",
                "jack_disconnect SuperCollider:out_3 system:playback_2",
                "jack_disconnect SuperCollider:out_3 SuperCollider:in_1",
                "jack_disconnect SuperCollider:out_3 SuperCollider:in_2",
                "jack_disconnect SuperCollider:out_3 SuperCollider:in_3",
                "jack_disconnect SuperCollider:out_3 SuperCollider:in_4",
                "jack_disconnect SuperCollider:out_4 system:playback_1",
                "jack_disconnect SuperCollider:out_4 system:playback_2",
                "jack_disconnect SuperCollider:out_4 SuperCollider:in_1",
                "jack_disconnect SuperCollider:out_4 SuperCollider:in_2",
                "jack_disconnect SuperCollider:out_4 SuperCollider:in_3",
                "jack_disconnect SuperCollider:out_4 SuperCollider:in_4",
                "jack_connect SuperCollider:out_1 system:playback_1",
                "jack_connect SuperCollider:out_2 system:playback_2"
            ].do({ |cmd| cmd.unixCmdGetStdOut; });
            "EAP JACK outputs connected to system playback (fallback)".postln;
        });
        ok;
    };
    Routine({
        [1.0, 3.0, 8.0, 20.0].do({ |delay|
            delay.wait;
            if(~eapConnectJackOut.value.not, {
                "EAP JACK connect retry at " ++ delay ++ "s".postln;
            });
        });
    }).play(SystemClock);

    OSCdef(\eapRandomScenes, { |msg|
        var count = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var modifier = if(msg.size > 2, { ~eapScenes[\modifierFromCode].value(~eapScenes, msg[2]) }, { nil });
        ~eapScenes[\seed].value(~eapScenes, count, modifier);
        ("EAP manual random scene set: " ++ count ++ " modifier=" ++ (modifier ? \default)).postln;
    }, '/eap/scenes');

    OSCdef(\eapSceneSlot, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var action = (msg[2] ? 0).asInteger;
        var modifier = if(msg.size > 3, { ~eapScenes[\modifierFromCode].value(~eapScenes, msg[3]) }, { nil });
        var state;
        if(action == 1, {
            state = ~eapScenes[\generateSlot].value(~eapScenes, slot, nil, modifier);
            ("EAP slot OSC regenerate: " ++ slot ++ " modifier=" ++ (modifier ? \default) ++ " state=" ++ state).postln;
        }, {
            state = ~eapScenes[\toggleSlot].value(~eapScenes, slot, modifier);
            ("EAP slot OSC toggle: " ++ slot ++ " modifier=" ++ (modifier ? \default) ++ " state=" ++ state).postln;
        });
    }, '/eap/slot');

    OSCdef(\eapClear, { |msg|
        ~eapScenes[\clear].value(~eapScenes);
        "EAP all scene lanes cleared".postln;
    }, '/eap/clear', nil);

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

    OSCdef(\eapSlotVolume, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var value = ((msg[2] ? 100).asInteger / 127).clip(0, 1);
        ~eapScenes[\setSlotVolume].value(~eapScenes, slot, value);
    }, '/eap/slot/volume');

    OSCdef(\eapSlotPan, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var value = ((msg[2] ? 64).asInteger / 127).linlin(0, 1, -1, 1).clip(-1, 1);
        ~eapScenes[\setSlotPan].value(~eapScenes, slot, value);
    }, '/eap/slot/pan');

    OSCdef(\eapSlotDensity, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var value = ((msg[2] ? 100).asInteger / 127).linlin(0, 1, 0.05, 1.0).clip(0.05, 1);
        ~eapScenes[\setSlotDensity].value(~eapScenes, slot, value);
    }, '/eap/slot/density');

    OSCdef(\eapSlotTimbre, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var value = ((msg[2] ? 0).asInteger / 127).clip(0, 1);
        ~eapScenes[\setSlotTimbreMotion].value(~eapScenes, slot, value);
    }, '/eap/slot/timbre');

    OSCdef(\eapSlotReverbSend, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var value = ((msg[2] ? 64).asInteger / 127).clip(0, 1);
        ~eapScenes[\setSlotReverbSend].value(~eapScenes, slot, value);
    }, '/eap/slot/reverb');

    OSCdef(\eapSlotTranspose, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var semitones = (msg[2] ? 0).asInteger.clip(-36, 36);
        ~eapScenes[\setSlotTranspose].value(~eapScenes, slot, semitones);
    }, '/eap/slot/transpose');

    OSCdef(\eapGridFx, { |msg|
        var index = (msg[1] ? 1).asInteger.clip(1, 30);
        var enabled = (msg[2] ? 0).asInteger.clip(0, 1);
        ~eapScenes[\setGridFx].value(~eapScenes, index, enabled);
    }, '/eap/gridfx');

    OSCdef(\eapGridFxLock, { |msg|
        var index = (msg[1] ? 1).asInteger.clip(1, 30);
        var locked = (msg[2] ? 0).asInteger.clip(0, 1);
        ~eapScenes[\setGridFxLock].value(~eapScenes, index, locked);
    }, '/eap/gridfx/lock');

    OSCdef(\eapGridFxScene, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var enabled = (msg[2] ? 0).asInteger.clip(0, 1);
        ~eapScenes[\setGridFxScene].value(~eapScenes, slot, enabled);
    }, '/eap/gridfx/scene');

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

    OSCdef(\eapTuning, { |msg|
        var scaleIndex = (msg[1] ? ~eapScenes[\scaleIndex]).asInteger.clip(0, 7);
        var rootNote = (msg[2] ? ~eapScenes[\rootNote]).asInteger.clip(0, 11);
        ~eapScenes[\setTuning].value(~eapScenes, scaleIndex, rootNote);
    }, '/eap/tuning');

    OSCdef(\eapSourceEngine, { |msg|
        var code = (msg[1] ? 0).asInteger.clip(0, 8);
        ~eapScenes[\setSourceEnginePreference].value(~eapScenes, code);
    }, '/eap/engine');

    OSCdef(\eapDexedRescan, { |msg|
        var result = ~eapScenes[\refreshDexed].value(~eapScenes);
        ("EAP Dexed rescan result=" ++ result).postln;
    }, '/eap/dexed/rescan');

    OSCdef(\eapVcvRescan, { |msg|
        var result = ~eapScenes[\refreshVcv].value(~eapScenes);
        ("EAP VCV rescan result=" ++ result).postln;
    }, '/eap/vcv/rescan');

    OSCdef(\eapTest, { |msg|
        var freq = (msg[1] ? 440).asFloat.clip(20, 4000);
        var dur = (msg[2] ? 1.2).asFloat.clip(0.1, 6);
        ~eapScenes[\playTestTone].value(~eapScenes, freq, dur);
    }, '/eap/test');

    OSCdef(\eapStatus, { |msg|
        ~eapScenes[\audioStatus].value(~eapScenes);
    }, '/eap/status', nil);

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
