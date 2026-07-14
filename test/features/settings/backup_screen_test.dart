import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/providers/app_state.dart';
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

      expect(find.text('恢复成功'), findsNothing);
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

  @override
  void refresh() {
    refreshCount++;
  }
}
