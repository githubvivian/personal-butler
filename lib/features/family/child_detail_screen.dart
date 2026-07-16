import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../../core/repositories/schedule_repository.dart';
import '../widgets/common_widgets.dart';
import '../schedule/schedule_support.dart';

class ChildDetailScreen extends StatefulWidget {
  final String ownerId;
  final ScheduleRepository? scheduleRepository;
  final ItemRepository? itemRepository;

  const ChildDetailScreen({
    super.key,
    required this.ownerId,
    this.scheduleRepository,
    this.itemRepository,
  });

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<ScheduleEntryModel> _schedule = [];
  List<ItemModel> _events = [];
  ScheduleSettingsModel? _settings;
  int? _selectedWeek;
  DataLoadStatus _loadStatus = DataLoadStatus.loading;
  int _loadGeneration = 0;
  int _mutationGeneration = 0;
  bool _mutationInFlight = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void didUpdateWidget(covariant ChildDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.scheduleRepository != widget.scheduleRepository ||
        oldWidget.itemRepository != widget.itemRepository) {
      _mutationGeneration++;
      _mutationInFlight = false;
      _selectedWeek = null;
      _load();
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final ownerId = widget.ownerId;
    final schedules =
        widget.scheduleRepository ?? context.read<AppState>().schedules;
    final items = widget.itemRepository ?? context.read<AppState>().items;
    if (mounted) {
      setState(() {
        _loadStatus = DataLoadStatus.loading;
        _schedule = [];
        _events = [];
        _settings = null;
      });
    }
    try {
      final schedule = await schedules.getByOwner(ownerId);
      final settings = await schedules.getSettings();
      final now = DateTime.now();
      final events = await items.getFamilyItems(now, [ownerId]);
      if (!mounted ||
          generation != _loadGeneration ||
          ownerId != widget.ownerId) {
        return;
      }
      final autoWeek = settings.currentWeekFor(now);
      var selectedWeek =
          _selectedWeek ?? autoWeek ?? settings.semesterStartWeek;
      if (selectedWeek < settings.semesterStartWeek ||
          selectedWeek > settings.semesterEndWeek) {
        selectedWeek = autoWeek ?? settings.semesterStartWeek;
      }
      setState(() {
        _loadStatus = DataLoadStatus.ready;
        _schedule = schedule;
        _events = events;
        _settings = settings;
        _selectedWeek = selectedWeek;
      });
    } catch (_) {
      if (!mounted ||
          generation != _loadGeneration ||
          ownerId != widget.ownerId) {
        return;
      }
      setState(() {
        _loadStatus = DataLoadStatus.failed;
        _schedule = [];
        _events = [];
        _settings = null;
      });
    }
  }

  int? _beginMutation() {
    if (_mutationInFlight || !mounted) return null;
    final generation = ++_mutationGeneration;
    setState(() => _mutationInFlight = true);
    return generation;
  }

  bool _isCurrentMutation(int generation, String ownerId) {
    return mounted &&
        _mutationInFlight &&
        generation == _mutationGeneration &&
        ownerId == widget.ownerId;
  }

  void _finishMutation(int generation) {
    if (!mounted || generation != _mutationGeneration) return;
    setState(() => _mutationInFlight = false);
  }

