import 'package:flick/models/audio_engine_type.dart';
import 'package:flick/services/android_audio_device_service.dart';
import 'package:flick/services/audio_session_manager.dart';
import 'package:flick/services/uac2_preferences_service.dart';
import 'package:flick/services/uac2_service.dart';
import 'package:flick/src/rust/api/audio_api.dart' as rust_audio;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeviceService extends Fake implements AndroidAudioDeviceService {
  _DeviceService(AndroidPlaybackDeviceInfo info)
    : deviceInfoNotifier = ValueNotifier(info);

  @override
  final ValueNotifier<AndroidPlaybackDeviceInfo> deviceInfoNotifier;

  @override
  Future<void> initialize() async {}

  @override
  Future<AndroidPlaybackDeviceInfo> refresh() async => deviceInfoNotifier.value;
}

class _Preferences extends Fake implements Uac2PreferencesService {
  @override
  Future<void> initializeDeveloperModeCache() async {}

  @override
  Future<void> initializeKillIsochronousUsbOnQuitCache() async {}

  @override
  Future<void> initialize432HzTuningCache() async {}

  @override
  Future<void> initializeBtFlagsCache() async {}

  @override
  Future<bool> getBitPerfectEnabled() async => false;

  @override
  Future<bool> getDapBitPerfectEnabled() async => false;

  @override
  Future<AudioEnginePreference> getAudioEnginePreference() async =>
      AudioEnginePreference.exoPlayer;
}

class _Uac2 extends Fake implements Uac2Service {
  int debugReads = 0;

  @override
  bool get shouldFreezeAndroidDirectUsbSessionQueries => false;

  @override
  Future<rust_audio.AudioCapabilityInfo>
  getAndroidAudioCapabilityInfo() async => const rust_audio.AudioCapabilityInfo(
    capabilities: [rust_audio.AudioCapabilityType.standard],
    routeType: 'internal',
    routeLabel: 'Built-in output',
    maxSampleRate: 48000,
  );

  @override
  Future<Map<String, dynamic>?> getAndroidPlaybackDebugState() async {
    debugReads++;
    return {
      'rustAudioState': {
        'device_profile': {
          'kind': {'Dap': 'Sony'},
        },
      },
    };
  }
}

void main() {
  Future<({AudioEngineType mode, int debugReads})> resolve(
    AndroidPlaybackDeviceInfo info,
  ) async {
    final device = _DeviceService(info);
    final uac2 = _Uac2();
    final manager = AudioSessionManager(
      deviceService: device,
      preferencesService: _Preferences(),
      uac2Service: uac2,
      onSwitchEngine:
          ({
            required from,
            required to,
            required initializeNewEngine,
            required reason,
          }) async {},
      isPlaybackActive: () => false,
    );
    try {
      final mode = await manager.resolvePreferredMode();
      return (mode: mode, debugReads: uac2.debugReads);
    } finally {
      manager.dispose();
      device.deviceInfoNotifier.dispose();
    }
  }

  test(
    'standard internal ExoPlayer route never reads native Rust debug state',
    () async {
      final result = await resolve(
        const AndroidPlaybackDeviceInfo(
          hasUsbDac: false,
          hasAttachedUac2Device: false,
          manufacturer: 'Erisin',
          model: 'ES8189C',
          routeType: 'internal',
          routeLabel: 'Built-in output',
        ),
      );

      expect(result.mode, AudioEngineType.normalAndroid);
      expect(result.debugReads, 0);
    },
  );

  test('known DAP route retains native profile detection', () async {
    final result = await resolve(
      const AndroidPlaybackDeviceInfo(
        hasUsbDac: false,
        hasAttachedUac2Device: false,
        manufacturer: 'Sony',
        model: 'NW-WM1A',
        routeType: 'internal',
        routeLabel: 'Built-in output',
      ),
    );

    expect(result.mode, AudioEngineType.rustOboe);
    expect(result.debugReads, greaterThan(0));
  });
}
