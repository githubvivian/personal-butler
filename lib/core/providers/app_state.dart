import 'dart:async';

import 'package:flutter/foundation.dart';
import '../repositories/item_repository.dart';
import '../repositories/other_repositories.dart';
import '../repositories/schedule_repository.dart';
import '../security/session_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_sync_service.dart';

typedef BootstrapAction = Future<void> Function();
typedef BootstrapCheck = Future<bool> Function();

class AppState extends ChangeNotifier {
  final items = ItemRepository();
  final schedules = ScheduleRepository();
  final birthdays = BirthdayRepository();
  final ideas = IdeaRepository();
  final vault = VaultRepository();
  final session = SessionService.instance;

  final BootstrapAction _initializeNotifications;
  final BootstrapCheck _readInitialized;
  final BootstrapCheck _validateSession;
  final BootstrapAction? _syncRemindersCallback;

  bool _unlocked = false;
  bool _initialized = false;
  bool _loading = true;
  Object? _bootstrapError;
  Future<void>? _bootstrapFuture;

  AppState({
    BootstrapAction? initializeNotifications,
    BootstrapCheck? readInitialized,
    BootstrapCheck? validateSession,
    BootstrapAction? syncReminders,
  }) : _initializeNotifications =
           initializeNotifications ?? NotificationService.instance.init,
       _readInitialized =
           readInitialized ?? SessionService.instance.isAppInitialized,
       _validateSession =
           validateSession ?? SessionService.instance.isSessionValid,
       _syncRemindersCallback = syncReminders;

  bool get unlocked => _unlocked;
  bool get initialized => _initialized;
  bool get loading => _loading;
  Object? get bootstrapError => _bootstrapError;

  Future<void> bootstrap() {
    final inFlight = _bootstrapFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    final future = completer.future;
    _bootstrapFuture = future;

    unawaited(
      _runBootstrap()
          .whenComplete(() {
            if (identical(_bootstrapFuture, future)) {
              _bootstrapFuture = null;
            }
          })
          .then<void>(
            (_) => completer.complete(),
            onError: (Object error, StackTrace stackTrace) {
              completer.completeError(error, stackTrace);
            },
          ),
    );
    return future;
  }

  Future<void> _runBootstrap() async {
    _loading = true;
    _unlocked = false;
    _bootstrapError = null;
    notifyListeners();

    try {
      await _initializeNotifications();
    } catch (_) {}

    try {
      final initialized = await _readInitialized();
      var unlocked = false;
      if (initialized) {
        unlocked = await _validateSession();
        if (unlocked) {
          try {
            await _syncReminders();
          } catch (_) {}
        }
      }

      _initialized = initialized;
      _unlocked = unlocked;
    } catch (error) {
      _unlocked = false;
      _bootstrapError = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _syncReminders() {
    final callback = _syncRemindersCallback;
    if (callback != null) return callback();
    return ReminderSyncService.instance.reconcileAll(
      items: items,
      birthdays: birthdays,
    );
  }

  Future<bool> setupFirstRun() async {
    final ok = await session.authenticate(reason: '请验证指纹以初始化个人管家');
    if (!ok) return false;
    await session.markInitialized();
    _initialized = true;
    _unlocked = true;
    notifyListeners();
    return true;
  }

  Future<bool> unlock() async {
    final ok = await session.authenticate();
    if (ok) {
      try {
        await _syncReminders();
      } catch (_) {}
    }
    _unlocked = ok;
    notifyListeners();
    return ok;
  }

  void lock() {
    session.lock();
    session.lockVault();
    _unlocked = false;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}
