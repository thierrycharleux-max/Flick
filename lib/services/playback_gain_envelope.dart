import 'dart:async';

/// A short, cancellable gain envelope, independent of the user's volume.
/// Writes are awaited so a slow platform channel cannot accumulate ramps.
class PlaybackGainEnvelope {
  PlaybackGainEnvelope({required this.applyGain});

  final Future<void> Function(double gain) applyGain;
  double get gain => _gain;
  double _gain = 1;
  int _generation = 0;

  void cancel() => _generation++;

  Future<void> jumpTo(double value) async {
    cancel();
    _gain = value.clamp(0.0, 1.0).toDouble();
    await applyGain(_gain);
  }

  Future<void> fadeTo(double target, Duration duration) async {
    final generation = ++_generation;
    final start = _gain;
    final end = target.clamp(0.0, 1.0).toDouble();
    if (duration <= Duration.zero || start == end) {
      _gain = end;
      await applyGain(_gain);
      return;
    }
    const tick = Duration(milliseconds: 20);
    final steps = (duration.inMicroseconds / tick.inMicroseconds).ceil();
    for (var step = 1; step <= steps; step++) {
      await Future<void>.delayed(tick);
      if (_generation != generation) return;
      final p = step / steps;
      // Smoothstep has no sudden slope at either end of a pause/resume.
      final eased = p * p * (3 - 2 * p);
      _gain = start + (end - start) * eased;
      await applyGain(_gain);
      if (_generation != generation) return;
    }
  }
}
