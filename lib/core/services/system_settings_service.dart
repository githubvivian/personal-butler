import 'package:flutter/services.dart';

enum SystemSettingsLaunchResult { launched, unavailable }

typedef NotificationSettingsOpener =
    Future<SystemSettingsLaunchResult> Function();

class SystemSettingsService {
  const SystemSettingsService();

  static const _channel = MethodChannel(
    'com.beihe.guanjia.personal_butler/system_settings',
  );

  Future<SystemSettingsLaunchResult> openAppNotificationSettings() async {
    try {
      final launched = await _channel.invokeMethod<bool>(
        'openAppNotificationSettings',
      );
      return launched == true
          ? SystemSettingsLaunchResult.launched
          : SystemSettingsLaunchResult.unavailable;
    } on PlatformException {
      return SystemSettingsLaunchResult.unavailable;
    } on MissingPluginException {
      return SystemSettingsLaunchResult.unavailable;
    }
  }
}
