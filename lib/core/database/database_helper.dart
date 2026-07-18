import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../constants/app_constants.dart';
import '../security/encryption_service.dart';
import 'database_schema.dart';

typedef DatabaseOpener = Future<Database> Function();

class DatabaseHelper {
  DatabaseHelper._() : _databaseOpener = null;

  @visibleForTesting
  DatabaseHelper.forTesting({required DatabaseOpener databaseOpener})
    : _databaseOpener = databaseOpener;

  static final DatabaseHelper instance = DatabaseHelper._();
  static const backupTableNames = <String>[
    'items',
    'attachments',
    'schedule_entries',
    'schedule_settings',
    'birthdays',
    'ideas',
    'vault_entries',
  ];
  final DatabaseOpener? _databaseOpener;
  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database {
    final current = _db;
    if (current != null) return Future<Database>.value(current);

    final opening = _opening;
    if (opening != null) return opening;

    final rawOpening = Future<Database>.sync(
      () => (_databaseOpener ?? _initDb)(),
    );
    late final Future<Database> trackedOpening;
    trackedOpening = rawOpening.then<Database>(
      (database) {
        if (identical(_opening, trackedOpening)) {
          _db = database;
          _opening = null;
        }
        return database;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_opening, trackedOpening)) _opening = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _opening = trackedOpening;
    return trackedOpening;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);
    final password = await EncryptionService.instance.getOrCreateDbPassword();
    return openDatabase(
      path,
      password: password,
      version: AppConstants.dbVersion,
      onCreate: DatabaseSchema.onCreate,
      onUpgrade: DatabaseSchema.onUpgrade,
    );
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    final database = _db;
    _db = null;
    await database?.close();
    if (opening != null) {
      try {
        final opened = await opening;
        if (!identical(opened, database)) await opened.close();
      } catch (_) {
        // A failed in-flight open has no database to close.
      }
    }
  }

  Future<void> replaceAllData(
    Map<String, List<Map<String, dynamic>>> data,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'attachments',
        'items',
        'schedule_entries',
        'schedule_settings',
        'birthdays',
        'ideas',
        'vault_entries',
      ]) {
        await txn.delete(table);
      }
      for (final entry in data.entries) {
        for (final row in entry.value) {
          await txn.insert(entry.key, row);
        }
      }
    });
  }

  Future<Map<String, List<Map<String, dynamic>>>> exportAllData() async {
    final db = await database;
    final result = <String, List<Map<String, dynamic>>>{};
    for (final table in backupTableNames) {
      result[table] = await db.query(table);
    }
    return result;
  }
}
