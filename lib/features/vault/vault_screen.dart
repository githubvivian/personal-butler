import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_state.dart';
import '../../core/repositories/other_repositories.dart';
import '../../core/security/session_service.dart';
import '../widgets/common_widgets.dart';
import 'vault_session_controller.dart';

typedef VaultClipboardWriter = Future<void> Function(String text);
typedef VaultClipboardReader = Future<String?> Function();

class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    this.controller,
    this.repository,
    this.clipboardWriter,
    this.clipboardReader,
  });

  final VaultSessionController? controller;
  final VaultRepository? repository;
  final VaultClipboardWriter? clipboardWriter;
  final VaultClipboardReader? clipboardReader;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  static const _clipboardClearDelay = Duration(seconds: 60);
  static const _clipboardClearRetryDelay = Duration(seconds: 5);

  late VaultSessionController _controller;
  late bool _ownsController;
  VaultRepository? _repository;
  VaultSessionCapability? _activeCapability;
  String? _category;
  List<VaultEntryModel> _entries = const [];
  bool _dependenciesReady = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _saving = false;
  bool _disposed = false;
  int _securityGeneration = 0;
  int _loadGeneration = 0;
  BuildContext? _dialogContext;
  ModalRoute<bool>? _dialogRoute;
  final Map<String, Object> _decryptOperations = {};
  final Map<Object, _VaultMutation> _saveOperations = {};
  final Map<int, _VaultClipboardOwnership> _clipboardOwnerships = {};
  Timer? _clipboardClearTimer;
  Future<void> _clipboardQueue = Future<void>.value();
  int _clipboardGeneration = 0;

  @override
  void initState() {
    super.initState();
    _installController(widget.controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _repository = widget.repository ?? context.read<AppState>().vault;
    _dependenciesReady = true;
    unawaited(_controller.initialize());
  }

  @override
  void didUpdateWidget(covariant VaultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      widget.controller,
      oldWidget.controller,
    );
    final repositoryChanged = !identical(
      widget.repository,
      oldWidget.repository,
    );
    final previousRepository = _repository;

    if (repositoryChanged) {
      _repository = widget.repository ?? context.read<AppState>().vault;
    }

    if (controllerChanged) {
      final previousController = _controller;
      final ownedPreviousController = _ownsController;
      previousController.removeListener(_handleControllerChanged);
      _revokeActiveMutations(controller: previousController);
      _invalidateSensitiveState();
      if (ownedPreviousController) {
        previousController.dispose();
      } else {
        unawaited(previousController.deactivate());
      }
      _installController(widget.controller);
      if (_dependenciesReady) unawaited(_controller.initialize());
      return;
    }

    if (repositoryChanged) {
      final cancelPendingAuthentication =
          _controller.status == VaultSessionStatus.authenticating;
      _controller.removeListener(_handleControllerChanged);
      _revokeActiveMutations(repository: previousRepository);
      if (cancelPendingAuthentication) {
        unawaited(_controller.cancelPendingAuthentication());
      }
      _controller.addListener(_handleControllerChanged);
      _invalidateSensitiveState();
      final capability = _controller.isUnlocked ? _controller.capability : null;
      _activeCapability = capability;
      if (capability != null && _dependenciesReady) unawaited(_load());
    }
  }

  void _installController(VaultSessionController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? VaultSessionController();
    _controller.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    if (_disposed || !mounted) return;
    final capability = _controller.isUnlocked ? _controller.capability : null;
    final capabilityChanged = !identical(capability, _activeCapability);

    if (capabilityChanged) {
      _invalidateSensitiveState();
      _activeCapability = capability;
    }

    setState(() {});
    if (capabilityChanged && capability != null && _dependenciesReady) {
      unawaited(_load());
    }
  }

  void _invalidateSensitiveState() {
    _securityGeneration += 1;
    _loadGeneration += 1;
    _entries = const [];
    _loading = false;
    _loadFailed = false;
    _saving = false;
    _decryptOperations.clear();
    _activeCapability = null;
    _dismissActiveDialog();
    _clearVaultClipboardBestEffort();
  }

  void _revokeActiveMutations({
    VaultSessionController? controller,
    VaultRepository? repository,
  }) {
    for (final mutation in _saveOperations.values) {
      if (controller != null && !identical(mutation.controller, controller)) {
        continue;
      }
      if (repository != null && !identical(mutation.repository, repository)) {
        continue;
      }
      unawaited(
        mutation.controller
            .revokeCapability(mutation.capability)
            .catchError((_) {}),
      );
    }
  }

  void _lockControllerBestEffort(VaultSessionController controller) {
    unawaited(controller.lock().catchError((_) {}));
  }

  Future<void> _load() async {
    final repository = _repository;
    final capability = _activeCapability;
    final controller = _controller;
    if (repository == null ||
        capability == null ||
        !controller.isUnlocked ||
        !identical(controller.capability, capability)) {
      return;
    }

    final securityGeneration = _securityGeneration;
    final loadGeneration = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }

    try {
      final entries = await repository.getAll(
        capability: capability,
        category: _category,
      );
      if (!_isCurrentBinding(
            controller: controller,
            repository: repository,
            capability: capability,
            securityGeneration: securityGeneration,
          ) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on VaultAccessDeniedException {
      if (_matchesBinding(
        controller: controller,
        repository: repository,
        securityGeneration: securityGeneration,
      )) {
        _lockControllerBestEffort(controller);
      }
    } catch (_) {
      if (!_isCurrentBinding(
            controller: controller,
            repository: repository,
            capability: capability,
            securityGeneration: securityGeneration,
          ) ||
          loadGeneration != _loadGeneration) {
        return;
      }
      setState(() {
        _entries = const [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _add() async {
    final repository = _repository;
    final capability = _activeCapability;
    final controller = _controller;
    if (_saving ||
        repository == null ||
        capability == null ||
        !controller.isUnlocked) {
      return;
    }
    final securityGeneration = _securityGeneration;
    final name = TextEditingController();
    final account = TextEditingController();
    final password = TextEditingController();
    final notes = TextEditingController();
    var category = AppConstants.vaultCategories.first.id;
    bool? confirmed;
    String? nameValue;
    String? accountValue;
    String? passwordValue;
    String? notesValue;

    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          _dialogContext = dialogContext;
          _dialogRoute = ModalRoute.of(dialogContext);
          return StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              key: const Key('vault_add_dialog'),
              title: const Text('添加账号'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      items: AppConstants.vaultCategories
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setLocal(() => category = value ?? category);
                      },
                    ),
                    TextField(
                      key: const Key('vault_name_field'),
                      controller: name,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    TextField(
                      controller: account,
                      decoration: const InputDecoration(labelText: '账号'),
                    ),
                    TextField(
                      key: const Key('vault_password_field'),
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                    ),
                    TextField(
                      controller: notes,
                      decoration: const InputDecoration(labelText: '备注'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const Key('vault_dialog_save'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('保存'),
                ),
              ],
            ),
          );
        },
      );
      if (confirmed == true) {
        nameValue = name.text.trim();
        accountValue = account.text.trim();
        passwordValue = password.text;
        final trimmedNotes = notes.text.trim();
        notesValue = trimmedNotes.isEmpty ? null : trimmedNotes;
      }
    } finally {
      final dialogRoute = _dialogRoute;
      _dialogContext = null;
      _dialogRoute = null;
      if (dialogRoute != null) {
        try {
          await dialogRoute.completed;
        } catch (_) {}
      }
      name.dispose();
      account.dispose();
      password.dispose();
      notes.dispose();
    }

    if (confirmed != true || nameValue == null || nameValue.isEmpty) return;
    if (!_isCurrentBinding(
      controller: controller,
      repository: repository,
      capability: capability,
      securityGeneration: securityGeneration,
    )) {
      return;
    }

    final saveOperation = Object();
    _saveOperations[saveOperation] = _VaultMutation(
      controller: controller,
      repository: repository,
      capability: capability,
    );
    setState(() => _saving = true);
    try {
      final save = repository.saveEntry(
        capability: capability,
        category: category,
        name: nameValue,
        account: accountValue ?? '',
        password: passwordValue ?? '',
        notes: notesValue,
      );
      passwordValue = null;
      notesValue = null;
      await save;
      if (_isCurrentBinding(
        controller: controller,
        repository: repository,
        capability: capability,
        securityGeneration: securityGeneration,
      )) {
        await _load();
      }
    } on VaultAccessDeniedException {
      if (_matchesBinding(
        controller: controller,
        repository: repository,
        securityGeneration: securityGeneration,
      )) {
        _lockControllerBestEffort(controller);
      }
    } catch (_) {
      if (mounted &&
          _isCurrentBinding(
            controller: controller,
            repository: repository,
            capability: capability,
            securityGeneration: securityGeneration,
          )) {
        snack(context, '保存失败，请重新验证后再试');
      }
    } finally {
      _saveOperations.remove(saveOperation);
      passwordValue = null;
      notesValue = null;
      if (_isCurrentBinding(
        controller: controller,
        repository: repository,
        capability: capability,
        securityGeneration: securityGeneration,
      )) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _copyPassword(VaultEntryModel entry) async {
    final repository = _repository;
    final capability = _activeCapability;
    final controller = _controller;
    if (repository == null || capability == null || !controller.isUnlocked) {
      return;
    }
    final clipboardGeneration = _beginClipboardCopy();
    final securityGeneration = _securityGeneration;
    final operation = Object();
    _decryptOperations[entry.id] = operation;
    setState(() {});
    _VaultClipboardOwnership? clipboardOwnership;

    try {
      var password = await repository.decryptPassword(
        entry,
        capability: capability,
      );
      if (!_isCurrentDecrypt(
            entry.id,
            operation,
            controller: controller,
            repository: repository,
            capability: capability,
            securityGeneration: securityGeneration,
          ) ||
          clipboardGeneration != _clipboardGeneration) {
        password = '';
        return;
      }

      _scheduleAllClipboardClears();
      final ownership = _VaultClipboardOwnership(
        generation: clipboardGeneration,
        text: password,
      );
      clipboardOwnership = ownership;
      _clipboardOwnerships[clipboardGeneration] = ownership;
      final clipboardWrite = _enqueueClipboardOperation(() async {
        if (clipboardGeneration != _clipboardGeneration ||
            !identical(_clipboardOwnerships[clipboardGeneration], ownership)) {
          _forgetClipboardOwnership(ownership);
          return;
        }
        final text = ownership.text;
        if (text == null) return;
        ownership.mayOwnClipboard = true;
        await _writeClipboard(text);
      });
      password = '';
      await clipboardWrite;
      if (!_isCurrentDecrypt(
        entry.id,
        operation,
        controller: controller,
        repository: repository,
        capability: capability,
        securityGeneration: securityGeneration,
      )) {
        _scheduleClipboardClear(ownership);
        return;
      }
      if (clipboardGeneration != _clipboardGeneration) return;

      _forgetSupersededClipboardOwnerships(ownership);
      _armClipboardClearTimer(ownership);
      if (mounted) {
        snack(context, '密码已复制，60秒后自动清除剪贴板');
      }
    } on VaultAccessDeniedException {
      if (_matchesBinding(
        controller: controller,
        repository: repository,
        securityGeneration: securityGeneration,
      )) {
        _lockControllerBestEffort(controller);
      }
    } catch (_) {
      final ownership = clipboardOwnership;
      if (ownership != null) {
        _scheduleClipboardClear(ownership);
      } else if (clipboardGeneration == _clipboardGeneration) {
        _scheduleAllClipboardClears();
      }
      if (mounted &&
          _isCurrentBinding(
            controller: controller,
            repository: repository,
            capability: capability,
            securityGeneration: securityGeneration,
          )) {
        snack(context, '读取密码失败，请重新验证后再试');
      }
    } finally {
      if (identical(_decryptOperations[entry.id], operation)) {
        _decryptOperations.remove(entry.id);
        if (mounted) setState(() {});
      }
    }
  }

  bool _isCurrentDecrypt(
    String entryId,
    Object operation, {
    required VaultSessionController controller,
    required VaultRepository repository,
    required VaultSessionCapability capability,
    required int securityGeneration,
  }) {
    return identical(_decryptOperations[entryId], operation) &&
        _isCurrentBinding(
          controller: controller,
          repository: repository,
          capability: capability,
          securityGeneration: securityGeneration,
        );
  }

  bool _isCurrentBinding({
    required VaultSessionController controller,
    required VaultRepository repository,
    required VaultSessionCapability capability,
    required int securityGeneration,
  }) {
    return _matchesBinding(
          controller: controller,
          repository: repository,
          securityGeneration: securityGeneration,
        ) &&
        controller.isUnlocked &&
        identical(controller.capability, capability) &&
        identical(_activeCapability, capability);
  }

  bool _matchesBinding({
    required VaultSessionController controller,
    required VaultRepository repository,
    required int securityGeneration,
  }) {
    return !_disposed &&
        mounted &&
        securityGeneration == _securityGeneration &&
        identical(controller, _controller) &&
        identical(repository, _repository);
  }

  void _dismissActiveDialog() {
    final dialogContext = _dialogContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    final route = _dialogRoute ?? ModalRoute.of(dialogContext);
    if (route == null || !route.isActive) return;
    final navigator = route.navigator;
    if (navigator == null) return;
    if (route.isCurrent) {
      navigator.pop(false);
    } else {
      navigator.removeRoute(route, false);
    }
  }

  Future<void> _writeClipboard(String text) {
    final writer = widget.clipboardWriter;
    if (writer != null) return writer(text);
    return Clipboard.setData(ClipboardData(text: text));
  }

  Future<String?> _readClipboard() async {
    final reader = widget.clipboardReader;
    if (reader != null) return reader();
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  int _beginClipboardCopy() {
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = null;
    _clipboardGeneration += 1;
    _scheduleAllClipboardClears();
    return _clipboardGeneration;
  }

  Future<T> _enqueueClipboardOperation<T>(Future<T> Function() operation) {
    final result = _clipboardQueue.then((_) => operation());
    _clipboardQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  void _armClipboardClearTimer(
    _VaultClipboardOwnership ownership, {
    Duration delay = _clipboardClearDelay,
  }) {
    _clipboardClearTimer?.cancel();
    final generation = ownership.generation;
    _clipboardClearTimer = Timer(delay, () {
      if (_disposed || generation != _clipboardGeneration) return;
      unawaited(
        _clearClipboardOwnership(
          ownership,
          requiredGeneration: generation,
        ).catchError((_) {
          if (!_disposed &&
              generation == _clipboardGeneration &&
              ownership.text != null &&
              identical(_clipboardOwnerships[generation], ownership)) {
            _armClipboardClearTimer(
              ownership,
              delay: _clipboardClearRetryDelay,
            );
          }
        }),
      );
    });
  }

  void _scheduleAllClipboardClears() {
    for (final ownership in _clipboardOwnerships.values.toList()) {
      _scheduleClipboardClear(ownership);
    }
  }

  void _scheduleClipboardClear(
    _VaultClipboardOwnership ownership, {
    int? requiredGeneration,
  }) {
    unawaited(
      _clearClipboardOwnership(
        ownership,
        requiredGeneration: requiredGeneration,
      ).catchError((_) {}),
    );
  }

  Future<void> _clearClipboardOwnership(
    _VaultClipboardOwnership ownership, {
    int? requiredGeneration,
  }) {
    return _enqueueClipboardOperation(() async {
      final ownedText = ownership.text;
      if (ownedText == null ||
          !ownership.mayOwnClipboard ||
          !identical(_clipboardOwnerships[ownership.generation], ownership)) {
        return;
      }
      if (requiredGeneration != null &&
          requiredGeneration != _clipboardGeneration) {
        return;
      }

      final currentText = await _readClipboard();
      if (ownership.text != ownedText ||
          !identical(_clipboardOwnerships[ownership.generation], ownership)) {
        return;
      }
      if (requiredGeneration != null &&
          requiredGeneration != _clipboardGeneration) {
        return;
      }
      if (currentText != ownedText) {
        _forgetClipboardOwnership(ownership);
        return;
      }

      final clearedOwnerships = _clipboardOwnerships.values
          .where(
            (candidate) =>
                candidate.mayOwnClipboard && candidate.text == ownedText,
          )
          .toList();
      await _writeClipboard('');
      for (final clearedOwnership in clearedOwnerships) {
        if (clearedOwnership.text == ownedText) {
          _forgetClipboardOwnership(clearedOwnership);
        }
      }
    });
  }

  void _forgetClipboardOwnership(_VaultClipboardOwnership ownership) {
    if (identical(_clipboardOwnerships[ownership.generation], ownership)) {
      _clipboardOwnerships.remove(ownership.generation);
    }
    ownership.text = null;
  }

  void _forgetSupersededClipboardOwnerships(
    _VaultClipboardOwnership currentOwnership,
  ) {
    for (final ownership in _clipboardOwnerships.values.toList()) {
      if (!identical(ownership, currentOwnership)) {
        _forgetClipboardOwnership(ownership);
      }
    }
  }

  void _clearVaultClipboardBestEffort() {
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = null;
    _clipboardGeneration += 1;
    _scheduleAllClipboardClears();
  }

  String _maskAccount(String account) {
    if (account.length <= 4) return '****';
    return '${account.substring(0, 3)}****${account.substring(account.length - 2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('密码保险库'),
        actions: _controller.isUnlocked
            ? [
                IconButton(
                  key: const Key('vault_add'),
                  onPressed: _saving ? null : _add,
                  icon: const Icon(Icons.add),
                ),
              ]
            : null,
      ),
      body: switch (_controller.status) {
        VaultSessionStatus.checking || VaultSessionStatus.authenticating =>
          const Center(child: CircularProgressIndicator()),
        VaultSessionStatus.locked => _buildLocked(),
        VaultSessionStatus.unlocked => _buildUnlocked(),
      },
    );
  }

  Widget _buildLocked() {
    return Center(
      key: const Key('vault_locked'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          const Text('密码库已锁定'),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('vault_reauthenticate'),
            onPressed: () => unawaited(_controller.authenticate()),
            icon: const Icon(Icons.fingerprint),
            label: const Text('重新验证'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlocked() {
    return Column(
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
                  setState(() => _category = null);
                  unawaited(_load());
                },
              ),
              ...AppConstants.vaultCategories.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(item.label),
                    selected: _category == item.id,
                    onSelected: (_) {
                      setState(() => _category = item.id);
                      unawaited(_load());
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildVaultEntries()),
      ],
    );
  }

  Widget _buildVaultEntries() {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: FilledButton(
          onPressed: () => unawaited(_load()),
          child: const Text('加载失败，点击重试'),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('暂无密码条目'));
    }
    return ListView.builder(
      key: const Key('vault_entry_list'),
      padding: const EdgeInsets.all(16),
      itemCount: _entries.length,
      itemBuilder: (_, index) {
        final entry = _entries[index];
        final decrypting = _decryptOperations.containsKey(entry.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: ListTile(
              leading: const Icon(Icons.lock_outline, color: AppColors.primary),
              title: Text(entry.name),
              subtitle: Text(_maskAccount(entry.account)),
              trailing: IconButton(
                key: Key('vault_copy_${entry.id}'),
                icon: decrypting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.copy),
                onPressed: decrypting
                    ? null
                    : () => unawaited(_copyPassword(entry)),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    final controller = _controller;
    final ownsController = _ownsController;
    controller.removeListener(_handleControllerChanged);
    _disposed = true;
    _securityGeneration += 1;
    _loadGeneration += 1;
    _dismissActiveDialog();
    _clearVaultClipboardBestEffort();
    _revokeActiveMutations();
    _saveOperations.clear();
    _clipboardClearTimer?.cancel();
    if (ownsController) {
      controller.dispose();
    } else {
      unawaited(controller.deactivate());
    }
    _entries = const [];
    _saving = false;
    _decryptOperations.clear();
    super.dispose();
  }
}

class _VaultMutation {
  const _VaultMutation({
    required this.controller,
    required this.repository,
    required this.capability,
  });

  final VaultSessionController controller;
  final VaultRepository repository;
  final VaultSessionCapability capability;
}

class _VaultClipboardOwnership {
  _VaultClipboardOwnership({required this.generation, required this.text});

  final int generation;
  String? text;
  bool mayOwnClipboard = false;
}
