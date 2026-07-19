import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/security/encryption_service.dart';

void main() {
  const password = 'do-not-leak-this-password';

  Map<String, dynamic> validEnvelope() => {
    'v': 1,
    'salt': base64Encode(List<int>.filled(16, 1)),
    'iv': base64Encode(List<int>.filled(16, 2)),
    'data': base64Encode(List<int>.filled(16, 3)),
  };

  Matcher formatExceptionContaining(String text) => isA<FormatException>()
      .having((error) => error.message, 'message', contains(text))
      .having((error) => error.toString(), 'error', isNot(contains(password)));

  group('backup envelope validation', () {
    test('redacts the source of malformed envelope JSON', () async {
      const marker = 'ENVELOPE_SECRET_MARKER_7D2C8A';
      const malformedJson = '{"v":1,"secret":"$marker"';

      await expectLater(
        EncryptionService.instance.decryptBackupPayload(
          malformedJson,
          password,
        ),
        throwsA(
          isA<FormatException>()
              .having((error) => error.source, 'source', isNull)
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('envelope'),
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
    });

    test('rejects an envelope whose JSON root is not an object', () async {
      await expectLater(
        EncryptionService.instance.decryptBackupPayload('[]', password),
        throwsA(formatExceptionContaining('object')),
      );
    });

    test('rejects an envelope with no version', () async {
      await expectLater(
        EncryptionService.instance.decryptBackupPayload('{}', password),
        throwsA(formatExceptionContaining('version')),
      );
    });

    test('rejects an envelope with a non-integer version', () async {
      await expectLater(
        EncryptionService.instance.decryptBackupPayload(
          jsonEncode({'v': '1'}),
          password,
        ),
        throwsA(formatExceptionContaining('version')),
      );
    });

    test(
      'rejects an unsupported envelope version before other fields',
      () async {
        await expectLater(
          EncryptionService.instance.decryptBackupPayload(
            jsonEncode({'v': 2}),
            password,
          ),
          throwsA(formatExceptionContaining('version')),
        );
      },
    );

    for (final field in ['salt', 'iv', 'data']) {
      test('rejects an envelope whose $field is not a string', () async {
        final envelope = validEnvelope()..[field] = 7;

        await expectLater(
          EncryptionService.instance.decryptBackupPayload(
            jsonEncode(envelope),
            password,
          ),
          throwsA(formatExceptionContaining(field)),
        );
      });
    }

    for (final field in ['salt', 'iv', 'data']) {
      test('rejects malformed base64 in $field', () async {
        final envelope = validEnvelope()..[field] = 'not-base64*';

        await expectLater(
          EncryptionService.instance.decryptBackupPayload(
            jsonEncode(envelope),
            password,
          ),
          throwsA(formatExceptionContaining(field)),
        );
      });
    }

    for (final field in ['salt', 'iv']) {
      test('rejects a $field value with the wrong decoded length', () async {
        final envelope = validEnvelope()
          ..[field] = base64Encode(List<int>.filled(15, 4));

        await expectLater(
          EncryptionService.instance.decryptBackupPayload(
            jsonEncode(envelope),
            password,
          ),
          throwsA(formatExceptionContaining(field)),
        );
      });
    }

    test('rejects empty encrypted data', () async {
      final envelope = validEnvelope()..['data'] = base64Encode(const []);

      await expectLater(
        EncryptionService.instance.decryptBackupPayload(
          jsonEncode(envelope),
          password,
        ),
        throwsA(formatExceptionContaining('data')),
      );
    });

    test('rejects encrypted data that is not a complete AES block', () async {
      final envelope = validEnvelope()
        ..['data'] = base64Encode(List<int>.filled(15, 5));

      await expectLater(
        EncryptionService.instance.decryptBackupPayload(
          jsonEncode(envelope),
          password,
        ),
        throwsA(formatExceptionContaining('data')),
      );
    });
  });
}
