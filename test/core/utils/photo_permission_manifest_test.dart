import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest declares image-only media access', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      _declaresPermission(manifest, 'android.permission.READ_MEDIA_IMAGES'),
      isTrue,
    );
    expect(
      _declaresPermission(
        manifest,
        'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
      ),
      isTrue,
    );
    expect(
      _declaresPermission(
        manifest,
        'android.permission.READ_EXTERNAL_STORAGE',
        maxSdkVersion: 32,
      ),
      isTrue,
    );
    expect(
      _declaresPermission(manifest, 'android.permission.READ_MEDIA_VIDEO'),
      isFalse,
    );
  });

  test('photo_manager supports image-only Android permission requests', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();

    expect(
      RegExp(
        r'^\s*photo_manager:\s*\^3\.10\.0\s*$',
        multiLine: true,
      ).hasMatch(pubspec),
      isTrue,
    );

    final lockedVersion = RegExp(
      r'^  photo_manager:\r?\n(?:.*\r?\n)*?    version: "([^"]+)"$',
      multiLine: true,
    ).firstMatch(lockfile)?.group(1);
    expect(lockedVersion, isNotNull);
    expect(_isAtLeast(lockedVersion!, const [3, 10, 0]), isTrue);
  });
}

bool _isAtLeast(String version, List<int> minimum) {
  final actual = version.split('.').map(int.parse).toList();
  for (var index = 0; index < minimum.length; index++) {
    final actualPart = index < actual.length ? actual[index] : 0;
    if (actualPart != minimum[index]) {
      return actualPart > minimum[index];
    }
  }
  return true;
}

bool _declaresPermission(
  String manifest,
  String permission, {
  int? maxSdkVersion,
}) {
  final escapedPermission = RegExp.escape(permission);
  final maxSdkLookahead = maxSdkVersion == null
      ? ''
      : '(?=[^>]*android:maxSdkVersion="$maxSdkVersion")';
  return RegExp(
    '<uses-permission\\b'
    '(?=[^>]*android:name="$escapedPermission")'
    '$maxSdkLookahead'
    '[^>]*/?>',
  ).hasMatch(manifest);
}
