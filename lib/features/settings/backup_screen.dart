import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_state.dart';
import '../../core/services/backup_service.dart';
import '../widgets/common_widgets.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.backupService});

  final BackupService? backupService;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _password = TextEditingController();
  late final BackupService _backup;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _backup = widget.backupService ?? BackupService();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_password.text.length < 6) {
      snack(context, '备份密码至少6位');
      return;
    }
    setState(() => _busy = true);
    try {
      await _backup.shareBackup(_password.text);
      if (mounted) snack(context, '加密备份已生成，请保存到安全位置');
    } catch (_) {
      if (mounted) snack(context, '备份失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_password.text.length < 6) {
      snack(context, '请输入备份时设置的密码');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text('恢复将覆盖当前全部数据，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    setState(() => _busy = true);
    try {
      final outcome = await _backup.importEncryptedBackup(_password.text);
      if (!mounted) return;
      if (outcome == BackupImportOutcome.cancelled) return;
      snack(context, '恢复成功');
      context.read<AppState>().refresh();
    } catch (e) {
      if (!mounted) return;
      snack(context, '恢复失败，请检查密码与文件');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AppCard(
            child: Text(
              '备份文件使用 AES 加密，扩展名 .pbak。请妥善保管备份密码，丢失将无法恢复。',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '备份密码'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.upload),
            label: const Text('导出加密备份'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.download),
            label: const Text('从备份恢复'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
