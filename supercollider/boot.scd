// Electroacoustic Playground SuperCollider boot.
// Starts the random independent scene-lane generator.

"Electroacoustic Playground: loading boot.scd".postln;

// Wire only main outs to playback; never autoconnect SC ports to each other.
"SC_JACK_DEFAULT_INPUTS".setenv("");
"SC_JACK_DEFAULT_OUTPUTS".setenv("system:playback_1,system:playback_2");

s = Server.default;
s.options.numInputBusChannels = 8;
s.options.numOutputBusChannels = 4;
s.options.sampleRate = 48000;
s.options.blockSize = 4096;
s.options.hardwareBufferSize = 4096;
s.options.memSize = 262144;
s.options.numWireBufs = 256;
s.options.maxNodes = 8192;
s.options.maxSynthDefs = 2048;
s.options.memoryLocking = true;
s.latency = 0.1;

s.waitForBoot({
    "Electroacoustic Playground: server booted".postln;
    thisProcess.interpreter.executeFile("/opt/electroacoustic-playground/supercollider/fx/Fx_Pedalboard.scd");
    thisProcess.interpreter.executeFile("/opt/electroacoustic-playground/supercollider/Scene_RandomLanes.scd");
    s.sync;

    ~eapScenes[\start].value(~eapScenes);

    OSCdef(\eapSeqEvent, { |msg|
        ~eapScenes[\onSubsequenceEvent].value(~eapScenes, msg);
    }, '/eap/seq/event');

    OSCdef(\eapRandomScenes, { |msg, time, addr|
        var count = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var modifier = if(msg.size > 2, { ~eapScenes[\modifierFromCode].value(~eapScenes, msg[2]) }, { nil });
        ~eapScenes[\seed].value(~eapScenes, count, modifier);
        ("EAP manual random scene set: " ++ count ++ " modifier=" ++ (modifier ? \default)).postln;
        ~eapScenes[\replySlotStates].value(~eapScenes, addr);
    }, '/eap/scenes');

    OSCdef(\eapSceneSlot, { |msg, time, addr|
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
        ~eapScenes[\replySlotStates].value(~eapScenes, addr);
    }, '/eap/slot');

    OSCdef(\eapSlotsQuery, { |msg, time, addr|
        ~eapScenes[\replySlotStates].value(~eapScenes, addr);
    }, '/eap/slots/query');

    OSCdef(\eapClear, { |msg, time, addr|
        ~eapScenes[\clear].value(~eapScenes);
        "EAP all scene lanes cleared".postln;
        ~eapScenes[\replySlotStates].value(~eapScenes, addr);
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

    OSCdef(\eapMuteMode, { |msg|
        var mode = (msg[1] ? 1).asInteger.clip(0, 1);
        ~eapScenes[\setMuteMode].value(~eapScenes, mode);
    }, '/eap/settings/mute_mode');

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

    OSCdef(\eapGranulatorActive, { |msg|
        var enabled = (msg[1] ? 0).asInteger.clip(0, 1);
        ~eapScenes[\setGranulatorActive].value(~eapScenes, enabled);
    }, '/eap/granulator/active');

    OSCdef(\eapGranulatorScene, { |msg|
        var slot = (msg[1] ? 1).asInteger.clip(1, ~eapScenes[\maxScenes]);
        var enabled = (msg[2] ? 0).asInteger.clip(0, 1);
        ~eapScenes[\setGranulatorScene].value(~eapScenes, slot, enabled);
    }, '/eap/granulator/scene');

    OSCdef(\eapGranulatorParam, { |msg|
        var param = (msg[1] ? 1).asInteger.clip(1, 7);
        var value = ((msg[2] ? 0).asInteger / 127).clip(0, 1);
        ~eapScenes[\setGranulatorParam].value(~eapScenes, param, value);
    }, '/eap/granulator/param');

    OSCdef(\eapGranulatorFreeze, { |msg|
        var frozen = (msg[1] ? 0).asInteger.clip(0, 1);
        ~eapScenes[\setGranulatorFreeze].value(~eapScenes, frozen);
    }, '/eap/granulator/freeze');

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
        var code = (msg[1] ? 0).asInteger.clip(0, ~eapScenes[\sourceEngineSymbols].size);
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

    OSCdef(\eapVcvTest, { |msg|
        ~eapScenes[\loadVcvPatch].value(~eapScenes, 99, 1, \percussive);
        ~eapScenes[\refreshVcv].value(~eapScenes);
        if(~eapScenes[\externalInputSynth].notNil, {
            ~eapScenes[\externalInputSynth].set(\amp, 0.9, \fadeTime, 0.02);
        });
        ~eapScenes[\sendVcvNote].value(~eapScenes, 60, 110, 1.2);
        "EAP VCV test note sent".postln;
    }, '/eap/vcv/test');

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
