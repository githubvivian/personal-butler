import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../services/reminder_sync_service.dart';

class ItemRepository extends ChangeNotifier {
  ItemRepository({
    Future<Database> Function()? databaseProvider,
    Future<void> Function(ItemModel)? syncItemReminder,
    Future<void> Function(int)? cancelNotification,
  }) : _databaseProvider = databaseProvider ?? _defaultDatabaseProvider,
       _syncItemReminder =
           syncItemReminder ?? ReminderSyncService.instance.syncItem,
       _cancelNotification =
           cancelNotification ?? NotificationService.instance.cancel;

  final _uuid = const Uuid();
  final Future<Database> Function() _databaseProvider;
  final Future<void> Function(ItemModel) _syncItemReminder;
  final Future<void> Function(int) _cancelNotification;
  final Map<String, Future<void>> _itemMutationTails = {};

  static Future<Database> _defaultDatabaseProvider() {
    return DatabaseHelper.instance.database;
  }

  Future<List<ItemModel>> getInboxItems() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'items',
      where: 'inbox_status = ? AND is_deleted = 0',
      whereArgs: ['inbox'],
      orderBy: 'created_at DESC',
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<List<ItemModel>> getPendingItems({bool includeDone = false}) async {
    final db = await _databaseProvider();
    final types = pendingItemTypes;
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
    final db = await _databaseProvider();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.query(
      'items',
      where:
          'is_deleted = 0 AND inbox_status = ? AND start_at >= ? AND start_at < ?',
      whereArgs: ['confirmed', start.toIso8601String(), end.toIso8601String()],
      orderBy: 'start_at ASC',
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<List<ItemModel>> getFamilyItems(
    DateTime day,
    List<String> owners,
  ) async {
    final db = await _databaseProvider();
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
    final db = await _databaseProvider();
    final rows = await db.query(
      'items',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return ItemModel.fromMap(rows.first);
  }

  Future<List<ItemModel>> getAllActiveConfirmed() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'items',
      where: 'is_deleted = 0 AND inbox_status = ?',
      whereArgs: ['confirmed'],
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<void> save(ItemModel item) {
    return _serializeItemMutation(item.id, () async {
      final db = await _databaseProvider();
      await db.transaction((txn) async {
        final existing = await txn.query(
          'items',
          columns: ['is_deleted'],
          where: 'id = ?',
          whereArgs: [item.id],
        );
        if (existing.isEmpty) {
          await txn.insert('items', item.toMap());
          return;
        }
        if ((existing.single['is_deleted'] as int? ?? 0) == 1) {
          throw StateError('Cannot save an item that has been deleted.');
        }
        final changed = await txn.update(
          'items',
          item.toMap(),
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [item.id],
        );
        if (changed == 0) {
          throw StateError('Cannot save an item that has been deleted.');
        }
      });
      notifyListeners();
      await _syncReminderBestEffort(item);
    });
  }

  Future<ItemModel?> updatePendingFollowUp(String id, DateTime nextFollowUpAt) {
    return _updateActiveItemFields(id, {
      'next_follow_up_at': nextFollowUpAt.toIso8601String(),
    });
  }

  Future<ItemModel?> updatePendingStatus(
    String id, {
    required String pendingStatus,
    required String status,
  }) {
    return _updateActiveItemFields(id, {
      'pending_status': pendingStatus,
      'status': status,
    });
  }

  Future<ItemModel?> _updateActiveItemFields(
    String id,
    Map<String, Object?> fields,
  ) {
    return _serializeItemMutation(id, () async {
      final db = await _databaseProvider();
      final updated = await db.transaction<ItemModel?>((txn) async {
        final changed = await txn.update(
          'items',
          {...fields, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [id],
        );
        if (changed == 0) return null;
        final rows = await txn.query(
          'items',
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [id],
        );
        if (rows.isEmpty) return null;
        return ItemModel.fromMap(rows.single);
      });
      if (updated == null) return null;
      notifyListeners();
      await _syncReminderBestEffort(updated);
      return updated;
    });
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
      pendingStatus: isPendingItemType(type) ? 'submitted' : null,
      nextFollowUpAt: isPendingItemType(type)
          ? now.add(const Duration(days: 7))
          : null,
      ocrText: ocrText,
      createdAt: now,
      updatedAt: now,
    );
    await save(item);
    return item;
  }

  Future<ItemModel> createOcrDraftWithAttachment({
    required String ocrText,
    required String assetId,
    String title = '',
    String? displayName,
    String owner = 'self',
  }) async {
    if (ocrText.trim().isEmpty) {
      throw ArgumentError('OCR text must not be blank.');
    }
    if (assetId.trim().isEmpty) {
      throw ArgumentError('Asset ID must not be blank.');
    }

    final now = DateTime.now();
    final item = ItemModel(
      id: _uuid.v4(),
      type: 'meeting',
      title: title.isEmpty ? '新事项' : title,
      owner: owner,
      inboxStatus: 'inbox',
      ocrText: ocrText,
      createdAt: now,
      updatedAt: now,
    );
    final attachment = AttachmentModel(
      id: _uuid.v4(),
      itemId: item.id,
      assetId: assetId,
      displayName: displayName,
      createdAt: now,
    );
    final db = await _databaseProvider();

    await db.transaction((txn) async {
      await txn.insert('items', item.toMap());
      await txn.insert('attachments', attachment.toMap());
    });
    notifyListeners();

    return item;
  }

  Future<void> softDelete(String id) {
    return _serializeItemMutation(id, () async {
      final db = await _databaseProvider();
      final changed = await db.update(
        'items',
        {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed > 0) notifyListeners();
      await _cancelBestEffort(ReminderSyncService.itemId(id));
      await _cancelBestEffort(ReminderSyncService.pendingId(id));
    });
  }

  Future<void> hardDelete(String id) {
    return _serializeItemMutation(id, () async {
      final db = await _databaseProvider();
      final changed = await db.transaction((txn) async {
        await txn.delete('attachments', where: 'item_id = ?', whereArgs: [id]);
        return txn.delete('items', where: 'id = ?', whereArgs: [id]);
      });
      if (changed > 0) notifyListeners();
      await _cancelBestEffort(ReminderSyncService.itemId(id));
      await _cancelBestEffort(ReminderSyncService.pendingId(id));
    });
  }

  Future<T> _serializeItemMutation<T>(
    String id,
    Future<T> Function() mutation,
  ) async {
    final previous = _itemMutationTails[id] ?? Future<void>.value();
    final completer = Completer<void>();
    final tail = completer.future;
    _itemMutationTails[id] = tail;
    await previous;
    try {
      return await mutation();
    } finally {
      completer.complete();
      if (identical(_itemMutationTails[id], tail)) {
        _itemMutationTails.remove(id);
      }
    }
  }

  Future<void> _syncReminderBestEffort(ItemModel item) async {
    try {
      await _syncItemReminder(item);
    } catch (_) {}
  }

  Future<void> _cancelBestEffort(int notificationId) async {
    try {
      await _cancelNotification(notificationId);
    } catch (_) {}
  }

  Future<List<AttachmentModel>> getAttachments(String itemId) async {
    final db = await _databaseProvider();
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
    final db = await _databaseProvider();
    await db.insert('attachments', {
      'id': _uuid.v4(),
      'item_id': itemId,
      'asset_id': assetId,
      'display_name': displayName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Signals that data was committed outside this repository, such as after
  /// replacing the database from a validated backup.
  void invalidateAfterExternalWrite() => notifyListeners();

  Future<Map<String, int>> getTodayStats() async {
    final db = await _databaseProvider();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    final inbox = await db.rawQuery(
      'SELECT COUNT(*) as c FROM items WHERE inbox_status = ? AND is_deleted = 0',
      ['inbox'],
    );
    final pendingPlaceholders = List.filled(
      pendingItemTypes.length,
      '?',
    ).join(',');
    final pending = await db.rawQuery(
      'SELECT COUNT(*) as c FROM items '
      'WHERE type IN ($pendingPlaceholders) AND inbox_status = ? '
      "AND status != 'done' AND is_deleted = 0",
      [...pendingItemTypes, 'confirmed'],
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
