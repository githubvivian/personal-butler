import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _scheduledReceiver =
    'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver';
const _bootReceiver =
    'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver';

void main() {
  test('Android manifest declares only the required alarm permissions', () {
    final manifest = File(_manifestPath).readAsStringSync();

    expect(
      _permissionDeclarations(
        manifest,
        'android.permission.SCHEDULE_EXACT_ALARM',
      ),
      hasLength(1),
    );
    expect(
      _permissionDeclarations(
        manifest,
        'android.permission.RECEIVE_BOOT_COMPLETED',
      ),
      hasLength(1),
    );
    expect(
      _permissionDeclarations(manifest, 'android.permission.USE_EXACT_ALARM'),
      isEmpty,
    );
  });

  test('scheduled notification receivers remain private and boot-aware', () {
    final manifest = File(_manifestPath).readAsStringSync();
    final scheduledDeclarations = _receiverDeclarations(
      manifest,
      _scheduledReceiver,
    );
    final bootDeclarations = _receiverDeclarations(manifest, _bootReceiver);

    expect(scheduledDeclarations, hasLength(1));
    expect(bootDeclarations, hasLength(1));

    final scheduledDeclaration = _receiverDeclaration(
      manifest,
      _scheduledReceiver,
    );
    final bootDeclaration = _receiverDeclaration(manifest, _bootReceiver);
    final bootBlock = _receiverBlock(manifest, _bootReceiver);

    expect(scheduledDeclaration, isNotNull);
    expect(_isSelfClosingReceiver(scheduledDeclaration!), isTrue);
    expect(
      _hasAttribute(scheduledDeclaration, 'android:exported', 'false'),
      isTrue,
    );
    expect(bootDeclaration, isNotNull);
    expect(_isSelfClosingReceiver(bootDeclaration!), isFalse);
    expect(_hasAttribute(bootDeclaration, 'android:exported', 'false'), isTrue);
    expect(bootBlock, isNotNull);
    expect(
      _declaresAction(bootBlock!, 'android.intent.action.BOOT_COMPLETED'),
      isTrue,
    );
    expect(
      _declaresAction(bootBlock, 'android.intent.action.MY_PACKAGE_REPLACED'),
      isTrue,
    );
    expect(
      _declaresAction(bootBlock, 'android.intent.action.QUICKBOOT_POWERON'),
      isTrue,
    );
  });

  test('manifest helpers ignore declarations inside XML comments', () {
    const manifest =
        '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <!--
  <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
  <application>
    <receiver android:name="$_scheduledReceiver" android:exported="false"/>
    <receiver android:name="$_bootReceiver" android:exported="false">
      <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
      </intent-filter>
    </receiver>
  </application>
  -->
</manifest>
''';

    expect(
      _declaresPermission(manifest, 'android.permission.SCHEDULE_EXACT_ALARM'),
      isFalse,
    );
    expect(_receiverDeclaration(manifest, _scheduledReceiver), isNull);
    expect(_receiverBlock(manifest, _bootReceiver), isNull);
    expect(
      _declaresAction(manifest, 'android.intent.action.BOOT_COMPLETED'),
      isFalse,
    );
  });

  test('receiver lookup rejects duplicate declarations', () {
    const manifest =
        '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application>
    <receiver android:name="$_scheduledReceiver" android:exported="false"/>
    <receiver android:name="$_scheduledReceiver" android:exported="false"/>
  </application>
</manifest>
''';

    expect(_receiverDeclarations(manifest, _scheduledReceiver), hasLength(2));
    expect(_receiverDeclaration(manifest, _scheduledReceiver), isNull);
  });
}

bool _declaresPermission(String manifest, String permission) {
  return _permissionDeclarations(manifest, permission).length == 1;
}

List<String> _permissionDeclarations(String manifest, String permission) {
  final uncommented = _withoutXmlComments(manifest);
  final escapedPermission = RegExp.escape(permission);
  return RegExp(
    '<uses-permission\\b'
    '(?=[^>]*android:name\\s*=\\s*"$escapedPermission")'
    '[^>]*/?>',
  ).allMatches(uncommented).map((match) => match.group(0)!).toList();
}

String? _receiverDeclaration(String manifest, String receiver) {
  final declarations = _receiverDeclarations(manifest, receiver);
  return declarations.length == 1 ? declarations.single : null;
}

List<String> _receiverDeclarations(String manifest, String receiver) {
  final uncommented = _withoutXmlComments(manifest);
  final escapedReceiver = RegExp.escape(receiver);
  return RegExp(
    '<receiver\\b'
    '(?=[^>]*android:name\\s*=\\s*"$escapedReceiver")'
    '[^>]*>',
  ).allMatches(uncommented).map((match) => match.group(0)!).toList();
}

String? _receiverBlock(String manifest, String receiver) {
  final uncommented = _withoutXmlComments(manifest);
  final declarations = _receiverDeclarations(uncommented, receiver);
  if (declarations.length != 1) return null;

  final declaration = declarations.single;
  if (_isSelfClosingReceiver(declaration)) return null;

  final receiverStart = uncommented.indexOf(declaration);
  if (receiverStart < 0) return null;
  final contentStart = receiverStart + declaration.length;
  final closingMatch = RegExp(
    r'</receiver\s*>',
  ).firstMatch(uncommented.substring(contentStart));
  if (closingMatch == null) return null;
  return uncommented.substring(receiverStart, contentStart + closingMatch.end);
}

bool _isSelfClosingReceiver(String declaration) =>
    RegExp(r'/\s*>$').hasMatch(declaration);

bool _hasAttribute(String declaration, String name, String value) {
  return RegExp(
    '${RegExp.escape(name)}\\s*=\\s*"${RegExp.escape(value)}"',
  ).hasMatch(declaration);
}

bool _declaresAction(String receiverBlock, String action) {
  final uncommented = _withoutXmlComments(receiverBlock);
  final escapedAction = RegExp.escape(action);
  return RegExp(
    '<action\\b'
    '(?=[^>]*android:name\\s*=\\s*"$escapedAction")'
    '[^>]*/?>',
  ).allMatches(uncommented).isNotEmpty;
}

String _withoutXmlComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
