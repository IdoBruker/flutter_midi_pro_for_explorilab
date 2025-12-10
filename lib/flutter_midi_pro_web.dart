// Web implementation using FluidSynth WASM via js-synthesizer for smooth note playback.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_midi_pro_platform_interface.dart';

class FlutterMidiProWeb extends FlutterMidiProPlatform {
  // Flutter serves package assets for the web build under assets/packages/<pkg>/...
  static const _jsAssetBase =
      'assets/packages/flutter_midi_pro/assets/web/js_synthesizer';
  static const _fluidsynthModule = '$_jsAssetBase/libfluidsynth-2.4.6.js';
  static const _synthWorkletModule =
      '$_jsAssetBase/js-synthesizer.worklet.min.js';

  void _log(String message) {
    // debug logging on web to help diagnose worker/worklet failures.
    // ignore: avoid_print
    print('[flutter_midi_pro_web] $message');
  }

  static void registerWith(Registrar registrar) {
    FlutterMidiProPlatform.instance = FlutterMidiProWeb();
    registrar.registerMessageHandler();
  }

  final Map<int, _WebSynth> _synths = {};
  int _nextId = 1;
  web.AudioContext? _audioContext;
  Future<void>? _workletModuleLoader;

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

  Future<void> _ensureWorkletModule(web.AudioContext ctx) {
    final worklet = ctx.audioWorklet;
    _workletModuleLoader ??= () async {
      _log(
          'Loading AudioWorklet modules: $_fluidsynthModule then $_synthWorkletModule');
      await worklet.addModule(_fluidsynthModule).toDart;
      await worklet.addModule(_synthWorkletModule).toDart;
      _log('AudioWorklet modules loaded');
    }();
    return _workletModuleLoader!;
  }

  Future<_WebSynth> _createWorkletSynth(web.AudioContext ctx) async {
    final jsSynth = _jsSynth;
    if (jsSynth == null) {
      throw StateError('JSSynth global not found on window');
    }
    final ctor = jsSynth.audioWorkletNodeSynthesizer;
    if (ctor == null) {
      throw StateError('JSSynth.AudioWorkletNodeSynthesizer not available');
    }
    final synth = AudioWorkletNodeSynthesizer();
    synth.init(ctx.sampleRate.toJS);
    _log('AudioWorkletNodeSynthesizer initialized at ${ctx.sampleRate}');
    final node = synth.createAudioNode(ctx);
    node.connect(ctx.destination);
    _log('AudioWorklet node created and connected');
    return _WebSynth(
      synth: synth,
      node: node,
      ready: Completer<void>()..complete(), // init done immediately
    );
  }

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
    final ctx = await _ensureAudioContext();
    await _ensureWorkletModule(ctx);
    final synth = await _createWorkletSynth(ctx);
    _log(
        'AudioWorklet synth created, loading SoundFont (${data.lengthInBytes} bytes)');
    final loadResult = await synth.synth.loadSFont(data.buffer.toJS).toDart;
    final sfontId = (loadResult as num?)?.toInt() ??
        (throw StateError('loadSFont returned null/undefined'));
    synth.soundfontId = sfontId;
    _log('SoundFont loaded id=$sfontId, selecting programs across channels');
    // Default program selection across all channels to align with native behavior.
    for (var channel = 0; channel < 16; channel++) {
      synth.synth.midiProgramSelect(
        channel.toJS,
        sfontId.toJS,
        bank.toJS,
        program.toJS,
      );
    }

    final id = _nextId++;
    synth.id = id;
    synth.soundfontId = sfontId;
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
    final sfontId = synth?.soundfontId;
    if (synth == null || sfontId == null) return;
    _log(
        'selectInstrument sfId=$sfId channel=$channel bank=$bank program=$program');
    synth.synth.midiProgramSelect(
      channel.toJS,
      sfontId.toJS,
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
    _log('noteOn sfId=$sfId channel=$channel key=$key velocity=$velocity');
    synth.synth.midiNoteOn(channel.toJS, key.toJS, velocity.toJS);
  }

  @override
  Future<void> stopNote(int channel, int key, int sfId) async {
    final synth = _synths[sfId];
    if (synth == null) return;
    _log('noteOff sfId=$sfId channel=$channel key=$key');
    synth.synth.midiNoteOff(channel.toJS, key.toJS);
  }

  @override
  Future<void> stopAllNotes(int sfId) async {
    final synth = _synths[sfId];
    if (synth == null) return;
    _log('stopAllNotes sfId=$sfId');
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
    synth.synth.midiSystemReset();
    synth.synth.unloadSFont(synth.soundfontId?.toJS ?? 0.toJS);
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
    required this.node,
    required this.ready,
    required this.synth,
  });

  int? id;
  final web.AudioWorkletNode node;
  final Completer<void> ready;
  final AudioWorkletNodeSynthesizer synth;
  int? soundfontId;
}

@JS('JSSynth')
external _JSSynth? get _jsSynth;

@JS('JSSynth')
@staticInterop
class _JSSynth {}

extension _JSSynthExt on _JSSynth {
  @JS('AudioWorkletNodeSynthesizer')
  external JSFunction? get audioWorkletNodeSynthesizer;
}

@JS('JSSynth.AudioWorkletNodeSynthesizer')
@staticInterop
class AudioWorkletNodeSynthesizer {
  external factory AudioWorkletNodeSynthesizer();
}

extension AudioWorkletNodeSynthesizerExt on AudioWorkletNodeSynthesizer {
  external void init(JSNumber sampleRate);
  external web.AudioWorkletNode createAudioNode(web.BaseAudioContext context);
  external JSPromise loadSFont(JSArrayBuffer buffer);
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
