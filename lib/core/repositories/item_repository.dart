import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../services/reminder_sync_service.dart';

class ItemRepository {
  final _uuid = const Uuid();

  Future<List<ItemModel>> getInboxItems() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'items',
      where: 'inbox_status = ? AND is_deleted = 0',
      whereArgs: ['inbox'],
      orderBy: 'created_at DESC',
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<List<ItemModel>> getPendingItems({bool includeDone = false}) async {
    final db = await DatabaseHelper.instance.database;
    final types = ['reimbursement', 'review'];
    final placeholders = List.filled(types.length, '?').join(',');
    var where =
        'type IN ($placeholders) AND inbox_status = ? AND is_deleted = 0';
    final args = [...types, 'confirmed'];
    if (!includeDone) {
      where += " AND status != 'done'";
    }
    final rows = await db.query(
      'items',
      where: where,
      whereArgs: args,
      orderBy: 'next_follow_up_at ASC',
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<List<ItemModel>> getCalendarItems(DateTime day) async {
    final db = await DatabaseHelper.instance.database;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.query(
      'items',
      where:
          'is_deleted = 0 AND inbox_status = ? AND start_at >= ? AND start_at < ?',
      whereArgs: [
        'confirmed',
        start.toIso8601String(),
        end.toIso8601String(),
      ],
      orderBy: 'start_at ASC',
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<List<ItemModel>> getFamilyItems(DateTime day, List<String> owners) async {
    final db = await DatabaseHelper.instance.database;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    if (owners.isEmpty) return [];
    final ownerPh = List.filled(owners.length, '?').join(',');
    final rows = await db.query(
      'items',
      where:
          'is_deleted = 0 AND inbox_status = ? AND owner IN ($ownerPh) AND start_at >= ? AND start_at < ?',
      whereArgs: [
        'confirmed',
        ...owners,
        start.toIso8601String(),
        end.toIso8601String(),
      ],
      orderBy: 'start_at ASC',
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<ItemModel?> getById(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('items', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ItemModel.fromMap(rows.first);
  }

  Future<List<ItemModel>> getAllActiveConfirmed() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'items',
      where: 'is_deleted = 0 AND inbox_status = ?',
      whereArgs: ['confirmed'],
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<void> save(ItemModel item) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await ReminderSyncService.instance.syncItem(item);
  }

  Future<ItemModel> createDraft({
    required String type,
    String title = '',
    String inboxStatus = 'inbox',
    String? ocrText,
    String owner = 'self',
  }) async {
    final now = DateTime.now();
    final item = ItemModel(
      id: _uuid.v4(),
      type: type,
      title: title.isEmpty ? '新事项' : title,
      owner: owner,
      inboxStatus: inboxStatus,
      pendingStatus: type == 'reimbursement' || type == 'review' ? 'submitted' : null,
      nextFollowUpAt: type == 'reimbursement' || type == 'review'
          ? now.add(const Duration(days: 7))
          : null,
      ocrText: ocrText,
      createdAt: now,
      updatedAt: now,
    );
    await save(item);
    return item;
  }

  Future<void> softDelete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'items',
      {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await NotificationService.instance.cancel(id.hashCode);
    await NotificationService.instance.cancel(ReminderSyncService.pendingId(id));
  }

  Future<void> hardDelete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('attachments', where: 'item_id = ?', whereArgs: [id]);
    await db.delete('items', where: 'id = ?', whereArgs: [id]);
    await NotificationService.instance.cancel(id.hashCode);
    await NotificationService.instance.cancel(ReminderSyncService.pendingId(id));
  }

  Future<List<AttachmentModel>> getAttachments(String itemId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'attachments',
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
    return rows.map(AttachmentModel.fromMap).toList();
  }

  Future<void> addAttachment({
    required String itemId,
    required String assetId,
    String? displayName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('attachments', {
      'id': _uuid.v4(),
      'item_id': itemId,
      'asset_id': assetId,
      'display_name': displayName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, int>> getTodayStats() async {
    final db = await DatabaseHelper.instance.database;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    final inbox = await db.rawQuery(
      'SELECT COUNT(*) as c FROM items WHERE inbox_status = ? AND is_deleted = 0',
      ['inbox'],
    );
    final pending = await db.rawQuery(
      "SELECT COUNT(*) as c FROM items WHERE type IN ('reimbursement','review') AND status != 'done' AND is_deleted = 0",
    );
    final todayItems = await db.rawQuery(
      'SELECT COUNT(*) as c FROM items WHERE start_at >= ? AND start_at < ? AND is_deleted = 0',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return {
      'inbox': inbox.first['c'] as int? ?? 0,
      'pending': pending.first['c'] as int? ?? 0,
      'today': todayItems.first['c'] as int? ?? 0,
    };
  }
}
