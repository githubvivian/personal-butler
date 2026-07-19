import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest declares internet for speech recognition services', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      RegExp(
        r'<uses-permission\b(?=[^>]*android:name="android\.permission\.INTERNET")[^>]*/?>',
      ).hasMatch(manifest),
      isTrue,
    );
  });
}
