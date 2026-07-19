import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_butler/core/database/database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDirectory;
  late String databasePath;
  Database? openDatabase;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'personal_butler_database_schema_',
    );
    databasePath = p.join(tempDirectory.path, 'schema.db');
  });

  tearDown(() async {
    await openDatabase?.close();
    openDatabase = null;
    await databaseFactoryFfi.deleteDatabase(databasePath);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<Database> open(
    int version, {
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
  }) async {
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        singleInstance: false,
      ),
    );
    openDatabase = database;
    return database;
  }

  Future<void> close() async {
    await openDatabase?.close();
    openDatabase = null;
  }

  Future<List<String>> columns(Database database, String table) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name']! as String).toList();
  }

  Future<Set<String>> tables(Database database) async {
    final rows = await database.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    return rows.map((row) => row['name']! as String).toSet();
  }

  Future<void> insertLegacyScheduleSentinel(Database database) async {
    await database.insert('schedule_entries', {
      'id': 'legacy-sentinel',
      'owner': 'family',
      'title': 'Legacy class',
      'weekday': 3,
      'start_time': '08:00',
      'end_time': '09:30',
      'location': 'Room 101',
      'week_pattern': 'odd',
      'is_deleted': 0,
      'created_at': '2026-01-02T03:04:05.000',
    });
  }

  // The repository has no historical schema snapshots. These v1/v2 fixtures
  // are reconstructed from the migration contract and the columns each
  // migration step is responsible for adding.
  group('DatabaseSchema migrations', () {
    test('migrates v1 directly to v3 without losing schedule data', () async {
      var database = await open(1, onCreate: _createV1Fixture);
      await insertLegacyScheduleSentinel(database);
      await close();

      database = await open(
        3,
        onCreate: DatabaseSchema.onCreate,
        onUpgrade: DatabaseSchema.onUpgrade,
      );

      expect(await database.getVersion(), 3);
      expect(
        await columns(database, 'schedule_entries'),
        containsAll(['start_week', 'end_week', 'repeat_mode', 'custom_weeks']),
      );
      expect(
        await columns(database, 'schedule_settings'),
        contains('semester_start_date'),
      );

      final sentinel = (await database.query(
        'schedule_entries',
        where: 'id = ?',
        whereArgs: ['legacy-sentinel'],
      )).single;
      expect(sentinel['title'], 'Legacy class');
      expect(sentinel['week_pattern'], 'odd');
      expect(sentinel['start_week'], 1);
      expect(sentinel['end_week'], 20);
      expect(sentinel['repeat_mode'], 'all');
      expect(sentinel['custom_weeks'], isNull);

      final settings = (await database.query(
        'schedule_settings',
        where: 'id = ?',
        whereArgs: ['default'],
      )).single;
      expect(settings['semester_start_week'], 1);
      expect(settings['semester_end_week'], 20);
      expect(settings['semester_start_date'], isNull);
    });

    test('migrates v1 to v2 and then v3 at the requested boundaries', () async {
      var database = await open(1, onCreate: _createV1Fixture);
      await close();

      database = await open(
        2,
        onCreate: DatabaseSchema.onCreate,
        onUpgrade: DatabaseSchema.onUpgrade,
      );

      expect(await database.getVersion(), 2);
      expect(
        await columns(database, 'schedule_entries'),
        containsAll(['start_week', 'end_week', 'repeat_mode', 'custom_weeks']),
      );
      expect(
        await columns(database, 'schedule_settings'),
        isNot(contains('semester_start_date')),
      );
      await close();

      database = await open(
        3,
        onCreate: DatabaseSchema.onCreate,
        onUpgrade: DatabaseSchema.onUpgrade,
      );

      final settingsColumns = await columns(database, 'schedule_settings');
      expect(await database.getVersion(), 3);
      expect(settingsColumns, contains('semester_start_date'));
      expect(
        settingsColumns.where((name) => name == 'semester_start_date'),
        hasLength(1),
      );
    });

    test('migrates v2 to v3 while preserving customized values', () async {
      var database = await open(2, onCreate: _createV2Fixture);
      await database.update(
        'schedule_settings',
        {
          'semester_start_week': 4,
          'semester_end_week': 16,
          'updated_at': '2026-02-03T04:05:06.000',
        },
        where: 'id = ?',
        whereArgs: ['default'],
      );
      await database.insert('schedule_entries', {
        'id': 'custom-v2-entry',
        'owner': 'self',
        'title': 'Custom weeks',
        'weekday': 5,
        'start_time': '13:00',
        'end_time': '15:00',
        'location': 'Lab',
        'start_week': 4,
        'end_week': 16,
        'repeat_mode': 'custom',
        'week_pattern': 'custom',
        'custom_weeks': '[4,7,11,16]',
        'is_deleted': 0,
        'created_at': '2026-02-03T04:05:06.000',
      });
      await close();

      database = await open(
        3,
        onCreate: DatabaseSchema.onCreate,
        onUpgrade: DatabaseSchema.onUpgrade,
      );

      final settings = (await database.query(
        'schedule_settings',
        where: 'id = ?',
        whereArgs: ['default'],
      )).single;
      expect(settings['semester_start_week'], 4);
      expect(settings['semester_end_week'], 16);
      expect(settings['updated_at'], '2026-02-03T04:05:06.000');
      expect(settings['semester_start_date'], isNull);

      final entry = (await database.query(
        'schedule_entries',
        where: 'id = ?',
        whereArgs: ['custom-v2-entry'],
      )).single;
      expect(entry['start_week'], 4);
      expect(entry['end_week'], 16);
      expect(entry['repeat_mode'], 'custom');
      expect(entry['custom_weeks'], '[4,7,11,16]');
    });

    test('creates a fresh v3 database with the complete schema', () async {
      final database = await open(
        3,
        onCreate: DatabaseSchema.onCreate,
        onUpgrade: DatabaseSchema.onUpgrade,
      );

      expect(await database.getVersion(), 3);
      expect(await tables(database), {
        'items',
        'attachments',
        'schedule_entries',
        'schedule_settings',
        'birthdays',
        'ideas',
        'vault_entries',
      });
      expect(
        await columns(database, 'schedule_entries'),
        containsAll(['start_week', 'end_week', 'repeat_mode', 'custom_weeks']),
      );
      expect(
        await columns(database, 'schedule_settings'),
        contains('semester_start_date'),
      );

      final settings = (await database.query(
        'schedule_settings',
        where: 'id = ?',
        whereArgs: ['default'],
      )).single;
      expect(settings['semester_start_week'], 1);
      expect(settings['semester_end_week'], 20);
      expect(settings['semester_start_date'], isNull);
    });

    test('rolls back schema changes when an upgrade callback fails', () async {
      var database = await open(1, onCreate: _createV1Fixture);
      await insertLegacyScheduleSentinel(database);
      await close();

      await expectLater(
        open(
          3,
          onUpgrade: (database, oldVersion, newVersion) async {
            await DatabaseSchema.onUpgrade(database, oldVersion, newVersion);
            throw StateError('forced upgrade failure');
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'forced upgrade failure',
          ),
        ),
      );

      database = await open(1);
      expect(await database.getVersion(), 1);
      expect(
        await columns(database, 'schedule_entries'),
        isNot(contains('start_week')),
      );
      expect(await tables(database), isNot(contains('schedule_settings')));
      expect(
        await database.query(
          'schedule_entries',
          where: 'id = ?',
          whereArgs: ['legacy-sentinel'],
        ),
        hasLength(1),
      );
    });
  });
}

