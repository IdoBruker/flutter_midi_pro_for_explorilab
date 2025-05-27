#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <map>
#include <android/log.h>

std::map<int, fluid_synth_t*> synths = {};
std::map<int, fluid_audio_driver_t*> drivers = {};
std::map<int, fluid_settings_t*> settings = {};
std::map<int, int> soundfonts = {};
int nextSfId = 1;

void fluid_log_callback(int level, const char* message, void* data) {
    __android_log_print(ANDROID_LOG_ERROR, "FluidSynth", "%s", message);
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env, jclass clazz, jstring path, jint bank, jint program) {
    settings[nextSfId] = new_fluid_settings();

    char *driver = nullptr;
    if (fluid_settings_getstr_default(settings[nextSfId], "audio.driver", &driver)) {
        __android_log_print(ANDROID_LOG_INFO, "FluidSynth", "Audio driver in use: %s", driver);
    } else {
        __android_log_print(ANDROID_LOG_ERROR, "FluidSynth", "Failed to get audio.driver");
    }

    fluid_settings_setnum(settings[nextSfId], "synth.gain", 1.0);
    fluid_settings_setint(settings[nextSfId], "audio.period-size", 64);
    fluid_settings_setint(settings[nextSfId], "audio.periods", 4);
//    fluid_settings_setint(settings[nextSfId], "audio.realtime-prio", 99);
    fluid_settings_setnum(settings[nextSfId], "synth.sample-rate", 44100.0);
    fluid_settings_setint(settings[nextSfId], "synth.polyphony", 32);

    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    fluid_set_log_function(FLUID_PANIC, fluid_log_callback, nullptr);
    fluid_set_log_function(FLUID_ERR, fluid_log_callback, nullptr);
    fluid_set_log_function(FLUID_WARN, fluid_log_callback, nullptr);
    fluid_set_log_function(FLUID_INFO, fluid_log_callback, nullptr);
    fluid_set_log_function(FLUID_DBG, fluid_log_callback, nullptr);

    synths[nextSfId] = new_fluid_synth(settings[nextSfId]);
    drivers[nextSfId] = new_fluid_audio_driver(settings[nextSfId], synths[nextSfId]);

    __android_log_print(ANDROID_LOG_DEBUG, "FluidSynth", "Trying to load soundfont at: %s", nativePath);

    FILE* file = fopen(nativePath, "rb");
    if (!file) {
        __android_log_print(ANDROID_LOG_ERROR, "FluidSynth", "Soundfont file not found or cannot be opened: %s", nativePath);
    } else {
        __android_log_print(ANDROID_LOG_DEBUG, "FluidSynth", "Soundfont file found and readable: %s", nativePath);
        fclose(file);
    }

    int sfId = fluid_synth_sfload(synths[nextSfId], nativePath, 0);
    __android_log_print(ANDROID_LOG_ERROR, "FluidSynth", "sfload() returned: %d", sfId);

    if (sfId == -1) {
        __android_log_print(ANDROID_LOG_ERROR, "FluidSynth", "Failed to load soundfont at path: %s", nativePath);
    } else {
        __android_log_print(ANDROID_LOG_ERROR, "FluidSynth", "loaded soundfont with id: %d", sfId);
    }

    for (int i = 0; i < 16; i++) {
        fluid_synth_program_select(synths[nextSfId], i, sfId, bank, program);
    }

    __android_log_print(ANDROID_LOG_ERROR, "FluidSynth", "selected programs for soundfontId: %d", sfId);

    env->ReleaseStringUTFChars(path, nativePath);
    soundfonts[nextSfId] = sfId;
    nextSfId++;
    return nextSfId - 1;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint bank, jint program) {
    fluid_synth_program_select(synths[sfId], channel, soundfonts[sfId], bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint velocity, jint sfId) {
    fluid_synth_noteon(synths[sfId], channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint sfId) {
    fluid_synth_noteoff(synths[sfId], channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopAllNotes(JNIEnv* env, jclass clazz, jint sfId) {
    fluid_synth_all_notes_off(synths[sfId], -1);
    fluid_synth_system_reset(synths[sfId]);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(JNIEnv* env, jclass clazz, jint sfId) {
    delete_fluid_audio_driver(drivers[sfId]);
    delete_fluid_synth(synths[sfId]);
    synths.erase(sfId);
    drivers.erase(sfId);
    soundfonts.erase(sfId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(JNIEnv* env, jclass clazz) {
    for (auto const& x : synths) {
        delete_fluid_audio_driver(drivers[x.first]);
        delete_fluid_synth(synths[x.first]);
        delete_fluid_settings(settings[x.first]);
    }
    synths.clear();
    drivers.clear();
    soundfonts.clear();
}