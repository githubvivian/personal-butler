import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../widgets/common_widgets.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final Set<String> _selected = {
    AppConstants.ownerBeibei,
    AppConstants.ownerHetao,
    AppConstants.ownerFamily,
  };
  DateTime _day = DateTime.now();
  List<ItemModel> _events = [];
  late ItemRepository _repository;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = context.read<AppState>().items;
    _repository.addListener(_handleItemMutation);
    _load();
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _repository.removeListener(_handleItemMutation);
    super.dispose();
  }

  void _handleItemMutation() => _load();

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final owners = _selected.toList();
    final day = _day;
    if (_selected.contains(AppConstants.ownerSelf)) {
      // self handled separately if needed
    }
    try {
      final events = await _repository.getFamilyItems(day, owners);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _events = events);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: '课表',
            onPressed: () => context.push('/schedule'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              children: [
                _filterChip('全部', {
                  AppConstants.ownerBeibei,
                  AppConstants.ownerHetao,
                  AppConstants.ownerFamily,
                }),
                _filterChip('贝贝', {AppConstants.ownerBeibei}),
                _filterChip('核桃', {AppConstants.ownerHetao}),
                _filterChip('家庭', {AppConstants.ownerFamily}),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    _day = _day.subtract(const Duration(days: 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat('M月d日 安排', 'zh_CN').format(_day),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _day = DateTime.now();
                    _load();
                  },
                  child: const Text('今天'),
                ),
                IconButton(
                  onPressed: () {
                    _day = _day.add(const Duration(days: 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._events.map(_eventCard),
            if (_events.isEmpty)
              const AppCard(child: Text('今日暂无家庭安排，可在创建事项时选择归属为贝贝或核桃')),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/child/${AppConstants.ownerBeibei}'),
                    icon: const Icon(Icons.child_care),
                    label: const Text('贝贝详情'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/child/${AppConstants.ownerHetao}'),
                    icon: const Icon(Icons.child_care),
                    label: const Text('核桃详情'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, Set<String> ids) {
    final selected =
        _selected.length == ids.length && ids.every(_selected.contains);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selected
            ..clear()
            ..addAll(ids);
        });
        _load();
      },
    );
  }

  Widget _eventCard(ItemModel item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        accentColor: AppColors.forOwner(item.owner),
        onTap: () => context.push('/item/${item.id}'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (item.startAt != null)
                    Text(
                      DateFormat('HH:mm').format(item.startAt!),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            OwnerChip(ownerId: item.owner),
          ],
        ),
      ),
    );
  }
}
