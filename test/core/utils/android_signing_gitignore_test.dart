import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android signing secrets are ignored recursively', () {
    final rules = File('android/.gitignore').readAsStringSync();

    expect(rules, contains('key.properties'));
    expect(rules, contains('keystore.properties'));
    for (final extension in [
      'keystore',
      'jks',
      'p12',
      'pfx',
      'pk8',
      'pkcs12',
      'pem',
      'key',
    ]) {
      expect(rules, contains('**/*.$extension'));
    }
  });
}