  Future<void> _addClass() async {
    final generation = _beginMutation();
    if (generation == null) return;
    final ownerId = widget.ownerId;
    final settings = _settings;
    final schedules =
        widget.scheduleRepository ?? context.read<AppState>().schedules;
    try {
      if (settings == null) return;
      final draft = await showScheduleEntryEditor(
        context,
        dialogTitle: '添加${AppConstants.ownerLabel(ownerId)}课程',
        settings: settings,
      );
      if (!mounted ||
          !_isCurrentMutation(generation, ownerId) ||
          draft == null) {
        return;
      }
      final conflicts = await schedules.findConflicts(
        owner: ownerId,
        weekday: draft.weekday,
        startTime: draft.startTime,
        endTime: draft.endTime,
        startWeek: draft.startWeek,
        endWeek: draft.endWeek,
        repeatMode: draft.repeatMode,
        customWeeks: draft.customWeeksText,
      );
      if (!mounted || !_isCurrentMutation(generation, ownerId)) return;
      if (conflicts.isNotEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('发现课表冲突'),
            content: Text(
              '以下课程与当前新增内容存在时间冲突：\n\n${scheduleConflictMessage(conflicts)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍然保存'),
              ),
            ],
          ),
        );
        if (!mounted ||
            !_isCurrentMutation(generation, ownerId) ||
            shouldContinue != true) {
          return;
        }
      }
      await schedules.create(
        owner: ownerId,
        title: draft.title,
        weekday: draft.weekday,
        startTime: draft.startTime,
        endTime: draft.endTime,
        location: draft.location,
        startWeek: draft.startWeek,
        endWeek: draft.endWeek,
        repeatMode: draft.repeatMode,
        customWeeks: draft.customWeeksText,
      );
      if (!mounted || !_isCurrentMutation(generation, ownerId)) return;
      await _load();
    } catch (_) {
      if (mounted && _isCurrentMutation(generation, ownerId)) {
        snack(context, '保存课程失败，请重试');
      }
    } finally {
      _finishMutation(generation);
    }
  }

  Future<void> _editClass(ScheduleEntryModel entry) async {
    final generation = _beginMutation();
    if (generation == null) return;
    final ownerId = widget.ownerId;
    final settings = _settings;
    final schedules =
        widget.scheduleRepository ?? context.read<AppState>().schedules;
    try {
      if (settings == null) return;
      final draft = await showScheduleEntryEditor(
        context,
        dialogTitle: '编辑${AppConstants.ownerLabel(ownerId)}课程',
        settings: settings,
        initialEntry: entry,
      );
      if (!mounted ||
          !_isCurrentMutation(generation, ownerId) ||
          draft == null) {
        return;
      }
      final conflicts = await schedules.findConflicts(
        owner: ownerId,
        weekday: draft.weekday,
        startTime: draft.startTime,
        endTime: draft.endTime,
        startWeek: draft.startWeek,
        endWeek: draft.endWeek,
        repeatMode: draft.repeatMode,
        customWeeks: draft.customWeeksText,
        excludeId: entry.id,
      );
      if (!mounted || !_isCurrentMutation(generation, ownerId)) return;
      if (conflicts.isNotEmpty) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('发现课表冲突'),
            content: Text(
              '以下课程与当前修改内容存在时间冲突：\n\n${scheduleConflictMessage(conflicts)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍然保存'),
              ),
            ],
          ),
        );
        if (!mounted ||
            !_isCurrentMutation(generation, ownerId) ||
            shouldContinue != true) {
          return;
        }
      }
      final updated = entry.copyWith(
        title: draft.title,
        weekday: draft.weekday,
        startTime: draft.startTime,
        endTime: draft.endTime,
        location: draft.location,
        startWeek: draft.startWeek,
        endWeek: draft.endWeek,
        repeatMode: draft.repeatMode,
        customWeeks: draft.customWeeksText,
      );
      await schedules.save(updated);
      if (!mounted || !_isCurrentMutation(generation, ownerId)) return;
      await _load();
    } catch (_) {
      if (mounted && _isCurrentMutation(generation, ownerId)) {
        snack(context, '保存课程失败，请重试');
      }
    } finally {
      _finishMutation(generation);
    }
  }

  Future<void> _deleteClass(ScheduleEntryModel entry) async {
    final generation = _beginMutation();
    if (generation == null) return;
    final ownerId = widget.ownerId;
    final schedules =
        widget.scheduleRepository ?? context.read<AppState>().schedules;
    try {
      final action = await ConfirmDeleteDialog.show(
        context,
        title: '删除课程',
        message: '仅删除课表记录',
        showHardDelete: false,
      );
      if (!mounted ||
          !_isCurrentMutation(generation, ownerId) ||
          action != 'soft') {
        return;
      }
      await schedules.softDelete(entry.id);
      if (!mounted || !_isCurrentMutation(generation, ownerId)) return;
      await _load();
    } catch (_) {
      if (mounted && _isCurrentMutation(generation, ownerId)) {
        snack(context, '删除课程失败，请重试');
      }
    } finally {
      _finishMutation(generation);
    }
  }

  String _weekLabel(int w) => const ['一', '二', '三', '四', '五', '六', '日'][w - 1];

  @override
  Widget build(BuildContext context) {
    final name = AppConstants.ownerLabel(widget.ownerId);
    final settings = _settings;
    final selectedWeek = _selectedWeek;
    final autoWeek = settings?.currentWeekFor(DateTime.now());
    final activeSchedule =
        selectedWeek == null
              ? _schedule
              : _schedule
                    .where((entry) => entry.matchesWeek(selectedWeek))
                    .toList()
          ..sort((a, b) {
            final weekdayCompare = a.weekday.compareTo(b.weekday);
            if (weekdayCompare != 0) return weekdayCompare;
            return a.startTime.compareTo(b.startTime);
          });
    return Scaffold(
      appBar: AppBar(
        title: Text('$name'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '课表'),
            Tab(text: '活动'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _mutationInFlight || _loadStatus != DataLoadStatus.ready
                ? null
                : _addClass,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loadStatus == DataLoadStatus.loading
          ? const Center(child: CircularProgressIndicator())
          : _loadStatus == DataLoadStatus.failed
          ? Center(child: DataLoadFailure(onRetry: _load))
          : TabBarView(
              controller: _tab,
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (settings != null)
                        AppCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '当前查看第$selectedWeek周 · 学期第${settings.semesterStartWeek}-${settings.semesterEndWeek}周',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (settings.semesterStartDate != null)
                                      Text(
                                        '开学日期：${settings.semesterStartDate!.year}-${settings.semesterStartDate!.month.toString().padLeft(2, '0')}-${settings.semesterStartDate!.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 124,
                                child: DropdownButtonFormField<int>(
                                  value: selectedWeek,
                                  decoration: const InputDecoration(
                                    labelText: '周次',
                                  ),
                                  items: [
                                    for (
                                      int week = settings.semesterStartWeek;
                                      week <= settings.semesterEndWeek;
                                      week++
                                    )
                                      DropdownMenuItem(
                                        value: week,
                                        child: Text('第$week周'),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _selectedWeek = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: autoWeek == null
                                    ? null
                                    : () => setState(
                                        () => _selectedWeek = autoWeek,
                                      ),
                                child: const Text('本周'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      ...List.generate(7, (i) {
                        final wd = i + 1;
                        final dayItems = activeSchedule
                            .where((e) => e.weekday == wd)
                            .toList();
                        return AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '周${_weekLabel(wd)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (dayItems.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    '无课程',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                )
                              else
                                ...dayItems.map(
                                  (e) => ListTile(
                                    onTap: _mutationInFlight
                                        ? null
                                        : () => _editClass(e),
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(e.title),
                                    subtitle: Text(
                                      '${e.startTime}-${e.endTime} ${e.location ?? ''}\n${e.weekDescription}',
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: AppColors.danger,
                                      ),
                                      onPressed: _mutationInFlight
                                          ? null
                                          : () => _deleteClass(e),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: _events.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            Center(child: Text('暂无活动')),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _events.length,
                          itemBuilder: (_, i) {
                            final e = _events[i];
                            return AppCard(
                              child: ListTile(
                                title: Text(e.title),
                                subtitle: Text(e.location ?? ''),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
