import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/services/system_settings_service.dart';

const _systemSettingsChannel = MethodChannel(
  'com.beihe.guanjia.personal_butler/system_settings',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemSettingsChannel, null);
  });

  test('invokes the notification settings method without arguments', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemSettingsChannel, (call) async {
          calls.add(call);
          return true;
        });

    final result = await const SystemSettingsService()
        .openAppNotificationSettings();

    expect(result, SystemSettingsLaunchResult.launched);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'openAppNotificationSettings');
    expect(calls.single.arguments, isNull);
  });

  test('maps a false channel result to unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemSettingsChannel, (_) async => false);

    final result = await const SystemSettingsService()
        .openAppNotificationSettings();

    expect(result, SystemSettingsLaunchResult.unavailable);
  });

  test('maps a null channel result to unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemSettingsChannel, (_) async => null);

    final result = await const SystemSettingsService()
        .openAppNotificationSettings();

    expect(result, SystemSettingsLaunchResult.unavailable);
  });

  test('maps PlatformException to unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _systemSettingsChannel,
          (_) async => throw PlatformException(code: 'settings_unavailable'),
        );

    final result = await const SystemSettingsService()
        .openAppNotificationSettings();

    expect(result, SystemSettingsLaunchResult.unavailable);
  });

  test('maps a missing plugin handler to unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_systemSettingsChannel, null);

    final result = await const SystemSettingsService()
        .openAppNotificationSettings();

    expect(result, SystemSettingsLaunchResult.unavailable);
  });
}
