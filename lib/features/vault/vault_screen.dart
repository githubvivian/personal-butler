import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/security/session_service.dart';
import '../widgets/common_widgets.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String? _category;
  List<VaultEntryModel> _entries = [];
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _checkVault();
  }

  Future<void> _checkVault() async {
    if (SessionService.instance.isVaultSessionValid) {
      setState(() => _unlocked = true);
      _load();
      return;
    }
    final ok = await SessionService.instance.authenticate(reason: '验证指纹以打开密码库');
    if (ok) {
      SessionService.instance.unlockVault();
      setState(() => _unlocked = true);
      _load();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _load() async {
    _entries = await context.read<AppState>().vault.getAll(category: _category);
    setState(() {});
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final account = TextEditingController();
    final password = TextEditingController();
    final notes = TextEditingController();
    String category = AppConstants.vaultCategories.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('添加账号'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: category,
                  items: AppConstants.vaultCategories
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label)))
                      .toList(),
                  onChanged: (v) => setLocal(() => category = v ?? category),
                ),
                TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
                TextField(controller: account, decoration: const InputDecoration(labelText: '账号')),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                TextField(controller: notes, decoration: const InputDecoration(labelText: '备注')),
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
    await context.read<AppState>().vault.saveEntry(
          category: category,
          name: name.text.trim(),
          account: account.text.trim(),
          password: password.text,
          notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
        );
    _load();
  }

  String _maskAccount(String account) {
    if (account.length <= 4) return '****';
    return '${account.substring(0, 3)}****${account.substring(account.length - 2)}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('密码保险库'),
        actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add))],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _category == null,
                  onSelected: (_) {
                    _category = null;
                    _load();
                  },
                ),
                ...AppConstants.vaultCategories.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(c.label),
                      selected: _category == c.id,
                      onSelected: (_) {
                        _category = c.id;
                        _load();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _entries.length,
              itemBuilder: (_, i) {
                final e = _entries[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline, color: AppColors.primary),
                      title: Text(e.name),
                      subtitle: Text(_maskAccount(e.account)),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          final pwd = await context.read<AppState>().vault.decryptPassword(e);
                          await Clipboard.setData(ClipboardData(text: pwd));
                          if (!context.mounted) return;
                          snack(context, '密码已复制，60秒后请手动清除剪贴板');
                          Future.delayed(const Duration(seconds: 60), () {
                            Clipboard.setData(const ClipboardData(text: ''));
                          });
                        },
                      ),
                    ),
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
