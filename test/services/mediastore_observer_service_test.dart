import 'dart:async';

import 'package:flick/services/library_scanner_service.dart';
import 'package:flick/services/mediastore_observer_service.dart';
import 'package:test/test.dart';

void main() {
  late int scanCalls;
  late int libraryChanges;
  late bool scannerBusy;

  setUp(() {
    scanCalls = 0;
    libraryChanges = 0;
    scannerBusy = false;
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 25));

  MediaStoreObserverService makeService({
    Stream<ScanProgress> Function()? scan,
  }) {
    final service = MediaStoreObserverService(
      scanAllFolders:
          scan ??
          () async* {
            scanCalls++;
            yield ScanProgress(
              songsFound: 1,
              totalFiles: 1,
              newSongs: 1,
              isComplete: true,
            );
          },
      isScanBusy: () => scannerBusy,
      onLibraryChanged: () => libraryChanges++,
      startupDelay: const Duration(milliseconds: 5),
      busyRetryDelay: const Duration(milliseconds: 5),
    );
    addTearDown(service.stop);
    return service;
  }

  test(
    'launch schedules one quick scan and publishes library changes',
    () async {
      final service = makeService()..start();
      service.start();
      await settle();
      expect(scanCalls, 1);
      expect(libraryChanges, 1);
    },
  );

  test('returning to foreground never requests another scan', () async {
    final service = makeService()..start();
    await settle();
    for (var i = 0; i < 10; i++) {
      service.notifyPaused();
      service.notifyResumed();
    }
    await settle();
    expect(scanCalls, 1);
  });

  test('a running manual scan postpones the single launch scan', () async {
    scannerBusy = true;
    makeService().start();
    await settle();
    expect(scanCalls, 0);
    scannerBusy = false;
    await settle();
    expect(scanCalls, 1);
    await settle();
    expect(scanCalls, 1);
  });

  test('stop cancels a launch scan that has not started', () async {
    final service = makeService()..start();
    service.stop();
    await settle();
    expect(scanCalls, 0);
  });

  test(
    'restarting the same service does not repeat a completed launch scan',
    () async {
      final service = makeService()..start();
      await settle();
      service.stop();
      service.start();
      await settle();
      expect(scanCalls, 1);
    },
  );

  test('unchanged scans do not invalidate the library', () async {
    makeService(
      scan: () async* {
        scanCalls++;
        yield ScanProgress(songsFound: 1, totalFiles: 1, isComplete: true);
      },
    ).start();
    await settle();
    expect(scanCalls, 1);
    expect(libraryChanges, 0);
  });
}
