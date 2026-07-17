import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../constants/app_constants.dart';

bool isSessionWithinLifetime({
  required DateTime now,
  required DateTime unlockedAt,
  required Duration lifetime,
}) {
  return remainingSessionLifetime(
        now: now,
        unlockedAt: unlockedAt,
        lifetime: lifetime,
      ) !=
      null;
}

Duration? remainingSessionLifetime({
  required DateTime now,
  required DateTime unlockedAt,
  required Duration lifetime,
}) {
  final elapsed = now.difference(unlockedAt);
  if (elapsed.isNegative || elapsed >= lifetime) return null;
  return lifetime - elapsed;
}

@visibleForTesting
Future<bool> authenticateAndPersistSession({
  required Future<bool> Function() authenticate,
  required Future<void> Function() persist,
}) async {
  try {
    if (!await authenticate()) return false;
    await persist();
    return true;
  } catch (_) {
    return false;
  }
}

final class VaultSessionCapability {
  const VaultSessionCapability._(
    this._generation,
    this._wallIssuedAt,
    this._issuedMonotonicMicros,
  );

  final int _generation;
  final DateTime _wallIssuedAt;
  final int _issuedMonotonicMicros;
}

class SessionService {
  SessionService._({
    DateTime Function()? wallNow,
    int Function()? monotonicMicros,
  }) : _wallNow = wallNow ?? DateTime.now,
       _monotonicMicros = monotonicMicros ?? _productionMonotonicMicros;

  static final SessionService instance = SessionService._();
  static final Stopwatch _productionMonotonicClock = Stopwatch()..start();

  @visibleForTesting
  factory SessionService.forTesting({
    required DateTime Function() wallNow,
    required int Function() monotonicMicros,
  }) {
    return SessionService._(wallNow: wallNow, monotonicMicros: monotonicMicros);
  }

  static int _productionMonotonicMicros() {
    return _productionMonotonicClock.elapsedMicroseconds;
  }

  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  final DateTime Function() _wallNow;
  final int Function() _monotonicMicros;
  static const _sessionKey = 'session_unlocked_at';
  static const _initializedKey = 'app_initialized';
  static const vaultSessionLifetime = Duration(minutes: 5);
  Object? _sessionRevocationFailure;
  StackTrace? _sessionRevocationFailureStackTrace;
  int _vaultAuthenticationGeneration = 0;
  int _vaultGeneration = 0;
  VaultSessionCapability? _activeVaultCapability;

  Future<bool> isAppInitialized() async {
    final v = await _storage.read(key: _initializedKey);
    return v == 'true';
  }

  Future<void> markInitialized() async {
    await _storage.write(key: _initializedKey, value: 'true');
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> isSessionValid() async {
    return await getRemainingSessionLifetime() != null;
  }

  Future<Duration?> getRemainingSessionLifetime({DateTime? now}) async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    final unlockedAt = DateTime.tryParse(raw);
    if (unlockedAt == null) return null;
    return remainingSessionLifetime(
      now: now ?? DateTime.now(),
      unlockedAt: unlockedAt,
      lifetime: const Duration(hours: AppConstants.sessionHours),
    );
  }

  Future<void> markUnlocked() async {
    await _storage.write(
      key: _sessionKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<void> lock() async {
    lockVault();
    await _storage.delete(key: _sessionKey);
  }

  void recordSessionRevocationFailure(Object error, StackTrace stackTrace) {
    _sessionRevocationFailure = error;
    _sessionRevocationFailureStackTrace = stackTrace;
  }

  void clearSessionRevocationFailure() {
    _sessionRevocationFailure = null;
    _sessionRevocationFailureStackTrace = null;
  }

  bool get hasSessionRevocationFailure => _sessionRevocationFailure != null;

  void throwIfSessionRevocationFailed() {
    final error = _sessionRevocationFailure;
    if (error == null) return;
    Error.throwWithStackTrace(
      error,
      _sessionRevocationFailureStackTrace ?? StackTrace.current,
    );
  }

  Future<bool> _authenticateBiometricOnly({
    String reason = '请验证指纹以进入个人管家',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = '请验证指纹以进入个人管家'}) {
    return authenticateAndPersistSession(
      authenticate: () => _authenticateBiometricOnly(reason: reason),
      persist: markUnlocked,
    );
  }

  Future<VaultSessionCapability?> authenticateVault({
    String reason = '验证指纹以打开密码库',
  }) async {
    final authenticationGeneration = ++_vaultAuthenticationGeneration;
    if (!await _authenticateBiometricOnly(reason: reason)) return null;
    if (authenticationGeneration != _vaultAuthenticationGeneration) {
      return null;
    }
    return _issueVaultCapability();
  }

  Future<void> stopAuthentication() async {
    _vaultAuthenticationGeneration += 1;
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }

  bool get isVaultSessionValid {
    final capability = _activeVaultCapability;
    return capability != null && isVaultCapabilityValid(capability);
  }

  VaultSessionCapability _issueVaultCapability() {
    _vaultGeneration += 1;
    final capability = VaultSessionCapability._(
      _vaultGeneration,
      _wallNow(),
      _monotonicMicros(),
    );
    _activeVaultCapability = capability;
    return capability;
  }

  VaultSessionCapability? currentVaultCapability() {
    final capability = _activeVaultCapability;
    if (capability == null || !isVaultCapabilityValid(capability)) {
      return null;
    }
    return capability;
  }

  bool isVaultCapabilityValid(VaultSessionCapability capability) {
    return getVaultRemainingLifetime(capability) != null;
  }

  Duration? getVaultRemainingLifetime(VaultSessionCapability capability) {
    if (!identical(capability, _activeVaultCapability) ||
        capability._generation != _vaultGeneration) {
      return null;
    }
    final wallRemaining = remainingSessionLifetime(
      now: _wallNow(),
      unlockedAt: capability._wallIssuedAt,
      lifetime: vaultSessionLifetime,
    );
    final monotonicElapsedMicros =
        _monotonicMicros() - capability._issuedMonotonicMicros;
    final monotonicRemaining =
        monotonicElapsedMicros < 0 ||
            monotonicElapsedMicros >= vaultSessionLifetime.inMicroseconds
        ? null
        : Duration(
            microseconds:
                vaultSessionLifetime.inMicroseconds - monotonicElapsedMicros,
          );
    if (wallRemaining == null || monotonicRemaining == null) {
      lockVault();
      return null;
    }
    return wallRemaining.compareTo(monotonicRemaining) <= 0
        ? wallRemaining
        : monotonicRemaining;
  }

  void revokeVaultCapability(VaultSessionCapability capability) {
    if (identical(capability, _activeVaultCapability) &&
        capability._generation == _vaultGeneration) {
      lockVault();
    }
  }

  void lockVault() {
    _vaultAuthenticationGeneration += 1;
    _vaultGeneration += 1;
    _activeVaultCapability = null;
  }
}
