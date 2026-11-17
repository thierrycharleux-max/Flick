import 'dart:async';

import 'library_scanner_service.dart';
import 'package:flick/core/utils/dev_log.dart';

/// One quick reconciliation per app launch. Lifecycle and media events do not
/// rescan: the user requested updates only when opening the app.
class MediaStoreObserverService {
  final Stream<ScanProgress> Function() _scanAllFolders;
  final bool Function() _isScanBusy;
  final void Function()? _onLibraryChanged;
  final Duration _startupDelay;
  final Duration _busyRetryDelay;

  Timer? _startupTimer;
  bool _started = false;
  bool _hasScanned = false;

  MediaStoreObserverService({
    Stream<ScanProgress> Function()? scanAllFolders,
    bool Function()? isScanBusy,
    void Function()? onLibraryChanged,
    Duration startupDelay = const Duration(seconds: 2),
    Duration busyRetryDelay = const Duration(seconds: 3),
  }) : _scanAllFolders =
           scanAllFolders ??
           (() => LibraryScannerService().scanAllFolders(sequential: true)),
       _isScanBusy = isScanBusy ?? (() => LibraryScannerService.isScanRunning),
       _onLibraryChanged = onLibraryChanged,
       _startupDelay = startupDelay,
       _busyRetryDelay = busyRetryDelay;

  void start() {
    if (_started) return;
    _started = true;
    if (!_hasScanned) _schedule(_startupDelay);
  }

  void stop() {
    _started = false;
    _startupTimer?.cancel();
    _startupTimer = null;
  }

  // Returning from another app is not a new launch.
  void notifyPaused() {}
  void notifyResumed() {}

  void _schedule(Duration delay) {
    _startupTimer?.cancel();
    _startupTimer = Timer(delay, () => unawaited(_scanOnLaunch()));
  }

  Future<void> _scanOnLaunch() async {
    _startupTimer = null;
    if (!_started || _hasScanned) return;
    if (_isScanBusy()) {
      _schedule(_busyRetryDelay);
      return;
    }
    _hasScanned = true;
    try {
      var changed = false;
      await for (final progress in _scanAllFolders()) {
        changed =
            changed ||
            progress.newSongs > 0 ||
            progress.modifiedSongs > 0 ||
            progress.deletedSongs > 0;
      }
      if (_started && changed) _onLibraryChanged?.call();
      devLog('Launch library quick scan complete');
    } catch (e) {
      devLog('Launch library quick scan failed: $e');
    }
  }
}
