import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../widgets/common_widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _format = CalendarFormat.week;
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  List<ItemModel> _dayItems = [];
  DataLoadStatus _loadStatus = DataLoadStatus.loading;
  bool _hasSnapshot = false;
  late ItemRepository _repository;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = context.read<AppState>().items;
    _repository.addListener(_handleItemMutation);
    _load(resetSnapshot: true);
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _repository.removeListener(_handleItemMutation);
    super.dispose();
  }

  void _handleItemMutation() => _load();

  Future<void> _load({bool resetSnapshot = false}) async {
    final generation = ++_loadGeneration;
    final selected = _selected;
    final repository = _repository;
    if (mounted) {
      setState(() {
        if (resetSnapshot) {
          _dayItems = [];
          _hasSnapshot = false;
        }
        _loadStatus = DataLoadStatus.loading;
      });
    }
    try {
      final items = await repository.getCalendarItems(selected);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _dayItems = items;
        _hasSnapshot = true;
        _loadStatus = DataLoadStatus.ready;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadStatus = DataLoadStatus.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          IconButton(
            icon: Icon(
              _format == CalendarFormat.week
                  ? Icons.calendar_view_month
                  : Icons.view_week,
            ),
            onPressed: () {
              setState(() {
                _format = _format == CalendarFormat.week
                    ? CalendarFormat.month
                    : CalendarFormat.week;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2100),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            calendarFormat: _format,
            onFormatChanged: (f) => setState(() => _format = f),
            onDaySelected: (s, f) {
              setState(() {
                _selected = s;
                _focused = f;
              });
              _load(resetSnapshot: true);
            },
            headerStyle: const HeaderStyle(formatButtonVisible: false),
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: AppColors.accentTeal,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(_selected),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: _buildDayItems(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayItems() {
    if (!_hasSnapshot) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 80),
          if (_loadStatus == DataLoadStatus.loading)
            const Center(child: CircularProgressIndicator())
          else
            DataLoadFailure(onRetry: () => _load()),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (_loadStatus == DataLoadStatus.loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        if (_loadStatus == DataLoadStatus.failed) ...[
          DataLoadFailure(onRetry: () => _load()),
          const SizedBox(height: 12),
        ],
        if (_dayItems.isEmpty) ...[
          const SizedBox(height: 80),
          const Center(child: Text('今天暂无日程')),
        ] else
          ..._dayItems.map(_timelineTile),
      ],
    );
  }

  Widget _timelineTile(ItemModel item) {
    final time = item.startAt != null
        ? DateFormat('HH:mm').format(item.startAt!)
        : '--:--';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        accentColor: AppColors.forItemType(item.type),
        onTap: () => context.push('/item/${item.id}'),
        child: Row(
          children: [
            Text(
              time,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (item.location != null)
                    Text(
                      item.location!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
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
