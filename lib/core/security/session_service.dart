import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../constants/app_constants.dart';

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();
  static const _sessionKey = 'session_unlocked_at';
  static const _initializedKey = 'app_initialized';

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
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return false;
    final unlockedAt = DateTime.tryParse(raw);
    if (unlockedAt == null) return false;
    return DateTime.now().difference(unlockedAt) <
        const Duration(hours: AppConstants.sessionHours);
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

  DateTime? vaultUnlockedAt;
  bool get isVaultSessionValid {
    if (vaultUnlockedAt == null) return false;
    return DateTime.now().difference(vaultUnlockedAt!) <
        const Duration(minutes: 5);
  }

  void unlockVault() => vaultUnlockedAt = DateTime.now();
  void lockVault() => vaultUnlockedAt = null;
}
