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

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  static const _sessionKey = 'session_unlocked_at';
  static const _initializedKey = 'app_initialized';
  Object? _sessionRevocationFailure;
  StackTrace? _sessionRevocationFailureStackTrace;

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

  Future<bool> authenticate({String reason = '请验证指纹以进入个人管家'}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) await markUnlocked();
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }

  DateTime? vaultUnlockedAt;
  bool get isVaultSessionValid {
    if (vaultUnlockedAt == null) return false;
    return isSessionWithinLifetime(
      now: DateTime.now(),
      unlockedAt: vaultUnlockedAt!,
      lifetime: const Duration(minutes: 5),
    );
  }

  void unlockVault() => vaultUnlockedAt = DateTime.now();
  void lockVault() => vaultUnlockedAt = null;
}
