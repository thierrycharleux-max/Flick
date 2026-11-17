import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/android_audio_engine.dart';
import 'package:flick/services/app_preferences_service.dart';

class _Player extends Fake implements ja.AudioPlayer {
  final samples = <double>[];
  final events = <String>[];
  final positions = StreamController<Duration>.broadcast();
  final states = StreamController<ja.PlayerState>.broadcast();
  final playbacks = <Completer<void>>[];
  bool _playing = false;
  double _volume = 1;
  int volumeFailuresRemaining = 0;
  @override
  bool get playing => _playing;
  @override
  double get volume => _volume;
  @override
  double get speed => 1;
  @override
  Duration get duration => const Duration(seconds: 5);
  @override
  Duration get position => Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  int get currentIndex => 0;
  @override
  List<ja.IndexedAudioSource> get sequence => [];
  @override
  Stream<ja.PlayerState> get playerStateStream => states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<ja.PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<ja.SequenceState> get sequenceStateStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<ja.ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Stream<ja.PlayerException> get errorStream => const Stream.empty();
  @override
  Future<void> setVolume(double v) async {
    if (volumeFailuresRemaining > 0) {
      volumeFailuresRemaining--;
      throw StateError('Volume channel interrupted');
    }
    _volume = v;
    samples.add(v);
  }

  @override
  Future<void> setLoopMode(ja.LoopMode mode) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<Duration?> setAudioSource(
    ja.AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    events.add('load:$volume');
    return duration;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}
  @override
  Future<void> play() {
    events.add('play:$volume');
    _playing = true;
    states.add(ja.PlayerState(true, ja.ProcessingState.ready));
    final result = Completer<void>();
    playbacks.add(result);
    // Deliberately pending until pause/stop: ExoPlayer's play future does NOT
    // resolve when audio starts. A fade must not await the end of the track.
    return result.future;
  }

  @override
  Future<void> pause() async {
    events.add('pause:$volume');
    _playing = false;
    states.add(ja.PlayerState(false, ja.ProcessingState.ready));
    for (final playback in playbacks) {
      if (!playback.isCompleted) playback.complete();
    }
  }

  @override
  Future<void> stop() => pause();
  @override
  Future<void> dispose() async {
    if (states.isClosed) return;
    await pause();
    await positions.close();
    await states.close();
  }
}

