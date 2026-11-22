import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/models/audio_engine_type.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/rust_audio_engine.dart';
import 'package:flick/services/rust_audio_service.dart';

class _Rust extends Fake implements RustAudioService {
  @override
  final stateNotifier = ValueNotifier(RustPlaybackState.idle);
  @override
  final positionNotifier = ValueNotifier(Duration.zero);
  @override
  final durationNotifier = ValueNotifier(const Duration(minutes: 3));
  @override
  final bufferLevelNotifier = ValueNotifier(0.0);
  @override
  final volumeNotifier = ValueNotifier(0.35);
  final gains = <double>[];
  final events = <String>[];
  double gain = 1;
  bool bufferStart = false;
  bool sourceReady = true;
  @override
  bool get isPlaybackSourceReady => sourceReady;
  int failedGainWrites = 0;
  @override
  Future<void> setPlaybackGain(double value) async {
    if (failedGainWrites > 0) {
      failedGainWrites--;
      throw StateError('gain unavailable');
    }
    gain = value;
    gains.add(value);
  }

  @override
  Future<void> play(String path, {double? startSecs, double? endSecs}) async {
    events.add('play:$path:$gain');
    stateNotifier.value = bufferStart
        ? RustPlaybackState.buffering
        : RustPlaybackState.playing;
  }

  @override
  Future<void> pause() async {
    events.add('pause:$gain');
    stateNotifier.value = RustPlaybackState.paused;
  }

  @override
  Future<void> resume() async {
    events.add('resume:$gain');
    stateNotifier.value = RustPlaybackState.playing;
  }

  @override
  Future<void> stop() async {
    stateNotifier.value = RustPlaybackState.stopped;
  }

  @override
  Future<void> seek(Duration position) async {
    positionNotifier.value = position;
  }
}

Song _song(int id) => Song(
  id: '$id',
  title: 'Title $id',
  artist: 'Artist',
  filePath: '/track-$id.flac',
  fileType: 'FLAC',
  duration: const Duration(minutes: 3),
);

Future<void> _fullGain(_Rust service) async {
  for (var i = 0; i < 50 && service.gain != 1; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(service.gain, 1);
}

void main() {
  late _Rust service;
  late RustAudioEngine engine;
  setUp(() {
    service = _Rust();
    engine = RustAudioEngine(
      playbackMode: AudioEngineType.rustOboe,
      rustAudioService: service,
      ensureInitialized: () async {},
      resolvePlaybackPath: (song) async => song.filePath,
      disposeEngine: () => service.stop(),
    );
  });
  tearDown(() async {
    await engine.dispose();
    service.stateNotifier.dispose();
    service.positionNotifier.dispose();
    service.durationNotifier.dispose();
    service.bufferLevelNotifier.dispose();
    service.volumeNotifier.dispose();
  });

  test(
    'high-quality pause fades native gain before pausing and resumes smoothly',
    () async {
      await engine.load(_song(1));
      await engine.play();
      await _fullGain(service);
      service.gains.clear();
      await engine.pause();
      expect(service.events.last, 'pause:0.0');
      expect(service.gains.where((g) => g > 0 && g < 1), isNotEmpty);
      for (var i = 1; i < service.gains.length; i++) {
        expect(service.gains[i], lessThanOrEqualTo(service.gains[i - 1]));
      }
      expect(service.volumeNotifier.value, 0.35);
      await engine.play();
      await _fullGain(service);
      expect(service.events.last, 'resume:0.0');
      expect(service.volumeNotifier.value, 0.35);
    },
  );

  test(
    'next fades the old title and waits for audio readiness to fade in',
    () async {
      await engine.load(_song(1));
      await engine.play();
      await _fullGain(service);
      await engine.load(_song(2));
      expect(service.events.last, 'pause:0.0');
      service.bufferStart = true;
      await engine.play().timeout(const Duration(seconds: 1));
      expect(service.events.last, 'play:/track-2.flac:0.0');
      // A slow SD/decoder must not consume the whole ramp in silence, or block
      // the command queue until it becomes ready.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(service.gain, 0);
      service.stateNotifier.value = RustPlaybackState.playing;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.gain, greaterThan(0));
      expect(service.gain, lessThan(1));
      await _fullGain(service);
    },
  );

  test('a stale Playing event cannot consume the new source fade-in', () async {
    service.sourceReady = false;
    await engine.load(_song(1));
    await engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(service.gain, 0);
    service.sourceReady = true;
    // A source may become ready without another state transition.
    service.positionNotifier.value = const Duration(milliseconds: 20);
    await _fullGain(service);
  });

  test('pausing a buffering title cancels its deferred fade-in', () async {
    service.bufferStart = true;
    await engine.load(_song(1));
    await engine.play();
    await engine.pause();
    service.stateNotifier.value = RustPlaybackState.playing;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(service.gain, 0);
    expect(service.events.last, 'pause:0.0');
  });

  test('stop cancels an in-flight gain ramp', () async {
    await engine.load(_song(1));
    await engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await engine.stop();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(service.gain, 0);
    expect(service.stateNotifier.value, RustPlaybackState.stopped);
  });

  test('disposing the engine cancels all subsequent ramp writes', () async {
    await engine.load(_song(1));
    await engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await engine.dispose();
    final count = service.gains.length;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(service.gains.length, count);
    expect(service.stateNotifier.value, RustPlaybackState.stopped);
    await expectLater(engine.play(), throwsStateError);
  });

  test('a gain API error never prevents pausing the native player', () async {
    await engine.load(_song(1));
    await engine.play();
    await _fullGain(service);
    service.failedGainWrites = 2;
    await engine.pause();
    expect(service.stateNotifier.value, RustPlaybackState.paused);
  });

  test(
    'changing the chosen volume during a ramp is never overwritten',
    () async {
      await engine.load(_song(1));
      await engine.play();
      service.volumeNotifier.value = 0;
      await _fullGain(service);
      await engine.pause();
      await engine.play();
      await _fullGain(service);
      expect(service.volumeNotifier.value, 0);
    },
  );
}
