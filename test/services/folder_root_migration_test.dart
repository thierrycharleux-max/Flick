import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/data/database.dart';
import 'package:flick/data/repositories/folder_repository.dart';
import 'package:flick/services/folder_root_migration.dart';
import 'package:flick/services/music_folder_service.dart';
import 'package:flick/services/permission_service.dart';

const parent =
    'content://com.android.externalstorage.documents/tree/1234-5678%3A';
const child =
    'content://com.android.externalstorage.documents/tree/1234-5678%3AHaevn';
const file = '$child/document/1234-5678%3AHaevn%2F01.flac';

class Picker extends PermissionService {
  String selection = parent;
  final grants = <String>[];
  @override
  Future<String?> openFolderPicker() async => selection;
  @override
  Future<bool> takePersistablePermission(String uri) async {
    grants.add(uri);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Isar db;
  late Directory directory;
  const channel = MethodChannel('com.mossapps.flick/storage');
  setUpAll(() {
    final cache =
        Platform.environment['PUB_CACHE'] ??
        p.join(
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!,
          '.pub-cache',
        );
    final libraryName = Platform.isMacOS
        ? 'libisar.dylib'
        : Platform.isWindows
        ? 'isar.dll'
        : 'libisar.so';
    Isar.initializeIsarCore(
      libraries: {
        Abi.current(): p.join(
          cache,
          'hosted',
          'pub.dev',
          'isar_community_flutter_libs-3.3.2',
          Platform.operatingSystem,
          libraryName,
        ),
      },
    );
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('flick-root-migration');
    db = await Isar.open(
      [FolderEntitySchema, SongEntitySchema],
      directory: directory.path,
      name: p.basename(directory.path),
      inspector: false,
    );
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close(deleteFromDisk: true);
    await directory.delete(recursive: true);
  });
  test(
    'whole SD replaces album roots preserving IDs, edits and CUE windows',
    () async {
      final repository = FolderRepository(isar: db);
      await repository.upsertFolder(
        FolderEntity()
          ..uri = child
          ..displayName = 'Haevn'
          ..dateAdded = DateTime(2026),
      );
      final song = SongEntity()
        ..filePath = file
        ..folderUri = child
        ..title = 'Edited title'
        ..artist = 'Haevn'
        ..dateAdded = DateTime(2026)
        ..hasLocalEdits = true
        ..startOffsetMs = 1000
        ..endOffsetMs = 5000;
      await db.writeTxn(() async {
        await db.songEntitys.put(song);
      });
      final id = song.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorite_song_ids', ['$id']);
      await prefs.setStringList('music_folders', [
        jsonEncode(
          MusicFolder(
            uri: child,
            displayName: 'Haevn',
            dateAdded: DateTime(2026),
          ).toJson(),
        ),
      ]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getDocumentDisplayName') {
              return 'SD Card';
            }
            if (call.method == 'hasAllFilesAccess') {
              return true;
            }
            if (call.method == 'resolveStorageInfo') {
              return {
                'fsPath': '/storage/1234-5678',
                'isRemovable': true,
                'allFilesAccess': true,
                'state': 'mounted',
              };
            }
            return null;
          });
      final picker = Picker();
      final service = MusicFolderService(
        permissionService: picker,
        folderRepository: repository,
      );
      expect((await service.addFolder())?.uri, parent);
      final roots = await repository.getAllFolders();
      expect(roots.map((root) => root.uri), [parent]);
      final migrated = await db.songEntitys.get(id);
      expect(migrated?.filePath, '/storage/1234-5678/Haevn/01.flac');
      expect(migrated?.folderUri, parent);
      expect(migrated?.relativeFolderPath, 'Haevn');
      expect(migrated?.hasLocalEdits, true);
      expect(migrated?.title, 'Edited title');
      expect(migrated?.startOffsetMs, 1000);
      expect(migrated?.endOffsetMs, 5000);
      expect(prefs.getStringList('favorite_song_ids'), ['$id']);
      expect((await service.getSavedFolders()).map((f) => f.uri), [parent]);
      picker.selection = child;
      await expectLater(
        service.addFolder(),
        throwsA(isA<FolderAlreadyExistsException>()),
      );
      expect(await db.songEntitys.count(), 1);
    },
  );
  test('SAF grant changes retain document identity and accented paths', () {
    const nested =
        '$child/document/1234-5678%3AHaevn%2F%C3%89t%C3%A9%2F01.flac';
    final migrated = migrateFolderSongPath(nested, parent);
    expect(externalDocumentId(migrated), '1234-5678:Haevn/Été/01.flac');
    expect(externalDocumentId(migrated, tree: true), '1234-5678:');
    expect(migratedRelativeFolder(nested, parent), 'Haevn/Été');
    expect(
      migrateFolderSongPath(nested, parent, rawRoot: '/storage/1234-5678'),
      '/storage/1234-5678/Haevn/Été/01.flac',
    );
    expect(
      migrateFolderSongPath('/storage/OTHER/song.flac', parent),
      '/storage/OTHER/song.flac',
    );
    expect(
      migrateFolderSongPath(
        nested,
        'content://com.android.externalstorage.documents/tree/OTHER%3A',
      ),
      nested,
    );
  });
}
