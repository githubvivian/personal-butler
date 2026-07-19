import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_butler/core/database/database_schema.dart';
import 'package:personal_butler/core/models/models.dart';
import 'package:personal_butler/core/repositories/other_repositories.dart';
import 'package:personal_butler/core/security/session_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final session = SessionService.instance;
  late Database database;

  setUp(() async {
    session.lockVault();
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: DatabaseSchema.onCreate,
        singleInstance: false,
      ),
    );
  });

  tearDown(() async {
    session.lockVault();
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
  });

  test(
    'valid capability permits repository operations with an injected field codec',
    () async {
      final capability = await _authenticateVault(session);
      final repository = _repository(database);

      await repository.saveEntry(
        capability: capability,
        category: 'work',
        name: 'Email',
        account: 'person@example.com',
        password: 'private-password',
        notes: 'private-note',
      );

      final entries = await repository.getAll(capability: capability);
      expect(entries, hasLength(1));
      expect(entries.single.passwordEnc, 'encrypted:private-password');
      expect(entries.single.notesEnc, 'encrypted:private-note');
      expect(
        await repository.decryptPassword(
          entries.single,
          capability: capability,
        ),
        'private-password',
      );

      await repository.softDelete(entries.single.id, capability: capability);
      expect(await repository.getAll(capability: capability), isEmpty);
    },
  );

  test('getAll rejects a revoked capability before database access', () async {
    var databaseRequests = 0;
    final repository = _repository(
      database,
      databaseProvider: () async {
        databaseRequests += 1;
        return database;
      },
    );
    final capability = await _authenticateVault(session);
    session.lockVault();

    await expectLater(
      repository.getAll(capability: capability),
      throwsA(isA<VaultAccessDeniedException>()),
    );
    expect(databaseRequests, 0);
  });

  test(
    'saveEntry rejects a revoked capability before encryption or writes',
    () async {
      var encryptionRequests = 0;
      var databaseRequests = 0;
      final repository = _repository(
        database,
        databaseProvider: () async {
          databaseRequests += 1;
          return database;
        },
        encryptVaultField: (value) async {
          encryptionRequests += 1;
          return 'encrypted:$value';
        },
      );
      final capability = await _authenticateVault(session);
      session.lockVault();

      await expectLater(
        repository.saveEntry(
          capability: capability,
          category: 'work',
          name: 'Email',
          account: 'person@example.com',
          password: 'private-password',
        ),
        throwsA(isA<VaultAccessDeniedException>()),
      );
      expect(encryptionRequests, 0);
      expect(databaseRequests, 0);
      expect(await database.query('vault_entries'), isEmpty);
    },
  );

  test(
    'decryptPassword rejects a revoked capability before decryption',
    () async {
      var decryptionRequests = 0;
      final repository = _repository(
        database,
        decryptVaultField: (value) async {
          decryptionRequests += 1;
          return 'private-password';
        },
      );
      final capability = await _authenticateVault(session);
      session.lockVault();

      await expectLater(
        repository.decryptPassword(
          _entry(passwordEnc: 'encrypted:private-password'),
          capability: capability,
        ),
        throwsA(isA<VaultAccessDeniedException>()),
      );
      expect(decryptionRequests, 0);
    },
  );

  test(
    'softDelete rejects a revoked capability before database access',
    () async {
      await database.insert('vault_entries', _entry().toMap());
      var databaseRequests = 0;
      final repository = _repository(
        database,
        databaseProvider: () async {
          databaseRequests += 1;
          return database;
        },
      );
      final capability = await _authenticateVault(session);
      session.lockVault();

      await expectLater(
        repository.softDelete('entry-1', capability: capability),
        throwsA(isA<VaultAccessDeniedException>()),
      );
      expect(databaseRequests, 0);
      final rows = await database.query('vault_entries');
      expect(rows.single['is_deleted'], 0);
    },
  );

  test(
    'reauthentication makes the old capability unusable by the repository',
    () async {
      final repository = _repository(database);
      final previous = await _authenticateVault(session);
      final current = await _authenticateVault(session);

      await expectLater(
        repository.getAll(capability: previous),
        throwsA(isA<VaultAccessDeniedException>()),
      );
      expect(await repository.getAll(capability: current), isEmpty);
    },
  );

  test(
    'getAll does not return rows when revoked during database acquisition',
    () async {
      await database.insert('vault_entries', _entry().toMap());
      final databaseRequested = Completer<void>();
      final databaseGate = Completer<Database>();
      final repository = _repository(
        database,
        databaseProvider: () {
          databaseRequested.complete();
          return databaseGate.future;
        },
      );
      final capability = await _authenticateVault(session);

      final result = repository.getAll(capability: capability);
      await databaseRequested.future;
      session.lockVault();
      databaseGate.complete(database);

      await expectLater(result, throwsA(isA<VaultAccessDeniedException>()));
    },
  );

  test(
    'getAll rejects rows when revoked after the awaited database query',
    () async {
      await database.insert('vault_entries', _entry().toMap());
      var queryCompleted = false;
      final repository = _repository(
        database,
        databaseProvider: () async => _QueryBoundaryDatabase(
          database,
          afterQuery: () {
            queryCompleted = true;
            session.lockVault();
          },
        ),
      );
      final capability = await _authenticateVault(session);

      await expectLater(
        repository.getAll(capability: capability),
        throwsA(isA<VaultAccessDeniedException>()),
      );

      expect(queryCompleted, isTrue);
    },
  );

  test('saveEntry does not write when revoked during encryption', () async {
    final encryptionStarted = Completer<void>();
    final encryptionGate = Completer<String>();
    final repository = _repository(
      database,
      encryptVaultField: (value) {
        encryptionStarted.complete();
        return encryptionGate.future;
      },
    );
    final capability = await _authenticateVault(session);

    final save = repository.saveEntry(
      capability: capability,
      category: 'work',
      name: 'Email',
      account: 'person@example.com',
      password: 'private-password',
    );
    await encryptionStarted.future;
    session.lockVault();
    encryptionGate.complete('encrypted:private-password');

    await expectLater(save, throwsA(isA<VaultAccessDeniedException>()));
    expect(await database.query('vault_entries'), isEmpty);
  });

  test(
    'saveEntry rolls back an insert when revoked after the transaction mutation',
    () async {
      var insertCompleted = false;
      final repository = _repository(
        database,
        databaseProvider: () async => _MutationBoundaryDatabase(
          database,
          afterInsert: () {
            insertCompleted = true;
            session.lockVault();
          },
        ),
      );
      final capability = await _authenticateVault(session);

      await expectLater(
        repository.saveEntry(
          capability: capability,
          category: 'work',
          name: 'Email',
          account: 'person@example.com',
          password: 'private-password',
        ),
        throwsA(isA<VaultAccessDeniedException>()),
      );

      expect(insertCompleted, isTrue);
      expect(await database.query('vault_entries'), isEmpty);
    },
  );

  test(
    'decryptPassword does not return plaintext when revoked during decryption',
    () async {
      final decryptionStarted = Completer<void>();
      final decryptionGate = Completer<String>();
      final repository = _repository(
        database,
        decryptVaultField: (value) {
          decryptionStarted.complete();
          return decryptionGate.future;
        },
      );
      final capability = await _authenticateVault(session);

      final decrypt = repository.decryptPassword(
        _entry(passwordEnc: 'encrypted:private-password'),
        capability: capability,
      );
      await decryptionStarted.future;
      session.lockVault();
      decryptionGate.complete('private-password');

      await expectLater(decrypt, throwsA(isA<VaultAccessDeniedException>()));
    },
  );

  test(
    'softDelete does not write when revoked during database acquisition',
    () async {
      await database.insert('vault_entries', _entry().toMap());
      final databaseRequested = Completer<void>();
      final databaseGate = Completer<Database>();
      final repository = _repository(
        database,
        databaseProvider: () {
          databaseRequested.complete();
          return databaseGate.future;
        },
      );
      final capability = await _authenticateVault(session);

      final delete = repository.softDelete('entry-1', capability: capability);
      await databaseRequested.future;
      session.lockVault();
      databaseGate.complete(database);

      await expectLater(delete, throwsA(isA<VaultAccessDeniedException>()));
      final rows = await database.query('vault_entries');
      expect(rows.single['is_deleted'], 0);
    },
  );

  test(
    'softDelete rolls back an update when revoked after the transaction mutation',
    () async {
      await database.insert('vault_entries', _entry().toMap());
      var updateCompleted = false;
      final repository = _repository(
        database,
        databaseProvider: () async => _MutationBoundaryDatabase(
          database,
          afterUpdate: () {
            updateCompleted = true;
            session.lockVault();
          },
        ),
      );
      final capability = await _authenticateVault(session);

      await expectLater(
        repository.softDelete('entry-1', capability: capability),
        throwsA(isA<VaultAccessDeniedException>()),
      );

      expect(updateCompleted, isTrue);
      final rows = await database.query('vault_entries');
      expect(rows.single['is_deleted'], 0);
    },
  );
}

