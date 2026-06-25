import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../widgets/common_widgets.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<ItemModel> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final app = context.read<AppState>();
    _items = await app.items.getPendingItems(includeDone: _tab.index == 3);
    setState(() => _loading = false);
  }

  List<ItemModel> get _filtered {
    switch (_tab.index) {
      case 1:
        return _items.where((i) => i.pendingStatus == 'need_action').toList();
      case 2:
        return _items
            .where((i) => i.pendingStatus != 'done' && i.pendingStatus != 'need_action')
            .toList();
      case 3:
        return _items.where((i) => i.status == 'done').toList();
      default:
        return _items;
    }
  }

  String _statusLabel(String? id) {
    return AppConstants.pendingStatuses
        .firstWhere((s) => s.id == id, orElse: () => (id: id ?? '', label: id ?? '未知'))
        .label;
  }

  Future<void> _postpone(ItemModel item) async {
    final app = context.read<AppState>();
    await app.items.save(
      item.copyWith(nextFollowUpAt: DateTime.now().add(const Duration(days: 7))),
    );
    _load();
  }

  Future<void> _updateStatus(ItemModel item) async {
    final statuses = AppConstants.pendingStatuses;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: statuses
              .map((s) => ListTile(
                    title: Text(s.label),
                    onTap: () => Navigator.pop(context, s.id),
                  ))
              .toList(),
        ),
      ),
    );
    if (selected == null) return;
    final app = context.read<AppState>();
    await app.items.save(
      item.copyWith(
        pendingStatus: selected,
        status: selected == 'done' ? 'done' : item.status,
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('悬而未决'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          onTap: (_) => _load(),
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '待我处理'),
            Tab(text: '进行中'),
            Tab(text: '已完成'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _filtered.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      Center(child: Text('暂无悬而未决事项')),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _card(_filtered[i]),
                    ),
            ),
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
                  child: Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (item.amount != null)
                  Text('¥${item.amount!.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppColors.accentOrange, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text('提交：${DateFormat('yyyy-MM-dd').format(item.createdAt)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Text('状态：${_statusLabel(item.pendingStatus)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
