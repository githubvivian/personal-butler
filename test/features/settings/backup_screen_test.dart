import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/providers/app_state.dart';
import 'package:personal_butler/core/repositories/item_repository.dart';
import 'package:personal_butler/core/services/backup_service.dart';
import 'package:personal_butler/features/settings/backup_screen.dart';
import 'package:provider/provider.dart';

const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
  StandardMethodCodec(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, null);
  });

  testWidgets('backup screen warns about non-portable protected data', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BackupScreen()));

    expect(find.textContaining('不包含相册原图'), findsOneWidget);
    expect(find.textContaining('卸载应用、清除应用数据或换机后可能无法解密'), findsOneWidget);
    expect(find.textContaining('请勿将其视为完整换机或灾难恢复备份'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'secret1');
    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();

    expect(find.textContaining('密码保险库内容可能无法解密'), findsOneWidget);
    expect(find.textContaining('相册原图不会恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelling backup selection does not report success or refresh data',
    (tester) async {
      final appState = _TrackingAppState();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_filePickerChannel, (_) async => null);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: BackupScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'secret1');
      await tester.tap(find.text('从备份恢复'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.textContaining('数据库记录已恢复'), findsNothing);
      expect(appState.refreshCount, 0);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '从备份恢复'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('export failure shows a safe message and restores the controls', (
    tester,
  ) async {
    final backupService = _ControlledBackupService(
      (_) => Future<void>.error(
        StateError('private-path-token from a platform plugin'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: BackupScreen(backupService: backupService)),
    );
    await tester.enterText(find.byType(TextField), 'secret1');
    await tester.tap(find.text('导出加密备份'));
    await tester.pump();

    expect(find.text('备份失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('private-path-token'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '导出加密备份'))
          .onPressed,
      isNotNull,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful restore invalidates retained item screens once', (
    tester,
  ) async {
    final appState = _TrackingAppState();
    var itemInvalidations = 0;
    appState.items.addListener(() => itemInvalidations += 1);
    final backupService = _ControlledImportBackupService();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(home: BackupScreen(backupService: backupService)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'secret1');
    await tester.tap(find.text('从备份恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(backupService.imports, 1);
    expect(itemInvalidations, 1);
    expect(appState.refreshCount, 1);
    expect(find.text('数据库记录已恢复；请核对保险库和相册引用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'committed restore invalidates data after the backup screen is disposed',
    (tester) async {
      final appState = _TrackingAppState();
      var itemInvalidations = 0;
      appState.items.addListener(() => itemInvalidations += 1);
      final backupService = _DeferredImportBackupService();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(home: BackupScreen(backupService: backupService)),
        ),
      );
      await tester.enterText(find.byType(TextField), 'secret1');
      await tester.tap(find.text('从备份恢复'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pump();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      backupService.outcome.complete(BackupImportOutcome.imported);
      await tester.pump();

      expect(itemInvalidations, 1);
      expect(appState.refreshCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('export failure after disposal does not use the stale context', (
    tester,
  ) async {
    final export = Completer<void>();
    final backupService = _ControlledBackupService((_) => export.future);

    await tester.pumpWidget(
      MaterialApp(home: BackupScreen(backupService: backupService)),
    );
    await tester.enterText(find.byType(TextField), 'secret1');
    await tester.tap(find.text('导出加密备份'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    export.completeError(
      StateError('private-path-token from a delayed platform plugin'),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _ControlledBackupService extends BackupService {
  _ControlledBackupService(this._shareBackup);

  final Future<void> Function(String password) _shareBackup;

  @override
  Future<void> shareBackup(String password) => _shareBackup(password);
}

class _ControlledImportBackupService extends BackupService {
  int imports = 0;

  @override
  Future<BackupImportOutcome> importEncryptedBackup(String password) async {
    imports += 1;
    return BackupImportOutcome.imported;
  }
}

class _DeferredImportBackupService extends BackupService {
  final outcome = Completer<BackupImportOutcome>();

  @override
  Future<BackupImportOutcome> importEncryptedBackup(String password) {
    return outcome.future;
  }
}

class _TrackingAppState extends AppState {
  _TrackingAppState()
    : super(
        initializeNotifications: () async {},
        readInitialized: () async => false,
        validateSession: () async => false,
        syncReminders: () async {},
      );

  int refreshCount = 0;
  final ItemRepository _items = ItemRepository();

  @override
  ItemRepository get items => _items;

  @override
  void refresh() {
    refreshCount++;
    super.refresh();
  }
}
