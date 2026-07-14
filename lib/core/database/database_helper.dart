import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../constants/app_constants.dart';
import '../security/encryption_service.dart';
import 'database_schema.dart';

class DatabaseHelper {
  DatabaseHelper._();
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
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
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
    await _db?.close();
    _db = null;
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
