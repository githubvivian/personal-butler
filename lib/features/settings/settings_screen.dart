import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/item_repository.dart';
import '../../core/repositories/other_repositories.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/reminder_sync_service.dart';
import '../../core/services/system_settings_service.dart';
import '../widgets/common_widgets.dart';

typedef ExactAlarmPermissionRequester = Future<bool?> Function();
typedef ReminderReconciler =
    Future<void> Function({
      required ItemRepository items,
      required BirthdayRepository birthdays,
    });

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.notificationSettingsOpener,
    this.exactAlarmPermissionRequester,
    this.reminderReconciler,
  });

  final NotificationSettingsOpener? notificationSettingsOpener;
  final ExactAlarmPermissionRequester? exactAlarmPermissionRequester;
  final ReminderReconciler? reminderReconciler;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, int> _stats = {};
  String _scheduleSummary = '';
  Future<void>? _exactAlarmPermissionRequest;
  late AppState _appState;
  late ItemRepository _itemRepository;
  late int _observedDataRevision;
  int _loadGeneration = 0;
  int _statsGeneration = 0;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _itemRepository = _appState.items;
    _observedDataRevision = _appState.dataRevision;
    _appState.addListener(_handleExternalDataRefresh);
    _itemRepository.addListener(_handleItemMutation);
    _load();
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _statsGeneration += 1;
    _appState.removeListener(_handleExternalDataRefresh);
    _itemRepository.removeListener(_handleItemMutation);
    super.dispose();
  }

  void _handleItemMutation() => _loadItemStats();

  void _handleExternalDataRefresh() {
    final revision = _appState.dataRevision;
    if (revision == _observedDataRevision) return;
    _observedDataRevision = revision;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final statsGeneration = ++_statsGeneration;
    try {
      final stats = Map<String, int>.from(
        await _itemRepository.getTodayStats(),
      );
      final ideas = await _appState.ideas.getAll();
      final birthdays = await _appState.birthdays.getAll();
      final scheduleSettings = await _appState.schedules.getSettings();
      if (!mounted || generation != _loadGeneration) return;
      stats['ideas'] = ideas.length;
      stats['birthdays'] = birthdays.length;
      setState(() {
        if (statsGeneration == _statsGeneration) {
          _stats = stats;
        } else {
          _stats = {
            ..._stats,
            'ideas': ideas.length,
            'birthdays': birthdays.length,
          };
        }
        _scheduleSummary =
            '第${scheduleSettings.semesterStartWeek}-${scheduleSettings.semesterEndWeek}周'
            '${scheduleSettings.semesterStartDate == null ? '' : ' · 已设开学日期'}';
      });
    } catch (_) {}
  }

  Future<void> _loadItemStats() async {
    final generation = ++_statsGeneration;
    try {
      final stats = Map<String, int>.from(
        await _itemRepository.getTodayStats(),
      );
      if (!mounted || generation != _statsGeneration) return;
      stats['ideas'] = _stats['ideas'] ?? 0;
      stats['birthdays'] = _stats['birthdays'] ?? 0;
      setState(() => _stats = stats);
    } catch (_) {}
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
              _openNotificationSettings,
            ),
            _menuTile(
              Icons.alarm_on_outlined,
              '提高会议提醒准点性',
              _requestExactAlarmPermission,
              subtitle: '进入系统精确闹钟授权，帮助会议提醒更准时',
            ),
            _menuTile(Icons.security, '隐私与安全', () => _showPrivacy()),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _lock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('立即锁定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lock() async {
    final appState = context.read<AppState>();
    try {
      await appState.lock();
    } catch (_) {
      if (!mounted) return;
      snack(context, '会话已锁定，但安全清理未完成，请稍后重试');
    }
  }

  Future<void> _openNotificationSettings() async {
    var result = SystemSettingsLaunchResult.unavailable;
    try {
      result =
          await (widget.notificationSettingsOpener ??
              const SystemSettingsService().openAppNotificationSettings)();
    } catch (_) {}

    if (!mounted) return;
    if (result == SystemSettingsLaunchResult.unavailable) {
      snack(context, '无法打开系统通知设置，请手动前往应用设置');
    }
  }

  Future<void> _requestExactAlarmPermission() {
    final inFlight = _exactAlarmPermissionRequest;
    if (inFlight != null) return inFlight;

    late final Future<void> request;
    request = _runExactAlarmPermissionRequest().whenComplete(() {
      if (identical(_exactAlarmPermissionRequest, request)) {
        _exactAlarmPermissionRequest = null;
      }
    });
    _exactAlarmPermissionRequest = request;
    return request;
  }

  Future<void> _runExactAlarmPermissionRequest() async {
    final appState = context.read<AppState>();
    final requester =
        widget.exactAlarmPermissionRequester ??
        NotificationService.instance.requestExactAlarmsPermission;
    final reconciler =
        widget.reminderReconciler ?? ReminderSyncService.instance.reconcileAll;

    bool? granted;
    try {
      granted = await requester();
    } catch (_) {
      if (!mounted) return;
      snack(context, '无法请求精确闹钟权限，请稍后重试');
      return;
    }

    if (granted != true) {
      if (!mounted) return;
      snack(context, '未获得精确闹钟权限，会议提醒仍将使用普通模式');
      return;
    }

    try {
      await reconciler(items: appState.items, birthdays: appState.birthdays);
    } catch (_) {
      if (!mounted) return;
      snack(context, '权限已开启，但会议提醒重新同步失败，请稍后重试');
      return;
    }

    if (!mounted) return;
    snack(context, '精确闹钟权限已开启，会议提醒已重新同步');
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
