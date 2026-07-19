import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../security/encryption_service.dart';
import '../security/session_service.dart';
import '../services/reminder_sync_service.dart';
import '../utils/birthday_date_helper.dart';

class BirthdayRepository {
  BirthdayRepository({
    Future<Database> Function()? databaseProvider,
    Future<void> Function(BirthdayModel)? syncBirthdayReminder,
    Future<void> Function(String)? cancelBirthdayReminders,
    Future<void> Function(int)? cancelNotification,
  }) : _databaseProvider = databaseProvider ?? _defaultDatabaseProvider,
       _syncBirthdayReminder =
           syncBirthdayReminder ?? ReminderSyncService.instance.syncBirthday,
       _cancelBirthdayReminders =
           cancelBirthdayReminders ??
           (cancelNotification == null
               ? ReminderSyncService.instance.cancelBirthday
               : null),
       _cancelNotification = cancelNotification;

  final _uuid = const Uuid();
  final Future<Database> Function() _databaseProvider;
  final Future<void> Function(BirthdayModel) _syncBirthdayReminder;
  final Future<void> Function(String)? _cancelBirthdayReminders;
  final Future<void> Function(int)? _cancelNotification;

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
    if (!BirthdayDateHelper.isValidDate(
      isLunar: model.isLunar,
      month: model.month,
      day: model.day,
    )) {
      throw ArgumentError('Invalid birthday date.');
    }
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
    await _cancelBirthdayRemindersBestEffort(id);
  }

  Future<void> _cancelBirthdayRemindersBestEffort(String birthdayId) async {
    final birthdayCanceller = _cancelBirthdayReminders;
    if (birthdayCanceller != null) {
      try {
        await birthdayCanceller(birthdayId);
      } catch (_) {}
      return;
    }
    final legacyCanceller = _cancelNotification!;
    await _cancelBestEffort(
      legacyCanceller,
      ReminderSyncService.birthdayAdvanceId(birthdayId),
    );
    await _cancelBestEffort(
      legacyCanceller,
      ReminderSyncService.birthdayDayId(birthdayId),
    );
  }

  Future<void> _cancelBestEffort(
    Future<void> Function(int) cancelNotification,
    int notificationId,
  ) async {
    try {
      await cancelNotification(notificationId);
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
    await db.update(
      'ideas',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class VaultAccessDeniedException implements Exception {
  const VaultAccessDeniedException();

  @override
  String toString() => 'Vault access denied: the vault session is not valid.';
}

class VaultRepository {
  VaultRepository({
    Future<Database> Function()? databaseProvider,
    Future<String> Function(String)? encryptVaultField,
    Future<String> Function(String)? decryptVaultField,
    String Function()? createId,
    DateTime Function()? now,
  }) : _databaseProvider = databaseProvider ?? _defaultDatabaseProvider,
       _encryptVaultField =
           encryptVaultField ?? EncryptionService.instance.encryptVaultField,
       _decryptVaultField =
           decryptVaultField ?? EncryptionService.instance.decryptVaultField,
       _createId = createId ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final Future<Database> Function() _databaseProvider;
  final Future<String> Function(String) _encryptVaultField;
  final Future<String> Function(String) _decryptVaultField;
  final String Function() _createId;
  final DateTime Function() _now;

  static Future<Database> _defaultDatabaseProvider() {
    return DatabaseHelper.instance.database;
  }

  void _requireCapability(VaultSessionCapability capability) {
    if (!SessionService.instance.isVaultCapabilityValid(capability)) {
      throw const VaultAccessDeniedException();
    }
  }

  Future<List<VaultEntryModel>> getAll({
    required VaultSessionCapability capability,
    String? category,
  }) async {
    _requireCapability(capability);
    final db = await _databaseProvider();
    _requireCapability(capability);
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
    _requireCapability(capability);
    return rows.map(VaultEntryModel.fromMap).toList();
  }

  Future<void> saveEntry({
    required VaultSessionCapability capability,
    String? id,
    required String category,
    required String name,
    required String account,
    required String password,
    String? notes,
  }) async {
    _requireCapability(capability);
    final passwordEnc = await _encryptVaultField(password);
    _requireCapability(capability);
    final notesEnc = notes != null && notes.isNotEmpty
        ? await _encryptVaultField(notes)
        : null;
    _requireCapability(capability);
    final now = _now();
    final entry = VaultEntryModel(
      id: id ?? _createId(),
      category: category,
      name: name,
      account: account,
      passwordEnc: passwordEnc,
      notesEnc: notesEnc,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _databaseProvider();
    _requireCapability(capability);
    await db.transaction((transaction) async {
      _requireCapability(capability);
      await transaction.insert(
        'vault_entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _requireCapability(capability);
    });
  }

  Future<String> decryptPassword(
    VaultEntryModel entry, {
    required VaultSessionCapability capability,
  }) async {
    _requireCapability(capability);
    final password = await _decryptVaultField(entry.passwordEnc);
    _requireCapability(capability);
    return password;
  }

  Future<void> softDelete(
    String id, {
    required VaultSessionCapability capability,
  }) async {
    _requireCapability(capability);
    final db = await _databaseProvider();
    _requireCapability(capability);
    await db.transaction((transaction) async {
      _requireCapability(capability);
      await transaction.update(
        'vault_entries',
        {'is_deleted': 1, 'updated_at': _now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      _requireCapability(capability);
    });
  }
}
