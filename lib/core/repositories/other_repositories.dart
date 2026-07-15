import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../security/encryption_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_sync_service.dart';

class BirthdayRepository {
  BirthdayRepository({
    Future<Database> Function()? databaseProvider,
    Future<void> Function(BirthdayModel)? syncBirthdayReminder,
    Future<void> Function(int)? cancelNotification,
  }) : _databaseProvider = databaseProvider ?? _defaultDatabaseProvider,
       _syncBirthdayReminder =
           syncBirthdayReminder ?? ReminderSyncService.instance.syncBirthday,
       _cancelNotification =
           cancelNotification ?? NotificationService.instance.cancel;

  final _uuid = const Uuid();
  final Future<Database> Function() _databaseProvider;
  final Future<void> Function(BirthdayModel) _syncBirthdayReminder;
  final Future<void> Function(int) _cancelNotification;

  static Future<Database> _defaultDatabaseProvider() {
    return DatabaseHelper.instance.database;
  }

  Future<List<BirthdayModel>> getAll() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'birthdays',
      where: 'is_deleted = 0',
      orderBy: 'month ASC, day ASC',
    );
    return rows.map(BirthdayModel.fromMap).toList();
  }

  Future<void> save(BirthdayModel model) async {
    final db = await _databaseProvider();
    await db.insert(
      'birthdays',
      model.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      await _syncBirthdayReminder(model);
    } catch (_) {}
  }

  Future<BirthdayModel> create({
    required String name,
    required bool isLunar,
    required int month,
    required int day,
    String relation = '',
    bool isLeapMonth = false,
    int remindDaysBefore = 3,
  }) async {
    final model = BirthdayModel(
      id: _uuid.v4(),
      name: name,
      relation: relation,
      isLunar: isLunar,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
      remindDaysBefore: remindDaysBefore,
      createdAt: DateTime.now(),
    );
    await save(model);
    return model;
  }

  Future<void> softDelete(String id) async {
    final db = await _databaseProvider();
    await db.update(
      'birthdays',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _cancelBestEffort(ReminderSyncService.birthdayAdvanceId(id));
    await _cancelBestEffort(ReminderSyncService.birthdayDayId(id));
  }

  Future<void> _cancelBestEffort(int notificationId) async {
    try {
      await _cancelNotification(notificationId);
    } catch (_) {}
  }
}

class IdeaRepository {
  final _uuid = const Uuid();

  Future<List<IdeaModel>> getAll({String? tag}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = tag == null
        ? await db.query(
            'ideas',
            where: 'is_deleted = 0',
            orderBy: 'is_starred DESC, created_at DESC',
          )
        : await db.query(
            'ideas',
            where: 'is_deleted = 0 AND tag = ?',
            whereArgs: [tag],
            orderBy: 'is_starred DESC, created_at DESC',
          );
    return rows.map(IdeaModel.fromMap).toList();
  }

  Future<void> save(IdeaModel idea) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'ideas',
      idea.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<IdeaModel> create({
    required String title,
    required String content,
    String tag = '生活',
  }) async {
    final idea = IdeaModel(
      id: _uuid.v4(),
      title: title,
      content: content,
      tag: tag,
      createdAt: DateTime.now(),
    );
    await save(idea);
    return idea;
  }

  Future<void> softDelete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('ideas', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }
}

class VaultRepository {
  final _uuid = const Uuid();
  final _enc = EncryptionService.instance;

  Future<List<VaultEntryModel>> getAll({String? category}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = category == null
        ? await db.query(
            'vault_entries',
            where: 'is_deleted = 0',
            orderBy: 'name ASC',
          )
        : await db.query(
            'vault_entries',
            where: 'is_deleted = 0 AND category = ?',
            whereArgs: [category],
            orderBy: 'name ASC',
          );
    return rows.map(VaultEntryModel.fromMap).toList();
  }

  Future<void> saveEntry({
    String? id,
    required String category,
    required String name,
    required String account,
    required String password,
    String? notes,
  }) async {
    final now = DateTime.now();
    final passwordEnc = await _enc.encryptVaultField(password);
    final notesEnc =
        notes != null && notes.isNotEmpty ? await _enc.encryptVaultField(notes) : null;
    final entry = VaultEntryModel(
      id: id ?? _uuid.v4(),
      category: category,
      name: name,
      account: account,
      passwordEnc: passwordEnc,
      notesEnc: notesEnc,
      createdAt: now,
      updatedAt: now,
    );
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'vault_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> decryptPassword(VaultEntryModel entry) =>
      _enc.decryptVaultField(entry.passwordEnc);

  Future<void> softDelete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'vault_entries',
      {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
