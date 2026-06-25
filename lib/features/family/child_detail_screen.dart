import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../widgets/common_widgets.dart';
import '../schedule/schedule_support.dart';

class ChildDetailScreen extends StatefulWidget {
  final String ownerId;
  const ChildDetailScreen({super.key, required this.ownerId});

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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    _schedule = await app.schedules.getByOwner(widget.ownerId);
    _settings = await app.schedules.getSettings();
    final now = DateTime.now();
    _events = await app.items.getFamilyItems(now, [widget.ownerId]);
    _selectedWeek ??=
        _settings?.currentWeekFor(DateTime.now()) ??
        _settings?.semesterStartWeek;
    if (_settings != null &&
        (_selectedWeek! < _settings!.semesterStartWeek ||
            _selectedWeek! > _settings!.semesterEndWeek)) {
      _selectedWeek =
          _settings!.currentWeekFor(DateTime.now()) ??
          _settings!.semesterStartWeek;
    }
    setState(() {});
  }

  Future<void> _addClass() async {
    final settings = _settings;
    if (settings == null) return;
    final draft = await showScheduleEntryEditor(
      context,
      dialogTitle: '添加${AppConstants.ownerLabel(widget.ownerId)}课程',
      settings: settings,
    );
    if (draft == null) return;
    final conflicts = await context.read<AppState>().schedules.findConflicts(
      owner: widget.ownerId,
      weekday: draft.weekday,
      startTime: draft.startTime,
      endTime: draft.endTime,
      startWeek: draft.startWeek,
      endWeek: draft.endWeek,
      repeatMode: draft.repeatMode,
      customWeeks: draft.customWeeksText,
    );
    if (conflicts.isNotEmpty) {
      if (!mounted) return;
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
      if (shouldContinue != true) return;
    }
    await context.read<AppState>().schedules.create(
      owner: widget.ownerId,
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
    _load();
  }

  Future<void> _editClass(ScheduleEntryModel entry) async {
    final settings = _settings;
    if (settings == null) return;
    final draft = await showScheduleEntryEditor(
      context,
      dialogTitle: '编辑${AppConstants.ownerLabel(widget.ownerId)}课程',
      settings: settings,
      initialEntry: entry,
    );
    if (draft == null) return;
    final conflicts = await context.read<AppState>().schedules.findConflicts(
      owner: widget.ownerId,
      weekday: draft.weekday,
      startTime: draft.startTime,
      endTime: draft.endTime,
      startWeek: draft.startWeek,
      endWeek: draft.endWeek,
      repeatMode: draft.repeatMode,
      customWeeks: draft.customWeeksText,
      excludeId: entry.id,
    );
    if (conflicts.isNotEmpty) {
      if (!mounted) return;
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
      if (shouldContinue != true) return;
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
    await context.read<AppState>().schedules.save(updated);
    await _load();
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
          IconButton(onPressed: _addClass, icon: const Icon(Icons.add)),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
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
                            decoration: const InputDecoration(labelText: '周次'),
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
                              : () => setState(() => _selectedWeek = autoWeek),
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
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (dayItems.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              '无课程',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        else
                          ...dayItems.map(
                            (e) => ListTile(
                              onTap: () => _editClass(e),
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
                                onPressed: () async {
                                  final action = await ConfirmDeleteDialog.show(
                                    context,
                                    title: '删除课程',
                                    message: '仅删除课表记录',
                                    showHardDelete: false,
                                  );
                                  if (action == 'soft') {
                                    await context
                                        .read<AppState>()
                                        .schedules
                                        .softDelete(e.id);
                                    _load();
                                  }
                                },
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
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('暂无活动')),
                    ],
                  )
                : ListView.builder(
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
