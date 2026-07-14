import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../constants/app_constants.dart';
import '../security/encryption_service.dart';

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
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        asset_id TEXT NOT NULL,
        display_name TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (item_id) REFERENCES items(id)
      )
    ''');
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE schedule_settings (
        id TEXT PRIMARY KEY,
        semester_start_week INTEGER DEFAULT 1,
        semester_end_week INTEGER DEFAULT 20,
        semester_start_date TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.insert('schedule_settings', {
      'id': 'default',
      'semester_start_week': 1,
      'semester_end_week': 20,
      'semester_start_date': null,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE schedule_entries ADD COLUMN start_week INTEGER DEFAULT 1",
      );
      await db.execute(
        "ALTER TABLE schedule_entries ADD COLUMN end_week INTEGER DEFAULT 20",
      );
      await db.execute(
        "ALTER TABLE schedule_entries ADD COLUMN repeat_mode TEXT DEFAULT 'all'",
      );
      await db.execute(
        "ALTER TABLE schedule_entries ADD COLUMN custom_weeks TEXT",
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS schedule_settings (
          id TEXT PRIMARY KEY,
          semester_start_week INTEGER DEFAULT 1,
          semester_end_week INTEGER DEFAULT 20,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.insert('schedule_settings', {
        'id': 'default',
        'semester_start_week': 1,
        'semester_end_week': 20,
        'semester_start_date': null,
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE schedule_settings ADD COLUMN semester_start_date TEXT",
      );
    }
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
