import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<Database> openMemoryDatabase() => databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );

  test('concurrent first access shares one database open', () async {
    final gate = Completer<void>();
    var openCalls = 0;
    final helper = DatabaseHelper.forTesting(
      databaseOpener: () async {
        openCalls++;
        await gate.future;
        return openMemoryDatabase();
      },
    );
    addTearDown(helper.close);

    final first = helper.database;
    final second = helper.database;

    expect(openCalls, 1);
    expect(identical(first, second), isTrue);

    gate.complete();
    final firstDatabase = await first;
    final secondDatabase = await second;

    expect(identical(firstDatabase, secondDatabase), isTrue);
    expect(openCalls, 1);
  });

  test('a failed open clears the single-flight guard for retry', () async {
    var openCalls = 0;
    var fail = true;
    final helper = DatabaseHelper.forTesting(
      databaseOpener: () {
        openCalls++;
        if (fail) throw StateError('forced database open failure');
        return openMemoryDatabase();
      },
    );
    addTearDown(helper.close);

    final first = helper.database;
    final second = helper.database;
    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    expect(openCalls, 1);

    fail = false;
    final database = await helper.database;

    expect(database.isOpen, isTrue);
    expect(openCalls, 2);
  });

  test('close during an open prevents caching the closed database', () async {
    final firstGate = Completer<void>();
    var openCalls = 0;
    final helper = DatabaseHelper.forTesting(
      databaseOpener: () async {
        openCalls++;
        if (openCalls == 1) await firstGate.future;
        return openMemoryDatabase();
      },
    );
    addTearDown(helper.close);

    final first = helper.database;
    final closing = helper.close();
    firstGate.complete();
    await closing;

    expect((await first).isOpen, isFalse);
    final reopened = await helper.database;
    expect(reopened.isOpen, isTrue);
    expect(openCalls, 2);
  });
}
