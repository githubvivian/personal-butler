import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/security/session_service.dart';

enum VaultSessionStatus { checking, authenticating, unlocked, locked }

class VaultSessionController extends ChangeNotifier
    with WidgetsBindingObserver {
  VaultSessionController({
    VaultSessionCapability? Function()? currentCapability,
    Future<VaultSessionCapability?> Function()? authenticateVault,
    Duration? Function(VaultSessionCapability)? remainingLifetime,
    void Function(VaultSessionCapability)? revokeVault,
    Future<void> Function()? stopAuthentication,
  }) : _currentCapability =
           currentCapability ??
           (() => SessionService.instance.currentVaultCapability()),
       _authenticateVault =
           authenticateVault ??
           (() =>
               SessionService.instance.authenticateVault(reason: '验证指纹以打开密码库')),
       _remainingLifetime =
           remainingLifetime ??
           ((capability) =>
               SessionService.instance.getVaultRemainingLifetime(capability)),
       _revokeVault =
           revokeVault ?? SessionService.instance.revokeVaultCapability,
       _stopAuthentication =
           stopAuthentication ?? SessionService.instance.stopAuthentication;

  final VaultSessionCapability? Function() _currentCapability;
  final Future<VaultSessionCapability?> Function() _authenticateVault;
  final Duration? Function(VaultSessionCapability) _remainingLifetime;
  final void Function(VaultSessionCapability) _revokeVault;
  final Future<void> Function() _stopAuthentication;

  VaultSessionStatus _status = VaultSessionStatus.checking;
  VaultSessionCapability? _capability;
  Future<bool>? _authenticationFuture;
  Timer? _expiryTimer;
  int _operationGeneration = 0;
  int _timerGeneration = 0;
  bool _observingLifecycle = false;
  bool _disposed = false;
  Object? _revocationFailure;
  StackTrace? _revocationFailureStackTrace;

  VaultSessionStatus get status => _status;
  VaultSessionCapability? get capability => _capability;
  bool get isUnlocked => _status == VaultSessionStatus.unlocked;
  bool get hasRevocationFailure => _revocationFailure != null;
  Object? get revocationFailure => _revocationFailure;

  Future<bool> initialize() {
    if (_disposed) return Future<bool>.value(false);
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    if (hasRevocationFailure) {
      _setLockedLocally();
      return Future<bool>.value(false);
    }
    if (_restoreExistingCapability()) return Future<bool>.value(true);
    return authenticate();
  }

  Future<bool> authenticate() {
    if (_disposed) return Future<bool>.value(false);
    if (hasRevocationFailure) {
      _setLockedLocally();
      return Future<bool>.value(false);
    }
    final inFlight = _authenticationFuture;
    if (inFlight != null) return inFlight;
    if (_restoreExistingCapability()) return Future<bool>.value(true);

    _cancelExpiryTimer();
    _status = VaultSessionStatus.authenticating;
    _capability = null;
    _notifyListenersIfActive();
    final generation = ++_operationGeneration;

    late final Future<bool> future;
    future = _runAuthentication(generation).whenComplete(() {
      if (identical(_authenticationFuture, future)) {
        _authenticationFuture = null;
      }
    });
    _authenticationFuture = future;
    return future;
  }

  Future<bool> _runAuthentication(int generation) async {
    VaultSessionCapability? capability;
    try {
      capability = await _authenticateVault();
    } catch (_) {
      capability = null;
    }
    if (!_isCurrentOperation(generation)) {
      if (capability != null) _revokeCapabilityWithFallback(capability);
      return false;
    }
    if (capability == null) {
      _status = VaultSessionStatus.locked;
      _capability = null;
      _notifyListenersIfActive();
      return false;
    }
    return _adoptCapability(capability);
  }

  void _revokeCapabilityWithFallback(VaultSessionCapability capability) {
    try {
      _revokeVault(capability);
    } catch (error, stackTrace) {
      _fallbackRevokeCapability(capability);
      if (!_disposed) _recordRevocationFailure(error, stackTrace);
    }
  }

  void _fallbackRevokeCapability(VaultSessionCapability capability) {
    try {
      SessionService.instance.revokeVaultCapability(capability);
    } catch (_) {}
  }

  bool revalidate() {
    if (_disposed) return false;
    if (hasRevocationFailure) {
      _setLockedLocally();
      return false;
    }
    if (_status == VaultSessionStatus.authenticating) return false;
    final capability = _capability ?? _currentCapability();
    if (capability == null) {
      _setLockedLocally();
      return false;
    }
    return _adoptCapability(capability);
  }

  Future<void> lock() async {
    if (_disposed) return;
    if (hasRevocationFailure) {
      _setLockedLocally();
      _throwRecordedRevocationFailure();
    }

    _operationGeneration += 1;
    _cancelExpiryTimer();
    final shouldStopAuthentication = _authenticationFuture != null;
    _authenticationFuture = null;
    final capability = _capability;
    _setLockedLocally();

    Object? revokeFailure;
    StackTrace? revokeFailureStackTrace;
    if (capability != null) {
      try {
        _revokeVault(capability);
      } catch (error, stackTrace) {
        _fallbackRevokeCapability(capability);
        _recordRevocationFailure(error, stackTrace);
        revokeFailure = error;
        revokeFailureStackTrace = stackTrace;
      }
    }
    if (shouldStopAuthentication) {
      try {
        await _stopAuthentication();
      } catch (_) {}
    }
    if (revokeFailure != null) {
      Error.throwWithStackTrace(
        revokeFailure,
        revokeFailureStackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> deactivate() async {
    if (_disposed) return;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    await cancelPendingAuthentication();
  }

  Future<void> cancelPendingAuthentication() async {
    if (_disposed) return;
    if (_authenticationFuture == null) return;

    _operationGeneration += 1;
    _authenticationFuture = null;
    if (_status == VaultSessionStatus.authenticating) {
      _setLockedLocally();
    }
    try {
      await _stopAuthentication();
    } catch (_) {}
  }

  Future<void> revokeCapability(VaultSessionCapability capability) async {
    if (_disposed) return;
    if (hasRevocationFailure) {
      _setLockedLocally();
      _throwRecordedRevocationFailure();
    }
    if (identical(_capability, capability)) {
      _operationGeneration += 1;
      _cancelExpiryTimer();
      _setLockedLocally();
    }
    try {
      _revokeVault(capability);
    } catch (error, stackTrace) {
      _fallbackRevokeCapability(capability);
      _recordRevocationFailure(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool _restoreExistingCapability() {
    if (hasRevocationFailure) return false;
    final capability = _currentCapability();
    if (capability == null) return false;
    return _adoptCapability(capability);
  }

  bool _adoptCapability(VaultSessionCapability capability) {
    if (hasRevocationFailure) {
      _setLockedLocally();
      return false;
    }
    Duration? remaining;
    try {
      remaining = _remainingLifetime(capability);
    } catch (_) {
      remaining = null;
    }
    if (remaining == null || remaining <= Duration.zero) {
      _rejectCapability(capability);
      return false;
    }

    _capability = capability;
    _status = VaultSessionStatus.unlocked;
    _armExpiryTimer(remaining);
    _notifyListenersIfActive();
    return true;
  }

  void _rejectCapability(VaultSessionCapability capability) {
    _operationGeneration += 1;
    _cancelExpiryTimer();
    _setLockedLocally();
    _revokeCapabilityWithFallback(capability);
  }

  void _armExpiryTimer(Duration remaining) {
    _cancelExpiryTimer();
    final generation = _timerGeneration;
    _expiryTimer = Timer(remaining, () {
      if (_disposed || generation != _timerGeneration) return;
      _expireCapability();
    });
  }

  void _cancelExpiryTimer() {
    _timerGeneration += 1;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void _expireCapability() {
    if (_disposed) return;
    _operationGeneration += 1;
    _cancelExpiryTimer();
    final capability = _capability;
    _setLockedLocally();
    if (capability == null) return;
    try {
      _revokeVault(capability);
    } catch (error, stackTrace) {
      _fallbackRevokeCapability(capability);
      _recordRevocationFailure(error, stackTrace);
    }
  }

  void _recordRevocationFailure(Object error, StackTrace stackTrace) {
    _revocationFailure ??= error;
    _revocationFailureStackTrace ??= stackTrace;
    _operationGeneration += 1;
    _cancelExpiryTimer();
    _setLockedLocally();
  }

  Never _throwRecordedRevocationFailure() {
    Error.throwWithStackTrace(
      _revocationFailure!,
      _revocationFailureStackTrace ?? StackTrace.current,
    );
  }

  void _setLockedLocally() {
    final changed = _status != VaultSessionStatus.locked || _capability != null;
    _status = VaultSessionStatus.locked;
    _capability = null;
    if (changed) _notifyListenersIfActive();
  }

  bool _isCurrentOperation(int generation) {
    return !hasRevocationFailure &&
        !_disposed &&
        generation == _operationGeneration;
  }

  void _notifyListenersIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) revalidate();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _operationGeneration += 1;
    _cancelExpiryTimer();
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    if (_authenticationFuture != null) {
      unawaited(_stopAuthentication().catchError((_) {}));
    }
    _authenticationFuture = null;
    _capability = null;
    super.dispose();
  }
}
