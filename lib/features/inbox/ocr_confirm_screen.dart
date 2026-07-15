import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../../core/services/notification_permission_coordinator.dart';
import '../../core/utils/ocr_service.dart';
import '../widgets/common_widgets.dart';

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
  String? _assetId;
  Uint8List? _thumb;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = widget.itemRepository ?? context.read<AppState>().items;
    final item = await repository.getById(widget.itemId);
    if (item == null) return;
    final parsed = OcrParser.parse(item.ocrText ?? '');
    _title.text = item.title;
    _location.text = item.location ?? parsed['location'] ?? '';
    _notes.text = item.notes ?? '';
    _type = item.type;
    if (item.startAt != null) {
      _startAt = item.startAt;
    } else if (parsed['startAt'] != null) {
      _startAt = DateTime.tryParse(parsed['startAt']!);
    }
    final attachments = await repository.getAttachments(widget.itemId);
    if (attachments.isNotEmpty) {
      _assetId = attachments.first.assetId;
      final asset = await AssetEntity.fromId(_assetId!);
      _thumb = await asset?.thumbnailDataWithSize(const ThumbnailSize(400, 400));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() {
      _startAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _confirm() async {
    final repository = widget.itemRepository ?? context.read<AppState>().items;
    final item = await repository.getById(widget.itemId);
    if (item == null) return;

    final isPending = _type == 'reimbursement' || _type == 'review';
    final updated = item.copyWith(
      type: _type,
      title: _title.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      startAt: _startAt,
      inboxStatus: 'confirmed',
      pendingStatus: isPending ? (item.pendingStatus ?? 'submitted') : null,
      nextFollowUpAt: isPending
          ? (item.nextFollowUpAt ?? DateTime.now().add(const Duration(days: 7)))
          : null,
      status: isPending ? 'active' : item.status,
    );
    final permissionResult =
        await (widget.notificationPermissionCoordinator ??
                NotificationPermissionCoordinator.instance)
            .requestThenPersist(
              requiresPermission: itemHasActiveReminder(updated),
              persist: () => repository.save(updated),
            );
    if (!mounted) return;
    snack(
      context,
      permissionResult.warningMessage ?? (isPending ? '已加入悬而未决' : '已加入日历'),
    );
    context.go(isPending ? '/pending' : '/calendar');
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_thumb != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_thumb!, height: 160, width: double.infinity, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: AppConstants.itemTypes
                      .map((t) => DropdownMenuItem(value: t.id, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v ?? 'meeting'),
                ),
                const SizedBox(height: 12),
                TextField(controller: _title, decoration: const InputDecoration(labelText: '标题')),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('时间'),
                  subtitle: Text(_startAt?.toString().substring(0, 16) ?? '未设置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickTime,
                ),
                const SizedBox(height: 12),
                TextField(controller: _location, decoration: const InputDecoration(labelText: '地点')),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '备注 / OCR 原文可修改'),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _confirm, child: const Text('确认入库')),
              ],
            ),
    );
  }
}
