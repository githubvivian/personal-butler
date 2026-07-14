import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/services/backup_service.dart';

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

  test('returns cancelled when the system file picker is dismissed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, (_) async => null);

    final outcome = await BackupService().importEncryptedBackup('secret1');

    expect(outcome, BackupImportOutcome.cancelled);
  });

  test('rejects a selected backup with no readable path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _filePickerChannel,
          (_) async => [
            {'path': null, 'name': 'backup.pbak', 'size': 0, 'bytes': null},
          ],
        );

    await expectLater(
      BackupService().importEncryptedBackup('secret1'),
      throwsA(isA<BackupImportSelectionException>()),
    );
  });

  test('rejects a picker result containing more than one file', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _filePickerChannel,
          (_) async => [
            {
              'path': 'Z:/not-read/first.pbak',
              'name': 'first.pbak',
              'size': 0,
              'bytes': null,
            },
            {
              'path': 'Z:/not-read/second.pbak',
              'name': 'second.pbak',
              'size': 0,
              'bytes': null,
            },
          ],
        );

    await expectLater(
      BackupService().importEncryptedBackup('secret1'),
      throwsA(isA<BackupImportSelectionException>()),
    );
  });
}
