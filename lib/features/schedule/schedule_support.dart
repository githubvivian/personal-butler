import 'package:flutter/material.dart';
import '../../core/models/models.dart';

class ScheduleSectionPreset {
  final String id;
  final String label;
  final String detail;
  final String startTime;
  final String endTime;

  const ScheduleSectionPreset({
    required this.id,
    required this.label,
    required this.detail,
    required this.startTime,
    required this.endTime,
  });
}

const scheduleSectionPresets = [
  ScheduleSectionPreset(
    id: 'section1',
    label: '第一大节',
    detail: '8:00-8:45 / 8:55-9:40',
    startTime: '08:00',
    endTime: '09:40',
  ),
  ScheduleSectionPreset(
    id: 'section2',
    label: '第二大节',
    detail: '10:00-11:40',
    startTime: '10:00',
    endTime: '11:40',
  ),
  ScheduleSectionPreset(
    id: 'lab',
    label: '中午实验课',
    detail: '12:30-14:20',
    startTime: '12:30',
    endTime: '14:20',
  ),
  ScheduleSectionPreset(
    id: 'section3',
    label: '第三大节',
    detail: '14:30-16:10',
    startTime: '14:30',
    endTime: '16:10',
  ),
  ScheduleSectionPreset(
    id: 'section4',
    label: '第四大节',
    detail: '16:30-18:10',
    startTime: '16:30',
    endTime: '18:10',
  ),
  ScheduleSectionPreset(
    id: 'section5',
    label: '第五大节',
    detail: '19:30-21:10',
    startTime: '19:30',
    endTime: '21:10',
  ),
  ScheduleSectionPreset(
    id: 'custom',
    label: '自定义时间',
    detail: '手动输入开始和结束时间',
    startTime: '',
    endTime: '',
  ),
];

