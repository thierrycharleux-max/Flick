import 'package:flick/features/albums/widgets/album_landscape_layout.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/common/detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final density in [1.0, 1.5, 2.0]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets(
        'album actions stay visible at 1024x600, density $density, text $textScale',
        (tester) async {
          tester.view.physicalSize = const Size(1024, 600);
          tester.view.devicePixelRatio = density;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final calls = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              locale: kFallbackLocale,
              supportedLocales: kSupportedLocales,
              localizationsDelegates: kAppLocalizationsDelegates,
              localeResolutionCallback: resolveAppLocale,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: Scaffold(
                body: Column(
                  children: [
                    const SizedBox(key: ValueKey('song_pill'), height: 48),
                    Expanded(
                      child: AlbumLandscapeLayout(
                        title:
                            'A long album title that must fit on a shallow screen',
                        artist: 'An artist name that can also be long',
                        meta:
                            'Alternative rock · 2026 · 40 tracks · 2h 45m · Lossless',
                        artwork: const ColoredBox(color: Colors.blue),
                        onBack: () => calls.add('back'),
                        actions: DetailActionCapsule(
                          isFavorite: false,
                          onToggleFavorite: () => calls.add('favorite'),
                          onShuffle: () => calls.add('shuffle'),
                          onPlay: () => calls.add('play'),
                          onQueue: () => calls.add('queue'),
                          onMore: () => calls.add('more'),
                        ),
                        tracks: ListView.builder(
                          itemExtent: 64,
                          itemCount: 40,
                          itemBuilder: (_, index) => Text('Track $index'),
                        ),
                      ),
                    ),
                    const SizedBox(key: ValueKey('persistent_bar'), height: 56),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final actions = find.byKey(const ValueKey('album_fixed_actions'));
          final viewport = find.byKey(const ValueKey('album_tracks_viewport'));
          final initialActions = tester.getRect(actions);
          final bar = tester.getRect(
            find.byKey(const ValueKey('persistent_bar')),
          );
          final songPill = tester.getRect(
            find.byKey(const ValueKey('song_pill')),
          );
          expect(initialActions.top, greaterThanOrEqualTo(songPill.bottom));
          expect(initialActions.bottom, lessThanOrEqualTo(bar.top));
          expect(find.text('Track 0'), findsOneWidget);
          final trackRect = tester.getRect(viewport);
          if (1024 / density >= 560) {
            expect(trackRect.left, greaterThan(initialActions.right));
          } else {
            expect(trackRect.top, greaterThanOrEqualTo(initialActions.bottom));
          }

          for (final label in [
            'Favorite all',
            'Shuffle',
            'Play',
            'Queue',
            'More',
          ]) {
            await tester.tap(find.byTooltip(label));
          }
          await tester.pumpAndSettle();
          expect(calls, ['favorite', 'shuffle', 'play', 'queue', 'more']);

          await tester.drag(viewport, const Offset(0, -400));
          await tester.pumpAndSettle();
          final scroll = tester.state<ScrollableState>(
            find.descendant(of: viewport, matching: find.byType(Scrollable)),
          );
          expect(scroll.position.pixels, greaterThan(0));
          expect(tester.getRect(actions), initialActions);
          await tester.tap(find.byTooltip('Play'));
          expect(calls.last, 'play');
          expect(calls.length, 6);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
