import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/security/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final session = SessionService.instance;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    session.lockVault();
  });

  tearDown(session.lockVault);

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
    test('rejects an in-memory unlock timestamp in the future', () {
      session.vaultUnlockedAt = DateTime.now().add(const Duration(minutes: 1));

      expect(session.isVaultSessionValid, isFalse);
    });

    test('accepts a recent in-memory timestamp', () {
      session.vaultUnlockedAt = DateTime.now().subtract(
        const Duration(minutes: 4),
      );

      expect(session.isVaultSessionValid, isTrue);
    });
  });
}
