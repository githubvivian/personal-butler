import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/security/encryption_service.dart';
import 'package:personal_butler/core/services/backup_service.dart';

const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
  StandardMethodCodec(),
);

const _backupPassword = 'secret1';
const _backupTableNames = <String>[
  'items',
  'attachments',
  'schedule_entries',
  'schedule_settings',
  'birthdays',
  'ideas',
  'vault_entries',
];

Map<String, dynamic> _validPayload() => {
  'exported_at': '2026-07-15T00:00:00.000Z',
  'version': 1,
  'tables': <String, dynamic>{
    for (final table in _backupTableNames) table: <dynamic>[],
  },
};

Future<void> _selectRawBackupContent(String content) async {
  final directory = await Directory.systemTemp.createTemp(
    'personal_butler_backup_test_',
  );
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/backup.pbak');
  await file.writeAsString(content);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        _filePickerChannel,
        (_) async => [
          {
            'path': file.path,
            'name': 'backup.pbak',
            'size': await file.length(),
            'bytes': null,
          },
        ],
      );
}

Future<void> _selectEncryptedPayload(Object? payload) async {
  final content = await EncryptionService.instance.encryptBackupPayload(
    jsonEncode(payload),
    _backupPassword,
  );
  await _selectRawBackupContent(content);
}

Future<void> _expectEnvelopeRejectedBeforeReplace(
  String content,
  String expectedMessage,
) async {
  await _selectRawBackupContent(content);
  var replaceCalls = 0;
  var reconcileCalls = 0;
  final service = BackupService(
    replaceAllData: (_) async {
      replaceCalls++;
    },
    reconcileReminders: () async {
      reconcileCalls++;
    },
  );

  await expectLater(
    service.importEncryptedBackup(_backupPassword),
    throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains(expectedMessage),
      ),
    ),
  );
  expect(replaceCalls, 0);
  expect(reconcileCalls, 0);
}

