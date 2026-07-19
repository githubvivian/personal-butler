import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _gradlePropertiesPath = 'android/gradle.properties';
const _expectedJvmArgsLine =
    'org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G '
    '-XX:ReservedCodeCacheSize=384m -XX:+HeapDumpOnOutOfMemoryError';

void main() {
  test('Gradle JVM arguments stay within the workstation memory budget', () {
    final lines = File(_gradlePropertiesPath).readAsLinesSync();

    expect(lines, isNotEmpty);
    expect(lines.first, _expectedJvmArgsLine);

    final jvmArgsDeclarations = lines.where((line) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#') || trimmed.startsWith('!')) return false;
      return trimmed.startsWith('org.gradle.jvmargs');
    }).toList();

    expect(jvmArgsDeclarations, <String>[_expectedJvmArgsLine]);
  });
}
