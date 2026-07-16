import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/schedule_repository.dart';
import '../widgets/common_widgets.dart';

class ScheduleSettingsScreen extends StatefulWidget {
  const ScheduleSettingsScreen({super.key, this.scheduleRepository});

  final ScheduleRepository? scheduleRepository;

  @override
  State<ScheduleSettingsScreen> createState() => _ScheduleSettingsScreenState();
}

class _ScheduleSettingsScreenState extends State<ScheduleSettingsScreen> {
  ScheduleSettingsModel? _settings;
  int? _semesterStartWeek;
  int? _semesterEndWeek;
  DateTime? _semesterStartDate;
  bool _saving = false;
  DataLoadStatus _loadStatus = DataLoadStatus.loading;
  int _loadGeneration = 0;
  int _saveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ScheduleSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheduleRepository != widget.scheduleRepository) {
      _saveGeneration++;
      _saving = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final schedules =
        widget.scheduleRepository ?? context.read<AppState>().schedules;
    if (mounted) {
      setState(() {
        _loadStatus = DataLoadStatus.loading;
        _settings = null;
        _semesterStartWeek = null;
        _semesterEndWeek = null;
        _semesterStartDate = null;
      });
    }
    try {
      final settings = await schedules.getSettings();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadStatus = DataLoadStatus.ready;
        _settings = settings;
        _semesterStartWeek = settings.semesterStartWeek;
        _semesterEndWeek = settings.semesterEndWeek;
        _semesterStartDate = settings.semesterStartDate;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadStatus = DataLoadStatus.failed;
        _settings = null;
        _semesterStartWeek = null;
        _semesterEndWeek = null;
        _semesterStartDate = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _loadStatus != DataLoadStatus.ready) return;
    final start = _semesterStartWeek;
    final end = _semesterEndWeek;
    if (start == null || end == null) return;
    if (start > end) {
      snack(context, '开始周不能大于结束周');
      return;
    }
    final schedules =
        widget.scheduleRepository ?? context.read<AppState>().schedules;
    final settings = _settings;
    final generation = ++_saveGeneration;
    setState(() => _saving = true);
    try {
      await schedules.saveSettings(
        ScheduleSettingsModel(
          id: settings?.id ?? 'default',
          semesterStartWeek: start,
          semesterEndWeek: end,
          semesterStartDate: _semesterStartDate,
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted || generation != _saveGeneration) return;
      snack(context, '课表设置已保存');
    } catch (_) {
      if (!mounted || generation != _saveGeneration) return;
      snack(context, '保存课表设置失败，请重试');
    } finally {
      if (mounted && generation == _saveGeneration) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = _semesterStartWeek;
    final end = _semesterEndWeek;
    final startDate = _semesterStartDate;
    final totalText = (start != null && end != null && end >= start)
        ? '共 ${end - start + 1} 周'
        : '';
    final currentWeek = start == null || end == null || startDate == null
        ? null
        : ScheduleSettingsModel(
            id: _settings?.id ?? 'default',
            semesterStartWeek: start,
            semesterEndWeek: end,
            semesterStartDate: startDate,
            updatedAt: _settings?.updatedAt ?? DateTime.now(),
          ).currentWeekFor(DateTime.now());

    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('课表设置')),
      body: _loadStatus == DataLoadStatus.loading
          ? const Center(child: CircularProgressIndicator())
          : _loadStatus == DataLoadStatus.failed
          ? Center(child: DataLoadFailure(onRetry: _load))
          : settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '学期周范围',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '用于新增课程时限定可选周次，并在课表页切换查看具体周。',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_available_outlined),
                        title: const Text('开学日期'),
                        subtitle: Text(
                          startDate == null
                              ? '未设置，课表页仍可手动切换周次'
                              : DateFormat(
                                  'yyyy年M月d日',
                                  'zh_CN',
                                ).format(startDate),
                        ),
                        trailing: TextButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final loadGeneration = _loadGeneration;
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: startDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (!mounted ||
                                      picked == null ||
                                      loadGeneration != _loadGeneration) {
                                    return;
                                  }
                                  setState(() => _semesterStartDate = picked);
                                },
                          child: const Text('选择'),
                        ),
                      ),
                      if (startDate != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _saving
                                ? null
                                : () =>
                                      setState(() => _semesterStartDate = null),
                            child: const Text('清除开学日期'),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: start,
                              decoration: const InputDecoration(
                                labelText: '开始周',
                              ),
                              items: [
                                for (int week = 1; week <= 30; week++)
                                  DropdownMenuItem(
                                    value: week,
                                    child: Text('第$week周'),
                                  ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _semesterStartWeek = value;
                                        if ((_semesterEndWeek ?? value) <
                                            value) {
                                          _semesterEndWeek = value;
                                        }
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: end,
                              decoration: const InputDecoration(
                                labelText: '结束周',
                              ),
                              items: [
                                for (int week = start ?? 1; week <= 30; week++)
                                  DropdownMenuItem(
                                    value: week,
                                    child: Text('第$week周'),
                                  ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() => _semesterEndWeek = value);
                                    },
                            ),
                          ),
                        ],
                      ),
                      if (totalText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          totalText,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (currentWeek != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '按开学日期自动计算，当前为第$currentWeek周',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '说明',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('1. 每门课都可以单独设置起始周和结束周。'),
                      SizedBox(height: 4),
                      Text('2. 排课规则支持每周、单周、双周、自定义周次。'),
                      SizedBox(height: 4),
                      Text('3. 已存在课程若未设置周次，会默认按整学期每周生效。'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中...' : '保存设置'),
                ),
              ],
            ),
    );
  }
}