Future<void> _createV1Fixture(Database database, int version) async {
  await _createNonScheduleTables(database);
  await database.execute('''
    CREATE TABLE schedule_entries (
      id TEXT PRIMARY KEY,
      owner TEXT NOT NULL,
      title TEXT NOT NULL,
      weekday INTEGER NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      location TEXT,
      week_pattern TEXT,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
}

Future<void> _createV2Fixture(Database database, int version) async {
  await _createNonScheduleTables(database);
  await database.execute('''
    CREATE TABLE schedule_entries (
      id TEXT PRIMARY KEY,
      owner TEXT NOT NULL,
      title TEXT NOT NULL,
      weekday INTEGER NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      location TEXT,
      start_week INTEGER DEFAULT 1,
      end_week INTEGER DEFAULT 20,
      repeat_mode TEXT DEFAULT 'all',
      week_pattern TEXT,
      custom_weeks TEXT,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE schedule_settings (
      id TEXT PRIMARY KEY,
      semester_start_week INTEGER DEFAULT 1,
      semester_end_week INTEGER DEFAULT 20,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.insert('schedule_settings', {
    'id': 'default',
    'semester_start_week': 1,
    'semester_end_week': 20,
    'updated_at': '2026-01-01T00:00:00.000',
  });
}

Future<void> _createNonScheduleTables(Database database) async {
  await database.execute('''
    CREATE TABLE items (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      owner TEXT DEFAULT 'self',
      start_at TEXT,
      end_at TEXT,
      location TEXT,
      participants TEXT,
      status TEXT DEFAULT 'active',
      inbox_status TEXT DEFAULT 'confirmed',
      pending_status TEXT,
      next_follow_up_at TEXT,
      amount REAL,
      ocr_text TEXT,
      notes TEXT,
      reminder_minutes INTEGER DEFAULT 60,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE attachments (
      id TEXT PRIMARY KEY,
      item_id TEXT NOT NULL,
      asset_id TEXT NOT NULL,
      display_name TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (item_id) REFERENCES items(id)
    )
  ''');
  await database.execute('''
    CREATE TABLE birthdays (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      relation TEXT,
      is_lunar INTEGER DEFAULT 0,
      month INTEGER NOT NULL,
      day INTEGER NOT NULL,
      is_leap_month INTEGER DEFAULT 0,
      remind_days_before INTEGER DEFAULT 3,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE ideas (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      tag TEXT DEFAULT '生活',
      is_starred INTEGER DEFAULT 0,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE vault_entries (
      id TEXT PRIMARY KEY,
      category TEXT NOT NULL,
      name TEXT NOT NULL,
      account TEXT NOT NULL,
      password_enc TEXT NOT NULL,
      notes_enc TEXT,
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
}
