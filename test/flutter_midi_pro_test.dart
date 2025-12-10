import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_method_channel.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default instance is MethodChannelFlutterMidiPro', () {
    expect(FlutterMidiProPlatform.instance, isA<MethodChannelFlutterMidiPro>());
  });

  test('MidiPro delegates to platform interface', () async {
    final fake = _FakePlatform();
    FlutterMidiProPlatform.instance = fake;
    final midi = MidiPro();

    final bytes = Uint8List.fromList([1, 2, 3]);
    final sfId = await midi.loadSoundfontData(
      data: bytes,
      bank: 2,
      program: 10,
    );
    expect(sfId, 7);
    expect(fake.loadBytesArgs?.bank, 2);
    expect(fake.loadBytesArgs?.program, 10);
    expect(fake.loadBytesArgs?.bytes, bytes);

    await midi.selectInstrument(sfId: sfId, channel: 3, bank: 4, program: 5);
    expect(fake.selectArgs?.sfId, sfId);
    expect(fake.selectArgs?.channel, 3);
    expect(fake.selectArgs?.bank, 4);
    expect(fake.selectArgs?.program, 5);

    await midi.playNote(channel: 1, key: 60, velocity: 90, sfId: sfId);
    expect(fake.playArgs?.channel, 1);
    expect(fake.playArgs?.key, 60);
    expect(fake.playArgs?.velocity, 90);
    expect(fake.playArgs?.sfId, sfId);

    await midi.stopNote(channel: 1, key: 60, sfId: sfId);
    expect(fake.stopArgs?.channel, 1);
    expect(fake.stopArgs?.key, 60);
    expect(fake.stopArgs?.sfId, sfId);

    await midi.stopAllNotes(sfId: sfId);
    expect(fake.stopAllArgs, sfId);

    await midi.unloadSoundfont(sfId);
    expect(fake.unloadArgs, sfId);

    await midi.dispose();
    expect(fake.disposeCalled, isTrue);
  });
}

class _FakePlatform extends FlutterMidiProPlatform {
  _LoadBytesArgs? loadBytesArgs;
  _SelectArgs? selectArgs;
  _PlayArgs? playArgs;
  _StopArgs? stopArgs;
  int? stopAllArgs;
  int? unloadArgs;
  bool disposeCalled = false;

  @override
  Future<int> loadSoundfont(String path, int bank, int program) {
    return Future.value(6);
  }

  @override
  Future<int> loadSoundfontBytes(Uint8List data, int bank, int program) {
    loadBytesArgs = _LoadBytesArgs(bank: bank, program: program, bytes: data);
    return Future.value(7);
  }

  @override
  Future<void> selectInstrument(
    int sfId,
    int channel,
    int bank,
    int program,
  ) {
    selectArgs = _SelectArgs(
      sfId: sfId,
      channel: channel,
      bank: bank,
      program: program,
    );
    return Future.value();
  }

  @override
  Future<void> playNote(int channel, int key, int velocity, int sfId) {
    playArgs = _PlayArgs(
      channel: channel,
      key: key,
      velocity: velocity,
      sfId: sfId,
    );
    return Future.value();
  }

  @override
  Future<void> stopNote(int channel, int key, int sfId) {
    stopArgs = _StopArgs(channel: channel, key: key, sfId: sfId);
    return Future.value();
  }

  @override
  Future<void> stopAllNotes(int sfId) {
    stopAllArgs = sfId;
    return Future.value();
  }

  @override
  Future<void> unloadSoundfont(int sfId) {
    unloadArgs = sfId;
    return Future.value();
  }

  @override
  Future<void> dispose() {
    disposeCalled = true;
    return Future.value();
  }
}

class _LoadBytesArgs {
  _LoadBytesArgs({
    required this.bank,
    required this.program,
    required this.bytes,
  });

  final int bank;
  final int program;
  final Uint8List bytes;
}

class _SelectArgs {
  _SelectArgs({
    required this.sfId,
    required this.channel,
    required this.bank,
    required this.program,
  });

  final int sfId;
  final int channel;
  final int bank;
  final int program;
}

class _PlayArgs {
  _PlayArgs({
    required this.channel,
    required this.key,
    required this.velocity,
    required this.sfId,
  });

  final int channel;
  final int key;
  final int velocity;
  final int sfId;
}

class _StopArgs {
  _StopArgs({
    required this.channel,
    required this.key,
    required this.sfId,
  });

  final int channel;
  final int key;
  final int sfId;
}
