import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../../core/services/notification_permission_coordinator.dart';
import '../widgets/common_widgets.dart';

class CreateItemScreen extends StatefulWidget {
  const CreateItemScreen({
    super.key,
    this.itemRepository,
    this.notificationPermissionCoordinator,
  });

  final ItemRepository? itemRepository;
  final NotificationPermissionCoordinator? notificationPermissionCoordinator;

  @override
  State<CreateItemScreen> createState() => _CreateItemScreenState();
}

class _CreateItemScreenState extends State<CreateItemScreen> {
  final _uuid = const Uuid();
  String _type = 'meeting';
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _amount = TextEditingController();
  String _owner = AppConstants.ownerSelf;
  DateTime? _startAt;
  int _reminderMinutes = 60;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _amount.dispose();
    super.dispose();
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

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      snack(context, '请输入标题');
      return;
    }
    final isPending = isPendingItemType(_type);
    if (!isPending && _startAt == null) {
      snack(context, '请设置时间');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final item = ItemModel(
        id: _uuid.v4(),
        type: _type,
        title: _title.text.trim(),
        owner: _owner,
        startAt: _startAt,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        amount: double.tryParse(_amount.text.trim()),
        inboxStatus: 'confirmed',
        pendingStatus: isPending ? 'submitted' : null,
        nextFollowUpAt: isPending ? now.add(const Duration(days: 7)) : null,
        reminderMinutes: _reminderMinutes,
        createdAt: now,
        updatedAt: now,
      );
      final repository =
          widget.itemRepository ?? context.read<AppState>().items;
      final permissionResult =
          await (widget.notificationPermissionCoordinator ??
                  NotificationPermissionCoordinator.instance)
              .requestThenPersist(
                requiresPermission: itemHasActiveReminder(item),
                persist: () => repository.save(item),
              );
      if (!mounted) return;
      snack(context, permissionResult.warningMessage ?? '已保存');
      context.pop();
    } catch (_) {
      if (mounted) snack(context, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = isPendingItemType(_type);
    return Scaffold(
      appBar: AppBar(title: const Text('创建事项')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: AppConstants.itemTypes.map((t) {
              final selected = _type == t.id;
              return ChoiceChip(
                avatar: Icon(t.icon, size: 18),
                label: Text(t.label),
                selected: selected,
                onSelected: (_) => setState(() => _type = t.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(controller: _title, decoration: const InputDecoration(labelText: '标题')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _owner,
            decoration: const InputDecoration(labelText: '归属'),
            items: AppConstants.owners
                .map((o) => DropdownMenuItem(value: o.id, child: Text(o.label)))
                .toList(),
            onChanged: (v) => setState(() => _owner = v ?? _owner),
          ),
          if (!isPending) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('时间'),
              subtitle: Text(_startAt?.toString().substring(0, 16) ?? (isPending ? '未设置' : '未设置（必填）')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTime,
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: '地点')),
          if (isPending) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '金额（可选）'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: '备注')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _reminderMinutes,
            decoration: const InputDecoration(labelText: '提前提醒'),
            items: const [
              DropdownMenuItem(value: 15, child: Text('15分钟')),
              DropdownMenuItem(value: 60, child: Text('1小时')),
              DropdownMenuItem(value: 1440, child: Text('1天')),
            ],
            onChanged: (v) => setState(() => _reminderMinutes = v ?? 60),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('create-save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}

enum _ItemDetailLoadState { loading, ready, notFound, failed }

class ItemDetailScreen extends StatefulWidget {
  final String itemId;
  final ItemRepository? itemRepository;

  const ItemDetailScreen({
    super.key,
    required this.itemId,
    this.itemRepository,
  });

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  ItemModel? _item;
  _ItemDetailLoadState _loadState = _ItemDetailLoadState.loading;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ItemDetailScreen oldWidget) {
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
    setState(() {
      _item = null;
      _loadState = _ItemDetailLoadState.loading;
    });
    try {
      final item = await repository.getById(itemId);
      if (!_isCurrentLoad(generation, itemId)) return;
      setState(() {
        _item = item;
        _loadState = item == null
            ? _ItemDetailLoadState.notFound
            : _ItemDetailLoadState.ready;
      });
    } catch (_) {
      if (!_isCurrentLoad(generation, itemId)) return;
      setState(() {
        _item = null;
        _loadState = _ItemDetailLoadState.failed;
      });
    }
  }

  bool _isCurrentLoad(int generation, String itemId) {
    return mounted && generation == _loadGeneration && widget.itemId == itemId;
  }

  Future<void> _delete() async {
    final item = _item;
    final itemId = widget.itemId;
    final generation = _loadGeneration;
    if (_loadState != _ItemDetailLoadState.ready || item?.id != itemId) return;
    final repository = widget.itemRepository ?? context.read<AppState>().items;
    final action = await ConfirmDeleteDialog.show(
      context,
      title: '删除事项',
      message: '移入已删除可保留记录；彻底删除不可恢复。相册原图不会被删除。',
    );
    if (action == null ||
        !_isCurrentLoad(generation, itemId) ||
        _loadState != _ItemDetailLoadState.ready ||
        _item?.id != itemId) {
      return;
    }
    if (action == 'hard') {
      await repository.hardDelete(itemId);
    } else {
      await repository.softDelete(itemId);
    }
    if (!mounted || !_isCurrentLoad(generation, itemId)) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('事项详情'),
        actions: _loadState == _ItemDetailLoadState.ready
            ? [
                IconButton(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ]
            : null,
      ),
      body: switch (_loadState) {
        _ItemDetailLoadState.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        _ItemDetailLoadState.notFound => const Center(child: Text('事项不存在或已删除')),
        _ItemDetailLoadState.failed => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('事项加载失败，请重试'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
        _ItemDetailLoadState.ready => _buildReady(_item!),
      },
    );
  }

  Widget _buildReady(ItemModel item) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              OwnerChip(ownerId: item.owner),
              const SizedBox(height: 16),
              _row(Icons.category, '类型', AppConstants.itemTypes.firstWhere((t) => t.id == item.type, orElse: () => (id: item.type, label: item.type, icon: Icons.label)).label),
              if (item.startAt != null)
                _row(Icons.access_time, '时间', DateFormat('yyyy-MM-dd HH:mm').format(item.startAt!)),
              if (item.location != null) _row(Icons.place, '地点', item.location!),
              if (item.participants != null) _row(Icons.people, '参与人', item.participants!),
              if (item.amount != null) _row(Icons.payments, '金额', '¥${item.amount!.toStringAsFixed(2)}'),
              if (item.pendingStatus != null)
                _row(Icons.pending, '流程状态', AppConstants.pendingStatuses.firstWhere((s) => s.id == item.pendingStatus, orElse: () => (id: item.pendingStatus!, label: item.pendingStatus!)).label),
              if (item.notes != null) _row(Icons.notes, '备注', item.notes!),
              _row(Icons.notifications, '提醒', '提前 ${item.reminderMinutes} 分钟'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
