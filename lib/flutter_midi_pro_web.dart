// Web implementation using FluidSynth WASM via js-synthesizer for smooth note playback.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_midi_pro_platform_interface.dart';

class FlutterMidiProWeb extends FlutterMidiProPlatform {
  // Flutter serves package assets for the web build under assets/packages/<pkg>/...
  static const _jsAssetBase =
      'assets/packages/flutter_midi_pro/assets/web/js_synthesizer';

  void _log(String message) {
    // debugPrint keeps logs concise and is dropped in release.
    debugPrint('[flutter_midi_pro_web] $message');
  }

  static void registerWith(Registrar registrar) {
    FlutterMidiProPlatform.instance = FlutterMidiProWeb();
    registrar.registerMessageHandler();
  }

  final Map<int, _WebSynth> _synths = {};
  int _nextId = 1;
  Future<void>? _loader;
  web.AudioContext? _audioContext;

  Future<void> _ensureLibrariesLoaded() {
    _loader ??= _loadLibraries();
    return _loader!;
  }

  Future<void> _loadLibraries() async {
    // Scripts are expected to be preloaded in web/index.html.
    final jsSynth = _jsSynth;
    if (jsSynth == null) {
      _log('JSSynth global is null.');
      throw StateError(
        'JSSynth not found. Ensure web/index.html preloads '
        '$_jsAssetBase/libfluidsynth-2.4.6.js and js-synthesizer.min.js.',
      );
    }
    _log('JSSynth found, waiting for ready.');
    await jsSynth.waitForReady().toDart;
    _log('JSSynth is ready.');
  }

  Future<web.AudioContext> _ensureAudioContext() async {
    if (_audioContext != null) {
      return _audioContext!;
    }
    final ctx = web.AudioContext();
    try {
      await ctx.resume().toDart;
    } catch (_) {
      // Some browsers require user gesture; we'll retry on first playback.
    }
    _audioContext = ctx;
    return ctx;
  }

  JSSynth? get _jsSynth => _jsSynthGlobal;

  @override
  Future<int> loadSoundfont(String assetPath, int bank, int program) async {
    final byteData = await rootBundle.load(assetPath);
    final data = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return loadSoundfontBytes(data, bank, program);
  }

  @override
  Future<int> loadSoundfontBytes(Uint8List data, int bank, int program) async {
    await _ensureLibrariesLoaded();
    final ctx = await _ensureAudioContext();
    final jsSynth = _jsSynth;
    if (jsSynth == null) {
      _log('JSSynth is null inside loadSoundfontBytes.');
      throw StateError('JSSynth is not available after script load.');
    }
    final synthCtor = jsSynth.synthesizer;
    if (synthCtor == null) {
      _log('JSSynth.Synthesizer is null.');
      throw StateError(
        'JSSynth.Synthesizer not found. Confirm scripts load order: '
        'libfluidsynth-2.4.6.js then js-synthesizer.min.js.',
      );
    }
    _log('Found synthesizer constructor on JSSynth.');
    final synthInstance = Synthesizer();
    _log('Synthesizer constructed. Starting init.');
    final synthObj = synthInstance;
    final initOptions = SynthInitOptions(
      // Lower gain to reduce clipping artifacts in browsers.
      initialGain: 0.45.toJS,
      // Lower polyphony to ease CPU and reduce voice stealing.
      polyphony: 32.toJS,
      midiChannelCount: 16.toJS,
    );
    _log(
      'Calling init(sampleRate=${ctx.sampleRate}) with gain=${0.8}, '
      'polyphony=64, midiChannels=16.',
    );
    synthObj.init(ctx.sampleRate.toJS, initOptions);
    _log(
        'Synthesizer init done; loading SoundFont bytes (${data.length} bytes).');
    final loadResult = await synthObj.loadSFont(data.buffer.toJS).toDart;
    final int sfontId = (loadResult as num?)?.toInt() ??
        (throw StateError('loadSFont returned null/undefined'));
    _log('SoundFont loaded with id $sfontId; creating audio node.');
    final node = synthObj.createAudioNode(
      ctx,
      // Larger buffer helps avoid underruns/metallic artifacts on web.
      2048.toJS,
    );
    if (node == null) {
      _log('createAudioNode returned null.');
      throw StateError('createAudioNode returned null/undefined');
    }
    _log('Audio node created; connecting to destination.');
    node.connect(ctx.destination);
    // Match native behavior by selecting program on all 16 channels.
    _log('Selecting bank=$bank program=$program on all 16 channels.');
    for (var channel = 0; channel < 16; channel++) {
      synthObj.midiProgramSelect(
        channel.toJS,
        sfontId.toJS,
        bank.toJS,
        program.toJS,
      );
    }
    _log('Program selection done; storing synth instance.');
    final synth = _WebSynth(
      synth: synthObj,
      node: node,
      soundfontId: sfontId,
    );
    final id = _nextId++;
    _synths[id] = synth;
    return id;
  }

