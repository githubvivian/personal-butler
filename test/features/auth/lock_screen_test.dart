import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/features/auth/lock_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('setup exception is safe and leaves a retryable button', (
    tester,
  ) async {
    final appState = _LockTestAppState(
      initialized: false,
      setupAction: () async =>
          throw StateError('private secure storage failure'),
    );
    addTearDown(appState.dispose);

    await tester.pumpWidget(_host(appState));
    await tester.pumpAndSettle();

    expect(find.text('初始化失败，请重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('private secure storage failure'), findsNothing);
    expect(find.text('开始初始化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlock exception is safe and leaves a retryable button', (
    tester,
  ) async {
    final appState = _LockTestAppState(
      initialized: true,
      unlockAction: () async => throw StateError('private biometric failure'),
    );
    addTearDown(appState.dispose);

    await tester.pumpWidget(_host(appState));
    await tester.pumpAndSettle();

    expect(find.text('验证失败，请重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('private biometric failure'), findsNothing);
    expect(find.text('验证指纹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame retry taps start only one authentication', (
    tester,
  ) async {
    var attempts = 0;
    final retryGate = Completer<bool>();
    final appState = _LockTestAppState(
      initialized: true,
      unlockAction: () async {
        attempts++;
        return attempts == 1 ? false : retryGate.future;
      },
    );
    addTearDown(appState.dispose);

    await tester.pumpWidget(_host(appState));
    await tester.pumpAndSettle();
    expect(find.text('验证失败，请重试'), findsOneWidget);

    await tester.tap(find.text('验证指纹'));
    await tester.tap(find.text('验证指纹'));
    expect(attempts, 2);
    retryGate.complete(false);
    await tester.pumpAndSettle();

    expect(attempts, 2); // one automatic attempt and one coalesced retry
    expect(find.text('验证失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending authentication completion after disposal is ignored', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final appState = _LockTestAppState(
      initialized: true,
      unlockAction: () => gate.future,
    );

    await tester.pumpWidget(_host(appState));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    appState.dispose();
  });
}

Widget _host(_LockTestAppState appState) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: const MaterialApp(home: LockScreen()),
  );
}

class _LockTestAppState extends AppState {
  _LockTestAppState({
    required this.initialized,
    this.setupAction,
    this.unlockAction,
  }) : super(
         initializeNotifications: () async {},
         readInitialized: () async => false,
         validateSession: () async => false,
         syncReminders: () async {},
       );

  @override
  final bool initialized;
  final Future<bool> Function()? setupAction;
  final Future<bool> Function()? unlockAction;

  @override
  Future<bool> setupFirstRun() =>
      setupAction?.call() ?? Future<bool>.value(false);

  @override
  Future<bool> unlock() => unlockAction?.call() ?? Future<bool>.value(false);
}