VaultRepository _repository(
  Database database, {
  Future<Database> Function()? databaseProvider,
  Future<String> Function(String)? encryptVaultField,
  Future<String> Function(String)? decryptVaultField,
}) {
  return VaultRepository(
    databaseProvider: databaseProvider ?? () async => database,
    encryptVaultField: encryptVaultField ?? (value) async => 'encrypted:$value',
    decryptVaultField:
        decryptVaultField ??
        (value) async => value.startsWith('encrypted:')
            ? value.substring('encrypted:'.length)
            : value,
    createId: () => 'entry-1',
    now: () => DateTime.utc(2026, 7, 17, 12),
  );
}

VaultEntryModel _entry({String passwordEnc = 'encrypted:private-password'}) {
  final now = DateTime.utc(2026, 7, 17, 12);
  return VaultEntryModel(
    id: 'entry-1',
    category: 'work',
    name: 'Email',
    account: 'person@example.com',
    passwordEnc: passwordEnc,
    notesEnc: 'encrypted:private-note',
    createdAt: now,
    updatedAt: now,
  );
}

Future<VaultSessionCapability> _authenticateVault(
  SessionService session,
) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_localAuthChannel, (call) async {
        if (call.method == 'authenticate') return true;
        return null;
      });
  final capability = await session.authenticateVault(reason: 'Test vault');
  expect(capability, isNotNull);
  return capability!;
}

