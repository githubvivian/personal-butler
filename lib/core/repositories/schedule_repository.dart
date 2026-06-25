import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class ScheduleRepository {
  final _uuid = const Uuid();

  Future<ScheduleSettingsModel> getSettings() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'schedule_settings',
      where: 'id = ?',
      whereArgs: ['default'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return ScheduleSettingsModel.fromMap(rows.first);
    }
    final settings = ScheduleSettingsModel(updatedAt: DateTime.now());
    await saveSettings(settings);
    return settings;
  }

  Future<void> saveSettings(ScheduleSettingsModel settings) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'schedule_settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ScheduleEntryModel>> getByOwner(String owner) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'schedule_entries',
      where: 'owner = ? AND is_deleted = 0',
      whereArgs: [owner],
      orderBy: 'weekday ASC, start_time ASC',
    );
    return rows.map(ScheduleEntryModel.fromMap).toList();
  }

  Future<void> save(ScheduleEntryModel entry) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'schedule_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ScheduleEntryModel> create({
    required String owner,
    required String title,
    required int weekday,
    required String startTime,
    required String endTime,
    String? location,
    required int startWeek,
    required int endWeek,
    String repeatMode = 'all',
    String? customWeeks,
  }) async {
    final entry = ScheduleEntryModel(
      id: _uuid.v4(),
      owner: owner,
      title: title,
      weekday: weekday,
      startTime: startTime,
      endTime: endTime,
      location: location,
      startWeek: startWeek,
      endWeek: endWeek,
      repeatMode: repeatMode,
      customWeeks: customWeeks,
      createdAt: DateTime.now(),
    );
    await save(entry);
    return entry;
  }

  Future<List<ScheduleEntryModel>> findConflicts({
    required String owner,
    required int weekday,
    required String startTime,
    required String endTime,
    required int startWeek,
    required int endWeek,
    String repeatMode = 'all',
    String? customWeeks,
    String? excludeId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'schedule_entries',
      where: 'owner = ? AND weekday = ? AND is_deleted = 0',
      whereArgs: [owner, weekday],
      orderBy: 'start_time ASC',
    );

    final candidate = ScheduleEntryModel(
      id: excludeId ?? '_candidate_',
      owner: owner,
      title: '',
      weekday: weekday,
      startTime: startTime,
      endTime: endTime,
      startWeek: startWeek,
      endWeek: endWeek,
      repeatMode: repeatMode,
      customWeeks: customWeeks,
      createdAt: DateTime.now(),
    );

    final conflicts = <ScheduleEntryModel>[];
    for (final row in rows) {
      final existing = ScheduleEntryModel.fromMap(row);
      if (excludeId != null && existing.id == excludeId) continue;
      if (_hasConflict(existing, candidate)) {
        conflicts.add(existing);
      }
    }
    return conflicts;
  }

  bool _hasConflict(ScheduleEntryModel a, ScheduleEntryModel b) {
    final latestStart = a.startMinutes > b.startMinutes
        ? a.startMinutes
        : b.startMinutes;
    final earliestEnd = a.endMinutes < b.endMinutes
        ? a.endMinutes
        : b.endMinutes;
    final timeOverlaps = latestStart < earliestEnd;
    if (!timeOverlaps) return false;

    final aWeeks = a.activeWeeks().toSet();
    final bWeeks = b.activeWeeks().toSet();
    return aWeeks.intersection(bWeeks).isNotEmpty;
  }

  Future<void> softDelete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'schedule_entries',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
