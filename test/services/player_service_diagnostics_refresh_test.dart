import 'dart:async';

import 'package:flick/models/audio_engine_type.dart';
import 'package:flick/services/player_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ExoPlayer skips native Rust diagnostics while Rust retains them',
    (tester) async {
      const channel = MethodChannel('com.mossapps.flick/uac2');
      final calls = <String>[];
      const nativeState = <String, dynamic>{
        'audioFocusHeld': false,
        'rustAudioStateJson': '{"engine":{"manager_engine":"rust"}}',
      };
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return nativeState;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      Future<Map<String, dynamic>?> readNativeState() =>
          channel.invokeMapMethod<String, dynamic>('getDirectUsbDiagnostics');

      expect(
        await loadAudioOutputDebugState(
          activeEngine: AudioEngineType.normalAndroid,
          readNativeState: readNativeState,
        ),
        isNull,
      );
      expect(calls, isEmpty);

      expect(
        await loadAudioOutputDebugState(
          activeEngine: AudioEngineType.rustOboe,
          readNativeState: readNativeState,
        ),
        nativeState,
      );
      expect(calls, ['getDirectUsbDiagnostics']);
    },
  );

  testWidgets('continuous progress does not starve diagnostics refresh', (
    tester,
  ) async {
    Timer? pending;
    var latestTick = 0;
    final snapshots = <int>[];

    for (var tick = 1; tick <= 12; tick++) {
      latestTick = tick;
      pending = coalescePlaybackDiagnosticsRefresh(
        pending: pending,
        interval: const Duration(milliseconds: 300),
        refresh: () {
          pending = null;
          snapshots.add(latestTick);
        },
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    pending?.cancel();
    expect(snapshots, [6, 12]);
  });

  testWidgets('a cancelled diagnostics deadline can be replaced', (
    tester,
  ) async {
    var oldRefreshes = 0;
    var newRefreshes = 0;
    final cancelled = coalescePlaybackDiagnosticsRefresh(
      pending: null,
      interval: const Duration(milliseconds: 300),
      refresh: () => oldRefreshes++,
    );
    cancelled.cancel();
    final replacement = coalescePlaybackDiagnosticsRefresh(
      pending: cancelled,
      interval: const Duration(milliseconds: 300),
      refresh: () => newRefreshes++,
    );

    await tester.pump(const Duration(milliseconds: 300));
    replacement.cancel();
    expect(identical(cancelled, replacement), isFalse);
    expect(oldRefreshes, 0);
    expect(newRefreshes, 1);
  });
}
