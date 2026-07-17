import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/database/database_schema.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/security/session_service.dart';
import 'package:personal_butler/features/vault/vault_screen.dart';
import 'package:personal_butler/features/vault/vault_session_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final session = SessionService.instance;

  setUp(session.lockVault);
  tearDown(() {
    session.lockVault();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

  testWidgets('expiry hides entries and offers a successful reauthentication', (
    tester,
  ) async {
    VaultSessionCapability? current = await _authenticateVault(session);
    final first = current;
    var authentications = 0;
    final controller = VaultSessionController(
      currentCapability: () => current,
      authenticateVault: () async {
        authentications += 1;
        current = await _authenticateVault(session);
        return current!;
      },
      remainingLifetime: (capability) => identical(capability, first)
          ? const Duration(minutes: 1)
          : const Duration(minutes: 5),
      revokeVault: (capability) {
        session.revokeVaultCapability(capability);
        if (identical(current, capability)) current = null;
      },
      stopAuthentication: () async {},
    );
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
    );

    await tester.pumpWidget(_app(controller, repository));
    await tester.pump();
    expect(find.text('Primary email'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(find.text('Primary email'), findsNothing);
    expect(find.byKey(const Key('vault_locked')), findsOneWidget);

    await tester.tap(find.byKey(const Key('vault_reauthenticate')));
    await tester.pump();
    await tester.pump();

    expect(authentications, 1);
    expect(find.text('Primary email'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'late load from replaced controller and repository cannot update the screen',
    (tester) async {
      final oldCapability = await _authenticateVault(session);
      final oldLoadStarted = Completer<void>();
      final oldLoadGate = Completer<List<VaultEntryModel>>();
      final oldController = _unlockedController(oldCapability);
      final oldRepository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) {
          oldLoadStarted.complete();
          return oldLoadGate.future;
        },
      );

      await tester.pumpWidget(
        _app(oldController, oldRepository, screenKey: const ValueKey('vault')),
      );
      await tester.pump();
      await oldLoadStarted.future;

      final newCapability = await _authenticateVault(session);
      final newController = _unlockedController(newCapability);
      final newRepository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) async => [
          _entry(id: 'new-entry', name: 'Current entry'),
        ],
      );
      await tester.pumpWidget(
        _app(newController, newRepository, screenKey: const ValueKey('vault')),
      );
      await tester.pump();

      oldLoadGate.complete([_entry(id: 'old-entry', name: 'Stale entry')]);
      await tester.pump();

      expect(find.text('Current entry'), findsOneWidget);
      expect(find.text('Stale entry'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      oldController.dispose();
      newController.dispose();
    },
  );

  testWidgets('controller-only replacement ignores the previous pending load', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final oldLoadStarted = Completer<void>();
    final oldLoadGate = Completer<List<VaultEntryModel>>();
    var loadCalls = 0;
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) {
        loadCalls += 1;
        if (loadCalls == 1) {
          oldLoadStarted.complete();
          return oldLoadGate.future;
        }
        return Future.value([
          _entry(id: 'new-entry', name: 'Current controller entry'),
        ]);
      },
    );
    final oldController = _unlockedController(
      capability,
      revokeVault: _ignoreRevocation,
    );
    final newController = _unlockedController(
      capability,
      revokeVault: _ignoreRevocation,
    );

    await tester.pumpWidget(
      _app(oldController, repository, screenKey: const ValueKey('vault')),
    );
    await tester.pump();
    await oldLoadStarted.future;

    await tester.pumpWidget(
      _app(newController, repository, screenKey: const ValueKey('vault')),
    );
    await tester.pump();

    oldLoadGate.complete([
      _entry(id: 'old-entry', name: 'Previous controller entry'),
    ]);
    await tester.pump();

    expect(find.text('Current controller entry'), findsOneWidget);
    expect(find.text('Previous controller entry'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    oldController.dispose();
    newController.dispose();
  });

  testWidgets('repository-only replacement ignores the previous pending load', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final oldLoadStarted = Completer<void>();
    final oldLoadGate = Completer<List<VaultEntryModel>>();
    final oldRepository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) {
        oldLoadStarted.complete();
        return oldLoadGate.future;
      },
    );
    final newRepository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(id: 'new-entry', name: 'Current repository entry'),
      ],
    );

    await tester.pumpWidget(
      _app(controller, oldRepository, screenKey: const ValueKey('vault')),
    );
    await tester.pump();
    await oldLoadStarted.future;

    await tester.pumpWidget(
      _app(controller, newRepository, screenKey: const ValueKey('vault')),
    );
    await tester.pump();

    oldLoadGate.complete([
      _entry(id: 'old-entry', name: 'Previous repository entry'),
    ]);
    await tester.pump();

    expect(find.text('Current repository entry'), findsOneWidget);
    expect(find.text('Previous repository entry'), findsNothing);
    expect(session.currentVaultCapability(), same(capability));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'replacing controllers that share a capability keeps the capability valid',
    (tester) async {
      final capability = await _authenticateVault(session);
      final oldController = VaultSessionController(
        authenticateVault: () async => null,
        stopAuthentication: () async {},
      );
      final newController = VaultSessionController(
        authenticateVault: () async => null,
        stopAuthentication: () async {},
      );
      final repository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) async => [
          _entry(name: 'Shared capability entry'),
        ],
      );

      await tester.pumpWidget(
        _app(oldController, repository, screenKey: const ValueKey('vault')),
      );
      await tester.pump();
      expect(find.text('Shared capability entry'), findsOneWidget);

      await tester.pumpWidget(
        _app(newController, repository, screenKey: const ValueKey('vault')),
      );
      await tester.pump();
      await tester.pump();

      expect(session.currentVaultCapability(), same(capability));
      expect(newController.capability, same(capability));
      expect(find.text('Shared capability entry'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      oldController.dispose();
      newController.dispose();
    },
  );

  testWidgets(
    'replacing the controller preserves a newer capability when old biometrics finish late',
    (tester) async {
      final oldAuthenticationStarted = Completer<void>();
      final oldAuthenticationResult = Completer<bool>();
      var authenticationCalls = 0;
      var stops = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_localAuthChannel, (call) async {
            if (call.method != 'authenticate') return null;
            authenticationCalls += 1;
            if (authenticationCalls == 1) {
              oldAuthenticationStarted.complete();
              return oldAuthenticationResult.future;
            }
            return true;
          });
      final oldController = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () =>
            session.authenticateVault(reason: 'Old controller authentication'),
        remainingLifetime: (_) => const Duration(minutes: 5),
        stopAuthentication: () async {
          stops += 1;
          await session.stopAuthentication();
        },
      );

      await tester.pumpWidget(
        _app(
          oldController,
          _FakeVaultRepository(),
          screenKey: const ValueKey('vault'),
        ),
      );
      await tester.pump();
      await oldAuthenticationStarted.future;

      final newCapability = await session.authenticateVault(
        reason: 'New controller authentication',
      );
      expect(newCapability, isNotNull);
      final currentCapability = newCapability!;
      final newController = _unlockedController(currentCapability);
      final newRepository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) async => [
          _entry(id: 'new-entry', name: 'Current entry'),
        ],
      );
      await tester.pumpWidget(
        _app(newController, newRepository, screenKey: const ValueKey('vault')),
      );
      oldAuthenticationResult.complete(true);
      await tester.pump();
      await tester.pump();

      expect(authenticationCalls, 2);
      expect(stops, 1);
      expect(session.currentVaultCapability(), same(currentCapability));
      expect(newController.capability, same(currentCapability));
      expect(find.text('Current entry'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      oldController.dispose();
      newController.dispose();
    },
  );

  testWidgets('replacing the repository cancels pending authentication', (
    tester,
  ) async {
    final authenticationGate = Completer<void>();
    var lateIssues = 0;
    var stops = 0;
    var stopped = false;
    final controller = VaultSessionController(
      currentCapability: () => null,
      authenticateVault: () async {
        await authenticationGate.future;
        if (stopped) return null;
        lateIssues += 1;
        return _authenticateVault(session);
      },
      remainingLifetime: (_) => const Duration(minutes: 5),
      stopAuthentication: () async {
        stops += 1;
        stopped = true;
      },
    );

    await tester.pumpWidget(
      _app(
        controller,
        _FakeVaultRepository(),
        screenKey: const ValueKey('vault'),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      _app(
        controller,
        _FakeVaultRepository(),
        screenKey: const ValueKey('vault'),
      ),
    );
    authenticationGate.complete();
    await tester.pump();
    await tester.pump();

    expect(lateIssues, 0);
    expect(stops, 1);
    expect(session.currentVaultCapability(), isNull);
    expect(find.byKey(const Key('vault_locked')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'disposing the screen cancels late authentication on an external controller',
    (tester) async {
      final authenticationGate = Completer<void>();
      var lateIssues = 0;
      var stops = 0;
      var stopped = false;
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () async {
          await authenticationGate.future;
          if (stopped) return null;
          lateIssues += 1;
          return _authenticateVault(session);
        },
        remainingLifetime: (_) => const Duration(minutes: 5),
        stopAuthentication: () async {
          stops += 1;
          stopped = true;
        },
      );

      await tester.pumpWidget(_app(controller, _FakeVaultRepository()));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      authenticationGate.complete();
      await tester.pump();
      await tester.pump();

      expect(lateIssues, 0);
      expect(stops, 1);
      expect(controller.capability, isNull);
      expect(session.currentVaultCapability(), isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'disposing an idle screen preserves its capability for controller reuse',
    (tester) async {
      final capability = await _authenticateVault(session);
      var authentications = 0;
      var loads = 0;
      final controller = VaultSessionController(
        authenticateVault: () async {
          authentications += 1;
          return null;
        },
        stopAuthentication: () async {},
      );
      final repository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) async {
          loads += 1;
          return [_entry(name: 'Reusable entry')];
        },
      );

      await tester.pumpWidget(_app(controller, repository));
      await tester.pump();
      expect(find.text('Reusable entry'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(session.currentVaultCapability(), same(capability));
      expect(controller.capability, same(capability));

      await tester.pumpWidget(_app(controller, repository));
      await tester.pump();

      expect(find.text('Reusable entry'), findsOneWidget);
      expect(authentications, 0);
      expect(loads, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('replacing the repository revokes an in-flight save', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final saveStarted = Completer<void>();
    final saveGate = Completer<void>();
    var committedSaves = 0;
    final oldRepository = _FakeVaultRepository(
      saveHandler:
          ({
            required capability,
            id,
            required category,
            required name,
            required account,
            required password,
            notes,
          }) async {
            saveStarted.complete();
            await saveGate.future;
            if (session.isVaultCapabilityValid(capability)) {
              committedSaves += 1;
            }
          },
    );

    await tester.pumpWidget(
      _app(controller, oldRepository, screenKey: const ValueKey('vault')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vault_name_field')),
      'New account',
    );
    await tester.tap(find.byKey(const Key('vault_dialog_save')));
    await tester.pumpAndSettle();
    await saveStarted.future;

    await tester.pumpWidget(
      _app(
        controller,
        _FakeVaultRepository(),
        screenKey: const ValueKey('vault'),
      ),
    );
    await tester.pump();
    saveGate.complete();
    await tester.pump();

    expect(committedSaves, 0);
    expect(find.byKey(const Key('vault_locked')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('disposing during a save prevents a database write', (
    tester,
  ) async {
    final database = (await tester.runAsync(_openVaultDatabase))!;
    addTearDown(database.close);
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final saveStarted = Completer<void>();
    final saveGate = Completer<void>();
    final saveFinished = Completer<void>();
    final repository = _FakeVaultRepository(
      saveHandler:
          ({
            required capability,
            id,
            required category,
            required name,
            required account,
            required password,
            notes,
          }) async {
            saveStarted.complete();
            await saveGate.future;
            try {
              if (session.isVaultCapabilityValid(capability)) {
                await database.insert(
                  'vault_entries',
                  _entry(id: 'disposed-save', name: name).toMap(),
                );
              }
            } finally {
              saveFinished.complete();
            }
          },
    );

    await tester.pumpWidget(_app(controller, repository));
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vault_name_field')),
      'New account',
    );
    await tester.enterText(
      find.byKey(const Key('vault_password_field')),
      'private-password',
    );
    await tester.tap(find.byKey(const Key('vault_dialog_save')));
    await tester.pumpAndSettle();
    await saveStarted.future;

    await tester.pumpWidget(const SizedBox.shrink());
    saveGate.complete();
    for (var i = 0; i < 20 && !saveFinished.isCompleted; i += 1) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(saveFinished.isCompleted, isTrue);
    final rows = await tester.runAsync(() => database.query('vault_entries'));
    expect(rows, isEmpty);
    expect(session.currentVaultCapability(), isNull);
    controller.dispose();
  });

  testWidgets(
    'disposing the screen removes its active dialog from a retained navigator',
    (tester) async {
      final capability = await _authenticateVault(session);
      final controller = _unlockedController(capability);
      var showVault = true;
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return showVault
                  ? VaultScreen(
                      controller: controller,
                      repository: _FakeVaultRepository(),
                    )
                  : const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault_add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault_add_dialog')), findsOneWidget);

      setHostState(() => showVault = false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vault_add_dialog')), findsNothing);
      expect(session.currentVaultCapability(), same(capability));
      controller.dispose();
    },
  );

  testWidgets('expiry while the add dialog is open prevents saving', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final repository = _FakeVaultRepository();

    await tester.pumpWidget(_app(controller, repository));
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('vault_name_field')),
      'New account',
    );
    await tester.enterText(
      find.byKey(const Key('vault_password_field')),
      'private-password',
    );

    await controller.lock();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vault_add_dialog')), findsNothing);
    expect(find.byKey(const Key('vault_locked')), findsOneWidget);
    expect(repository.saveCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'old entries stay hidden while the post-expiry reauthentication load is pending',
    (tester) async {
      VaultSessionCapability? current = await _authenticateVault(session);
      final firstCapability = current;
      final newLoadStarted = Completer<void>();
      final newLoadGate = Completer<List<VaultEntryModel>>();
      var loadCalls = 0;
      void revoke([VaultSessionCapability? target]) {
        if (target == null) {
          session.lockVault();
        } else {
          session.revokeVaultCapability(target);
        }
        if (identical(current, target) || target == null) current = null;
      }

      final controller = VaultSessionController(
        currentCapability: () => current,
        authenticateVault: () async {
          current = await _authenticateVault(session);
          return current!;
        },
        remainingLifetime: (capability) =>
            identical(capability, firstCapability)
            ? const Duration(minutes: 1)
            : const Duration(minutes: 5),
        revokeVault: revoke,
        stopAuthentication: () async {},
      );
      final repository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) {
          loadCalls += 1;
          if (loadCalls == 1) {
            return Future.value([_entry(name: 'Expired entry')]);
          }
          newLoadStarted.complete();
          return newLoadGate.future;
        },
      );

      await tester.pumpWidget(_app(controller, repository));
      await tester.pump();
      expect(find.text('Expired entry'), findsOneWidget);

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault_reauthenticate')));
      await tester.pump();
      await newLoadStarted.future;

      expect(find.text('Expired entry'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      newLoadGate.complete([_entry(name: 'Fresh entry')]);
      await tester.pump();
      expect(find.text('Fresh entry'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('expiry during decryption prevents clipboard writes', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final decryptStarted = Completer<void>();
    final decryptGate = Completer<String>();
    final clipboardWrites = <String>[];
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
      decryptHandler: (entry, {required capability}) {
        decryptStarted.complete();
        return decryptGate.future;
      },
    );

    await tester.pumpWidget(
      _app(
        controller,
        repository,
        clipboardWriter: (text) async => clipboardWrites.add(text),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_copy_entry-1')));
    await decryptStarted.future;

    await controller.lock();
    decryptGate.complete('private-password');
    await tester.pump();
    await tester.pump();

    expect(clipboardWrites, isEmpty);
    expect(find.byKey(const Key('vault_locked')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('expiry clears a clipboard write that was already in progress', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    final clipboardWrites = <String>[];
    String? clipboardText;
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
    );

    await tester.pumpWidget(
      _app(
        controller,
        repository,
        clipboardWriter: (text) {
          clipboardWrites.add(text);
          clipboardText = text;
          if (text.isNotEmpty) {
            writeStarted.complete();
            return writeGate.future;
          }
          return Future.value();
        },
        clipboardReader: () async => clipboardText,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_copy_entry-1')));
    await writeStarted.future;

    await controller.lock();
    writeGate.complete();
    await tester.pump();
    await tester.pump();

    expect(clipboardWrites, ['private-password', '']);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('dispose clears a clipboard write that was already in progress', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final writeStarted = Completer<void>();
    final writeGate = Completer<void>();
    final clipboardWrites = <String>[];
    String? clipboardText;
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
    );

    await tester.pumpWidget(
      _app(
        controller,
        repository,
        clipboardWriter: (text) {
          clipboardWrites.add(text);
          clipboardText = text;
          if (text.isNotEmpty) {
            writeStarted.complete();
            return writeGate.future;
          }
          return Future.value();
        },
        clipboardReader: () async => clipboardText,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_copy_entry-1')));
    await writeStarted.future;

    await tester.pumpWidget(const SizedBox.shrink());
    writeGate.complete();
    await tester.pump();
    await tester.pump();

    expect(clipboardWrites, ['private-password', '']);
    expect(session.currentVaultCapability(), same(capability));
    controller.dispose();
  });

  testWidgets(
    'starting a second copy clears the first secret before the later write',
    (tester) async {
      final capability = await _authenticateVault(session);
      final controller = _unlockedController(capability);
      final secondDecryptStarted = Completer<void>();
      final secondDecryptGate = Completer<String>();
      final clipboardWrites = <String>[];
      String? clipboardText;
      final repository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) async => [
          _entry(id: 'first', name: 'First account'),
          _entry(id: 'second', name: 'Second account'),
        ],
        decryptHandler: (entry, {required capability}) {
          if (entry.id == 'second') {
            secondDecryptStarted.complete();
            return secondDecryptGate.future;
          }
          return Future.value('first-password');
        },
      );

      await tester.pumpWidget(
        _app(
          controller,
          repository,
          clipboardWriter: (text) async {
            clipboardWrites.add(text);
            clipboardText = text;
          },
          clipboardReader: () async => clipboardText,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault_copy_first')));
      await tester.pump();
      await tester.pump();
      expect(clipboardText, 'first-password');

      await tester.pump(const Duration(seconds: 59));
      await tester.tap(find.byKey(const Key('vault_copy_second')));
      await secondDecryptStarted.future;
      await tester.pump();
      await tester.pump();
      expect(clipboardText, '');

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(clipboardText, '');
      expect(clipboardWrites, contains(''));

      secondDecryptGate.complete('second-password');
      await tester.pump();
      await tester.pump();
      expect(clipboardText, 'second-password');

      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(clipboardText, '');

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'clearing an old copy does not discard a queued copy of the same password',
    (tester) async {
      final capability = await _authenticateVault(session);
      final controller = _unlockedController(capability);
      final oldClearReadStarted = Completer<void>();
      final oldClearReadGate = Completer<String?>();
      final secondDecryptStarted = Completer<void>();
      final secondDecryptGate = Completer<String>();
      final clipboardWrites = <String>[];
      String? clipboardText;
      var clipboardReads = 0;
      final repository = _FakeVaultRepository(
        getAllHandler: ({required capability, category}) async => [
          _entry(id: 'first', name: 'First account'),
          _entry(id: 'second', name: 'Second account'),
        ],
        decryptHandler: (entry, {required capability}) {
          if (entry.id == 'second') {
            secondDecryptStarted.complete();
            return secondDecryptGate.future;
          }
          return Future.value('shared-password');
        },
      );

      await tester.pumpWidget(
        _app(
          controller,
          repository,
          clipboardWriter: (text) async {
            clipboardWrites.add(text);
            clipboardText = text;
          },
          clipboardReader: () {
            clipboardReads += 1;
            if (clipboardReads == 1) {
              oldClearReadStarted.complete();
              return oldClearReadGate.future;
            }
            return Future.value(clipboardText);
          },
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('vault_copy_first')));
      await tester.pump();
      await tester.pump();
      expect(clipboardText, 'shared-password');

      await tester.tap(find.byKey(const Key('vault_copy_second')));
      await secondDecryptStarted.future;
      await oldClearReadStarted.future;
      secondDecryptGate.complete('shared-password');
      await tester.pump();

      oldClearReadGate.complete('shared-password');
      await tester.pump();
      await tester.pump();

      expect(clipboardWrites, ['shared-password', '', 'shared-password']);
      expect(clipboardText, 'shared-password');

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('timer preserves clipboard content copied outside the vault', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final clipboardWrites = <String>[];
    String? clipboardText;
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
    );

    await tester.pumpWidget(
      _app(
        controller,
        repository,
        clipboardWriter: (text) async {
          clipboardWrites.add(text);
          clipboardText = text;
        },
        clipboardReader: () async => clipboardText,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_copy_entry-1')));
    await tester.pump();
    await tester.pump();
    clipboardText = 'user clipboard text';

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();

    expect(clipboardText, 'user clipboard text');
    expect(clipboardWrites, ['private-password']);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('failed clipboard clear is retried when leaving the vault', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    var emptyWriteAttempts = 0;
    String? clipboardText;
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
    );

    await tester.pumpWidget(
      _app(
        controller,
        repository,
        clipboardWriter: (text) async {
          if (text.isEmpty) {
            emptyWriteAttempts += 1;
            if (emptyWriteAttempts == 1) {
              throw StateError('clipboard clear failed');
            }
          }
          clipboardText = text;
        },
        clipboardReader: () async => clipboardText,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_copy_entry-1')));
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(emptyWriteAttempts, 1);
    expect(clipboardText, 'private-password');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();

    expect(emptyWriteAttempts, 2);
    expect(clipboardText, '');
    controller.dispose();
  });

  testWidgets('failed timer clear retries while the vault remains open', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    var emptyWriteAttempts = 0;
    String? clipboardText;
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
    );

    await tester.pumpWidget(
      _app(
        controller,
        repository,
        clipboardWriter: (text) async {
          if (text.isEmpty) {
            emptyWriteAttempts += 1;
            if (emptyWriteAttempts == 1) {
              throw StateError('clipboard clear failed');
            }
          }
          clipboardText = text;
        },
        clipboardReader: () async => clipboardText,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_copy_entry-1')));
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(emptyWriteAttempts, 1);
    expect(clipboardText, 'private-password');

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(emptyWriteAttempts, 2);
    expect(clipboardText, '');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('leaving the vault clears a password copied by the screen', (
    tester,
  ) async {
    final capability = await _authenticateVault(session);
    final controller = _unlockedController(capability);
    final clipboardWrites = <String>[];
    String? clipboardText;
    final repository = _FakeVaultRepository(
      getAllHandler: ({required capability, category}) async => [
        _entry(name: 'Primary email'),
      ],
    );

    await tester.pumpWidget(
      _app(
        controller,
        repository,
        clipboardWriter: (text) async {
          clipboardWrites.add(text);
          clipboardText = text;
        },
        clipboardReader: () async => clipboardText,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('vault_copy_entry-1')));
    await tester.pump();
    await tester.pump();
    expect(clipboardWrites, ['private-password']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(clipboardWrites, ['private-password', '']);
    controller.dispose();
  });

  testWidgets(
    'failed initial authentication shows a retry instead of a spinner',
    (tester) async {
      final controller = VaultSessionController(
        currentCapability: () => null,
        authenticateVault: () async => null,
        remainingLifetime: (_) => const Duration(minutes: 5),
        revokeVault: (_) => session.lockVault(),
        stopAuthentication: () async {},
      );

      await tester.pumpWidget(_app(controller, _FakeVaultRepository()));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('vault_locked')), findsOneWidget);
      expect(find.byKey(const Key('vault_reauthenticate')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}

Widget _app(
  VaultSessionController controller,
  VaultRepository repository, {
  Key? screenKey,
  Future<void> Function(String)? clipboardWriter,
  Future<String?> Function()? clipboardReader,
}) {
  return MaterialApp(
    home: VaultScreen(
      key: screenKey,
      controller: controller,
      repository: repository,
      clipboardWriter: clipboardWriter,
      clipboardReader: clipboardReader,
    ),
  );
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

VaultSessionController _unlockedController(
  VaultSessionCapability capability, {
  void Function([VaultSessionCapability? capability])? revokeVault,
}) {
  return VaultSessionController(
    currentCapability: () => capability,
    authenticateVault: () => SessionService.instance.authenticateVault(),
    remainingLifetime: (_) => const Duration(minutes: 5),
    revokeVault: revokeVault,
    stopAuthentication: () async {},
  );
}

void _ignoreRevocation([VaultSessionCapability? capability]) {}

Future<Database> _openVaultDatabase() {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: DatabaseSchema.onCreate,
      singleInstance: false,
    ),
  );
}

VaultEntryModel _entry({String id = 'entry-1', required String name}) {
  final now = DateTime.utc(2026, 7, 17, 12);
  return VaultEntryModel(
    id: id,
    category: 'work',
    name: name,
    account: 'person@example.com',
    passwordEnc: 'encrypted:private-password',
    createdAt: now,
    updatedAt: now,
  );
}

typedef _GetAllHandler =
    Future<List<VaultEntryModel>> Function({
      required VaultSessionCapability capability,
      String? category,
    });

typedef _DecryptHandler =
    Future<String> Function(
      VaultEntryModel entry, {
      required VaultSessionCapability capability,
    });

typedef _SaveHandler =
    Future<void> Function({
      required VaultSessionCapability capability,
      String? id,
      required String category,
      required String name,
      required String account,
      required String password,
      String? notes,
    });

class _FakeVaultRepository extends VaultRepository {
  _FakeVaultRepository({
    _GetAllHandler? getAllHandler,
    _DecryptHandler? decryptHandler,
    this._saveHandler,
  }) : _getAllHandler =
           getAllHandler ??
           (({required capability, category}) async => <VaultEntryModel>[]),
       _decryptHandler =
           decryptHandler ??
           ((entry, {required capability}) async => 'private-password');

  final _GetAllHandler _getAllHandler;
  final _DecryptHandler _decryptHandler;
  final _SaveHandler? _saveHandler;
  int saveCalls = 0;

  @override
  Future<List<VaultEntryModel>> getAll({
    required VaultSessionCapability capability,
    String? category,
  }) {
    return _getAllHandler(capability: capability, category: category);
  }

  @override
  Future<void> saveEntry({
    required VaultSessionCapability capability,
    String? id,
    required String category,
    required String name,
    required String account,
    required String password,
    String? notes,
  }) async {
    saveCalls += 1;
    await _saveHandler?.call(
      capability: capability,
      id: id,
      category: category,
      name: name,
      account: account,
      password: password,
      notes: notes,
    );
  }

  @override
  Future<String> decryptPassword(
    VaultEntryModel entry, {
    required VaultSessionCapability capability,
  }) {
    return _decryptHandler(entry, capability: capability);
  }

  @override
  Future<void> softDelete(
    String id, {
    required VaultSessionCapability capability,
  }) async {}
}
