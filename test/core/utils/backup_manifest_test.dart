import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest disables system backup and references extraction rules', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application = RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(manifest)?.group(0);
    expect(application, isNotNull);
    expect(application, contains('android:allowBackup="false"'));
    expect(application, contains('android:fullBackupContent="false"'));
    expect(application, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  test('data extraction rules exclude all app-private domains', () {
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final domain in <String>[
      'root', 'file', 'database', 'sharedpref', 'external',
      'device_root', 'device_file', 'device_database',
      'device_sharedpref',
    ]) {
      expect(rules, contains('<exclude domain="$domain" path="." />'));
    }
    expect(RegExp(r'<cloud-backup>[\s\S]*</cloud-backup>').hasMatch(rules), isTrue);
    expect(RegExp(r'<device-transfer>[\s\S]*</device-transfer>').hasMatch(rules), isTrue);
  });
}