int? scheduleTimeToMinutes(String value) {
  final match = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').firstMatch(value.trim());
  if (match == null) return null;
  final parts = value.trim().split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String? scheduleTimeRangeError(String startTime, String endTime) {
  final startMinutes = scheduleTimeToMinutes(startTime);
  final endMinutes = scheduleTimeToMinutes(endTime);
  if (startMinutes == null || endMinutes == null) {
    return '时间格式应为 HH:mm（例如 08:00）';
  }
  if (endMinutes <= startMinutes) return '结束时间必须晚于开始时间';
  return null;
}

String scheduleConflictMessage(List<ScheduleEntryModel> conflicts) {
  return conflicts
      .map(
        (e) =>
            '${e.title}（周${const ['一', '二', '三', '四', '五', '六', '日'][e.weekday - 1]} '
            '${e.startTime}-${e.endTime}，${e.weekDescription}）',
      )
      .join('\n');
}

class ScheduleEntryDraft {
  final String title;
  final String? location;
  final int weekday;
  final String startTime;
  final String endTime;
  final int startWeek;
  final int endWeek;
  final String repeatMode;
  final List<int> customWeeks;
  final String sectionPresetId;

  const ScheduleEntryDraft({
    required this.title,
    this.location,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.startWeek,
    required this.endWeek,
    required this.repeatMode,
    required this.customWeeks,
    required this.sectionPresetId,
  });

  String? get customWeeksText {
    if (repeatMode != 'custom' || customWeeks.isEmpty) return null;
    return customWeeks.join(',');
  }
}

Future<ScheduleEntryDraft?> showScheduleEntryEditor(
  BuildContext context, {
  required String dialogTitle,
  required ScheduleSettingsModel settings,
  ScheduleEntryModel? initialEntry,
}) async {
  String inferPresetId(String startTime, String endTime) {
    final preset = scheduleSectionPresets
        .where((preset) => preset.id != 'custom')
        .firstWhere(
          (preset) =>
              preset.startTime == startTime && preset.endTime == endTime,
          orElse: () => scheduleSectionPresets.last,
        );
    return preset.id;
  }

  final title = TextEditingController(text: initialEntry?.title ?? '');
  final location = TextEditingController(text: initialEntry?.location ?? '');
  final titleStart =
      initialEntry?.startTime ?? scheduleSectionPresets.first.startTime;
  final titleEnd =
      initialEntry?.endTime ?? scheduleSectionPresets.first.endTime;
  final start = TextEditingController(text: titleStart);
  final end = TextEditingController(text: titleEnd);
  int weekday = initialEntry?.weekday ?? 1;
  int startWeek = initialEntry?.startWeek ?? settings.semesterStartWeek;
  int endWeek = initialEntry?.endWeek ?? settings.semesterEndWeek;
  String repeatMode = initialEntry?.repeatMode ?? 'all';
  String sectionPresetId = inferPresetId(titleStart, titleEnd);
  final customWeeks = <int>{...(initialEntry?.customWeekList ?? const <int>[])};
  String? errorText;

  final result = await showDialog<ScheduleEntryDraft>(
    context: context,
    builder: (_) => _ScheduleEditorControllerOwner(
      controllers: [title, location, start, end],
      child: StatefulBuilder(
        builder: (context, setLocal) {
          final weekItems = [
            for (
              int week = settings.semesterStartWeek;
              week <= settings.semesterEndWeek;
              week++
            )
              DropdownMenuItem(value: week, child: Text('第$week周')),
          ];
          return AlertDialog(
            title: Text(dialogTitle),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: '课程名称'),
                    ),
                    TextField(
                      controller: location,
                      decoration: const InputDecoration(labelText: '地点/教室'),
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: sectionPresetId,
                      decoration: const InputDecoration(labelText: '节次模板'),
                      items: scheduleSectionPresets
                          .map(
                            (preset) => DropdownMenuItem(
                              value: preset.id,
                              child: Text('${preset.label}  ${preset.detail}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setLocal(() {
                          sectionPresetId = value;
                          final preset = scheduleSectionPresets.firstWhere(
                            (item) => item.id == value,
                          );
                          if (preset.id != 'custom') {
                            start.text = preset.startTime;
                            end.text = preset.endTime;
                          }
                        });
                      },
                    ),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: weekday,
                      decoration: const InputDecoration(labelText: '星期'),
                      items: List.generate(
                        7,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text(
                            '周${const ['一', '二', '三', '四', '五', '六', '日'][i]}',
                          ),
                        ),
                      ),
                      onChanged: (v) => setLocal(() => weekday = v ?? 1),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: start,
                            decoration: const InputDecoration(
                              labelText: '开始时间',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: end,
                            decoration: const InputDecoration(
                              labelText: '结束时间',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '上课周次',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: startWeek,
                            decoration: const InputDecoration(labelText: '起始周'),
                            items: weekItems,
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() {
                                startWeek = v;
                                if (endWeek < startWeek) endWeek = startWeek;
                                customWeeks.removeWhere(
                                  (week) => week < startWeek || week > endWeek,
                                );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: endWeek,
                            decoration: const InputDecoration(labelText: '结束周'),
                            items: weekItems
                                .where((item) => item.value! >= startWeek)
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() {
                                endWeek = v;
                                customWeeks.removeWhere(
                                  (week) => week < startWeek || week > endWeek,
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: repeatMode,
                      decoration: const InputDecoration(labelText: '排课规则'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('每周')),
                        DropdownMenuItem(value: 'odd', child: Text('单周')),
                        DropdownMenuItem(value: 'even', child: Text('双周')),
                        DropdownMenuItem(value: 'custom', child: Text('自定义周')),
                      ],
                      onChanged: (v) => setLocal(() => repeatMode = v ?? 'all'),
                    ),
                    if (repeatMode == 'custom') ...[
                      const SizedBox(height: 8),
                      const Text(
                        '选择具体周次',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (int week = startWeek; week <= endWeek; week++)
                            FilterChip(
                              label: Text('$week'),
                              selected: customWeeks.contains(week),
                              onSelected: (selected) {
                                setLocal(() {
                                  if (selected) {
                                    customWeeks.add(week);
                                  } else {
                                    customWeeks.remove(week);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final courseTitle = title.text.trim();
                  if (courseTitle.isEmpty) {
                    setLocal(() => errorText = '请填写课程名称');
                    return;
                  }
                  final timeError = scheduleTimeRangeError(
                    start.text,
                    end.text,
                  );
                  if (timeError != null) {
                    setLocal(() => errorText = timeError);
                    return;
                  }
                  if (startWeek > endWeek) {
                    setLocal(() => errorText = '起始周不能大于结束周');
                    return;
                  }
                  if (repeatMode == 'custom' && customWeeks.isEmpty) {
                    setLocal(() => errorText = '请选择至少一个具体周次');
                    return;
                  }
                  Navigator.pop(
                    context,
                    ScheduleEntryDraft(
                      title: courseTitle,
                      location: location.text.trim().isEmpty
                          ? null
                          : location.text.trim(),
                      weekday: weekday,
                      startTime: start.text.trim(),
                      endTime: end.text.trim(),
                      startWeek: startWeek,
                      endWeek: endWeek,
                      repeatMode: repeatMode,
                      customWeeks: customWeeks.toList()..sort(),
                      sectionPresetId: sectionPresetId,
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    ),
  );

  return result;
}

class _ScheduleEditorControllerOwner extends StatefulWidget {
  const _ScheduleEditorControllerOwner({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_ScheduleEditorControllerOwner> createState() =>
      _ScheduleEditorControllerOwnerState();
}

class _ScheduleEditorControllerOwnerState
    extends State<_ScheduleEditorControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