Future<void> _expectPayloadRejectedBeforeReplace(
  Object? payload,
  String expectedMessage,
) async {
  await _selectEncryptedPayload(payload);
  var replaceCalls = 0;
  var reconcileCalls = 0;
  final service = BackupService(
    replaceAllData: (_) async {
      replaceCalls++;
    },
    reconcileReminders: () async {
      reconcileCalls++;
    },
  );

  await expectLater(
    service.importEncryptedBackup(_backupPassword),
    throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains(expectedMessage),
      ),
    ),
  );
  expect(replaceCalls, 0);
  expect(reconcileCalls, 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, null);
  });

  test('returns cancelled when the system file picker is dismissed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePickerChannel, (_) async => null);
    var reconcileCalls = 0;

    final outcome = await BackupService(
      reconcileReminders: () async {
        reconcileCalls++;
      },
    ).importEncryptedBackup('secret1');

    expect(outcome, BackupImportOutcome.cancelled);
    expect(reconcileCalls, 0);
  });

  test('rejects a selected backup with no readable path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _filePickerChannel,
          (_) async => [
            {'path': null, 'name': 'backup.pbak', 'size': 0, 'bytes': null},
          ],
        );

    var reconcileCalls = 0;
    await expectLater(
      BackupService(
        reconcileReminders: () async {
          reconcileCalls++;
        },
      ).importEncryptedBackup('secret1'),
      throwsA(isA<BackupImportSelectionException>()),
    );
    expect(reconcileCalls, 0);
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

    var reconcileCalls = 0;
    await expectLater(
      BackupService(
        reconcileReminders: () async {
          reconcileCalls++;
        },
      ).importEncryptedBackup('secret1'),
      throwsA(isA<BackupImportSelectionException>()),
    );
    expect(reconcileCalls, 0);
  });

  test(
    'imports a valid backup whose seven required tables are empty',
    () async {
      await _selectEncryptedPayload(_validPayload());
      var replaceCalls = 0;
      Map<String, List<Map<String, dynamic>>>? receivedData;

      final outcome = await BackupService(
        replaceAllData: (data) async {
          replaceCalls++;
          receivedData = data;
        },
        reconcileReminders: () async {},
      ).importEncryptedBackup(_backupPassword);

      expect(outcome, BackupImportOutcome.imported);
      expect(replaceCalls, 1);
      expect(receivedData?.keys.toSet(), _backupTableNames.toSet());
      expect(receivedData?.values, everyElement(isEmpty));
    },
  );

  test('reconciles reminders after replacing restored data', () async {
    await _selectEncryptedPayload(_validPayload());
    final events = <String>[];

    final outcome = await BackupService(
      replaceAllData: (_) async {
        events.add('replace');
      },
      reconcileReminders: () async {
        events.add('reconcile');
      },
    ).importEncryptedBackup(_backupPassword);

    expect(outcome, BackupImportOutcome.imported);
    expect(events, ['replace', 'reconcile']);
  });

  test(
    'reports a committed import whose reminder reconciliation failed',
    () async {
      await _selectEncryptedPayload(_validPayload());
      var replaceCompleted = false;

      final outcome = await BackupService(
        replaceAllData: (_) async {
          replaceCompleted = true;
        },
        reconcileReminders: () async {
          throw StateError('notification side effect failed');
        },
      ).importEncryptedBackup(_backupPassword);

      expect(outcome, BackupImportOutcome.importedWithReminderSyncFailure);
      expect(replaceCompleted, isTrue);
    },
  );

  test('propagates replace failure without reconciling reminders', () async {
    await _selectEncryptedPayload(_validPayload());
    final failure = StateError('database replacement failed');
    var reconcileCalls = 0;
    final service = BackupService(
      replaceAllData: (_) async {
        throw failure;
      },
      reconcileReminders: () async {
        reconcileCalls++;
      },
    );

    await expectLater(
      service.importEncryptedBackup(_backupPassword),
      throwsA(same(failure)),
    );
    expect(reconcileCalls, 0);
  });

  test('imports a valid non-empty row without losing field values', () async {
    final payload = _validPayload();
    final tables = payload['tables']! as Map<String, dynamic>;
    tables['items'] = <dynamic>[
      <String, dynamic>{
        'id': 'item-1',
        'title': 'Sample item',
        'count': 3,
        'optional': null,
      },
    ];
    await _selectEncryptedPayload(payload);
    var replaceCalls = 0;
    Map<String, List<Map<String, dynamic>>>? receivedData;

    final outcome = await BackupService(
      replaceAllData: (data) async {
        replaceCalls++;
        receivedData = data;
      },
      reconcileReminders: () async {},
    ).importEncryptedBackup(_backupPassword);

    expect(outcome, BackupImportOutcome.imported);
    expect(replaceCalls, 1);
    expect(receivedData?['items'], [
      {'id': 'item-1', 'title': 'Sample item', 'count': 3, 'optional': null},
    ]);
  });

  group('encrypted envelope validation before database replacement', () {
    test('rejects an unsupported envelope version before replace', () async {
      await _expectEnvelopeRejectedBeforeReplace(
        jsonEncode({'v': 2}),
        'version',
      );
    });

    test('rejects malformed encrypted data before replace', () async {
      await _expectEnvelopeRejectedBeforeReplace(
        jsonEncode({
          'v': 1,
          'salt': base64Encode(List<int>.filled(16, 1)),
          'iv': base64Encode(List<int>.filled(16, 2)),
          'data': 'not-base64*',
        }),
        'data',
      );
    });
  });

  group('decrypted payload validation before database replacement', () {
    test(
      'redacts malformed payload JSON before database replacement',
      () async {
        const marker = 'PAYLOAD_SECRET_MARKER_4B91EF';
        const malformedJson = '{"version":1,"secret":"$marker"';
        final encrypted = await EncryptionService.instance.encryptBackupPayload(
          malformedJson,
          _backupPassword,
        );
        await _selectRawBackupContent(encrypted);
        var replaceCalls = 0;
        var reconcileCalls = 0;
        final service = BackupService(
          replaceAllData: (_) async {
            replaceCalls++;
          },
          reconcileReminders: () async {
            reconcileCalls++;
          },
        );

        await expectLater(
          service.importEncryptedBackup(_backupPassword),
          throwsA(
            isA<FormatException>()
                .having((error) => error.source, 'source', isNull)
                .having(
                  (error) => error.message,
                  'message',
                  allOf(
                    contains('payload'),
                    contains('JSON'),
                    isNot(contains(marker)),
                  ),
                )
                .having(
                  (error) => error.toString(),
                  'error',
                  isNot(contains(marker)),
                ),
          ),
        );
        expect(replaceCalls, 0);
        expect(reconcileCalls, 0);
      },
    );

    test('rejects a payload whose JSON root is not an object', () async {
      await _expectPayloadRejectedBeforeReplace(<dynamic>[], 'payload');
    });

    test('rejects a payload with no version', () async {
      final payload = _validPayload()..remove('version');

      await _expectPayloadRejectedBeforeReplace(payload, 'version');
    });

    test('rejects a payload with a non-integer version', () async {
      final payload = _validPayload()..['version'] = '1';

      await _expectPayloadRejectedBeforeReplace(payload, 'version');
    });

    test('rejects an unsupported payload version', () async {
      final payload = _validPayload()..['version'] = 2;

      await _expectPayloadRejectedBeforeReplace(payload, 'version');
    });

    test('rejects a payload whose tables field is not an object', () async {
      final payload = _validPayload()..['tables'] = <dynamic>[];

      await _expectPayloadRejectedBeforeReplace(payload, 'tables');
    });

    test('rejects an empty tables object', () async {
      final payload = _validPayload()..['tables'] = <String, dynamic>{};

      await _expectPayloadRejectedBeforeReplace(payload, 'tables');
    });

    for (final missingTable in _backupTableNames) {
      test('rejects tables missing $missingTable', () async {
        final payload = _validPayload();
        final tables = payload['tables']! as Map<String, dynamic>;
        tables.remove(missingTable);

        await _expectPayloadRejectedBeforeReplace(payload, 'tables');
      });
    }

    test('rejects an unknown table', () async {
      final payload = _validPayload();
      final tables = payload['tables']! as Map<String, dynamic>;
      tables['unknown_table'] = <dynamic>[];

      await _expectPayloadRejectedBeforeReplace(payload, 'tables');
    });

    test('rejects a table value that is not a list', () async {
      final payload = _validPayload();
      final tables = payload['tables']! as Map<String, dynamic>;
      tables['items'] = <String, dynamic>{};

      await _expectPayloadRejectedBeforeReplace(payload, 'items');
    });

    test('rejects a table row that is not an object', () async {
      final payload = _validPayload();
      final tables = payload['tables']! as Map<String, dynamic>;
      tables['items'] = <dynamic>['not-a-row'];

      await _expectPayloadRejectedBeforeReplace(payload, 'items');
    });
  });
}
