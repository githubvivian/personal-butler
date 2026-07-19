import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/security/session_service.dart';
import 'package:personal_butler/features/vault/vault_session_controller.dart';

const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final session = SessionService.instance;

  setUp(session.lockVault);
  tearDown(() {
    session.lockVault();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

  testWidgets('restores an existing capability for its exact remaining time', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    var authentications = 0;
    var revocations = 0;
    final controller = VaultSessionController(
      currentCapability: () => capability,
      authenticateVault: () async {
        authentications += 1;
        return _authenticateVault(session);
      },
      remainingLifetime: (_) => const Duration(minutes: 2),
      revokeVault: (_) => revocations += 1,
      stopAuthentication: () async {},
    );

    expect(await controller.initialize(), isTrue);
    expect(controller.status, VaultSessionStatus.unlocked);
    expect(controller.capability, same(capability));
    expect(authentications, 0);

    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(controller.status, VaultSessionStatus.unlocked);

    await tester.pump(const Duration(seconds: 1));
    expect(controller.status, VaultSessionStatus.locked);
    expect(controller.capability, isNull);
    expect(revocations, 1);
    controller.dispose();
  });

  test('revoke callback receives the capability being locked', () async {
    final capability = await _authenticateVault(session);
    VaultSessionCapability? revokedCapability;
    final controller = VaultSessionController(
      currentCapability: () => capability,
      authenticateVault: () => session.authenticateVault(),
      remainingLifetime: (_) => const Duration(minutes: 5),
      revokeVault: (target) => revokedCapability = target,
      stopAuthentication: () async {},
    );

    expect(await controller.initialize(), isTrue);
    await controller.lock();

    expect(revokedCapability, same(capability));
    controller.dispose();
  });

  test(
    'locking an old controller does not revoke a newer real session capability',
    () async {
      final previousCapability = await _authenticateVault(session);
      final controller = VaultSessionController(
        authenticateVault: () async => null,
        stopAuthentication: () async {},
      );
      expect(await controller.initialize(), isTrue);
      expect(controller.capability, same(previousCapability));

      final currentCapability = await _authenticateVault(session);
      await controller.lock();

      expect(session.currentVaultCapability(), same(currentCapability));
      controller.dispose();
    },
  );

  testWidgets(
    'expiry in an old controller does not revoke a newer real session capability',
    (tester) async {
      final previousCapability = await _authenticateVault(session);
      final controller = VaultSessionController(
        authenticateVault: () async => null,
        remainingLifetime: (_) => const Duration(seconds: 1),
        stopAuthentication: () async {},
      );
      expect(await controller.initialize(), isTrue);
      expect(controller.capability, same(previousCapability));

      final currentCapability = await _authenticateVault(session);
      await tester.pump(const Duration(seconds: 1));

      expect(controller.status, VaultSessionStatus.locked);
      expect(session.currentVaultCapability(), same(currentCapability));
      controller.dispose();
    },
  );

  test('resume rechecks and hides a capability revoked elsewhere', () async {
    final capability = await _authenticateVault(session);
    Duration? remaining = const Duration(minutes: 3);
    var revocations = 0;
    final controller = VaultSessionController(
      currentCapability: () => capability,
      authenticateVault: () => session.authenticateVault(),
      remainingLifetime: (_) => remaining,
      revokeVault: (_) => revocations += 1,
      stopAuthentication: () async {},
    );
    await controller.initialize();
    remaining = null;

    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

    expect(controller.status, VaultSessionStatus.locked);
    expect(controller.capability, isNull);
    expect(revocations, 1);
    controller.dispose();
  });

  final invalidRemainingLifetimeCases =
      <String, Duration? Function(VaultSessionCapability)>{
        'null': (_) => null,
        'zero': (_) => Duration.zero,
        'negative': (_) => const Duration(milliseconds: -1),
        'exception': (_) => throw StateError('remaining lifetime failed'),
      };
  for (final testCase in invalidRemainingLifetimeCases.entries) {
    test(
      '${testCase.key} remaining lifetime revokes the rejected candidate',
      () async {
        final previousCapability = await _authenticateVault(session);
        final candidate = await _authenticateVault(session);
        var currentCapability = previousCapability;
        final revokedCapabilities = <VaultSessionCapability>[];
        final controller = VaultSessionController(
          currentCapability: () => currentCapability,
          authenticateVault: () async => null,
          remainingLifetime: (capability) {
            if (identical(capability, previousCapability)) {
              return const Duration(minutes: 5);
            }
            return testCase.value(capability);
          },
          revokeVault: revokedCapabilities.add,
          stopAuthentication: () async {},
        );

        expect(await controller.initialize(), isTrue);
        currentCapability = candidate;

        expect(await controller.authenticate(), isFalse);
        expect(controller.status, VaultSessionStatus.locked);
        expect(controller.capability, isNull);
        expect(revokedCapabilities, hasLength(1));
        expect(revokedCapabilities.single, same(candidate));
        controller.dispose();
      },
    );
  }

  test(
    'rejected candidate falls back to singleton revoke when injection throws first',
    () async {
      final candidate = await _authenticateVault(session);
      VaultSessionCapability? injectedTarget;
      final failure = StateError('candidate revoke failed');
      final controller = VaultSessionController(
        currentCapability: () => candidate,
        authenticateVault: () async => null,
        remainingLifetime: (_) => null,
        revokeVault: (capability) {
          injectedTarget = capability;
          throw failure;
        },
        stopAuthentication: () async {},
      );

      expect(await controller.initialize(), isFalse);
      expect(injectedTarget, same(candidate));
      expect(session.currentVaultCapability(), isNull);
      expect(controller.status, VaultSessionStatus.locked);
      expect(controller.capability, isNull);
      expect(controller.hasRevocationFailure, isTrue);
      expect(controller.revocationFailure, same(failure));
      controller.dispose();
    },
  );

  test(
    'concurrent authentication requests share one vault authentication',
    () async {
      final capability = await _authenticateVault(session);
      final authenticationGate = Completer<VaultSessionCapability?>();
      var authentications = 0;
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () {
          authentications += 1;
          return authenticationGate.future;
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: session.revokeVaultCapability,
        stopAuthentication: () async {},
      );

      final first = controller.authenticate();
      final second = controller.authenticate();

      expect(second, same(first));
      expect(authentications, 1);
      authenticationGate.complete(capability);
      expect(await first, isTrue);
      expect(controller.status, VaultSessionStatus.unlocked);
      expect(controller.capability, same(capability));
      controller.dispose();
    },
  );

  test('failed authentication leaves a retryable locked state', () async {
    final capability = await _authenticateVault(session);
    var authentications = 0;
    final controller = VaultSessionController(
      currentCapability: () => null,
      authenticateVault: () async {
        authentications += 1;
        return authentications > 1 ? capability : null;
      },
      remainingLifetime: (_) => const Duration(minutes: 5),
      revokeVault: session.revokeVaultCapability,
      stopAuthentication: () async {},
    );

    expect(await controller.authenticate(), isFalse);
    expect(controller.status, VaultSessionStatus.locked);
    expect(await controller.authenticate(), isTrue);
    expect(controller.status, VaultSessionStatus.unlocked);
    expect(authentications, 2);
    controller.dispose();
  });

  test('locking during authentication revokes the real late result', () async {
    final authenticationGate = Completer<void>();
    var authentications = 0;
    var stops = 0;
    final controller = VaultSessionController(
      currentCapability: () => null,
      authenticateVault: () async {
        authentications += 1;
        await authenticationGate.future;
        return _authenticateVault(session);
      },
      remainingLifetime: (_) => const Duration(minutes: 5),
      revokeVault: session.revokeVaultCapability,
      stopAuthentication: () async {
        stops += 1;
      },
    );

    final authentication = controller.authenticate();
    await controller.lock();
    authenticationGate.complete();

    expect(await authentication, isFalse);
    expect(controller.status, VaultSessionStatus.locked);
    expect(session.currentVaultCapability(), isNull);
    expect(authentications, 1);
    expect(stops, 1);
    controller.dispose();
  });

  test(
    'lock releases the authentication slot before the stale future completes',
    () async {
      final firstGate = Completer<VaultSessionCapability?>();
      final secondGate = Completer<VaultSessionCapability?>();
      var authentications = 0;
      var stops = 0;
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () {
          authentications += 1;
          return authentications == 1 ? firstGate.future : secondGate.future;
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: session.revokeVaultCapability,
        stopAuthentication: () async {
          stops += 1;
        },
      );
      addTearDown(() {
        if (!firstGate.isCompleted) firstGate.complete(null);
        if (!secondGate.isCompleted) secondGate.complete(null);
        controller.dispose();
      });

      final staleAuthentication = controller.authenticate();
      await controller.lock();
      final currentAuthentication = controller.authenticate();

      expect(authentications, 2);
      expect(stops, 1);

      firstGate.complete(null);
      expect(await staleAuthentication, isFalse);
      expect(controller.authenticate(), same(currentAuthentication));
      expect(authentications, 2);

      final capability = await _authenticateVault(session);
      secondGate.complete(capability);
      expect(await currentAuthentication, isTrue);
      expect(controller.capability, same(capability));
    },
  );

  test(
    'cancelPendingAuthentication revokes a real capability returned later',
    () async {
      final authenticationGate = Completer<void>();
      var stops = 0;
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () async {
          await authenticationGate.future;
          return _authenticateVault(session);
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: session.revokeVaultCapability,
        stopAuthentication: () async {
          stops += 1;
        },
      );

      final authentication = controller.authenticate();
      await controller.cancelPendingAuthentication();
      authenticationGate.complete();

      expect(await authentication, isFalse);
      expect(controller.status, VaultSessionStatus.locked);
      expect(session.currentVaultCapability(), isNull);
      expect(stops, 1);
      controller.dispose();
    },
  );

  test('dispose revokes a real capability returned later', () async {
    final authenticationGate = Completer<void>();
    var stops = 0;
    final controller = VaultSessionController(
      currentCapability: () => null,
      authenticateVault: () async {
        await authenticationGate.future;
        return _authenticateVault(session);
      },
      remainingLifetime: (_) => const Duration(minutes: 5),
      revokeVault: session.revokeVaultCapability,
      stopAuthentication: () async {
        stops += 1;
      },
    );

    final authentication = controller.authenticate();
    controller.dispose();
    authenticationGate.complete();

    expect(await authentication, isFalse);
    expect(session.currentVaultCapability(), isNull);
    expect(stops, 1);
  });

  test(
    'dispose falls back to the singleton when late injected revoke throws first',
    () async {
      final authenticationGate = Completer<void>();
      VaultSessionCapability? lateCapability;
      final failure = StateError('disposed late revoke failed');
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () async {
          await authenticationGate.future;
          lateCapability = await _authenticateVault(session);
          return lateCapability;
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: (_) => throw failure,
        stopAuthentication: () async {},
      );

      final authentication = controller.authenticate();
      controller.dispose();
      authenticationGate.complete();

      expect(await authentication, isFalse);
      expect(lateCapability, isNotNull);
      expect(session.currentVaultCapability(), isNull);
    },
  );

  test(
    'stale authentication targets its old token without revoking a newer token',
    () async {
      final authenticationGate = Completer<void>();
      VaultSessionCapability? lateCapability;
      VaultSessionCapability? newerCapability;
      VaultSessionCapability? revokedCapability;
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () async {
          await authenticationGate.future;
          lateCapability = await _authenticateVault(session);
          newerCapability = await _authenticateVault(session);
          return lateCapability;
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: (capability) {
          revokedCapability = capability;
          session.revokeVaultCapability(capability);
        },
        stopAuthentication: () async {},
      );

      final authentication = controller.authenticate();
      await controller.cancelPendingAuthentication();
      authenticationGate.complete();

      expect(await authentication, isFalse);
      expect(revokedCapability, same(lateCapability));
      expect(session.currentVaultCapability(), same(newerCapability));
      controller.dispose();
    },
  );

  test('late revoke failure is recorded after cancellation', () async {
    final authenticationGate = Completer<void>();
    VaultSessionCapability? lateCapability;
    final failure = StateError('late revoke failed');
    final controller = VaultSessionController(
      currentCapability: () => null,
      authenticateVault: () async {
        await authenticationGate.future;
        lateCapability = await _authenticateVault(session);
        return lateCapability;
      },
      remainingLifetime: (_) => const Duration(minutes: 5),
      revokeVault: (_) => throw failure,
      stopAuthentication: () async {},
    );

    final authentication = controller.authenticate();
    await controller.cancelPendingAuthentication();
    authenticationGate.complete();

    expect(await authentication, isFalse);
    expect(controller.status, VaultSessionStatus.locked);
    expect(controller.hasRevocationFailure, isTrue);
    expect(controller.revocationFailure, same(failure));
    expect(lateCapability, isNotNull);
    expect(session.currentVaultCapability(), isNull);
    controller.dispose();
  });

  test(
    'disposed late revoke failure is contained and preserves a newer token',
    () async {
      final authenticationGate = Completer<void>();
      VaultSessionCapability? lateCapability;
      VaultSessionCapability? newerCapability;
      VaultSessionCapability? revokedCapability;
      final failure = StateError('disposed late revoke failed');
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () async {
          await authenticationGate.future;
          lateCapability = await _authenticateVault(session);
          newerCapability = await _authenticateVault(session);
          return lateCapability;
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: (capability) {
          revokedCapability = capability;
          throw failure;
        },
        stopAuthentication: () async {},
      );

      final authentication = controller.authenticate();
      controller.dispose();
      authenticationGate.complete();

      expect(await authentication, isFalse);
      expect(revokedCapability, same(lateCapability));
      expect(session.currentVaultCapability(), same(newerCapability));
    },
  );

  test(
    'lock reports revoke failure and permanently blocks authentication',
    () async {
      final capability = await _authenticateVault(session);
      final failure = StateError('revoke failed');
      var authentications = 0;
      final controller = VaultSessionController(
        currentCapability: () => capability,
        authenticateVault: () async {
          authentications += 1;
          return _authenticateVault(session);
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: (_) => throw failure,
        stopAuthentication: () async {},
      );
      expect(await controller.initialize(), isTrue);

      await expectLater(controller.lock(), throwsA(same(failure)));

      expect(controller.status, VaultSessionStatus.locked);
      expect(controller.capability, isNull);
      expect(controller.hasRevocationFailure, isTrue);
      expect(controller.revocationFailure, same(failure));
      expect(session.currentVaultCapability(), isNull);
      expect(await controller.authenticate(), isFalse);
      expect(authentications, 0);
      controller.dispose();
    },
  );

  test(
    'explicit revoke reports failure while keeping the controller locked',
    () async {
      final capability = await _authenticateVault(session);
      final failure = StateError('revoke failed');
      final controller = VaultSessionController(
        currentCapability: () => capability,
        authenticateVault: () => session.authenticateVault(),
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: (_) => throw failure,
        stopAuthentication: () async {},
      );
      expect(await controller.initialize(), isTrue);

      await expectLater(
        controller.revokeCapability(capability),
        throwsA(same(failure)),
      );

      expect(controller.status, VaultSessionStatus.locked);
      expect(controller.hasRevocationFailure, isTrue);
      expect(session.currentVaultCapability(), isNull);
      controller.dispose();
    },
  );

  testWidgets('timer revoke failure is contained and blocks reauthentication', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final failure = StateError('timer revoke failed');
    var authentications = 0;
    final controller = VaultSessionController(
      currentCapability: () => capability,
      authenticateVault: () async {
        authentications += 1;
        return _authenticateVault(session);
      },
      remainingLifetime: (_) => const Duration(seconds: 1),
      revokeVault: (_) => throw failure,
      stopAuthentication: () async {},
    );
    expect(await controller.initialize(), isTrue);

    await tester.pump(const Duration(seconds: 1));

    expect(controller.status, VaultSessionStatus.locked);
    expect(controller.hasRevocationFailure, isTrue);
    expect(session.currentVaultCapability(), isNull);
    expect(tester.takeException(), isNull);
    expect(await controller.authenticate(), isFalse);
    expect(authentications, 0);
    controller.dispose();
  });
}

Future<VaultSessionCapability> _authenticateVault(
  SessionService session,
) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_localAuthChannel, (call) async {
        if (call.method == 'authenticate') return true;
        return null;
      });
  final capability = await session.authenticateVault(reason: 'Test vault');
  expect(capability, isNotNull);
  return capability!;
}