class _QueryBoundaryDatabase implements Database {
  _QueryBoundaryDatabase(this.delegate, {required this.afterQuery});

  final Database delegate;
  final void Function() afterQuery;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final rows = await delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    afterQuery();
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected database call: $invocation');
}

class _MutationBoundaryDatabase implements Database {
  _MutationBoundaryDatabase(
    this.delegate, {
    this.afterInsert,
    this.afterUpdate,
  });

  final Database delegate;
  final void Function()? afterInsert;
  final void Function()? afterUpdate;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction transaction) action, {
    bool? exclusive,
  }) {
    return delegate.transaction(
      (transaction) => action(
        _MutationBoundaryTransaction(
          transaction,
          afterInsert: afterInsert,
          afterUpdate: afterUpdate,
        ),
      ),
      exclusive: exclusive,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected database call: $invocation');
}

class _MutationBoundaryTransaction implements Transaction {
  _MutationBoundaryTransaction(
    this.delegate, {
    this.afterInsert,
    this.afterUpdate,
  });

  final Transaction delegate;
  final void Function()? afterInsert;
  final void Function()? afterUpdate;

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final result = await delegate.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
    afterInsert?.call();
    return result;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final result = await delegate.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
    afterUpdate?.call();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected transaction call: $invocation');
}
