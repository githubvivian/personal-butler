import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/utils/ocr_service.dart';

const _ocrChannel = MethodChannel('google_mlkit_text_recognizer');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocrChannel, null);
  });

  test('recognizeAsset closes its native recognizer after success', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocrChannel, (call) async {
          calls.add(call);
          if (call.method == 'vision#startTextRecognizer') {
            return <String, Object?>{'text': '识别结果', 'blocks': <Object?>[]};
          }
          return null;
        });
    final source = await _temporarySource();
    addTearDown(() => source.parent.delete(recursive: true));

    final text = await OcrService.instance.recognizeAsset(
      'local:${source.path}',
    );

    expect(text, '识别结果');
    expect(calls.map((call) => call.method), [
      'vision#startTextRecognizer',
      'vision#closeTextRecognizer',
    ]);
    expect(_recognizerId(calls[1]), _recognizerId(calls[0]));
  });

  test('recognizeAsset closes its native recognizer after failure', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocrChannel, (call) async {
          calls.add(call);
          if (call.method == 'vision#startTextRecognizer') {
            throw PlatformException(code: 'recognition_failed');
          }
          return null;
        });
    final source = await _temporarySource();
    addTearDown(() => source.parent.delete(recursive: true));

    await expectLater(
      OcrService.instance.recognizeAsset('local:${source.path}'),
      throwsA(isA<PlatformException>()),
    );

    expect(calls.map((call) => call.method), [
      'vision#startTextRecognizer',
      'vision#closeTextRecognizer',
    ]);
    expect(_recognizerId(calls[1]), _recognizerId(calls[0]));
  });

  test('cleanup failure does not discard successful OCR text', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocrChannel, (call) async {
          if (call.method == 'vision#startTextRecognizer') {
            return <String, Object?>{'text': '仍然可用', 'blocks': <Object?>[]};
          }
          throw PlatformException(code: 'close_failed');
        });
    final source = await _temporarySource();
    addTearDown(() => source.parent.delete(recursive: true));

    final text = await OcrService.instance.recognizeAsset(
      'local:${source.path}',
    );

    expect(text, '仍然可用');
  });

  test('concurrent requests use and close independent recognizers', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocrChannel, (call) async {
          calls.add(call);
          return call.method == 'vision#startTextRecognizer'
              ? <String, Object?>{'text': '并发结果', 'blocks': <Object?>[]}
              : null;
        });
    final source = await _temporarySource();
    addTearDown(() => source.parent.delete(recursive: true));

    final results = await Future.wait([
      OcrService.instance.recognizeAsset('local:${source.path}'),
      OcrService.instance.recognizeAsset('local:${source.path}'),
    ]);

    expect(results, ['并发结果', '并发结果']);
    final startIds = calls
        .where((call) => call.method == 'vision#startTextRecognizer')
        .map(_recognizerId)
        .toSet();
    final closeIds = calls
        .where((call) => call.method == 'vision#closeTextRecognizer')
        .map(_recognizerId)
        .toSet();
    expect(startIds, hasLength(2));
    expect(closeIds, startIds);
  });

  test('cleanup failure does not replace the recognition failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocrChannel, (call) async {
          if (call.method == 'vision#startTextRecognizer') {
            throw PlatformException(code: 'recognition_failed');
          }
          throw PlatformException(code: 'close_failed');
        });
    final source = await _temporarySource();
    addTearDown(() => source.parent.delete(recursive: true));

    await expectLater(
      OcrService.instance.recognizeAsset('local:${source.path}'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'recognition_failed',
        ),
      ),
    );
  });

  test('missing local source fails before allocating a recognizer', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocrChannel, (call) async {
          calls.add(call);
          return null;
        });
    final missingPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'personal-butler-missing-ocr-source.png';

    await expectLater(
      OcrService.instance.recognizeAsset('local:$missingPath'),
      throwsA(isA<OcrSourceUnavailableException>()),
    );

    expect(calls, isEmpty);
  });
}

Future<File> _temporarySource() async {
  final directory = await Directory.systemTemp.createTemp(
    'personal-butler-ocr-service-',
  );
  return File(
    '${directory.path}${Platform.pathSeparator}source.png',
  ).writeAsBytes(const [0]);
}

Object? _recognizerId(MethodCall call) {
  final arguments = Map<Object?, Object?>.from(call.arguments as Map);
  return arguments['id'];
}
