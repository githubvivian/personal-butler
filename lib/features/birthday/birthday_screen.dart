import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/utils/lunar_date_helper.dart';
import '../widgets/common_widgets.dart';

class BirthdayScreen extends StatefulWidget {
  const BirthdayScreen({super.key});

  @override
  State<BirthdayScreen> createState() => _BirthdayScreenState();
}

class _BirthdayScreenState extends State<BirthdayScreen> {
  List<BirthdayModel> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _items = await context.read<AppState>().birthdays.getAll();
    setState(() {});
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final relation = TextEditingController();
    bool isLunar = false;
    int month = 1;
    int day = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('添加生日'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: '姓名')),
                TextField(controller: relation, decoration: const InputDecoration(labelText: '关系')),
                SwitchListTile(
                  title: const Text('农历生日'),
                  value: isLunar,
                  onChanged: (v) => setLocal(() => isLunar = v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(labelText: '月'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => month = int.tryParse(v) ?? month,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(labelText: '日'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => day = int.tryParse(v) ?? day,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await context.read<AppState>().birthdays.create(
          name: name.text.trim(),
          relation: relation.text.trim(),
          isLunar: isLunar,
          month: month,
          day: day,
        );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生日提醒'),
        actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items.isEmpty
            ? ListView(children: const [
                SizedBox(height: 80),
                Center(child: Text('暂无生日记录')),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (_, i) => _card(_items[i]),
              ),
      ),
    );
  }

  Widget _card(BirthdayModel b) {
    final next = LunarDateHelper.nextSolarOccurrence(
      isLunar: b.isLunar,
      month: b.month,
      day: b.day,
      isLeapMonth: b.isLeapMonth,
    );
    final days = next?.difference(DateTime.now()).inDays;
    final lunarLabel = b.isLunar
        ? LunarDateHelper.formatLunarLabel(b.month, b.day, isLeap: b.isLeapMonth)
        : '${b.month}月${b.day}日';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        accentColor: AppColors.accentPink,
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.accentPink.withValues(alpha: 0.15),
              child: Text(b.name.isNotEmpty ? b.name[0] : '?', style: const TextStyle(color: AppColors.accentPink)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  Text(
                    b.isLunar ? '农历 $lunarLabel' : '阳历 $lunarLabel',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (next != null)
                    Text(
                      '下次：${DateFormat('yyyy-MM-dd').format(next)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            if (days != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$days天', style: const TextStyle(color: AppColors.accentPink, fontWeight: FontWeight.bold)),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () async {
                final action = await ConfirmDeleteDialog.show(
                  context,
                  title: '删除生日',
                  message: '确认删除该生日提醒？',
                  showHardDelete: false,
                );
                if (action == 'soft') {
                  await context.read<AppState>().birthdays.softDelete(b.id);
                  _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
