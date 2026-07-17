import 'dart:async';

import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../repositories/item_repository.dart';
import '../repositories/other_repositories.dart';
import '../repositories/schedule_repository.dart';
import '../security/session_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_sync_service.dart';

typedef BootstrapAction = Future<void> Function();
typedef BootstrapCheck = Future<bool> Function();
typedef SessionInitializeAction = Future<void> Function();
typedef SessionLockAction = Future<void> Function();
typedef SessionRemainingLifetimeReader = Future<Duration?> Function();
typedef SessionAuthenticationStopAction = Future<void> Function();

class AppState extends ChangeNotifier {
  static const sessionLifetime = Duration(hours: AppConstants.sessionHours);

  final items = ItemRepository();
  final schedules = ScheduleRepository();
  final birthdays = BirthdayRepository();
  final ideas = IdeaRepository();
  final vault = VaultRepository();
  final session = SessionService.instance;

  final BootstrapAction _initializeNotifications;
  final BootstrapCheck _readInitialized;
  final SessionInitializeAction _markSessionInitialized;
  final SessionRemainingLifetimeReader _readSessionRemainingLifetime;
  final SessionRemainingLifetimeReader
  _readAuthenticatedSessionRemainingLifetime;
  final SessionAuthenticationStopAction _stopAuthentication;
  final BootstrapAction? _syncRemindersCallback;
  final SessionLockAction _lockSession;

  bool _unlocked = false;
  bool _initialized = false;
  bool _loading = true;
  Object? _bootstrapError;
  Future<void>? _bootstrapFuture;
  int? _bootstrapFutureGeneration;
  Future<bool>? _revalidateFuture;
  int? _revalidateFutureGeneration;
  Future<void>? _sessionDeletionFuture;
  Future<void> _authenticationTail = Future<void>.value();
  int _pendingAuthenticationOperations = 0;
  Future<void>? _sessionLifecycleDeactivationFuture;
  int _dataRevision = 0;
  Timer? _sessionExpiryTimer;
  int _sessionTimerGeneration = 0;
  bool _sessionLifecycleActive = true;
  bool _disposed = false;

  AppState({
    BootstrapAction? initializeNotifications,
    BootstrapCheck? readInitialized,
    SessionInitializeAction? markSessionInitialized,
    BootstrapCheck? validateSession,
    SessionRemainingLifetimeReader? readSessionRemainingLifetime,
    SessionRemainingLifetimeReader? readAuthenticatedSessionRemainingLifetime,
    SessionAuthenticationStopAction? stopAuthentication,
    BootstrapAction? syncReminders,
    SessionLockAction? lockSession,
  }) : _initializeNotifications =
           initializeNotifications ?? NotificationService.instance.init,
       _readInitialized =
           readInitialized ?? SessionService.instance.isAppInitialized,
       _markSessionInitialized =
           markSessionInitialized ?? SessionService.instance.markInitialized,
       _readSessionRemainingLifetime =
           readSessionRemainingLifetime ??
           (validateSession != null
               ? () async => await validateSession() ? sessionLifetime : null
               : SessionService.instance.getRemainingSessionLifetime),
       _readAuthenticatedSessionRemainingLifetime =
           readAuthenticatedSessionRemainingLifetime ??
           SessionService.instance.getRemainingSessionLifetime,
       _stopAuthentication =
           stopAuthentication ?? SessionService.instance.stopAuthentication,
       _syncRemindersCallback = syncReminders,
       _lockSession = lockSession ?? SessionService.instance.lock;

  bool get unlocked => _unlocked;
  bool get initialized => _initialized;
  bool get loading => _loading;
  Object? get bootstrapError => _bootstrapError;
  int get dataRevision => _dataRevision;

