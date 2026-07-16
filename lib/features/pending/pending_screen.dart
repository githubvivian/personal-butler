import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../../core/services/notification_permission_coordinator.dart';
import '../widgets/common_widgets.dart';

typedef PendingItemBuilder =
    Widget Function(
      BuildContext context,
      ItemModel item,
      VoidCallback onPostpone,
      VoidCallback onUpdateStatus,
    );

class PendingScreen extends StatefulWidget {
  const PendingScreen({
    super.key,
    this.itemRepository,
    this.notificationPermissionCoordinator,
    this.itemBuilder,
  });

  final ItemRepository? itemRepository;
  final NotificationPermissionCoordinator? notificationPermissionCoordinator;
  final PendingItemBuilder? itemBuilder;

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class PendingReminderActions {
  const PendingReminderActions({
    required this.itemRepository,
    required this.notificationPermissionCoordinator,
  });

  final ItemRepository itemRepository;
  final NotificationPermissionCoordinator notificationPermissionCoordinator;

  Future<NotificationPermissionResult> postpone(ItemModel item) {
    return _persist(
      item.copyWith(
        nextFollowUpAt: DateTime.now().add(const Duration(days: 7)),
      ),
    );
  }

  Future<NotificationPermissionResult> updateStatus(
    ItemModel item,
    String selected,
  ) {
    return _persist(
      item.copyWith(
        pendingStatus: selected,
        status: selected == 'done' ? 'done' : 'active',
      ),
    );
  }

  Future<NotificationPermissionResult> _persist(ItemModel item) {
    return notificationPermissionCoordinator.requestThenPersist(
      requiresPermission: itemHasActiveReminder(item),
      persist: () => itemRepository.save(item),
    );
  }
}

class _PendingScreenState extends State<PendingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late ItemRepository _repository;
  List<ItemModel> _items = [];
  DataLoadStatus _loadStatus = DataLoadStatus.loading;
  bool _hasSnapshot = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _repository = _resolveRepository();
    _repository.addListener(_handleItemMutation);
    _load(resetSnapshot: true);
  }

  @override
  void didUpdateWidget(covariant PendingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemRepository != widget.itemRepository) {
      _bindRepository(_resolveRepository());
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _repository.removeListener(_handleItemMutation);
    _tab.dispose();
    super.dispose();
  }

  ItemRepository _resolveRepository() {
    return widget.itemRepository ?? context.read<AppState>().items;
  }

  void _bindRepository(ItemRepository repository) {
    if (identical(repository, _repository)) return;
    _repository.removeListener(_handleItemMutation);
    _repository = repository;
    _repository.addListener(_handleItemMutation);
    _load(resetSnapshot: true);
  }

  void _handleItemMutation() => _load();

  Future<void> _load({bool resetSnapshot = false}) async {
    final generation = ++_loadGeneration;
    final includeDone = _tab.index == 3;
    final repository = _repository;
    if (mounted) {
      setState(() {
        if (resetSnapshot) {
          _items = [];
          _hasSnapshot = false;
        }
        _loadStatus = DataLoadStatus.loading;
      });
    }
    try {
      final items = await repository.getPendingItems(includeDone: includeDone);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = items;
        _hasSnapshot = true;
        _loadStatus = DataLoadStatus.ready;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadStatus = DataLoadStatus.failed);
    }
  }

  List<ItemModel> get _filtered {
    switch (_tab.index) {
      case 1:
        return _items.where((i) => i.pendingStatus == 'need_action').toList();
      case 2:
        return _items
            .where(
              (i) =>
                  i.pendingStatus != 'done' && i.pendingStatus != 'need_action',
            )
            .toList();
      case 3:
        return _items.where((i) => i.status == 'done').toList();
      default:
        return _items;
    }
  }

  String _statusLabel(String? id) {
    return AppConstants.pendingStatuses
        .firstWhere(
          (s) => s.id == id,
          orElse: () => (id: id ?? '', label: id ?? '未知'),
        )
        .label;
  }

  PendingReminderActions get _actions => PendingReminderActions(
    itemRepository: _repository,
    notificationPermissionCoordinator:
        widget.notificationPermissionCoordinator ??
        NotificationPermissionCoordinator.instance,
  );

  Future<void> _postpone(ItemModel item) async {
    final permissionResult = await _actions.postpone(item);
    if (!mounted) return;
    final warning = permissionResult.warningMessage;
    if (warning != null) snack(context, warning);
  }

  Future<void> _updateStatus(ItemModel item) async {
    final statuses = AppConstants.pendingStatuses;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses
              .map(
                (s) => ListTile(
                  title: Text(s.label),
                  onTap: () => Navigator.pop(context, s.id),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final permissionResult = await _actions.updateStatus(item, selected);
    if (!mounted) return;
    final warning = permissionResult.warningMessage;
    if (warning != null) snack(context, warning);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('悬而未决'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          onTap: (_) => _load(resetSnapshot: true),
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '待我处理'),
            Tab(text: '进行中'),
            Tab(text: '已完成'),
          ],
        ),
      ),
      body: RefreshIndicator(onRefresh: () => _load(), child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (!_hasSnapshot) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 80),
          if (_loadStatus == DataLoadStatus.loading)
            const Center(child: CircularProgressIndicator())
          else
            DataLoadFailure(onRetry: () => _load()),
        ],
      );
    }

    final items = _filtered;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (_loadStatus == DataLoadStatus.loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        if (_loadStatus == DataLoadStatus.failed) ...[
          DataLoadFailure(onRetry: () => _load()),
          const SizedBox(height: 12),
        ],
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 68),
            child: Center(child: Text('暂无悬而未决事项')),
          )
        else
          ...items.map((item) {
            final itemBuilder = widget.itemBuilder;
            if (itemBuilder != null) {
              return itemBuilder(
                context,
                item,
                () => _postpone(item),
                () => _updateStatus(item),
              );
            }
            return _card(item);
          }),
      ],
    );
  }

  Widget _card(ItemModel item) {
    final follow = item.nextFollowUpAt;
    final daysLeft = follow == null
        ? null
        : follow.difference(DateTime.now()).inDays;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        accentColor: AppColors.forItemType(item.type),
        onTap: () => context.push('/item/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (item.amount != null)
                  Text(
                    '¥${item.amount!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '提交：${DateFormat('yyyy-MM-dd').format(item.createdAt)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            Text(
              '状态：${_statusLabel(item.pendingStatus)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (follow != null)
              Text(
                daysLeft != null && daysLeft >= 0
                    ? '下次关注：${DateFormat('MM-dd').format(follow)}（${daysLeft}天后）'
                    : '下次关注：已到期，建议查看',
                style: TextStyle(
                  color: daysLeft != null && daysLeft <= 0
                      ? AppColors.danger
                      : AppColors.accentOrange,
                  fontSize: 13,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => _postpone(item),
                  child: const Text('延期提醒'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => _updateStatus(item),
                  child: const Text('更新状态'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
