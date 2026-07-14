import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../security/encryption_service.dart';

enum BackupImportOutcome { imported, cancelled }

class BackupImportSelectionException implements Exception {
  const BackupImportSelectionException(this.message);

  final String message;

  @override
  String toString() => 'BackupImportSelectionException: $message';
}

typedef BackupDataReplacer =
    Future<void> Function(Map<String, List<Map<String, dynamic>>> data);

class BackupService {
  BackupService({BackupDataReplacer? replaceAllData})
    : _replaceAllData =
          replaceAllData ?? DatabaseHelper.instance.replaceAllData;

  final _enc = EncryptionService.instance;
  final BackupDataReplacer _replaceAllData;

  Future<String> exportEncryptedBackup(String password) async {
    final data = await DatabaseHelper.instance.exportAllData();
    final json = jsonEncode({
      'exported_at': DateTime.now().toIso8601String(),
      'version': 1,
      'tables': data,
    });
    final encrypted = await _enc.encryptBackupPayload(json, password);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/personal_butler_backup_${DateTime.now().millisecondsSinceEpoch}.pbak',
    );
    await file.writeAsString(encrypted);
    return file.path;
  }

  Future<void> shareBackup(String password) async {
    final path = await exportEncryptedBackup(password);
    await Share.shareXFiles([XFile(path)], text: '个人管家加密备份');
  }

  Future<BackupImportOutcome> importEncryptedBackup(String password) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pbak', 'txt', 'json'],
    );
    if (result == null) return BackupImportOutcome.cancelled;
    if (result.files.length != 1) {
      throw const BackupImportSelectionException(
        'Expected exactly one selected backup file.',
      );
    }
    final path = result.files.single.path;
    if (path == null) {
      throw const BackupImportSelectionException(
        'The selected backup file has no readable path.',
      );
    }
    final content = await File(path).readAsString();
    final json = await _enc.decryptBackupPayload(content, password);
    final data = _parseBackupPayload(json);
    await _replaceAllData(data);
    return BackupImportOutcome.imported;
  }

  Map<String, List<Map<String, dynamic>>> _parseBackupPayload(String json) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const FormatException('Backup payload is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup payload must be a JSON object.');
    }
    final version = decoded['version'];
    if (version is! int || version != 1) {
      throw const FormatException('Backup payload version must be integer 1.');
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const FormatException('Backup payload tables must be an object.');
    }
    final expectedTables = DatabaseHelper.backupTableNames.toSet();
    final actualTables = tables.keys.toSet();
    if (actualTables.length != expectedTables.length ||
        !actualTables.containsAll(expectedTables)) {
      throw const FormatException(
        'Backup payload tables must contain exactly the supported tables.',
      );
    }

    final data = <String, List<Map<String, dynamic>>>{};
    for (final table in DatabaseHelper.backupTableNames) {
      final rows = tables[table];
      if (rows is! List) {
        throw FormatException('Backup payload table $table must be a list.');
      }
      final validatedRows = <Map<String, dynamic>>[];
      for (final row in rows) {
        if (row is! Map) {
          throw FormatException(
            'Backup payload table $table contains a non-object row.',
          );
        }
        if (row.keys.any((key) => key is! String)) {
          throw FormatException(
            'Backup payload table $table contains a row with non-string keys.',
          );
        }
        final validatedRow = <String, dynamic>{};
        for (final entry in row.entries) {
          validatedRow[entry.key as String] = entry.value;
        }
        validatedRows.add(validatedRow);
      }
      data[table] = validatedRows;
    }
    return data;
  }
}
