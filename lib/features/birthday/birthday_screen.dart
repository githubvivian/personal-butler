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
      _items = [];
      _hasSnapshot = false;
      _load();
    }
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
    setState(() => _adding = true);
    try {
      await _addOnce();
    } catch (_) {
      if (mounted) snack(context, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addOnce() async {
    var nameInput = '';
    var relationInput = '';
    var monthInput = '1';
    var dayInput = '1';
    bool isLunar = false;
    bool dialogSubmitted = false;
    String? errorText;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('添加生日'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: '姓名'),
                  onChanged: (value) => nameInput = value,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: '关系'),
                  onChanged: (value) => relationInput = value,
                ),
                SwitchListTile(
                  title: const Text('农历生日'),
                  value: isLunar,
                  onChanged: (v) => setLocal(() => isLunar = v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: monthInput,
                        decoration: const InputDecoration(labelText: '月'),
                        keyboardType: TextInputType.number,
                        onChanged: (value) => monthInput = value,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: dayInput,
                        decoration: const InputDecoration(labelText: '日'),
                        keyboardType: TextInputType.number,
                        onChanged: (value) => dayInput = value,
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorText!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (dialogSubmitted) return;
                final nameValue = nameInput.trim();
                final month = int.tryParse(monthInput.trim());
                final day = int.tryParse(dayInput.trim());
                if (nameValue.isEmpty) {
                  setLocal(() => errorText = '请输入姓名');
                  return;
                }
                if (month == null ||
                    day == null ||
                    !BirthdayDateHelper.isValidDate(
                      isLunar: isLunar,
                      month: month,
                      day: day,
                    )) {
                  setLocal(() => errorText = '请输入有效的生日日期');
                  return;
                }
                dialogSubmitted = true;
                Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final nameValue = nameInput.trim();
    final relationValue = relationInput.trim();
    final month = int.tryParse(monthInput.trim());
    final day = int.tryParse(dayInput.trim());
    if (!mounted || ok != true || nameValue.isEmpty) return;
    if (month == null ||
        day == null ||
        !BirthdayDateHelper.isValidDate(
          isLunar: isLunar,
          month: month,
          day: day,
        )) {
      snack(context, '请输入有效的生日日期');
      return;
    }
    final repository = _repository;
    final permissionResult =
        await (widget.notificationPermissionCoordinator ??
                NotificationPermissionCoordinator.instance)
            .requestThenPersist(
              requiresPermission: true,
              persist: () async {
                await repository.create(
                  name: nameValue,
                  relation: relationValue,
                  isLunar: isLunar,
                  month: month,
                  day: day,
                );
              },
            );
    if (!mounted || !identical(repository, _repository)) return;
    final warning = permissionResult.warningMessage;
    if (warning != null) snack(context, warning);
    await _load();
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
