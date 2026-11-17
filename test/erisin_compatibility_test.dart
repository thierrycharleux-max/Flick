import 'package:flick/core/utils/responsive.dart';
import 'package:flick/features/songs/widgets/orbit_scroll.dart';
import 'package:flick/features/songs/widgets/song_card.dart';
import 'package:flick/models/song.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/audio_engine_type.dart';
import 'package:flick/models/player_action_button.dart';
import 'package:flick/models/mini_player_config.dart';
import 'package:flick/models/nav_bar_config.dart';
import 'package:flick/services/audio_session_manager.dart';
import 'package:flick/services/uac2_preferences_service.dart';
import 'package:flick/widgets/common/mini_player_bar.dart';
import 'package:flick/widgets/navigation/flick_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old USB DAC preferences cannot restore the direct output', () async {
    SharedPreferences.setMockInitialValues({
      'audio_engine_preference': 'isochronousUsb',
      'uac2_bit_perfect_enabled': true,
      'uac2_exclusive_dac_mode_enabled': true,
    });
    final prefs = Uac2PreferencesService();
    expect(await prefs.getAudioEnginePreference(), AudioEnginePreference.exoPlayer);
    expect(await prefs.getBitPerfectEnabled(), isFalse);
    expect(PlayerActionButtonX.fromStorageValue('usb_volume'), PlayerActionButton.volume);
    await prefs.setAudioEnginePreference(AudioEnginePreference.isochronousUsb);
    await prefs.setBitPerfectEnabled(true);
    expect(await prefs.getAudioEnginePreference(), AudioEnginePreference.exoPlayer);
    expect(await prefs.getBitPerfectEnabled(), isFalse);
    await prefs.setAudioEnginePreference(AudioEnginePreference.rustOboe);
    expect(await prefs.getAudioEnginePreference(), AudioEnginePreference.rustOboe);
  });

  test('a direct USB engine request is routed to Android', () async {
    AudioEngineType? initialized;
    final session = AudioSessionManager(
      onSwitchEngine: ({required from, required to, required initializeNewEngine, required reason}) async {
        initialized = to;
      },
      isPlaybackActive: () => false,
    );
    addTearDown(session.dispose);
    await session.switchMode(AudioEngineType.usbDacExperimental, initializeNewEngine: true);
    expect(session.selectedMode, AudioEngineType.normalAndroid);
    expect(session.initializedMode, AudioEngineType.normalAndroid);
    expect(initialized, AudioEngineType.normalAndroid);
  });

  testWidgets('car bar stays below content and both controls work', (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var plays = 0;
    int? selected;
    double? scaled;
    await tester.pumpWidget(MaterialApp(
      locale: kFallbackLocale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: kAppLocalizationsDelegates,
      localeResolutionCallback: resolveAppLocale,
      home: Scaffold(body: Column(children: [
        Expanded(child: Builder(builder: (context) {
          scaled = Responsive.scale(context, 100);
          return const ColoredBox(key: ValueKey('content'), color: Colors.black);
        })),
        FlickNavBar(
          compact: true,
          config: NavBarConfig.defaultConfig,
          currentIndex: 1,
          onTap: (index) => selected = index,
          showMiniPlayer: true,
          miniPlayerWidget: MiniPlayerBar(
            compact: true,
            config: MiniPlayerConfig.defaultConfig.copyWith(height: 52),
            songId: 'track',
            title: 'Back In The Water',
            artist: 'Haevn',
            enableHero: false,
            onPlayPause: () => plays++,
          ),
        ),
      ])),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final content = tester.getRect(find.byKey(const ValueKey('content')));
    final bar = tester.getRect(find.byKey(const ValueKey('erisin_bottom_bar')));
    final player = tester.getRect(find.byKey(const ValueKey('mini_player_surface')));
    expect(content.bottom, lessThanOrEqualTo(bar.top));
    expect(player.top, greaterThanOrEqualTo(bar.top));
    expect(player.bottom, lessThanOrEqualTo(bar.bottom));
    expect(bar.height, 72);
    expect(scaled, 100);
    await tester.tap(find.byTooltip('Play'));
    expect(plays, 1);
    await tester.tap(find.text('Settings'));
    expect(selected, 2);
    expect(tester.takeException(), isNull);
    tester.view.devicePixelRatio = 1.5;
    await tester.pumpAndSettle();
    final label = tester.getRect(find.text('Settings'));
    expect(label.height, greaterThan(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('orbit card fits the space under the search bar', (tester) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final song = Song(
      id: 'one', title: 'Track', artist: 'Artist', album: 'Album',
      duration: const Duration(seconds: 15), fileType: 'M4A',
    );
    await tester.pumpWidget(MaterialApp(
      locale: kFallbackLocale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: kAppLocalizationsDelegates,
      localeResolutionCallback: resolveAppLocale,
      home: Scaffold(body: Column(children: [
        const SizedBox(height: 170),
        Expanded(child: SizedBox(
          key: const ValueKey('orbit_viewport'),
          child: OrbitScroll(songs: [song], showGlow: false, showPath: false),
        )),
        const SizedBox(height: 72),
      ])),
    ));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byKey(const ValueKey('orbit_viewport')));
    final card = tester.getRect(find.descendant(
      of: find.byType(SongCard), matching: find.byType(ClipRRect).first,
    ));
    expect(card.top, greaterThanOrEqualTo(viewport.top - 0.1));
    expect(card.bottom, lessThanOrEqualTo(viewport.bottom + 0.1));
    expect(tester.takeException(), isNull);
  });

}
