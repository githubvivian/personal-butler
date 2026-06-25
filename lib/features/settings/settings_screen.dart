import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_state.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, int> _stats = {};
  String _scheduleSummary = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _stats = await context.read<AppState>().items.getTodayStats();
    final ideas = await context.read<AppState>().ideas.getAll();
    final birthdays = await context.read<AppState>().birthdays.getAll();
    final scheduleSettings = await context
        .read<AppState>()
        .schedules
        .getSettings();
    _stats['ideas'] = ideas.length;
    _stats['birthdays'] = birthdays.length;
    _scheduleSummary =
        '第${scheduleSettings.semesterStartWeek}-${scheduleSettings.semesterEndWeek}周'
        '${scheduleSettings.semesterStartDate == null ? '' : ' · 已设开学日期'}';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.person,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '个人管家',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '本地加密 · 仅您使用',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _miniStat('今日', '${_stats['today'] ?? 0}'),
                _miniStat('悬停', '${_stats['pending'] ?? 0}'),
                _miniStat('灵感', '${_stats['ideas'] ?? 0}'),
                _miniStat('生日', '${_stats['birthdays'] ?? 0}'),
              ],
            ),
            const SizedBox(height: 20),
            _menuTile(
              Icons.lock_outline,
              '密码保险库',
              () => context.push('/vault'),
            ),
            _menuTile(
              Icons.backup_outlined,
              '数据备份与恢复',
              () => context.push('/backup'),
            ),
            _menuTile(
              Icons.lightbulb_outline,
              '灵感库',
              () => context.push('/ideas'),
            ),
            _menuTile(
              Icons.cake_outlined,
              '生日提醒',
              () => context.push('/birthdays'),
            ),
            _menuTile(
              Icons.table_chart,
              '我的课表',
              () => context.push('/schedule'),
            ),
            _menuTile(
              Icons.settings_outlined,
              '课表设置',
              () async {
                await context.push('/schedule-settings');
                if (!mounted) return;
                _load();
              },
              subtitle: _scheduleSummary.isEmpty ? '设置学期周范围' : _scheduleSummary,
            ),
            _menuTile(
              Icons.notifications_outlined,
              '通知设置',
              () => snack(context, '使用系统通知渠道，可在系统设置中管理'),
            ),
            _menuTile(Icons.security, '隐私与安全', () => _showPrivacy()),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                context.read<AppState>().lock();
              },
              icon: const Icon(Icons.fingerprint),
              label: const Text('立即锁定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  void _showPrivacy() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('隐私与安全'),
        content: const Text(
          '· 数据全部存储在手机本地 SQLCipher 加密库\n'
          '· 截图仅保存相册引用，不复制原图\n'
          '· 密码库字段单独加密\n'
          '· 指纹解锁，${AppConstants.sessionHours}小时内免重复验证\n'
          '· 默认不上传任何数据到云端',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