  Future<void> bootstrap() {
    if (!_canManageSessionLifecycle) return Future<void>.value();

    final retryRevocation = session.hasSessionRevocationFailure;
    final currentGeneration = _sessionTimerGeneration;
    final inFlight = _bootstrapFuture;
    if (inFlight != null && _bootstrapFutureGeneration == currentGeneration) {
      return inFlight;
    }

    _cancelSessionExpiryTimer();
    final generation = _sessionTimerGeneration;
    final authenticationTail = _authenticationTail;

    final completer = Completer<void>();
    final future = completer.future;
    _bootstrapFuture = future;
    _bootstrapFutureGeneration = generation;

    unawaited(
      _runBootstrap(generation, authenticationTail, retryRevocation)
          .whenComplete(() {
            if (identical(_bootstrapFuture, future)) {
              _bootstrapFuture = null;
              _bootstrapFutureGeneration = null;
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

  Future<void> _runBootstrap(
    int generation,
    Future<void> authenticationTail,
    bool retryRevocation,
  ) async {
    if (!_isCurrentSessionLifecycle(generation)) return;
    _loading = true;
    _unlocked = false;
    _bootstrapError = null;
    _notifyListenersIfActive();

    try {
      await _initializeNotifications();
    } catch (_) {}

    try {
      try {
        await authenticationTail;
      } catch (_) {}
      if (!_isCurrentSessionLifecycle(generation)) return;
      if (retryRevocation) {
        await _startSessionDeletion();
      }
      await _awaitPendingSessionDeletionOrThrow();
      if (!_isCurrentSessionLifecycle(generation)) return;
      final initialized = await _readInitialized();
      if (!_isCurrentSessionLifecycle(generation)) return;
      _initialized = initialized;
      var unlocked = false;
      Duration? remainingLifetime;
      if (initialized) {
        remainingLifetime = await _readSessionRemainingLifetime();
        if (!_isCurrentSessionLifecycle(generation)) return;
        unlocked =
            remainingLifetime != null && remainingLifetime > Duration.zero;
        if (unlocked) {
          _armSessionExpiry(remainingLifetime);
          try {
            await _syncReminders();
          } catch (_) {}
        }
      }

      if (_isCurrentSessionLifecycle(generation)) {
        _unlocked = unlocked;
      }
    } catch (error) {
      if (_isCurrentSessionLifecycle(generation)) {
        _unlocked = false;
        _bootstrapError = error;
      }
    } finally {
      if (_canManageSessionLifecycle &&
          _bootstrapFutureGeneration == generation) {
        _loading = false;
        _notifyListenersIfActive();
      }
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

  Future<Duration?> _readAuthenticatedRemainingLifetime(int generation) async {
    Duration? remainingLifetime;
    try {
      remainingLifetime = await _readAuthenticatedSessionRemainingLifetime();
    } catch (_) {
      if (_isCurrentSessionLifecycle(generation)) {
        _failClosedBestEffort();
        await _awaitPendingSessionDeletion();
      } else {
        await _deletePersistedSessionAfterPendingBestEffort();
      }
      return null;
    }

    if (!_isCurrentSessionLifecycle(generation)) {
      await _deletePersistedSessionAfterPendingBestEffort();
      return null;
    }
    if (remainingLifetime == null || remainingLifetime <= Duration.zero) {
      _failClosedBestEffort();
      await _awaitPendingSessionDeletion();
      return null;
    }
    return remainingLifetime;
  }

  void _scheduleSessionExpiry(Duration remainingLifetime) {
    if (!_canManageSessionLifecycle || remainingLifetime <= Duration.zero) {
      return;
    }
    _cancelSessionExpiryTimer();
    _armSessionExpiry(remainingLifetime);
  }

  void _armSessionExpiry(Duration remainingLifetime) {
    if (!_canManageSessionLifecycle || remainingLifetime <= Duration.zero) {
      return;
    }
    final generation = _sessionTimerGeneration;
    _sessionExpiryTimer = Timer(remainingLifetime, () {
      if (!_isCurrentSessionLifecycle(generation)) return;
      _failClosedBestEffort();
    });
  }

  void _cancelSessionExpiryTimer() {
    _sessionTimerGeneration += 1;
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
  }

  Future<void> _deletePersistedSessionBestEffort() async {
    try {
      await _startSessionDeletion();
    } catch (_) {}
  }

  Future<void> _deletePersistedSessionAfterPendingBestEffort() async {
    await _awaitPendingSessionDeletion();
    try {
      await _startSessionDeletion();
    } catch (_) {}
  }

  Future<void> _startSessionDeletion() {
    final inFlight = _sessionDeletionFuture;
    if (inFlight != null) return inFlight;

    late final Future<void> deletion;
    deletion =
        (() async {
          try {
            await _lockSession();
            session.clearSessionRevocationFailure();
          } catch (error, stackTrace) {
            session.recordSessionRevocationFailure(error, stackTrace);
            Error.throwWithStackTrace(error, stackTrace);
          }
        })().whenComplete(() {
          if (identical(_sessionDeletionFuture, deletion)) {
            _sessionDeletionFuture = null;
          }
        });
    _sessionDeletionFuture = deletion;
    return deletion;
  }

  Future<void> _awaitPendingSessionDeletionOrThrow() async {
    final pending = _sessionDeletionFuture;
    if (pending != null) await pending;
    session.throwIfSessionRevocationFailed();
  }

  Future<void> _awaitPendingSessionDeletion() async {
    try {
      await _awaitPendingSessionDeletionOrThrow();
    } catch (_) {}
  }

  void _failClosedBestEffort() {
    if (!_canManageSessionLifecycle) return;
    final shouldNotify = _unlocked || session.isVaultSessionValid;
    _cancelSessionExpiryTimer();
    session.lockVault();
    _unlocked = false;
    final deletion = _deletePersistedSessionBestEffort();
    if (shouldNotify) {
      _notifyListenersIfActive();
    }
    unawaited(deletion);
  }

  void _notifyListenersIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _serializeAuthentication<T>(Future<T> Function() action) {
    _pendingAuthenticationOperations += 1;
    final previous = _authenticationTail;
    final result = Completer<T>();

    Future<void> run() async {
      try {
        await previous;
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _pendingAuthenticationOperations -= 1;
      }
    }

    final tail = run();
    _authenticationTail = tail;
    return result.future;
  }

  Future<bool> revalidateSession() {
    if (!_canManageSessionLifecycle || !_unlocked) {
      return Future<bool>.value(false);
    }

    final generation = _sessionTimerGeneration;
    final inFlight = _revalidateFuture;
    if (inFlight != null && _revalidateFutureGeneration == generation) {
      return inFlight;
    }

    final completer = Completer<bool>();
    final future = completer.future;
    _revalidateFuture = future;
    _revalidateFutureGeneration = generation;

    unawaited(
      _runSessionRevalidation(generation)
          .whenComplete(() {
            if (identical(_revalidateFuture, future)) {
              _revalidateFuture = null;
              _revalidateFutureGeneration = null;
            }
          })
          .then<void>(
            completer.complete,
            onError: (Object error, StackTrace stackTrace) {
              completer.completeError(error, stackTrace);
            },
          ),
    );
    return future;
  }

  Future<bool> _runSessionRevalidation(int generation) async {
    if (!_isCurrentSessionLifecycle(generation) || !_unlocked) return false;

    Duration? remainingLifetime;
    try {
      remainingLifetime = await _readSessionRemainingLifetime();
    } catch (_) {
      if (_isCurrentSessionLifecycle(generation)) {
        _failClosedBestEffort();
      }
      return false;
    }

    if (!_isCurrentSessionLifecycle(generation)) {
      return _canManageSessionLifecycle && _unlocked;
    }
    if (remainingLifetime == null || remainingLifetime <= Duration.zero) {
      _failClosedBestEffort();
      return false;
    }

    _scheduleSessionExpiry(remainingLifetime);
    return true;
  }

  Future<bool> setupFirstRun() {
    if (!_canManageSessionLifecycle) return Future<bool>.value(false);
    final requestGeneration = _sessionTimerGeneration;
    return _serializeAuthentication(() async {
      if (!_isCurrentSessionLifecycle(requestGeneration)) {
        return false;
      }
      return _runSetupFirstRun();
    });
  }

  Future<bool> _runSetupFirstRun() async {
    _cancelSessionExpiryTimer();
    final generation = _sessionTimerGeneration;
    await _awaitPendingSessionDeletion();
    if (!_isCurrentSessionLifecycle(generation)) return false;
    final ok = await session.authenticate(reason: '请验证指纹以初始化个人管家');
    if (!_isCurrentSessionLifecycle(generation)) {
      if (ok) await _deletePersistedSessionAfterPendingBestEffort();
      return false;
    }
    if (!ok) {
      if (_isCurrentSessionLifecycle(generation)) {
        session.lockVault();
        _unlocked = false;
        _notifyListenersIfActive();
      }
      return false;
    }
    final remainingLifetime = await _readAuthenticatedRemainingLifetime(
      generation,
    );
    if (remainingLifetime == null) return false;
    if (!_isCurrentSessionLifecycle(generation)) {
      await _deletePersistedSessionAfterPendingBestEffort();
      return false;
    }
    session.clearSessionRevocationFailure();
    _scheduleSessionExpiry(remainingLifetime);
    final authenticatedGeneration = _sessionTimerGeneration;
    try {
      await _markSessionInitialized();
    } catch (_) {
      if (_isCurrentSessionLifecycle(authenticatedGeneration)) {
        _failClosedBestEffort();
      } else {
        await _deletePersistedSessionAfterPendingBestEffort();
      }
      rethrow;
    }
    if (!_isCurrentSessionLifecycle(authenticatedGeneration)) {
      await _deletePersistedSessionAfterPendingBestEffort();
      return false;
    }
    _initialized = true;
    _unlocked = true;
    _notifyListenersIfActive();
    return true;
  }

  Future<bool> unlock() {
    if (!_canManageSessionLifecycle) return Future<bool>.value(false);
    final requestGeneration = _sessionTimerGeneration;
    return _serializeAuthentication(() async {
      if (!_isCurrentSessionLifecycle(requestGeneration)) {
        return false;
      }
      return _runUnlock();
    });
  }

  Future<bool> _runUnlock() async {
    _cancelSessionExpiryTimer();
    final generation = _sessionTimerGeneration;
    await _awaitPendingSessionDeletion();
    if (!_isCurrentSessionLifecycle(generation)) return false;
    final ok = await session.authenticate();
    if (!_isCurrentSessionLifecycle(generation)) {
      if (ok) await _deletePersistedSessionAfterPendingBestEffort();
      return false;
    }
    if (!ok) {
      _unlocked = false;
      session.lockVault();
      _notifyListenersIfActive();
      return false;
    }

    final remainingLifetime = await _readAuthenticatedRemainingLifetime(
      generation,
    );
    if (remainingLifetime == null) return false;
    if (!_isCurrentSessionLifecycle(generation)) {
      await _deletePersistedSessionAfterPendingBestEffort();
      return false;
    }
    session.clearSessionRevocationFailure();
    _scheduleSessionExpiry(remainingLifetime);
    final authenticatedGeneration = _sessionTimerGeneration;
    try {
      await _syncReminders();
    } catch (_) {}
    if (!_isCurrentSessionLifecycle(authenticatedGeneration)) {
      await _deletePersistedSessionAfterPendingBestEffort();
      return false;
    }

    _unlocked = true;
    _notifyListenersIfActive();
    return true;
  }

  Future<void> lock() async {
    if (!_canManageSessionLifecycle) return;
    _cancelSessionExpiryTimer();
    session.lockVault();
    _unlocked = false;
    final deletion = _startSessionDeletion();
    _notifyListenersIfActive();
    await deletion;
  }

  Future<void> deactivateSessionLifecycle() {
    final inFlight = _sessionLifecycleDeactivationFuture;
    if (!_sessionLifecycleActive) {
      return inFlight ?? Future<void>.value();
    }

    _sessionLifecycleActive = false;
    _cancelSessionExpiryTimer();
    final authenticationTail = _authenticationTail;
    final cancellation = _pendingAuthenticationOperations > 0
        ? Future<void>.sync(_stopAuthentication)
        : Future<void>.value();

    late final Future<void> deactivation;
    deactivation = _quiesceSessionLifecycle(cancellation, authenticationTail)
        .whenComplete(() {
          if (identical(_sessionLifecycleDeactivationFuture, deactivation)) {
            _sessionLifecycleDeactivationFuture = null;
          }
        });
    _sessionLifecycleDeactivationFuture = deactivation;
    return deactivation;
  }

  Future<void> _quiesceSessionLifecycle(
    Future<void> cancellation,
    Future<void> authenticationTail,
  ) async {
    try {
      await cancellation;
    } catch (_) {}
    try {
      await authenticationTail;
    } catch (_) {}
    await _awaitPendingSessionDeletion();
  }

  Future<void> activateSessionLifecycle() async {
    final deactivation = _sessionLifecycleDeactivationFuture;
    if (deactivation != null) await deactivation;
    if (_disposed) return;
    _sessionLifecycleActive = true;
  }

  bool get _canManageSessionLifecycle => !_disposed && _sessionLifecycleActive;

  bool _isCurrentSessionLifecycle(int generation) {
    return _canManageSessionLifecycle && generation == _sessionTimerGeneration;
  }

  /// Notifies consumers that persistent data was replaced outside the normal
  /// repositories, for example after a successful full backup restore.
  void refresh() {
    _dataRevision += 1;
    _notifyListenersIfActive();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionLifecycleActive = false;
    _cancelSessionExpiryTimer();
    super.dispose();
  }
}
