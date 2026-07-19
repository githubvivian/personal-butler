import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/security/session_service.dart';

const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final session = SessionService.instance;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    session.lockVault();
  });

  tearDown(session.lockVault);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

  group('session lifetime policy', () {
    final now = DateTime.utc(2026, 7, 15, 12);
    const lifetime = Duration(minutes: 5);

    test('accepts elapsed time strictly below the lifetime', () {
      expect(
        isSessionWithinLifetime(
          now: now,
          unlockedAt: now
              .subtract(lifetime)
              .add(const Duration(microseconds: 1)),
          lifetime: lifetime,
        ),
        isTrue,
      );
    });

    test('rejects elapsed time exactly equal to the lifetime', () {
      expect(
        isSessionWithinLifetime(
          now: now,
          unlockedAt: now.subtract(lifetime),
          lifetime: lifetime,
        ),
        isFalse,
      );
    });

    test('rejects negative elapsed time', () {
      expect(
        isSessionWithinLifetime(
          now: now,
          unlockedAt: now.add(const Duration(microseconds: 1)),
          lifetime: lifetime,
        ),
        isFalse,
      );
    });
  });

  group('main session lifetime', () {
    test('returns the exact remaining lifetime for a valid timestamp', () {
      final now = DateTime.utc(2026, 7, 17, 12);

      expect(
        remainingSessionLifetime(
          now: now,
          unlockedAt: now.subtract(const Duration(minutes: 30)),
          lifetime: const Duration(hours: 2),
        ),
        const Duration(minutes: 90),
      );
    });

    test('reads the remaining lifetime from the persisted timestamp', () async {
      final now = DateTime.utc(2026, 7, 17, 12);
      FlutterSecureStorage.setMockInitialValues({
        'session_unlocked_at': now
            .subtract(const Duration(minutes: 45))
            .toIso8601String(),
      });

      expect(
        await session.getRemainingSessionLifetime(now: now),
        const Duration(minutes: 75),
      );
    });

    test('returns null when the persisted timestamp is missing', () async {
      final now = DateTime.utc(2026, 7, 17, 12);

      expect(await session.getRemainingSessionLifetime(now: now), isNull);
    });

    test('returns null when the persisted timestamp is malformed', () async {
      FlutterSecureStorage.setMockInitialValues({
        'session_unlocked_at': 'not-a-date',
      });

      expect(
        await session.getRemainingSessionLifetime(
          now: DateTime.utc(2026, 7, 17, 12),
        ),
        isNull,
      );
    });

    test('returns null for a future or expired persisted timestamp', () async {
      final now = DateTime.utc(2026, 7, 17, 12);

      for (final unlockedAt in [
        now.add(const Duration(microseconds: 1)),
        now.subtract(const Duration(hours: 2)),
      ]) {
        FlutterSecureStorage.setMockInitialValues({
          'session_unlocked_at': unlockedAt.toIso8601String(),
        });

        expect(await session.getRemainingSessionLifetime(now: now), isNull);
      }
    });

    test('rejects a persisted unlock timestamp in the future', () async {
      FlutterSecureStorage.setMockInitialValues({
        'session_unlocked_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });

      expect(await session.isSessionValid(), isFalse);
    });

    test('accepts a recent persisted timestamp', () async {
      FlutterSecureStorage.setMockInitialValues({
        'session_unlocked_at': DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      });

      expect(await session.isSessionValid(), isTrue);
    });
  });

  group('vault session lifetime', () {
    test('does not expose a raw capability issuer', () {
      final dynamic dynamicSession = session;

      expect(
        () => dynamicSession.unlockVault(),
        throwsA(isA<NoSuchMethodError>()),
      );
    });

    test('does not issue a capability when biometrics return false', () async {
      _setAuthenticationResult(false);

      expect(await session.authenticateVault(reason: 'Open vault'), isNull);
      expect(session.currentVaultCapability(), isNull);
    });

    test('does not issue a capability when biometrics throw', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            throw PlatformException(code: 'auth_failed');
          });

      expect(await session.authenticateVault(reason: 'Open vault'), isNull);
      expect(session.currentVaultCapability(), isNull);
    });

    test(
      'issues the current capability only after biometrics succeed',
      () async {
        _setAuthenticationResult(true);

        final capability = await session.authenticateVault(
          reason: 'Open vault',
        );

        expect(capability, isNotNull);
        expect(session.currentVaultCapability(), same(capability));
      },
    );

    test(
      'a newer vault authentication invalidates an older late result',
      () async {
        final firstAuthenticationStarted = Completer<void>();
        final firstAuthenticationResult = Completer<bool>();
        var authenticationCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_localAuthChannel, (call) async {
              if (call.method != 'authenticate') return null;
              authenticationCalls += 1;
              if (authenticationCalls == 1) {
                firstAuthenticationStarted.complete();
                return firstAuthenticationResult.future;
              }
              return true;
            });

        final olderAuthentication = session.authenticateVault(
          reason: 'Older authentication',
        );
        await firstAuthenticationStarted.future;
        final newerCapability = await session.authenticateVault(
          reason: 'Newer authentication',
        );
        firstAuthenticationResult.complete(true);

        expect(newerCapability, isNotNull);
        expect(await olderAuthentication, isNull);
        expect(session.currentVaultCapability(), same(newerCapability));
      },
    );

    test('stopping authentication rejects a late biometric success', () async {
      final authenticationStarted = Completer<void>();
      final authenticationResult = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method == 'authenticate') {
              authenticationStarted.complete();
              return authenticationResult.future;
            }
            return null;
          });

      final authentication = session.authenticateVault(
        reason: 'Cancelled authentication',
      );
      await authenticationStarted.future;
      await session.stopAuthentication();
      authenticationResult.complete(true);

      expect(await authentication, isNull);
      expect(session.currentVaultCapability(), isNull);
    });

    test('locking the vault rejects a late biometric success', () async {
      final authenticationStarted = Completer<void>();
      final authenticationResult = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method == 'authenticate') {
              authenticationStarted.complete();
              return authenticationResult.future;
            }
            return null;
          });

      final authentication = session.authenticateVault(
        reason: 'Authentication before lock',
      );
      await authenticationStarted.future;
      session.lockVault();
      authenticationResult.complete(true);

      expect(await authentication, isNull);
      expect(session.currentVaultCapability(), isNull);
    });

    test('does not expose a writable vault issuance timestamp', () async {
      final capability = await _authenticateVault(session);
      final dynamic dynamicSession = session;

      expect(
        () => dynamicSession.vaultUnlockedAt = DateTime.now(),
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(session.isVaultCapabilityValid(capability), isTrue);
    });

    test('does not accept a caller-supplied vault issuance timestamp', () {
      final dynamic dynamicSession = session;

      expect(
        () => dynamicSession.authenticateVault(
          now: DateTime.now().add(const Duration(days: 1)),
        ),
        throwsA(isA<NoSuchMethodError>()),
      );
    });

    test('vault capability APIs reject caller-supplied clocks', () async {
      final capability = await _authenticateVault(session);
      final dynamic dynamicSession = session;

      for (final call in <void Function()>[
        () => dynamicSession.currentVaultCapability(now: DateTime.now()),
        () => dynamicSession.isVaultCapabilityValid(
          capability,
          now: DateTime.now(),
        ),
        () => dynamicSession.getVaultRemainingLifetime(
          capability,
          now: DateTime.now(),
        ),
      ]) {
        expect(call, throwsA(isA<NoSuchMethodError>()));
      }
    });

    test('locking revokes the active capability', () async {
      final capability = await _authenticateVault(session);

      session.lockVault();

      expect(session.isVaultCapabilityValid(capability), isFalse);
    });

    test(
      'reauthentication permanently revokes the previous capability',
      () async {
        final previous = await _authenticateVault(session);
        final current = await _authenticateVault(session);

        expect(session.isVaultCapabilityValid(previous), isFalse);
        expect(session.isVaultCapabilityValid(current), isTrue);
      },
    );

    test(
      'revoking an old capability cannot revoke the current capability',
      () async {
        final previous = await _authenticateVault(session);
        final current = await _authenticateVault(session);

        session.revokeVaultCapability(previous);

        expect(session.isVaultCapabilityValid(current), isTrue);
      },
    );

    test(
      'main session lock synchronously revokes the vault capability',
      () async {
        final capability = await _authenticateVault(session);

        final locking = session.lock();

        expect(session.isVaultCapabilityValid(capability), isFalse);
        expect(session.currentVaultCapability(), isNull);
        await locking;
      },
    );
  });

  group('vault capability clock policy', () {
    final issuedWallNow = DateTime.utc(2026, 7, 18, 12);
    const issuedMonotonicMicros = 1000000;
    late DateTime wallNow;
    late int monotonicMicros;
    late SessionService clockedSession;

    setUp(() {
      wallNow = issuedWallNow;
      monotonicMicros = issuedMonotonicMicros;
      clockedSession = SessionService.forTesting(
        wallNow: () => wallNow,
        monotonicMicros: () => monotonicMicros,
      );
    });

    test('small wall rollback cannot extend the real deadline', () async {
      final capability = await _authenticateVault(clockedSession);
      wallNow = issuedWallNow.add(const Duration(minutes: 4));
      monotonicMicros += const Duration(minutes: 4).inMicroseconds;

      expect(
        clockedSession.getVaultRemainingLifetime(capability),
        const Duration(minutes: 1),
      );

      wallNow = wallNow.subtract(const Duration(seconds: 30));
      monotonicMicros += const Duration(seconds: 10).inMicroseconds;

      expect(
        clockedSession.getVaultRemainingLifetime(capability),
        const Duration(seconds: 50),
      );
    });

    test('expires at exactly five monotonic minutes', () async {
      final capability = await _authenticateVault(clockedSession);
      wallNow = issuedWallNow.add(const Duration(minutes: 4, seconds: 59));
      monotonicMicros += const Duration(minutes: 5).inMicroseconds;

      expect(clockedSession.isVaultCapabilityValid(capability), isFalse);
      expect(clockedSession.currentVaultCapability(), isNull);
    });

    test('fails closed when the monotonic clock moves backwards', () async {
      final capability = await _authenticateVault(clockedSession);
      monotonicMicros = issuedMonotonicMicros - 1;

      expect(clockedSession.isVaultCapabilityValid(capability), isFalse);
      expect(clockedSession.currentVaultCapability(), isNull);
    });

    test('fails closed when the wall clock jumps forward', () async {
      final capability = await _authenticateVault(clockedSession);
      wallNow = issuedWallNow.add(const Duration(days: 1));
      monotonicMicros += const Duration(seconds: 1).inMicroseconds;

      expect(clockedSession.isVaultCapabilityValid(capability), isFalse);
      expect(clockedSession.currentVaultCapability(), isNull);
    });

    test('fails closed when the wall clock predates issuance', () async {
      final capability = await _authenticateVault(clockedSession);
      wallNow = issuedWallNow.subtract(const Duration(microseconds: 1));

      expect(clockedSession.isVaultCapabilityValid(capability), isFalse);
    });

    test('isolated capabilities are rejected by the singleton', () async {
      final capability = await _authenticateVault(clockedSession);

      expect(session.isVaultCapabilityValid(capability), isFalse);
      expect(clockedSession.isVaultCapabilityValid(capability), isTrue);
    });

    test('returns the current capability only before its deadline', () async {
      final capability = await _authenticateVault(clockedSession);
      wallNow = issuedWallNow.add(const Duration(minutes: 4));
      monotonicMicros += const Duration(minutes: 4).inMicroseconds;

      expect(clockedSession.currentVaultCapability(), same(capability));

      wallNow = issuedWallNow.add(const Duration(minutes: 5));
      monotonicMicros =
          issuedMonotonicMicros + const Duration(minutes: 5).inMicroseconds;

      expect(clockedSession.currentVaultCapability(), isNull);
      expect(clockedSession.currentVaultCapability(), isNull);
    });
  });

  group('biometric authentication modes', () {
    test(
      'vault-only authentication does not refresh the main session',
      () async {
        final persistedAt = DateTime.now().subtract(
          const Duration(minutes: 30),
        );
        FlutterSecureStorage.setMockInitialValues({
          'session_unlocked_at': persistedAt.toIso8601String(),
        });
        _setAuthenticationResult(true);

        expect(
          await session.authenticateVault(reason: 'Open vault'),
          isNotNull,
        );

        expect(
          await session.getRemainingSessionLifetime(
            now: persistedAt.add(const Duration(minutes: 30)),
          ),
          const Duration(minutes: 90),
        );
      },
    );

    test('main authentication still refreshes the main session', () async {
      FlutterSecureStorage.setMockInitialValues({});
      _setAuthenticationResult(true);

      expect(await session.authenticate(reason: 'Unlock app'), isTrue);
      expect(await session.isSessionValid(), isTrue);
    });

    test('main authentication returns false when biometrics throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            throw PlatformException(code: 'auth_failed');
          });

      expect(await session.authenticate(reason: 'Unlock app'), isFalse);
    });

    test(
      'main authentication flow returns false when persistence fails',
      () async {
        var persistCalls = 0;

        expect(
          await authenticateAndPersistSession(
            authenticate: () async => true,
            persist: () async {
              persistCalls += 1;
              throw StateError('write failed');
            },
          ),
          isFalse,
        );
        expect(persistCalls, 1);
      },
    );
  });
}

void _setAuthenticationResult(bool result) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_localAuthChannel, (call) async {
        if (call.method == 'authenticate') return result;
        return null;
      });
}

Future<VaultSessionCapability> _authenticateVault(
  SessionService session,
) async {
  _setAuthenticationResult(true);
  final capability = await session.authenticateVault(reason: 'Test vault');
  expect(capability, isNotNull);
  return capability!;
}
