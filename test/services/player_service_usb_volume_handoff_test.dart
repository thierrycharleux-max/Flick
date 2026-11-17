import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flick/data/database.dart';
import 'package:flick/models/audio_engine_type.dart';
import 'package:flick/services/audio_session_manager.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/uac2_preferences_service.dart';
import 'package:flick/services/uac2_service.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

String? _isarCorePath() {
  final override = Platform.environment['ISAR_CORE_LIB'];
  if (override != null && File(override).existsSync()) return override;

  final fileName = switch (Abi.current()) {
    Abi.linuxX64 || Abi.linuxArm || Abi.linuxArm64 => 'libisar.so',
    Abi.macosX64 || Abi.macosArm64 => 'libisar.dylib',
    Abi.windowsX64 => 'isar.dll',
    _ => null,
  };
  if (fileName == null) return null;

  // Isolate.resolvePackageUri is unsupported under `flutter test`, so read
  // the package config that pub already generated instead.
  final packageConfig = File(
    p.join(Directory.current.path, '.dart_tool', 'package_config.json'),
  );
  if (!packageConfig.existsSync()) return null;

  final config =
      jsonDecode(packageConfig.readAsStringSync()) as Map<String, dynamic>;
  final packages = config['packages'];
  if (packages is! List) return null;
  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_community_flutter_libs') {
      continue;
    }
    final rootUri = package['rootUri'];
    if (rootUri is! String) return null;
    final root = Directory.fromUri(packageConfig.uri.resolve(rootUri));
    final path = p.join(root.path, Platform.operatingSystem, fileName);
    return File(path).existsSync() ? path : null;
  }
  return null;
}

class _Session extends Fake implements AudioSessionManager {
  _Session(AudioEngineType initial)
    : selectedModeNotifier = ValueNotifier(initial),
      initializedModeNotifier = ValueNotifier(initial);
  @override
  final ValueNotifier<AudioEngineType> selectedModeNotifier;
  @override
  final ValueNotifier<AudioEngineType?> initializedModeNotifier;
  @override
  AudioEngineType get selectedMode => selectedModeNotifier.value;
  @override
  AudioEngineType? get initializedMode => initializedModeNotifier.value;
  int routeChanges = 0;
  @override
  Future<void> syncRouteSelection({required String reason}) async {
    routeChanges++;
  }
}

class _Usb extends Fake implements Uac2Service {
  int activations = 0;
  @override
  Future<bool> setBitPerfectEnabled(bool value, {bool persist = true}) async {
    activations++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDir;

  setUpAll(() async {
    databaseDir = await Directory.systemTemp.createTemp('flick_usb_volume');
    final corePath = _isarCorePath();
    if (corePath == null) {
      fail('isar core library not found; set ISAR_CORE_LIB');
    }
    Isar.initializeIsarCore(libraries: {Abi.current(): corePath});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => databaseDir.path,
        );
    await Database.init();
  });

  tearDownAll(() async {
    await Database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await databaseDir.delete(recursive: true);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final initial in [
    AudioEngineType.normalAndroid,
    AudioEngineType.rustOboe,
  ]) {
    for (final saved in <double?>[null, 0, 0.27, 1]) {
      test(
        'Erisin rejects USB activation from $initial with saved volume $saved',
        () async {
          final prefs = Uac2PreferencesService();
          await prefs.setAudioEnginePreference(
            AudioEnginePreference.isochronousUsb,
          );
          if (saved != null) await prefs.setUsbSoftwareVolume(saved);
          final session = _Session(initial);
          final usb = _Usb();
          final player = PlayerService.forTesting(
            sessionManager: session,
            uac2Service: usb,
          );
          addTearDown(session.selectedModeNotifier.dispose);
          addTearDown(session.initializedModeNotifier.dispose);
          addTearDown(player.currentVolumeNotifier.dispose);
          addTearDown(player.volumeTierNotifier.dispose);
          expect(await player.enableUsbDacBitPerfect(), false);
          expect(
            await prefs.getAudioEnginePreference(),
            AudioEnginePreference.exoPlayer,
          );
          expect(usb.activations, 0);
          expect(session.routeChanges, 0);
          expect(player.currentEngineType, initial);
          expect(player.currentVolume, 1);
          expect(player.currentSongNotifier.value, isNull);
          expect(player.isPlayingNotifier.value, false);
        },
      );
    }
  }
}
