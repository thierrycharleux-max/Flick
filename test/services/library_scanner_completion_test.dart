import 'dart:async';

import 'package:flick/services/library_scanner_service.dart';
import 'package:flick/services/scan_operation_gate.dart';
import 'package:test/test.dart';

void main() {
  test('breaking at isComplete keeps artwork Skip reachable', () async {
    final gate = ScanOperationGate();
    final finishArtwork = Completer<void>();
    var interruptions = 0;
    var nextScanStarted = false;
    final stream = gate.runStream(
      () => forwardScanProgress(
        source: Stream.value(
          ScanProgress(songsFound: 1, totalFiles: 1, isComplete: true),
        ),
        onInterrupted: () => interruptions++,
      ),
      afterOperation: () => finishArtwork.future,
    );

    Future<void> consumeLikeManualScan() async {
      await for (final progress in stream) {
        if (progress.isComplete) break;
      }
    }

    try {
      // The manual UI must reach its artwork/Skip stage while work remains.
      await consumeLikeManualScan().timeout(const Duration(seconds: 1));
      expect(interruptions, 0);
      expect(finishArtwork.isCompleted, isFalse);
      final nextScan = gate.run(() async {
        nextScanStarted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(nextScanStarted, isFalse);
      finishArtwork.complete();
      await nextScan;
      expect(nextScanStarted, isTrue);
    } finally {
      if (!finishArtwork.isCompleted) finishArtwork.complete();
    }
  });

  test('breaking before completion still interrupts the scan', () async {
    var interruptions = 0;
    await for (final _ in forwardScanProgress(
      source: Stream.value(ScanProgress(songsFound: 0, totalFiles: 1)),
      onInterrupted: () => interruptions++,
    )) {
      break;
    }
    expect(interruptions, 1);
  });
}
