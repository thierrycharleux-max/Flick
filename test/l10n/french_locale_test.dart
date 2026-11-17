import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/models/song.dart';
import 'package:flick/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocaleController.instance.load();
    LocaleController.instance.bindLocale(const Locale('fr'));
  });

  tearDown(() {
    LocaleController.instance.value = null;
    LocaleController.instance.bindLocale(kFallbackLocale);
  });

  test('Erisin defaults to French and preserves a saved language', () async {
    expect(LocaleController.instance.value, const Locale('fr'));
    expect(l10n.yourLibrary, 'Votre bibliothèque');
    await LocaleController.instance.select(const Locale('en'));
    await LocaleController.instance.load();
    expect(LocaleController.instance.value, const Locale('en'));
    await LocaleController.instance.select(null);
    await LocaleController.instance.load();
    expect(LocaleController.instance.value, isNull);
  });

  test('French catalog covers every message and retains placeholders', () {
    Map<String, dynamic> read(String lang) =>
        jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en = read('en');
    final fr = read('fr');
    final keys = en.keys.where((key) => !key.startsWith('@')).toSet();
    expect(fr.keys.where((key) => !key.startsWith('@')).toSet(), keys);
    Set<String> parameters(String value) {
      final names = <String>{};
      var i = 0;
      while (i < value.length) {
        if (value[i] != '{') {
          i++;
          continue;
        }
        final close = value.indexOf('}', i);
        final head = value.substring(i + 1, close);
        names.add(head.split(',').first.trim());
        if (head.contains(',')) {
          var depth = 1;
          i++;
          while (i < value.length && depth > 0) {
            if (value[i] == '{') depth++;
            if (value[i] == '}') depth--;
            i++;
          }
        } else {
          i = close + 1;
        }
      }
      return names;
    }

    for (final key in keys) {
      expect(fr[key], isNotEmpty, reason: key);
      expect(
        parameters(fr[key] as String),
        parameters(en[key] as String),
        reason: key,
      );
    }
    expect(
      fr.values.whereType<String>().where(
        (text) => RegExp(r'\bjoueurs?\b', caseSensitive: false).hasMatch(text),
      ),
      isEmpty,
    );
    final french = lookupAppLocalizations(const Locale('fr'));
    expect(french.playerLayout, 'Disposition du lecteur');
    expect(french.playNext, 'Lire ensuite');
    expect(french.waveformSeekbar, 'Barre de progression avec forme d’onde');
    expect(french.songsCount(1), '1 titre');
    expect(french.songsCount(2), '2 titres');
    expect(french.songsCount(0), '0 titre');
    expect(french.songsIn(4, 2), contains('4 titres'));
  });

  test(
    'notification controls use app language, preserving song metadata',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('com.mossapps.flick/player');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final song = Song(
        id: 'fr-test',
        title: 'Back In The Water',
        artist: 'Haevn',
        duration: const Duration(minutes: 4),
        fileType: 'FLAC',
      );
      await NotificationService().showNotification(song: song, isPlaying: true);
      final args = calls.single.arguments as Map;
      expect(args['title'], 'Back In The Water');
      expect(args['artist'], 'Haevn');
      expect(args['controlLabels']['play'], 'Lire');
      expect(args['controlLabels']['previous'], contains('précédent'));
      LocaleController.instance.bindLocale(const Locale('en'));
      await NotificationService().updatePlaybackState(isPlaying: false);
      expect((calls.last.arguments as Map)['controlLabels']['play'], 'Play');
    },
  );
}
