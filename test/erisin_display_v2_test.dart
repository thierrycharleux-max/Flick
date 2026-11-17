import 'package:flick/core/theme/app_theme.dart';
import 'package:flick/features/player/widgets/erisin_artwork_stage.dart';
import 'package:flick/features/songs/screens/songs_screen.dart';
import 'package:flick/features/songs/widgets/orbit_scroll.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/player_screen_mode.dart';
import 'package:flick/models/song.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/player_screen_mode_preference_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _songs = List.generate(
  12,
  (i) => Song(
    id: 'track-$i',
    title: 'Track $i',
    artist: 'An artist',
    album: 'Album $i',
    duration: const Duration(minutes: 4),
    fileType: 'M4A',
  ),
);

class _Songs extends SongsNotifier {
  @override
  Future<SongsState> build() async =>
      SongsState(songs: _songs, sortOption: SongSortOption.albumArtist);
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: kFallbackLocale,
  supportedLocales: kSupportedLocales,
  localizationsDelegates: kAppLocalizationsDelegates,
  localeResolutionCallback: resolveAppLocale,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cover is the upgraded default and later layout choices are retained',
    () async {
      SharedPreferences.setMockInitialValues({
        'player_screen_mode': 'immersive',
      });
      final prefs = PlayerScreenModePreferenceService();
      expect(await prefs.getMode(), PlayerScreenMode.artworkCard);
      await prefs.setMode(PlayerScreenMode.immersive);
      expect(await prefs.getMode(), PlayerScreenMode.immersive);
    },
  );

  testWidgets(
    'library gives its height to covers and opens inline search only on request',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            songsProvider.overrideWith(_Songs.new),
            currentSongProvider.overrideWith((ref) => null),
            isCastingProvider.overrideWith((ref) => false),
          ],
          child: _app(
            Column(
              children: [
                const SizedBox(height: 48),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(size: constraints.biggest),
                      child: const SongsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 56),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('erisin_library_search')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('erisin_library_toolbar')))
            .height,
        56,
      );
      expect(tester.getSize(find.byType(OrbitScroll)).height, greaterThan(230));
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('erisin_library_search')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('erisin_library_toolbar')))
            .height,
        56,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final density in [1.0, 1.5]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets(
        'approved landscape composition at dpi $density and text $textScale',
        (tester) async {
          tester.view.physicalSize = const Size(1024, 600);
          tester.view.devicePixelRatio = density;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final song = _songs.first.copyWith(
            title: 'Une vie à t’aimer — une version longue du titre',
            artist: 'Lorien Testard · Alice Duport-Percier · Victor B…',
            album: 'Clair Obscur: Expedition 33',
          );
          var artistTaps = 0;
          var albumTaps = 0;
          await tester.pumpWidget(
            _app(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Column(
                    children: [
                      const SizedBox(height: 64),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ErisinArtworkStage(
                                song: song,
                                footer: const SizedBox(height: 84),
                              ),
                            ),
                            Expanded(
                              child: ErisinPlaybackPanel(
                                song: song,
                                onArtist: () => artistTaps++,
                                onAlbum: () => albumTaps++,
                                controls: const SizedBox(
                                  key: ValueKey('test_transport'),
                                  height: 170,
                                  child: Center(child: Icon(Icons.play_arrow)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final art = tester.getRect(
            find.byKey(const ValueKey('erisin_player_cover')),
          );
          final title = tester.getRect(
            find.byKey(const ValueKey('erisin_player_title')),
          );
          final identity = tester.getRect(
            find.byKey(const ValueKey('erisin_player_identity')),
          );
          final controls = tester.getRect(
            find.byKey(const ValueKey('test_transport')),
          );
          expect(art.width, closeTo(art.height, 0.1));
          expect(art.height, greaterThan((600 / density - 64) * 0.65));
          expect(art.right, lessThan(title.left));
          expect(title.bottom, lessThan(identity.top));
          expect(
            identity.contains(tester.getCenter(find.text(song.artist))),
            isTrue,
          );
          expect(
            identity.contains(tester.getCenter(find.text(song.album!))),
            isTrue,
          );
          expect(controls.top, greaterThanOrEqualTo(identity.bottom));
          expect(controls.bottom, lessThanOrEqualTo(600 / density));
          expect(find.text(song.title), findsOneWidget);
          await tester.tap(find.text(song.artist));
          await tester.tap(find.text(song.album!));
          expect(artistTaps, 1);
          expect(albumTaps, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