final _songs = List.generate(
  2,
  (i) => Song(
    id: 'track-$i',
    title: 'Title $i',
    artist: 'Artist',
    fileType: 'WAV',
    filePath: '/test-$i.wav',
    duration: const Duration(seconds: 5),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Player primary;
  late _Player secondary;
  late AndroidAudioEngine engine;
  var advanced = 0;
  Completer<ja.AudioSource>? pendingNext;
  setUp(() {
    primary = _Player();
    secondary = _Player();
    advanced = 0;
    pendingNext = null;
    engine = AndroidAudioEngine(
      playerProvider: () async => primary,
      secondaryPlayerProvider: () async => secondary,
      sourcesBuilder: () async => ja.AudioSource.file('/test-0.wav'),
      sourceBuilder: (song) async => song.id == 'track-1' && pendingNext != null
          ? await pendingNext!.future
          : ja.AudioSource.file(song.filePath!),
      playlistProvider: () => _songs,
      configurePlayer: (_) => engine.setOutputVolume(0.4),
      disposeEngine: () async {
        await primary.dispose();
        await secondary.dispose();
      },
      shouldSuppressTrackSync: () => false,
      shouldIgnoreTrack: (_) => false,
      shouldFastStartCurrentTrackOnly: () => true,
      crossfadeConfigProvider: () => const AndroidCrossfadeConfig(
        enabled: true,
        durationSecs: 0.6,
        curve: AndroidCrossfadeCurve.equalPower,
      ),
      onNextSong: () => _songs[1],
      onTrackAdvanced: (_) => advanced++,
    );
  });
  tearDown(() => engine.dispose());

  test(
    'pause reaches zero before pausing; resume restores chosen level',
    () async {
      await engine.load(_songs[0]);
      await engine.play().timeout(const Duration(seconds: 2));
      primary.samples.clear();
      primary.events.clear();
      await engine.pause();
      expect(primary.events.last, 'pause:0.0');
      expect(primary.samples.where((v) => v > 0 && v < 0.4), isNotEmpty);
      expect(primary.volume, 0);
      expect(primary.playing, false);
      primary.events.clear();
      await engine.play().timeout(const Duration(seconds: 2));
      expect(primary.events.first, 'play:0.0');
      expect(primary.volume, closeTo(0.4, 1e-9));
      expect(primary.playing, true);
    },
  );

  test(
    'manual change loads silently then fades in without a full-volume burst',
    () async {
      await engine.load(_songs[0]);
      await engine.play();
      primary.samples.clear();
      primary.events.clear();
      await engine.load(_songs[1]);
      expect(primary.events, contains('load:0.0'));
      expect(primary.playing, false);
      expect(primary.volume, 0);
      await engine.play();
      expect(primary.samples.every((v) => v >= 0 && v <= 0.4), true);
      expect(primary.volume, closeTo(0.4, 1e-9));
    },
  );

  test('zero volume stays silent, including automatic crossfade', () async {
    await engine.load(_songs[0]);
    await engine.setOutputVolume(0);
    await engine.play();
    primary.samples.clear();
    secondary.samples.clear();
    primary.positions.add(const Duration(milliseconds: 4500));
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(advanced, 1);
    expect(primary.samples.every((v) => v == 0), true);
    expect(secondary.samples.every((v) => v == 0), true);
  });

  test('pause cancels a successor still being prepared', () async {
    await engine.load(_songs[0]);
    await engine.play();
    pendingNext = Completer<ja.AudioSource>();
    primary.positions.add(const Duration(milliseconds: 4500));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await engine.pause();
    pendingNext!.complete(ja.AudioSource.file('/test-1.wav'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(advanced, 0);
    expect(primary.playing, false);
    expect(secondary.playing, false);
    expect(secondary.events.where((e) => e.startsWith('play:')), isEmpty);
  });

  test(
    'pause during crossfade silences both players; resume keeps incoming title',
    () async {
      await engine.load(_songs[0]);
      await engine.play();
      primary.positions.add(const Duration(milliseconds: 4500));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(advanced, 1);
      await engine.pause();
      expect(primary.playing, false);
      expect(secondary.playing, false);
      expect(primary.volume, 0);
      expect(secondary.volume, 0);
      await engine.play().timeout(const Duration(seconds: 2));
      expect(identical(engine.activePlayer, secondary), true);
      expect(primary.playing, false);
      expect(secondary.playing, true);
      expect(secondary.volume, closeTo(0.4, 1e-9));
    },
  );

  test(
    'volume changes during a fade set the final level without being overwritten',
    () async {
      await engine.load(_songs[0]);
      final playing = engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await engine.setOutputVolume(0.15);
      await playing;
      expect(primary.volume, closeTo(0.15, 1e-9));
      await engine.pause();
      await engine.play();
      expect(primary.volume, closeTo(0.15, 1e-9));
    },
  );

  test('stop cancels an in-flight resume without later sound', () async {
    await engine.load(_songs[0]);
    final playing = engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await engine.stop();
    await playing;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(primary.playing, false);
    expect(primary.volume, 0);
  });

  test('a failed ramp write does not prevent pausing', () async {
    await engine.load(_songs[0]);
    await engine.play();
    primary.volumeFailuresRemaining = 1;
    await engine.pause();
    expect(primary.playing, false);
    expect(primary.volume, 0);
    await engine.play();
    expect(primary.volume, closeTo(0.4, 1e-9));
  });

  test('disposal cancels a ramp and rejects later playback', () async {
    await engine.load(_songs[0]);
    final playing = engine.play();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await engine.dispose();
    final writes = primary.samples.length;
    await playing;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(primary.samples.length, writes);
    expect(primary.playing, false);
    await expectLater(engine.play(), throwsStateError);
  });

  test(
    'short automatic crossfade is the default but saved settings survive',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPreferencesService();
      expect(await prefs.getCrossfadeEnabled(), true);
      expect(await prefs.getCrossfadeDurationSecs(), 0.6);
      await prefs.setCrossfadeEnabled(false);
      await prefs.setCrossfadeDurationSecs(3);
      expect(await prefs.getCrossfadeEnabled(), false);
      expect(await prefs.getCrossfadeDurationSecs(), 3);
    },
  );
}
