import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../../core/services/notification_permission_coordinator.dart';
import '../../core/utils/ocr_service.dart';
import '../widgets/common_widgets.dart';

enum _OcrConfirmLoadState { loading, ready, notFound, failed }

class OcrConfirmScreen extends StatefulWidget {
  final String itemId;
  final ItemRepository? itemRepository;
  final NotificationPermissionCoordinator? notificationPermissionCoordinator;

  const OcrConfirmScreen({
    super.key,
    required this.itemId,
    this.itemRepository,
    this.notificationPermissionCoordinator,
  });

  @override
  State<OcrConfirmScreen> createState() => _OcrConfirmScreenState();
}

class _OcrConfirmScreenState extends State<OcrConfirmScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _startAt;
  String _type = 'meeting';
  Uint8List? _thumb;
  String? _loadedItemId;
  _OcrConfirmLoadState _loadState = _OcrConfirmLoadState.loading;
  bool _saving = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OcrConfirmScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId ||
        oldWidget.itemRepository != widget.itemRepository) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final itemId = widget.itemId;
    final repository = widget.itemRepository ?? context.read<AppState>().items;
    _title.clear();
    _location.clear();
    _notes.clear();
    setState(() {
      _loadedItemId = null;
      _type = 'meeting';
      _startAt = null;
      _thumb = null;
      _saving = false;
      _loadState = _OcrConfirmLoadState.loading;
    });
    try {
      final item = await repository.getById(itemId);
      if (!_isCurrentLoad(generation, itemId)) return;
      if (item == null || item.id != itemId) {
        setState(() => _loadState = _OcrConfirmLoadState.notFound);
        return;
      }

      final parsed = OcrParser.parse(item.ocrText ?? '');
      _title.text = item.title;
      _location.text = item.location ?? parsed['location'] ?? '';
      _notes.text = item.notes ?? '';
      _type = item.type;
      _startAt = item.startAt;
      if (_startAt == null && parsed['startAt'] != null) {
        _startAt = DateTime.tryParse(parsed['startAt']!);
      }
      setState(() {
        _loadedItemId = itemId;
        _loadState = _OcrConfirmLoadState.ready;
      });

      await _loadPreview(repository, generation, itemId);
    } catch (_) {
      if (!_isCurrentLoad(generation, itemId)) return;
      setState(() {
        _loadedItemId = null;
        _loadState = _OcrConfirmLoadState.failed;
      });
    }
  }

  bool _isCurrentLoad(int generation, String itemId) {
    return mounted && generation == _loadGeneration && widget.itemId == itemId;
  }

  bool _isCurrentOperation(int generation, String itemId) {
    return _isCurrentLoad(generation, itemId) &&
        _loadState == _OcrConfirmLoadState.ready &&
        _loadedItemId == itemId;
  }

  Future<void> _loadPreview(
    ItemRepository repository,
    int generation,
    String itemId,
  ) async {
    try {
      final attachments = await repository.getAttachments(itemId);
      if (!_isCurrentLoad(generation, itemId) || attachments.isEmpty) return;
      final asset = await AssetEntity.fromId(attachments.first.assetId);
      if (!_isCurrentLoad(generation, itemId) || asset == null) return;
      final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(400, 400),
      );
      if (!_isCurrentLoad(generation, itemId) || thumb == null) return;
      setState(() => _thumb = thumb);
    } catch (_) {
      if (!_isCurrentLoad(generation, itemId)) return;
      setState(() => _thumb = null);
    }
  }

  Future<void> _pickTime() async {
    final generation = _loadGeneration;
    final itemId = widget.itemId;
    if (!_isCurrentOperation(generation, itemId)) return;
    final date = await showDatePicker(
      context: context,
      initialDate: _startAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null ||
        !mounted ||
        !_isCurrentOperation(generation, itemId)) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt ?? DateTime.now()),
    );
    if (time == null ||
        !mounted ||
        !_isCurrentOperation(generation, itemId)) {
      return;
    }
    setState(() {
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _confirm() async {
    final generation = _loadGeneration;
    final itemId = widget.itemId;
    if (_saving || !_isCurrentOperation(generation, itemId)) return;
    final form = (
      type: _type,
      title: _title.text.trim(),
      location: _location.text.trim(),
      notes: _notes.text.trim(),
      startAt: _startAt,
    );
    if (form.title.isEmpty) {
      snack(context, '请输入标题');
      return;
    }
    final isPending = isPendingItemType(form.type);
    if (!isPending && form.startAt == null) {
      snack(context, '请设置时间');
      return;
    }
    setState(() => _saving = true);

    final repository = widget.itemRepository ?? context.read<AppState>().items;
    final permissionCoordinator =
        widget.notificationPermissionCoordinator ??
        NotificationPermissionCoordinator.instance;
    try {
      final item = await repository.getById(itemId);
      if (!mounted || !_isCurrentOperation(generation, itemId)) return;
      if (item == null || item.id != itemId) {
        setState(() => _saving = false);
        snack(context, '事项不存在或已删除');
        return;
      }

      final updated = item.copyWith(
        type: form.type,
        title: form.title,
        location: form.location.isEmpty ? null : form.location,
        notes: form.notes.isEmpty ? null : form.notes,
        startAt: form.startAt,
        inboxStatus: 'confirmed',
        pendingStatus: isPending ? (item.pendingStatus ?? 'submitted') : null,
        nextFollowUpAt: isPending
            ? (item.nextFollowUpAt ??
                  DateTime.now().add(const Duration(days: 7)))
            : null,
        status: isPending ? 'active' : item.status,
      );
      final permissionResult = await permissionCoordinator.requestThenPersist(
        requiresPermission: itemHasActiveReminder(updated),
        persist: () async {
          if (!_isCurrentOperation(generation, itemId)) return;
          await repository.save(updated);
        },
      );
      if (!mounted || !_isCurrentOperation(generation, itemId)) return;
      setState(() => _saving = false);
      snack(
        context,
        permissionResult.warningMessage ?? (isPending ? '已加入悬而未决' : '已加入日历'),
      );
      context.go(isPending ? '/pending' : '/calendar');
    } catch (_) {
      if (!mounted || !_isCurrentOperation(generation, itemId)) return;
      setState(() => _saving = false);
      snack(context, '保存失败，请重试');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('确认内容')),
      body: switch (_loadState) {
        _OcrConfirmLoadState.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        _OcrConfirmLoadState.notFound => const Center(child: Text('事项不存在或已删除')),
        _OcrConfirmLoadState.failed => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('事项加载失败，请重试'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
        _OcrConfirmLoadState.ready => _buildReady(),
      },
    );
  }

  Widget _buildReady() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_thumb != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _thumb!,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _type,
          decoration: const InputDecoration(labelText: '类型'),
          items: AppConstants.itemTypes
              .map(
                (type) =>
                    DropdownMenuItem(value: type.id, child: Text(type.label)),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) => setState(() => _type = value ?? 'meeting'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('时间'),
          subtitle: Text(
            _startAt?.toString().substring(0, 16) ??
                (isPendingItemType(_type) ? '未设置' : '未设置（必填）'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _saving ? null : _pickTime,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _location,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: '地点'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          enabled: !_saving,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '备注 / OCR 原文可修改'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: Text(_saving ? '保存中…' : '确认入库'),
        ),
      ],
    );
  }
}