  @override
  Future<void> selectInstrument(
    int sfId,
    int channel,
    int bank,
    int program,
  ) async {
    final synth = _synths[sfId];
    if (synth == null) return;
    synth.synth.midiProgramSelect(
      channel.toJS,
      synth.soundfontId.toJS,
      bank.toJS,
      program.toJS,
    );
  }

  @override
  Future<void> playNote(int channel, int key, int velocity, int sfId) async {
    final synth = _synths[sfId];
    if (synth == null) return;
    if (_audioContext != null) {
      try {
        await _audioContext!.resume().toDart;
      } catch (_) {
        // ignore
      }
    }
    synth.synth.midiNoteOn(channel.toJS, key.toJS, velocity.toJS);
  }

  @override
  Future<void> stopNote(int channel, int key, int sfId) async {
    final synth = _synths[sfId];
    if (synth == null) return;
    synth.synth.midiNoteOff(channel.toJS, key.toJS);
  }

  @override
  Future<void> stopAllNotes(int sfId) async {
    final synth = _synths[sfId];
    if (synth == null) return;
    for (var channel = 0; channel < 16; channel++) {
      synth.synth.midiAllNotesOff(channel.toJS);
      synth.synth.midiAllSoundsOff(channel.toJS);
    }
    synth.synth.midiSystemReset();
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {
    final synth = _synths.remove(sfId);
    if (synth == null) return;
    for (var channel = 0; channel < 16; channel++) {
      synth.synth.midiAllSoundsOff(channel.toJS);
      synth.synth.midiAllNotesOff(channel.toJS);
    }
    synth.synth.midiSystemReset();
    synth.synth.unloadSFont(synth.soundfontId.toJS);
    synth.node.disconnect();
    synth.synth.close();
  }

  @override
  Future<void> dispose() async {
    final ids = List<int>.from(_synths.keys);
    for (final id in ids) {
      await unloadSoundfont(id);
    }
    _synths.clear();
  }
}

class _WebSynth {
  _WebSynth({
    required this.synth,
    required this.node,
    required this.soundfontId,
  });

  final Synthesizer synth;
  final web.AudioNode node;
  final int soundfontId;
}

@JS('JSSynth')
external JSSynth? get _jsSynthGlobal;

@JS('JSSynth')
@staticInterop
class JSSynth {}

extension JSSynthExt on JSSynth {
  external JSPromise waitForReady();
  @JS('Synthesizer')
  external JSFunction? get synthesizer;
}

@JS('JSSynth.Synthesizer')
@staticInterop
class Synthesizer {
  external factory Synthesizer();
}

extension SynthesizerExt on Synthesizer {
  external void init(JSAny sampleRate, SynthInitOptions options);
  external JSPromise loadSFont(JSArrayBuffer buffer);
  external web.AudioNode? createAudioNode(
    web.BaseAudioContext context,
    JSAny bufferSize,
  );
  external void midiProgramSelect(
    JSAny channel,
    JSAny sfontId,
    JSAny bank,
    JSAny program,
  );
  external void midiNoteOn(JSAny channel, JSAny key, JSAny velocity);
  external void midiNoteOff(JSAny channel, JSAny key);
  external void midiAllNotesOff(JSAny channel);
  external void midiAllSoundsOff(JSAny channel);
  external void midiSystemReset();
  external void unloadSFont(JSAny sfontId);
  external void close();
}

@JS()
@anonymous
@staticInterop
class SynthInitOptions {
  external factory SynthInitOptions({
    JSAny? initialGain,
    JSAny? polyphony,
    JSAny? midiChannelCount,
  });
}
