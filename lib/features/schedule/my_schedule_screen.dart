import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'schedule_support.dart';

class MyScheduleScreen extends StatefulWidget {
  const MyScheduleScreen({super.key});

  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  List<ScheduleEntryModel> _entries = [];
  ScheduleSettingsModel? _settings;
  int? _selectedWeek;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final entries = await app.schedules.getByOwner(AppConstants.ownerSelf);
    final settings = await app.schedules.getSettings();
    final autoWeek = settings.currentWeekFor(DateTime.now());
    setState(() {
      _entries = entries;
      _settings = settings;
      _selectedWeek ??= autoWeek ?? settings.semesterStartWeek;
      if (_selectedWeek! < settings.semesterStartWeek ||
          _selectedWeek! > settings.semesterEndWeek) {
        _selectedWeek = autoWeek ?? settings.semesterStartWeek;
      }
    });
  }

  Future<void> _add() async {
    final settings = _settings;
    if (settings == null) return;
    final draft = await showScheduleEntryEditor(
      context,
      dialogTitle: '添加上课',
      settings: settings,
    );
    if (draft == null) return;
    final conflicts = await context.read<AppState>().schedules.findConflicts(
      owner: AppConstants.ownerSelf,
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
      owner: AppConstants.ownerSelf,
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
    await _load();
  }

  Future<void> _edit(ScheduleEntryModel entry) async {
    final settings = _settings;
    if (settings == null) return;
    final draft = await showScheduleEntryEditor(
      context,
      dialogTitle: '编辑课程',
      settings: settings,
      initialEntry: entry,
    );
    if (draft == null) return;
    final conflicts = await context.read<AppState>().schedules.findConflicts(
      owner: AppConstants.ownerSelf,
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

  Future<void> _delete(ScheduleEntryModel entry) async {
    final action = await ConfirmDeleteDialog.show(
      context,
      title: '删除课程',
      message: '仅删除课表记录',
      showHardDelete: false,
    );
    if (action == 'soft') {
      await context.read<AppState>().schedules.softDelete(entry.id);
      await _load();
    }
  }

  int _timeToMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return 0;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return hour * 60 + minute;
  }

  @override
  Widget build(BuildContext context) {
    final timeSlots = scheduleSectionPresets
        .where((preset) => preset.id != 'custom')
        .toList();
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final settings = _settings;
    final selectedWeek = _selectedWeek;
    final autoWeek = settings?.currentWeekFor(DateTime.now());
    final activeEntries =
        selectedWeek == null
              ? _entries
              : _entries.where((e) => e.matchesWeek(selectedWeek)).toList()
          ..sort((a, b) {
            final weekdayCompare = a.weekday.compareTo(b.weekday);
            if (weekdayCompare != 0) return weekdayCompare;
            return a.startTime.compareTo(b.startTime);
          });

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的课表'),
        actions: [
          IconButton(
            onPressed: () async {
              await context.push('/schedule-settings');
              if (!mounted) return;
              _load();
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(onPressed: _add, icon: const Icon(Icons.add)),
        ],
      ),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '学期周设置',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '当前学期：第${settings.semesterStartWeek}-${settings.semesterEndWeek}周',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (settings.semesterStartDate != null)
                                Text(
                                  '开学日期：${settings.semesterStartDate!.year}-${settings.semesterStartDate!.month.toString().padLeft(2, '0')}-${settings.semesterStartDate!.day.toString().padLeft(2, '0')}，自动定位到第$selectedWeek周',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 128,
                          child: DropdownButtonFormField<int>(
                            value: selectedWeek,
                            decoration: const InputDecoration(
                              labelText: '查看周次',
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
                              : () => setState(() => _selectedWeek = autoWeek),
                          child: const Text('本周'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        AppColors.primary.withValues(alpha: 0.08),
                      ),
                      columns: [
                        const DataColumn(label: Text('时间')),
                        ...days.map((d) => DataColumn(label: Text(d))),
                      ],
                      rows: timeSlots.map((slot) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    slot.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    slot.detail,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            ...List.generate(7, (di) {
                              final wd = di + 1;
                              final match = activeEntries.where(
                                (e) =>
                                    e.weekday == wd &&
                                    e.startTime == slot.startTime &&
                                    e.endTime == slot.endTime,
                              );
                              if (match.isEmpty) {
                                final overlap = activeEntries.where(
                                  (e) =>
                                      e.weekday == wd &&
                                      !(e.endMinutes <=
                                              _timeToMinutes(slot.startTime) ||
                                          e.startMinutes >=
                                              _timeToMinutes(slot.endTime)),
                                );
                                if (overlap.isEmpty) {
                                  return const DataCell(Text(''));
                                }
                                final entry = overlap.first;
                                return DataCell(
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentOrange.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${entry.title}\n${entry.startTime}-${entry.endTime}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                );
                              }
                              final entry = match.first;
                              return DataCell(
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${entry.title}\n${entry.location ?? ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '第$selectedWeek周课程明细',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (activeEntries.isEmpty)
                          const Text(
                            '本周暂无课程',
                            style: TextStyle(color: AppColors.textSecondary),
                          )
                        else
                          ...activeEntries.map(
                            (entry) => ListTile(
                              onTap: () => _edit(entry),
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.title),
                              subtitle: Text(
                                '周${const ['一', '二', '三', '四', '五', '六', '日'][entry.weekday - 1]} '
                                '${entry.startTime}-${entry.endTime}'
                                '${entry.location == null ? '' : ' · ${entry.location}'}\n'
                                '${entry.weekDescription}',
                              ),
                              trailing: IconButton(
                                onPressed: () => _delete(entry),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
