package main

import fcore "fmod/core"
import fstudio "fmod/studio"

sound_state: Sound_State

Sound_State :: struct {
    sound_ticks:     u64,
	system:          ^fstudio.SYSTEM,
	core_system:     ^fcore.SYSTEM,
	bank:            ^fstudio.BANK,
	strings_bank:    ^fstudio.BANK,
    master_ch_group : ^fcore.CHANNELGROUP,
    menu_music:    Sound,
    game_ambiance: Sound,
}

Sound_Instance :: fstudio.EVENTINSTANCE

Sound :: struct {
    volume:   f32,
    pitch:    f32,
    playing:  bool,
    instance: ^Sound_Instance
}

audio_init :: proc() {
    fmod_error_check(fstudio.System_Create(&sound_state.system, fcore.VERSION))
	fmod_error_check(fstudio.System_Initialize(sound_state.system, 512, fstudio.INIT_NORMAL, fstudio.INIT_NORMAL, nil))
	fmod_error_check(fstudio.System_LoadBankFile(sound_state.system, "res/audio/Master.bank", fstudio.LOAD_BANK_NORMAL, &sound_state.bank))
	fmod_error_check(fstudio.System_LoadBankFile(sound_state.system, "res/audio/Master.strings.bank", fstudio.LOAD_BANK_NORMAL, &sound_state.strings_bank))
    fmod_error_check(fstudio.System_GetCoreSystem(sound_state.system, &sound_state.core_system))
    fmod_error_check(fcore.System_GetMasterChannelGroup(sound_state.core_system, &sound_state.master_ch_group));
}

audio_shutdown :: proc() {
    fmod_error_check(fstudio.System_Release(sound_state.system))
}

audio_update :: proc(listener_pos: v2) {
    fmod_error_check(fstudio.System_Update(sound_state.system))

    // update listener pos
	attributes : fcore._3D_ATTRIBUTES;
	attributes.position = {listener_pos.x, 0, listener_pos.y};
	attributes.forward = {0, 0, 1};
	attributes.up = {0, 1, 0};
	fmod_error_check(fstudio.System_SetListenerAttributes(sound_state.system, 0, attributes, nil));

    sound_state.sound_ticks += 1
}


INVALID_POS :: v2{ 99999, 99999 }

audio_play :: proc(event: string,  pos := INVALID_POS, volume:f32=1, pitch:f32=1, cooldown_ms :f32= 40.0) -> (Sound) {
    	event_desc: ^fstudio.EVENTDESCRIPTION
    	event_result := fstudio.System_GetEvent(sound_state.system, ctstr("event:/{}", event), &event_desc)

        if event_result != .OK {
            log_error("Failed to play sound {}. Error: {}", ctstr("event:/{}", event), fcore.error_string(event_result))
            return {}
        }

        instance: ^fstudio.EVENTINSTANCE
    	fmod_error_check(fstudio.EventDescription_CreateInstance(event_desc, &instance))

    	fstudio.EventInstance_SetVolume(instance, volume)
    	fstudio.EventInstance_SetPitch(instance, pitch)

        fmod_error_check(fstudio.EventInstance_SetProperty(instance, .EVENT_PROPERTY_COOLDOWN, cooldown_ms/1000.0))
    	fmod_error_check(fstudio.EventInstance_Start(instance))

    	attributes : fcore._3D_ATTRIBUTES;
    	attributes.position = {pos.x, 0, pos.y};
    	attributes.forward = {0, 0, 1};
    	attributes.up = {0, 1, 0};
    	fstudio.EventInstance_Set3DAttributes(instance, &attributes);

    	fmod_error_check(fstudio.EventInstance_Release(instance))

    	return { volume, pitch, true, instance }
}

audio_stop :: proc(sound: ^Sound, fade:=true) {
    if sound.instance != nil && sound.playing {
        fstudio.EventInstance_Stop(sound.instance,fade ? .STOP_ALLOWFADEOUT : .STOP_IMMEDIATE)
        sound.instance = nil
        sound.playing = false
    }
}

fmod_error_check :: proc(result: fcore.RESULT, loc:=#caller_location) {
	assert(result == .OK, fcore.error_string(result), loc=loc)
}