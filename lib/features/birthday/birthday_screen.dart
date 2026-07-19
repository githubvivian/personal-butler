import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/other_repositories.dart';
import '../../core/services/notification_permission_coordinator.dart';
import '../../core/utils/birthday_date_helper.dart';
import '../../core/utils/lunar_date_helper.dart';
import '../widgets/common_widgets.dart';

class BirthdayScreen extends StatefulWidget {
  const BirthdayScreen({
    super.key,
    this.birthdayRepository,
    this.notificationPermissionCoordinator,
  });

  final BirthdayRepository? birthdayRepository;
  final NotificationPermissionCoordinator? notificationPermissionCoordinator;

  @override
  State<BirthdayScreen> createState() => _BirthdayScreenState();
}

enum _BirthdayLoadStatus { loading, ready, failed }

class _BirthdayScreenState extends State<BirthdayScreen> {
  List<BirthdayModel> _items = [];
  _BirthdayLoadStatus _loadStatus = _BirthdayLoadStatus.loading;
  bool _hasSnapshot = false;
  bool _adding = false;
  int _loadGeneration = 0;
  int _addGeneration = 0;
  final Set<String> _deletingIds = <String>{};

  BirthdayRepository get _repository =>
      widget.birthdayRepository ?? context.read<AppState>().birthdays;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BirthdayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.birthdayRepository, widget.birthdayRepository)) {
      _addGeneration += 1;
      _adding = false;
      _items = [];
      _hasSnapshot = false;
      _load();
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _addGeneration += 1;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final repository = _repository;
    setState(() => _loadStatus = _BirthdayLoadStatus.loading);
    try {
      final items = await repository.getAll();
      if (!_isCurrentLoad(generation, repository)) return;
      setState(() {
        _items = items;
        _hasSnapshot = true;
        _loadStatus = _BirthdayLoadStatus.ready;
      });
    } catch (_) {
      if (!_isCurrentLoad(generation, repository)) return;
      setState(() => _loadStatus = _BirthdayLoadStatus.failed);
    }
  }

  bool _isCurrentLoad(int generation, BirthdayRepository repository) {
    return mounted &&
        generation == _loadGeneration &&
        identical(repository, _repository);
  }

  Future<void> _add() async {
    if (_adding) return;
    final generation = ++_addGeneration;
    final repository = _repository;
    final coordinator =
        widget.notificationPermissionCoordinator ??
        NotificationPermissionCoordinator.instance;
    setState(() => _adding = true);
    try {
      final permissionResult = await showDialog<NotificationPermissionResult>(
        context: context,
        builder: (_) => _BirthdayEditorDialog(
          onSave:
              ({
                required name,
                required relation,
                required isLunar,
                required month,
                required day,
              }) async {
                if (!_isCurrentAdd(generation, repository)) {
                  throw const _InactiveBirthdayEditor();
                }
                final result = await coordinator.requestThenPersist(
                  requiresPermission: true,
                  persist: () async {
                    if (!_isCurrentAdd(generation, repository)) {
                      throw const _InactiveBirthdayEditor();
                    }
                    await repository.create(
                      name: name,
                      relation: relation,
                      isLunar: isLunar,
                      month: month,
                      day: day,
                    );
                  },
                );
                if (!_isCurrentAdd(generation, repository)) {
                  throw const _InactiveBirthdayEditor();
                }
                return result;
              },
        ),
      );
      if (!_isCurrentAdd(generation, repository) || permissionResult == null) {
        return;
      }
      if (!mounted) return;
      final warning = permissionResult.warningMessage;
      if (warning != null) snack(context, warning);
      await _load();
    } catch (_) {
      if (mounted && _isCurrentAdd(generation, repository)) {
        snack(context, '保存失败，请重试');
      }
    } finally {
      if (mounted && generation == _addGeneration) {
        setState(() => _adding = false);
      }
    }
  }

  bool _isCurrentAdd(int generation, BirthdayRepository repository) {
    return mounted &&
        generation == _addGeneration &&
        identical(repository, _repository);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生日提醒'),
        actions: [
          IconButton(
            onPressed: _adding ? null : _add,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (!_hasSnapshot) {
      if (_loadStatus == _BirthdayLoadStatus.loading) {
        return _buildCenteredList(const CircularProgressIndicator());
      }
      return _buildCenteredList(_buildFailureNotice());
    }

    if (_items.isEmpty) {
      if (_loadStatus == _BirthdayLoadStatus.loading) {
        return _buildCenteredList(const CircularProgressIndicator());
      }
      if (_loadStatus == _BirthdayLoadStatus.failed) {
        return _buildCenteredList(_buildFailureNotice());
      }
      return _buildCenteredList(const Text('暂无生日记录'));
    }

    final showLoadState = _loadStatus != _BirthdayLoadStatus.ready;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _items.length + (showLoadState ? 1 : 0),
      itemBuilder: (_, index) {
        if (showLoadState && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _loadStatus == _BirthdayLoadStatus.loading
                ? const LinearProgressIndicator()
                : _buildFailureNotice(),
          );
        }
        return _card(_items[index - (showLoadState ? 1 : 0)]);
      },
    );
  }

  Widget _buildCenteredList(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 80),
        Center(child: child),
      ],
    );
  }

  Widget _buildFailureNotice() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('数据加载失败，请重试'),
        TextButton(onPressed: _load, child: const Text('重试')),
      ],
    );
  }

  Widget _card(BirthdayModel b) {
    final countdown = BirthdayDateHelper.nextCountdown(
      isLunar: b.isLunar,
      month: b.month,
      day: b.day,
      isLeapMonth: b.isLeapMonth,
    );
    final next = countdown?.date;
    final days = countdown?.daysUntil;
    final lunarLabel = b.isLunar
        ? LunarDateHelper.formatLunarLabel(
            b.month,
            b.day,
            isLeap: b.isLeapMonth,
          )
        : '${b.month}月${b.day}日';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        accentColor: AppColors.accentPink,
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.accentPink.withValues(alpha: 0.15),
              child: Text(
                b.name.isNotEmpty ? b.name[0] : '?',
                style: const TextStyle(color: AppColors.accentPink),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    b.isLunar ? '农历 $lunarLabel' : '阳历 $lunarLabel',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (next != null)
                    Text(
                      '下次：${DateFormat('yyyy-MM-dd').format(next)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (days != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$days天',
                  style: const TextStyle(
                    color: AppColors.accentPink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: _deletingIds.contains(b.id) ? null : () => _delete(b),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BirthdayModel birthday) async {
    if (_deletingIds.contains(birthday.id)) return;
    final repository = _repository;
    setState(() => _deletingIds.add(birthday.id));
    try {
      final action = await ConfirmDeleteDialog.show(
        context,
        title: '删除生日',
        message: '确认删除该生日提醒？',
        showHardDelete: false,
      );
      if (!mounted || action != 'soft') return;
      if (!identical(repository, _repository)) return;
      await repository.softDelete(birthday.id);
      if (!mounted || !identical(repository, _repository)) return;
      await _load();
    } catch (_) {
      if (mounted && identical(repository, _repository)) {
        snack(context, '删除失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _deletingIds.remove(birthday.id));
    }
  }
}

class _BirthdayEditorDialog extends StatefulWidget {
  const _BirthdayEditorDialog({required this.onSave});

  final Future<NotificationPermissionResult> Function({
    required String name,
    required String relation,
    required bool isLunar,
    required int month,
    required int day,
  })
  onSave;

  @override
  State<_BirthdayEditorDialog> createState() => _BirthdayEditorDialogState();
}

class _BirthdayEditorDialogState extends State<_BirthdayEditorDialog> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _month = TextEditingController(text: '1');
  final _day = TextEditingController(text: '1');
  bool _isLunar = false;
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _month.dispose();
    _day.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final relation = _relation.text.trim();
    final month = int.tryParse(_month.text.trim());
    final day = int.tryParse(_day.text.trim());
    if (name.isEmpty) {
      setState(() => _errorText = '请输入姓名');
      return;
    }
    if (month == null ||
        day == null ||
        !BirthdayDateHelper.isValidDate(
          isLunar: _isLunar,
          month: month,
          day: day,
        )) {
      setState(() => _errorText = '请输入有效的生日日期');
      return;
    }

    final isLunar = _isLunar;
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final result = await widget.onSave(
        name: name,
        relation: relation,
        isLunar: isLunar,
        month: month,
        day: day,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = '保存失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('添加生日'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('birthday_name_field'),
                controller: _name,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: '姓名'),
              ),
              TextField(
                key: const Key('birthday_relation_field'),
                controller: _relation,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: '关系'),
              ),
              SwitchListTile(
                title: const Text('农历生日'),
                value: _isLunar,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isLunar = value),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('birthday_month_field'),
                      controller: _month,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: '月'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('birthday_day_field'),
                      controller: _day,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: '日'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('birthday_dialog_save'),
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _InactiveBirthdayEditor implements Exception {
  const _InactiveBirthdayEditor();
}
